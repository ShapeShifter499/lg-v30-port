# SPDX-License-Identifier: GPL-3.0-only
"""Attach only one verified media process's helpers to explicit PipeWire endpoints.

No daemon startup, device opening, mixer changes, dialing or recording export.
The caller owns the PipeWire session and restores the mixer when the call ends.
"""
from pathlib import Path
import json, os, subprocess, time


def connect_media(env, media_pid, capture_node, playback_node, expected_uid, timeout=5):
    def command(*args):
        return subprocess.check_output(list(args), env=env, text=True, timeout=3)

    def graph():
        return json.loads(command('pw-dump'))

    def identity(pid):
        raw = Path(f'/proc/{pid}/stat').read_text()
        # The comm field may contain spaces and parentheses; use its final ')'.
        tail = raw.rsplit(')', 1)[1].split()
        return int(tail[1]), tail[19]  # parent and starttime

    _, starttime = identity(media_pid)
    # /proc/PID/cmdline can be transiently empty immediately after exec on
    # this kernel. The executable inode is the identity, not argv text.
    assert Path(f'/proc/{media_pid}/exe').resolve(strict=True) == Path('/opt/v30-mobile/bin/imsd-media'), 'Unexpected media executable'

    def is_helper(pid):
        try:
            args = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
            program = Path(args[0].decode()).name
            if program not in ('pw-record', 'pw-play'):
                return None
            uid = int(next(s for s in Path(f'/proc/{pid}/status').read_text().splitlines() if s.startswith('Uid:')).split()[2])
            if uid != expected_uid:
                return None
            current = pid
            for _ in range(8):
                parent, _ = identity(current)
                if parent == media_pid:
                    assert identity(media_pid)[1] == starttime, 'Media PID reused'
                    return program
                if parent <= 1:
                    return None
                current = parent
        except (FileNotFoundError, ProcessLookupError):
            return None
        return None

    deadline = time.monotonic() + timeout
    selected = {}
    while time.monotonic() < deadline:
        assert identity(media_pid)[1] == starttime, 'Media PID changed during attachment'
        objects = graph()
        clients = {o['id']: o.get('info', {}).get('props', {}) for o in objects
                   if o.get('type') == 'PipeWire:Interface:Client'}
        for obj in objects:
            if obj.get('type') != 'PipeWire:Interface:Node':
                continue
            props = obj.get('info', {}).get('props', {})
            # The Node points to its Client. Peer PID/UID are server-attested
            # client properties; nodes do not carry application.process.id.
            client = clients.get(int(props.get('client.id', -1)), {})
            process = client.get('pipewire.sec.pid')
            if process is None or int(client.get('pipewire.sec.uid', -1)) != expected_uid:
                continue
            program = is_helper(int(process))
            expected_class = {'pw-record': 'Stream/Input/Audio', 'pw-play': 'Stream/Output/Audio'}.get(program)
            if expected_class and props.get('media.class') == expected_class:
                assert program not in selected or selected[program]['id'] == obj['id'], 'Ambiguous media stream'
                selected[program] = obj
        if set(selected) == {'pw-record', 'pw-play'}:
            break
        time.sleep(.1)
    else:
        raise RuntimeError('Both media audio helpers were not found')

    for program, obj in selected.items():
        direction = 'Input' if program == 'pw-record' else 'Output'
        param = '{ direction = ' + direction + ' mode = dsp format = { mediaType = audio mediaSubtype = raw format = F32P rate = 48000 channels = 1 position = [ MONO ] } }'
        command('pw-cli', 'set-param', str(obj['id']), 'PortConfig', param)

    while time.monotonic() < deadline:
        objects = graph()
        nodes = {o['info']['props'].get('node.name'): o for o in objects if o.get('type') == 'PipeWire:Interface:Node'}
        assert capture_node in nodes and playback_node in nodes, 'Explicit endpoints missing'
        ports = [o for o in objects if o.get('type') == 'PipeWire:Interface:Port']

        def get_ports(node_id, direction):
            return [o for o in ports if int(o['info']['props']['node.id']) == node_id and o['info']['props']['port.direction'] == direction]

        source = get_ports(nodes[capture_node]['id'], 'out')
        sink = get_ports(nodes[playback_node]['id'], 'in')
        mic = get_ports(selected['pw-record']['id'], 'in')
        play = get_ports(selected['pw-play']['id'], 'out')
        if len(source) == 1 and len(sink) in (1, 2) and len(mic) == len(play) == 1:
            break
        time.sleep(.1)
    else:
        raise RuntimeError('Expected mono capture and mono/stereo playback ports missing')

    id_to_name = {o['id']: o['info']['props']['node.name'] for o in objects
                  if o.get('type') == 'PipeWire:Interface:Node'}

    def port_name(obj):
        props = obj['info']['props']
        return id_to_name[int(props['node.id'])] + ':' + props['port.name']

    pairs = [(source[0], mic[0])] + [(play[0], p) for p in sink]
    links = []
    for output, input_ in pairs:
        assert identity(media_pid)[1] == starttime, 'Media PID changed during attachment'
        command('pw-link', port_name(output), port_name(input_))
        links.append({'output_port': output['id'], 'input_port': input_['id'],
                      'output': port_name(output), 'input': port_name(input_)})
    return {'media_pid': media_pid, 'media_starttime': starttime,
            'audio_uid': expected_uid, 'helpers': {p: o['id'] for p, o in selected.items()}, 'links': links}

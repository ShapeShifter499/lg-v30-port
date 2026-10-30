#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-only
"""imsd media entry point for a prepared, temporary V30 call session.

The outer session owns PipeWire, mixer routes, network and their rollback.
This wrapper owns only its media child and links; it never dials or answers.
It preserves imsd's DTMF stdin and the media program's exit-code contract.
"""
from pathlib import Path
import hashlib
import importlib.util
import ipaddress
import json
import math
import os
import signal
import stat
import subprocess
import sys
import time
import traceback

MEDIA_SHA256 = '14a0a37f2f36cfdfd95db5629dd6b7d5d2b5d6ad27a599404e44478e183761fb'
SESSION_PATH = Path('/run/v30-call-audio/session.json')


def identity(pid):
    tail = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    return {'parent': int(tail[1]), 'start_ticks': tail[19]}


def media_arguments(args, session):
    if len(args) != 7:
        raise ValueError('Expected seven imsd-media arguments')
    local, port, peer, peer_port, payload, duration, output = args
    local_ip, peer_ip = ipaddress.ip_address(local), ipaddress.ip_address(peer)
    if str(local_ip) != session['local'] or local_ip.version != peer_ip.version:
        raise ValueError('Unexpected local address or mixed address families')
    if peer_ip.is_unspecified or peer_ip.is_multicast or peer_ip.is_loopback or peer_ip.is_link_local:
        raise ValueError('Invalid operator media peer')
    if int(port) != session['rtp_port'] or not 1 <= int(peer_port) <= 65535:
        raise ValueError('Unexpected RTP port')
    if not 0 <= int(payload) <= 127:
        raise ValueError('Invalid RTP payload type')
    seconds = float(duration)
    cap = float(session['max_media_seconds'])
    if not math.isfinite(seconds) or seconds <= 0 or not 1 <= cap <= 120:
        raise ValueError('Invalid bounded media duration')
    root = Path(session['out_dir']).resolve(strict=True)
    output_path = Path(output)
    if output_path.parent.resolve(strict=True) != root or not output_path.name.startswith('dialer_'):
        raise ValueError('Media output must remain in the private session directory')
    return [str(local_ip), str(int(port)), str(peer_ip), str(int(peer_port)),
            str(int(payload)), str(min(seconds, cap)), str(root/output_path.name)]


def signal_group(process, sig):
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def forward_media(argv, env, attach, *, stdin=None, poll_interval=.05):
    """Run one owned child; leave no helpers behind on cancellation/failure.

    `attach` is the same PID-verified connector used by the hardware bench.
    Dependency injection here is for exercising cancellation without hardware.
    """
    requested = []
    previous = {}
    child = None
    report = {'exit_code': None, 'cancelled': False, 'links': None,
              'cleanup_complete': False}

    def cancel(signum, frame):
        requested.append(signum)
        if child is not None:
            signal_group(child, signal.SIGTERM)

    for sig in [signal.SIGTERM, signal.SIGINT]:
        previous[sig] = signal.signal(sig, cancel)
    try:
        child = subprocess.Popen(argv, env=env, stdin=stdin,
                                 start_new_session=True)
        report['media_pid'] = child.pid
        if not requested:
            report['links'] = attach(child.pid)
        deadline = None
        while child.poll() is None:
            if requested:
                if deadline is None:
                    signal_group(child, signal.SIGTERM)
                    deadline = time.monotonic() + 2
                elif time.monotonic() >= deadline:
                    signal_group(child, signal.SIGKILL)
            time.sleep(poll_interval)
        report['cancelled'] = bool(requested)
        report['exit_code'] = 0 if requested else child.returncode
    except Exception as exc:
        report['error'] = repr(exc)
        # Bounded code locations only: do not include locals, SDP or media.
        report['error_stack'] = traceback.format_list(traceback.extract_tb(exc.__traceback__, limit=8))
        report['exit_code'] = 0 if requested else 1
        report['cancelled'] = bool(requested)
    finally:
        # imsd grants ten seconds to stop; bound this section to two seconds.
        if child is not None:
            signal_group(child, signal.SIGTERM)
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                signal_group(child, signal.SIGKILL)
                child.wait(timeout=1)
            # A reaped leader can still have pw-record/pw-play descendants.
            signal_group(child, signal.SIGKILL)
        report['cleanup_complete'] = True
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    return report


def trusted_file(path):
    info = path.lstat()
    assert stat.S_ISREG(info.st_mode) and info.st_uid == 0
    assert not info.st_mode & 0o022, 'Session file is writable by another user'
    assert info.st_size <= 1024 * 1024
    return path.read_bytes()


def main():
    assert os.geteuid() == 0
    session = json.loads(trusted_file(SESSION_PATH))
    assert Path('/proc/sys/kernel/random/boot_id').read_text().strip() == session['boot_id']
    assert time.monotonic() < session['expires_monotonic']
    assert session['audio_uid'] == 10000 and session['audio_user'] == 'v30'
    assert os.getppid() == session['imsd_pid']
    assert identity(os.getppid())['start_ticks'] == session['imsd_start_ticks']
    parent_program = Path(f'/proc/{os.getppid()}/cmdline').read_bytes().split(b'\0')[0]
    assert Path(os.fsdecode(parent_program)).name == 'imsd'
    assert identity(session['pipewire_pid'])['start_ticks'] == session['pipewire_start_ticks']
    assert Path('/sys/module/q6core/parameters/skip_versions').read_text().strip() == 'Y'
    assert Path('/sys/module/snd_soc_wcd934x/parameters/amic_hold_release').read_text().strip() == 'N'
    assert Path('/sys/module/snd_soc_wcd934x/parameters/tx_hw_snapshot').read_text().strip() == 'N'
    routes = Path('/proc/device-tree/sound/audio-routing').read_bytes().split(b'\0')
    pairs = list(zip(routes[0::2], routes[1::2]))
    assert (b'MIC BIAS3', b'MCLK') in pairs
    assert Path('/sys/fs/ext4/mmcblk0p2/errors_count').read_text().strip() == '0'
    media = Path(session['media_binary'])
    assert media.resolve().is_relative_to(SESSION_PATH.parent.resolve())
    assert hashlib.sha256(media.read_bytes()).hexdigest() == MEDIA_SHA256
    args = media_arguments(sys.argv[1:], session)
    socket = Path('/run/user/10000/pipewire-0')
    assert socket.is_socket() and socket.stat().st_uid == 10000
    connector = SESSION_PATH.parent/'link.py'
    assert hashlib.sha256(trusted_file(connector)).hexdigest() == session['connector_sha256']
    spec = importlib.util.spec_from_file_location('v30_media_link', connector)
    linker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(linker)
    env = os.environ.copy()
    env.update(MIC='1', PLAY='1', GAIN='1', PLAY_GAIN='1', AUDIO_USER='v30',
               PCM_DUMP='0', RTP_DUMP='0', XDG_RUNTIME_DIR='/run/user/10000',
               PIPEWIRE_RUNTIME_DIR='/run/user/10000', PIPEWIRE_REMOTE='pipewire-0',
               LD_LIBRARY_PATH=session['library_path'])
    env.pop('MIC_SRC', None)
    assert env.get('CODEC') in ['AMR-WB', 'AMR', 'PCMA', 'PCMU']
    report = forward_media([str(media), *args], env,
        lambda pid: linker.connect_media(env, pid, 'v30-call-microphone',
                                          'v30-call-speaker', 10000, timeout=4))
    # The outer session permits one call and owns the hardware daemon. Verify
    # helpers actually exited before reporting cleanup to that controller.
    report['helpers_stopped'] = all(subprocess.run(['pgrep', '-x', name],
        stdout=subprocess.DEVNULL).returncode == 1
        for name in ['imsd-media', 'pw-record', 'pw-play'])
    if not report['helpers_stopped']:
        report['cleanup_complete'] = False
        report['exit_code'] = 1
    report.update(boot_id=session['boot_id'], audio_uid=10000,
                  voice_recorded=False, sim_call_control=False)
    Path(args[-1]+'.audio-lifecycle.json').write_text(json.dumps(report, indent=2)+'\n')
    print('V30_CALL_AUDIO_RESULT', json.dumps(report), flush=True)
    return report['exit_code'] if report['exit_code'] in range(256) else 1


if __name__ == '__main__':
    sys.exit(main())

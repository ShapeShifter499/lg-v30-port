# SPDX-License-Identifier: GPL-3.0-only
"""Temporary hardware audio owner for an explicitly started IMS test session.

An outer controller must stop imsd (and its media wrapper) before close().
Importing this file does not open sound devices, modify mixers, or start services.
"""
from pathlib import Path
import grp
import hashlib
import json
import os
import platform
import pwd
import signal
import subprocess
import time


SETTINGS = [('ADC3 Volume', 12), ('AMIC MUX8', 'ADC3'), ('ADC MUX8', 'AMIC'),
            ('CDC_IF TX8 MUX', 'DEC8'), ('DEC8 Volume', 84),
            ('AIF1_CAP Mixer SLIM TX8', 1), ('MultiMedia1 Mixer SLIMBUS_0_TX', 1),
            ('Speaker Playback Volume', 8),
            ('TERT_MI2S_RX Audio Mixer MultiMedia1', 0),
            ('TERT_MI2S_RX Audio Mixer MultiMedia2', 1)]


def start_ticks(pid):
    return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]


class CallAudioSession:
    def __init__(self, root, boot_id):
        self.root = Path(root)
        assert self.root == Path('/run/v30-call-audio')
        self.boot_id = boot_id
        self.daemon = None
        self.before = {}
        self.logfile = None
        self.user_run_created = False
        self.env = None

    def command(self, args, **kwargs):
        return subprocess.run(args, capture_output=True, text=True, check=True,
                              timeout=kwargs.pop('timeout', 3), **kwargs)

    def get_control(self, name):
        text = self.command(['amixer', '-c', 'LGV30', 'cget', 'name='+name]).stdout
        return text.split('  : values=', 1)[1].splitlines()[0].strip()

    def set_control(self, name, value):
        self.command(['amixer', '-q', '-c', 'LGV30', 'cset', 'name='+name, str(value)])

    def pcm_status(self):
        return {p.parent.parent.name: p.read_text().strip()
                for p in Path('/proc/asound/card0').glob('pcm*/sub*/status')}

    def __enter__(self):
        assert os.geteuid() == 0
        assert Path('/proc/sys/kernel/random/boot_id').read_text().strip() == self.boot_id
        assert platform.release() == '7.2.0-rc2-v30-r30'
        assert self.root.is_dir() and self.root.stat().st_uid == 0
        assert not self.root.stat().st_mode & 0o022
        assert all(v == 'closed' for v in self.pcm_status().values())
        assert Path('/sys/module/q6core/parameters/skip_versions').read_text().strip() == 'Y'
        for name in ['amic_hold_release', 'tx_hw_snapshot']:
            assert Path('/sys/module/snd_soc_wcd934x/parameters', name).read_text().strip() == 'N'
        routes = Path('/proc/device-tree/sound/audio-routing').read_bytes().split(b'\0')
        assert (b'MIC BIAS3', b'MCLK') in zip(routes[0::2], routes[1::2])
        for name in ['pipewire', 'wireplumber', 'pw-play', 'pw-record', 'imsd-media']:
            assert subprocess.run(['pgrep', '-x', name], stdout=subprocess.DEVNULL).returncode == 1
        user = pwd.getpwnam('v30')
        groups = os.getgrouplist(user.pw_name, user.pw_gid)
        assert user.pw_uid == 10000 and grp.getgrnam('audio').gr_gid in groups
        self.user_run = Path('/run/user/10000')
        self.user_run_created = not self.user_run.exists()
        if self.user_run_created:
            self.user_run.mkdir(mode=0o700, parents=True)
            os.chown(self.user_run, user.pw_uid, user.pw_gid)
        assert self.user_run.stat().st_uid == user.pw_uid
        assert not (self.user_run/'pipewire-0').exists()
        assert not (self.user_run/'pipewire-0.lock').exists()
        self.env = os.environ.copy()
        self.env.update(XDG_RUNTIME_DIR=str(self.user_run),
                        PIPEWIRE_RUNTIME_DIR=str(self.user_run), PIPEWIRE_REMOTE='pipewire-0')
        self.before = {name: self.get_control(name) for name, _ in SETTINGS}
        assert self.before['AIF1_CAP Mixer SLIM TX8'] == 'off'
        assert self.before['MultiMedia1 Mixer SLIMBUS_0_TX'] == 'off'
        (self.root/'mixer-before.json').write_text(json.dumps(self.before, indent=2)+'\n')
        try:
            for name, value in SETTINGS:
                self.set_control(name, value)
            self.logfile = (self.root/'pipewire.log').open('wb')
            self.daemon = subprocess.Popen(['pipewire', '-c', str(self.root/'physical.conf')],
                env=self.env, stdin=subprocess.DEVNULL, stdout=self.logfile,
                stderr=subprocess.STDOUT, start_new_session=True,
                user=user.pw_uid, group=user.pw_gid, extra_groups=groups)
            until = time.monotonic()+3
            while not (self.user_run/'pipewire-0').is_socket():
                assert self.daemon.poll() is None
                if time.monotonic() >= until:
                    raise TimeoutError('PipeWire socket did not appear')
                time.sleep(.05)
            time.sleep(.3)
            idle = self.pcm_status()
            assert not any('RUNNING' in v for v in idle.values()), 'Audio running before a media call'
            (self.root/'audio-idle-before-call.json').write_text(json.dumps(idle, indent=2)+'\n')
            return self
        except BaseException:
            self.close()
            raise

    def arm(self, imsd_process, *, local, out_dir, media_binary, library_path,
            expires_in=300, max_media_seconds=45):
        assert self.daemon.poll() is None and imsd_process.poll() is None
        assert 1 <= expires_in <= 600 and 1 <= max_media_seconds <= 120
        session = {'boot_id': self.boot_id, 'imsd_pid': imsd_process.pid,
                   'imsd_start_ticks': start_ticks(imsd_process.pid),
                   'pipewire_pid': self.daemon.pid,
                   'pipewire_start_ticks': start_ticks(self.daemon.pid),
                   'audio_user': 'v30', 'audio_uid': 10000, 'local': local,
                   'rtp_port': 50004, 'out_dir': str(out_dir),
                   'media_binary': str(media_binary), 'library_path': str(library_path),
                   'expires_monotonic': time.monotonic()+expires_in,
                   'max_media_seconds': max_media_seconds,
                   'connector_sha256': hashlib.sha256((self.root/'link.py').read_bytes()).hexdigest()}
        temporary = self.root/'session.tmp'
        temporary.write_text(json.dumps(session, indent=2)+'\n')
        temporary.chmod(0o600)
        os.replace(temporary, self.root/'session.json')
        return session

    def close(self):
        (self.root/'session.json').unlink(missing_ok=True)
        errors = []
        if self.daemon is not None:
            try:
                if self.daemon.poll() is None:
                    self.daemon.terminate()
                    try:
                        self.daemon.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(self.daemon.pid, signal.SIGKILL)
                        self.daemon.wait(timeout=2)
            except Exception as exc:
                errors.append({'step':'stop-pipewire','error':repr(exc)})
        if self.logfile is not None:
            self.logfile.close()
        # Restore each control independently; one failure cannot skip the rest.
        for name, _ in reversed(SETTINGS):
            if name not in self.before:
                continue
            try:
                self.set_control(name, self.before[name])
            except Exception as exc:
                errors.append({'step':'restore-control','name':name,'error':repr(exc)})
        controls = {}
        for name, old in self.before.items():
            try:
                controls[name] = self.get_control(name) == old
            except Exception as exc:
                controls[name] = False
                errors.append({'step':'read-control','name':name,'error':repr(exc)})
        pcm = self.pcm_status()
        if self.user_run_created:
            for name in ['pipewire-0', 'pipewire-0.lock']:
                (self.user_run/name).unlink(missing_ok=True)
            try:
                self.user_run.rmdir()
            except OSError:
                pass
        result = {'controls':controls, 'errors':errors, 'pcm':pcm,
                  'passed':not errors and all(controls.values()) and
                           all(v == 'closed' for v in pcm.values())}
        (self.root/'audio-cleanup.json').write_text(json.dumps(result, indent=2)+'\n')
        return result

    def __exit__(self, exc_type, exc, traceback):
        result = self.close()
        if not result['passed'] and exc is None:
            raise RuntimeError('Audio rollback incomplete; inspect audio-cleanup.json')

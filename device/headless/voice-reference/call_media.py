#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-only
"""每次通话独占音频；IMS 父进程身份替代一次性测试的到期授权。"""
from pathlib import Path
import ctypes, fcntl, hashlib, ipaddress, json, math, os, signal, stat, sys, time
from audio_session import CallAudioSession
from media_helpers import forward_media
from mobile_common import start_ticks
from link import connect_media

BASE = Path('/opt/v30-mobile')
ROOT = Path('/run/v30-call-audio')
OWNER = Path('/run/v30-ims/owner.json')


def read_owner():
    info = OWNER.lstat()
    assert stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_mode & 0o077 == 0
    owner = json.loads(OWNER.read_text())
    parent = os.getppid()
    assert parent == owner['imsd_pid'] and start_ticks(parent) == owner['imsd_start_ticks']
    assert Path('/proc/sys/kernel/random/boot_id').read_text().strip() == owner['boot_id']
    assert Path(f'/proc/{parent}/exe').resolve() == BASE/'bin/imsd'
    assert hashlib.sha256((BASE/'bin/imsd').read_bytes()).hexdigest() == owner['imsd_sha256']
    return owner


def media_arguments(args, owner):
    if len(args) != 7:
        raise ValueError('Expected seven media arguments')
    local, port, peer, peer_port, payload, duration, output = args
    local_ip, peer_ip = ipaddress.ip_address(local), ipaddress.ip_address(peer)
    if str(local_ip) != owner['local'] or local_ip.version != peer_ip.version:
        raise ValueError('Unexpected media address family/local address')
    if peer_ip.is_unspecified or peer_ip.is_multicast or peer_ip.is_loopback or peer_ip.is_link_local:
        raise ValueError('Invalid media peer')
    if int(port) != owner['rtp_port'] or not 1 <= int(peer_port) <= 65535 or not 0 <= int(payload) <= 127:
        raise ValueError('Invalid media ports or payload')
    seconds = float(duration)
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError('Invalid duration')
    out = Path(output)
    if out.parent != Path('/run/v30-ims') or not out.name.startswith('dialer_') or '/' in out.name:
        raise ValueError('Output must remain in private RAM directory')
    return [str(local_ip), str(int(port)), str(peer_ip), str(int(peer_port)),
            str(int(payload)), str(min(seconds, 86400)), str(out)]


def interrupted(signum, frame):
    raise InterruptedError('IMS/audio session stopped')


def prepare_audio_root():
    ROOT.mkdir(mode=0o711, exist_ok=True)
    assert ROOT.stat().st_uid == 0 and ROOT.stat().st_mode & 0o022 == 0
    # umask 0077 would otherwise make this 0700 and prevent the v30-owned
    # PipeWire process from reading its fixed physical configuration.
    ROOT.chmod(0o711)
    config = ROOT/'physical.conf'
    if config.exists() or config.is_symlink():
        assert config.is_symlink() and config.resolve() == BASE/'libexec/physical.conf'
    else:
        config.symlink_to(BASE/'libexec/physical.conf')


def run_audio(owner, args):
    audio = CallAudioSession(ROOT, owner['boot_id'])
    report = None
    try:
        audio.__enter__()
        read_owner()
        env = os.environ.copy()
        env.update(MIC='1', PLAY='1', GAIN='1', PLAY_GAIN='1', AUDIO_USER='v30',
            PCM_DUMP='0', RTP_DUMP='0', XDG_RUNTIME_DIR='/run/user/10000',
            PIPEWIRE_RUNTIME_DIR='/run/user/10000', PIPEWIRE_REMOTE='pipewire-0',
            LD_LIBRARY_PATH=str(BASE/'lib'))
        env.pop('MIC_SRC', None)
        assert env.get('CODEC') in ['AMR-WB', 'AMR', 'PCMA', 'PCMU']
        report = forward_media([str(BASE/'bin/imsd-media'), *args], env,
            lambda pid: connect_media(env, pid, 'v30-call-microphone', 'v30-call-speaker', 10000, timeout=4))
        return report['exit_code'] if report['exit_code'] in range(256) else 1
    finally:
        # close() also rolls back a partially initialized graph/mixer.
        cleanup = audio.close()
        if report is None: report = {'exit_code': 1, 'cancelled': True}
        report.update(audio_cleanup=cleanup, boot_id=owner['boot_id'], voice_exported=False)
        Path(args[-1]+'.audio-lifecycle.json').write_text(json.dumps(report, indent=2)+'\n')
        if not cleanup['passed']: raise RuntimeError('Audio cleanup incomplete')


def main():
    assert os.geteuid() == 0
    os.umask(0o077)
    parent = os.getppid()
    # Covers an imsd crash as well as a normal BYE. Check again after prctl
    # so a death in the installation window cannot leave orphan audio.
    for sig in (signal.SIGTERM, signal.SIGINT): signal.signal(sig, interrupted)
    libc = ctypes.CDLL(None, use_errno=True)
    assert libc.prctl(1, signal.SIGTERM, 0, 0, 0) == 0
    assert os.getppid() == parent and parent > 1
    end = time.monotonic() + 2
    while not OWNER.exists() and time.monotonic() < end: time.sleep(.02)
    owner = read_owner()
    args = media_arguments(sys.argv[1:], owner)
    lock = Path('/run/v30-call-audio.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    prepare_audio_root()
    return run_audio(owner, args)


if __name__ == '__main__':
    raise SystemExit(main())

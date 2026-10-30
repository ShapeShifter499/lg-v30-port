#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-only
"""OpenRC 管理的持久 IMS 服务；不拨号、不自动接听、不发短信。"""
from pathlib import Path
import ctypes, fcntl, hashlib, json, os, platform, signal, subprocess, time
from mobile_common import atomic_json, hold_deadline, runtime_environment, start_ticks
from gvariant_json import parse_gvariant

BASE = Path('/opt/v30-mobile')
RUN = Path('/run/v30-ims')
STATE = Path('/var/lib/v30-mobile')
STOP = False
CHILD = None
LOCKED = False


def stop(signum, frame):
    global STOP
    STOP = True
    if CHILD is not None and CHILD.poll() is None:
        try: os.killpg(CHILD.pid, signal.SIGTERM)
        except ProcessLookupError: pass


def command(args, timeout=20, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, **kwargs)


def child_setup():
    parent = os.getppid()
    assert ctypes.CDLL(None).prctl(1, signal.SIGTERM, 0, 0, 0) == 0
    assert parent > 1 and os.getppid() == parent


def remove_firewall():
    old = command(['nft', '-j', '-a', 'list', 'chain', 'inet', 'filter', 'input'])
    if old.returncode:
        return
    for item in json.loads(old.stdout)['nftables']:
        rule = item.get('rule', {})
        if rule.get('comment') == 'v30-ims-owned':
            command(['nft', 'delete', 'rule', 'inet', 'filter', 'input', 'handle', str(rule['handle'])], check=True)
    command(['nft', 'flush', 'chain', 'inet', 'filter', 'v30_ims'])
    command(['nft', 'delete', 'chain', 'inet', 'filter', 'v30_ims'])


def stop_child():
    if CHILD is None:
        return
    if CHILD.poll() is None:
        try: os.killpg(CHILD.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: CHILD.wait(timeout=40)
        except subprocess.TimeoutExpired:
            os.killpg(CHILD.pid, signal.SIGKILL); CHILD.wait(timeout=3)


def preserve_hold(boot):
    prior = STATE/'backoff.json'
    record = json.loads(prior.read_text()) if prior.exists() else {}
    hold = STATE/'holds.json'
    if hold.exists():
        until = hold_deadline(json.loads(hold.read_text()), boot=boot,
            uptime=float(Path('/proc/uptime').read_text().split()[0]), epoch=time.time(),
            previous=float(record.get('not_before_epoch', 0)))
        if until > float(record.get('not_before_epoch', 0)):
            atomic_json(prior, {'not_before_epoch': until})


def main():
    global CHILD, LOCKED
    assert os.geteuid() == 0 and platform.release() == '7.2.0-rc2-v30-r30'
    os.umask(0o077)
    RUN.mkdir(mode=0o700, exist_ok=True); STATE.mkdir(mode=0o700, exist_ok=True)
    lock = (RUN/'supervisor.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    LOCKED = True
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    for sig in (signal.SIGINT, signal.SIGTERM): signal.signal(sig, stop)
    environment = os.environ.copy()
    environment.update(LD_LIBRARY_PATH=str(BASE/'lib'), IMS_PROFILE_ID='2', IMS_APN='ims',
        IMS_IP_TYPE='ipv6', IMSD_PCSCF=str(BASE/'bin/imsd-pcscf'), IMSD_ENV='/etc/v30-ims.env')
    environment.pop('PCSCF', None)
    while not STOP:
        # Cross-boot refusal waits require a meaningful wall clock. Data/NTP
        # start independently, so this never blocks data or the TTY boot.
        previous = STATE/'backoff.json'
        until = json.loads(previous.read_text()).get('not_before_epoch', 0) if previous.exists() else 0
        if time.time() < max(1793376000, until):
            atomic_json(RUN/'status.json', {'boot_id': boot, 'state': 'waiting-clock-or-backoff'})
            time.sleep(2); continue
        atomic_json(RUN/'status.json', {'boot_id': boot, 'state': 'bringing-up-ims-pdn'})
        # The upstream script is idempotent: it reuses profile 2, protects
        # the IMS netdev against RA default routes and rediscovers P-CSCF.
        CHILD = subprocess.Popen(['/bin/sh', str(BASE/'libexec/ims-pdn-up.sh')],
            env=environment, stdout=(RUN/'pdn.log').open('w'), stderr=subprocess.STDOUT,
            start_new_session=True, preexec_fn=child_setup)
        while CHILD.poll() is None and not STOP: time.sleep(.2)
        if STOP: break
        if CHILD.returncode:
            CHILD = None
            atomic_json(RUN/'status.json', {'boot_id': boot, 'state': 'pdn-retry'})
            for _ in range(120):
                if STOP: break
                time.sleep(1)
            continue
        derived = runtime_environment(Path('/run/imsd.env').read_text())
        if 'IMSD_IDLE' in derived:
            atomic_json(RUN/'status.json', {'boot_id': boot, 'state': 'idle', 'reason': derived['IMSD_IDLE']})
            while not STOP: time.sleep(1)
            break
        env = environment.copy(); env.update(derived)
        env.update(IPSEC_OFFER_PROFILE='lg-generic', STATE_FILE=str(STATE/'imsreg.state'),
            HOLDS_FILE=str(STATE/'holds.json'), OUT_DIR=str(RUN), DUMP_DIR=str(RUN),
            DUMP_SIP='0', PCM_DUMP='0', RTP_DUMP='0', TRACE_CALL_SIP='0',
            IMSD_MEDIA=str(BASE/'libexec/call_media.py'), AUDIO_USER='v30', MIC='1', PLAY='1',
            GAIN='1', PLAY_GAIN='1')
        for key in ['IMSD_IDLE', 'RESUME', 'SIP_TRANSPORT', 'USER_AGENT', 'EALG',
                    'INITIAL_REGISTER_ROUTE', 'MIC_SRC', 'CODEC', 'PRECOND', 'PCSCF']:
            env.pop(key, None)
        # Firewall is restricted to this IMS netdev/address and SIP ports;
        # the upstream helper's broad qmapmux rule is not installed.
        iface, local = derived['DEV'], derived['LOCAL']
        peers = derived.get('PCSCF_DISCOVERED', '').split(',')
        peers = [p for p in peers if p]
        assert peers
        peer_set = '{ ' + ', '.join(peers) + ' }'
        # Rules must be in the existing input chain: an earlier base-chain
        # accept cannot override a later base-chain drop.
        chain = 'v30_ims'
        remove_firewall()
        rules = f'''add chain inet filter {chain}
add rule inet filter {chain} iifname "{iface}" ip6 saddr {peer_set} meta l4proto esp accept
add rule inet filter {chain} iifname "{iface}" ip6 saddr {peer_set} meta l4proto {{ tcp, udp }} th dport {{ 45061, 45062 }} accept
add rule inet filter {chain} iifname "{iface}" ip6 daddr {local} udp dport 50004 accept
insert rule inet filter input jump {chain} comment "v30-ims-owned"
'''
        command(['nft', '-f', '-'], input=rules, check=True)
        # The child waits for this root-owned receipt before opening audio.
        with (RUN/'imsd.log').open('a') as log:
            CHILD = subprocess.Popen([str(BASE/'bin/imsd')], env=env, stdout=log,
                stderr=subprocess.STDOUT, start_new_session=True, preexec_fn=child_setup)
            atomic_json(RUN/'owner.json', {'boot_id': boot, 'imsd_pid': CHILD.pid,
                'imsd_start_ticks': start_ticks(CHILD.pid), 'local': local, 'rtp_port': 50004,
                'imsd_sha256': hashlib.sha256((BASE/'bin/imsd').read_bytes()).hexdigest()})
            while CHILD.poll() is None and not STOP:
                preserve_hold(boot)
                status = command(['gdbus', 'call', '--system', '--dest', 'net.catcrafts.IMS1',
                    '--object-path', '/net/catcrafts/IMS1', '--method', 'net.catcrafts.IMS1.GetStatus'], timeout=8)
                try: registered = status.returncode == 0 and parse_gvariant(status.stdout)[0].get('registered') is True
                except (ValueError, KeyError, IndexError): registered = False
                atomic_json(RUN/'status.json', {'boot_id': boot, 'state': 'running', 'registered': registered})
                if log.tell() > 2*1024*1024 or (RUN/'imsd.log').stat().st_size > 2*1024*1024:
                    os.ftruncate(log.fileno(), 0)
                stats = sorted(RUN.glob('dialer_*'), key=lambda p: p.stat().st_mtime)
                for stale in stats[:-64]: stale.unlink()
                for _ in range(5):
                    if STOP or CHILD.poll() is not None: break
                    time.sleep(1)
            stop_child()
            CHILD = None
            preserve_hold(boot)
            (RUN/'owner.json').unlink(missing_ok=True)
        if not STOP:
            for _ in range(120):
                if STOP: break
                time.sleep(1)
    if CHILD is not None and CHILD.poll() is None:
        CHILD.terminate(); CHILD.wait(timeout=35)
    (RUN/'owner.json').unlink(missing_ok=True)
    atomic_json(RUN/'status.json', {'boot_id': boot, 'state': 'stopped'})
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    finally:
        if LOCKED:
            stop_child()
            (RUN/'owner.json').unlink(missing_ok=True)
            remove_firewall()

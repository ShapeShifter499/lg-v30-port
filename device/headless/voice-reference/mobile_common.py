# SPDX-License-Identifier: GPL-3.0-only
"""V30 开机集成的纯数据校验与原子状态写入。"""
from pathlib import Path
import ipaddress, json, os, shlex

ENV_KEYS = {'DEV', 'LOCAL', 'PCSCF_DISCOVERED', 'PCSCF_DISCOVERY', 'IMSD_IDLE'}


def runtime_environment(text):
    result = {}
    for line in text.splitlines():
        if not line or line.startswith('#'):
            continue
        key, value = line.split('=', 1)
        if key not in ENV_KEYS or key in result:
            raise ValueError('Unexpected or duplicate runtime key')
        fields = shlex.split(value) if value else ['']
        if len(fields) != 1:
            raise ValueError('Invalid runtime value')
        result[key] = fields[0]
    if 'IMSD_IDLE' not in result:
        ipaddress.IPv6Address(result['LOCAL'])
        dev = result['DEV']
        if not dev.startswith('qmapmux') or not dev.replace('.', '').replace('qmapmux', '').isdigit():
            raise ValueError('Unexpected IMS interface')
        for address in filter(None, result.get('PCSCF_DISCOVERED', '').split(',')):
            ipaddress.IPv6Address(address)
    return result


def hold_deadline(hold, *, boot, uptime, epoch, previous=0):
    """保留跨进程/开机的运营商等待；不把旧 boot 的 uptime 用于新 boot。"""
    if hold.get('boot') != boot:
        return previous
    elapsed = max(0, uptime - float(hold.get('written_at', 0)))
    remaining = max(0, float(hold.get('hold', 0)) - elapsed,
                    float(hold.get('fresh_hold', 0)) - elapsed)
    return max(previous, epoch + remaining) if remaining else previous


def atomic_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, path)


def start_ticks(pid):
    return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]

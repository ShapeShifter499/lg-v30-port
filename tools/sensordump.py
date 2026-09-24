#!/usr/bin/env python3
"""Dump every mm-camera2 register list in a sensor library.

Lists are arrays of {u16 addr, u16 data, u32 delay}, zero-terminated and
zero-padded; each is preceded either by zeroes or by the previous list's
trailer.  Prints '# @offset n' then 'addr=data[+delay]' pairs."""
import struct, sys
b = open(sys.argv[1], 'rb').read()
n, i, seen = len(b) - 8, 0, 0
while i < n:
    a, d, dl = struct.unpack_from('<HHI', b, i)
    if a < 0x0100 or dl > 10000 or i < seen:
        i += 4; continue
    run, j = [], i
    while j < n:
        a, d, dl = struct.unpack_from('<HHI', b, j)
        if (a, d, dl) == (0, 0, 0) or a < 0x0100 or dl > 10000: break
        run.append((a, d, dl)); j += 8
    tail_zero = b[j:j + 64] == b'\0' * 64
    if len(run) >= 5 and tail_zero:
        print(f"# @0x{i:x} {len(run)}")
        print(' '.join(f"{a:04x}={d:02x}" + (f"+{dl}" if dl else "") for a, d, dl in run))
        seen = j; i = j
    else:
        i += 4

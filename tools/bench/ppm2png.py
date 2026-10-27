#!/usr/bin/env python3
"""ppm2png.py in.ppm out.png [scale]  -- P6 8-bit to PNG, integer downscale"""
import sys, zlib, struct
src, dst = sys.argv[1], sys.argv[2]
k = int(sys.argv[3]) if len(sys.argv) > 3 else 1
d = open(src, 'rb').read()
parts, pos = [], 0
while len(parts) < 4:
    while d[pos:pos+1].isspace(): pos += 1
    if d[pos:pos+1] == b'#':
        pos = d.index(b'\n', pos) + 1; continue
    e = pos
    while not d[e:e+1].isspace(): e += 1
    parts.append(d[pos:e]); pos = e
pos += 1
w, h, mx = int(parts[1]), int(parts[2]), int(parts[3])
px = d[pos:pos + w * h * 3]
W, H = w // k, h // k
rows = []
for y in range(H):
    r = bytearray(b'\0')
    base = y * k * w * 3
    row = px[base:base + w * 3]
    if k == 1:
        r += row
    else:
        for x in range(W):
            i = x * k * 3
            r += row[i:i+3]
    rows.append(bytes(r))
def chunk(t, b): return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 6)) + chunk(b'IEND', b'')
open(dst, 'wb').write(png)
print(W, H)

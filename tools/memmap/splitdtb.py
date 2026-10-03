import struct, sys, os, gzip, zlib
img, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
d = open(img, "rb").read()
# Android boot header v0
magic = d[:8]; assert magic == b"ANDROID!"
ksize, kaddr, rsize, raddr, ssize, saddr, tags, page = struct.unpack_from("<8I", d, 8)
kernel = d[page:page + ksize]
open(os.path.join(out, "kernel"), "wb").write(kernel)
n = 0; i = 0
while True:
    i = kernel.find(b"\xd0\x0d\xfe\xed", i)
    if i < 0: break
    tot = struct.unpack_from(">I", kernel, i + 4)[0]
    if 0x100 < tot < 0x400000 and i + tot <= len(kernel):
        open(os.path.join(out, f"dtb{n:02d}.dtb"), "wb").write(kernel[i:i + tot]); n += 1; i += tot
    else:
        i += 4
print(f"kernel {ksize:#x} bytes, {n} dtbs")

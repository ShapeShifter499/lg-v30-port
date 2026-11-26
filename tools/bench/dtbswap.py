#!/usr/bin/env python3
"""dtbswap.py <base boot.img> <new.dtb> <out boot.img>
Replace the DTB appended to a header-v0 boot.img kernel; everything else byte-identical."""
import struct, subprocess, sys, tempfile, os
base, dtb, out = sys.argv[1:4]
with tempfile.TemporaryDirectory() as t:
    args = subprocess.run(["unpack_bootimg", "--boot_img", base, "--out", t, "--format=mkbootimg"],
                          capture_output=True, text=True, check=True).stdout
    k = open(os.path.join(t, "kernel"), "rb").read()
    i = k.find(b"\xd0\x0d\xfe\xed")
    while i >= 0 and i + struct.unpack_from(">I", k, i + 4)[0] != len(k):
        i = k.find(b"\xd0\x0d\xfe\xed", i + 4)
    assert i > 0, "no appended dtb at end of kernel"
    open(os.path.join(t, "kernel"), "wb").write(k[:i] + open(dtb, "rb").read())
    import shlex
    subprocess.run(["mkbootimg"] + shlex.split(args) + ["-o", out], check=True, cwd=os.path.dirname(t) or ".")
print("wrote", out)

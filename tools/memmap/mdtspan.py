import struct, sys
for p in sys.argv[1:]:
    d = open(p, "rb").read()
    assert d[:4] == b"\x7fELF"
    cls = d[4]
    if cls == 1:
        phoff, = struct.unpack_from("<I", d, 28); phentsize, phnum = struct.unpack_from("<HH", d, 42)
        segs = [struct.unpack_from("<IIIIIIII", d, phoff + i * phentsize) for i in range(phnum)]
        segs = [(s[0], s[3], s[5], s[6]) for s in segs]  # type, paddr, memsz, flags
    else:
        phoff, = struct.unpack_from("<Q", d, 32); phentsize, phnum = struct.unpack_from("<HH", d, 54)
        segs = []
        for i in range(phnum):
            t, fl, off, va, pa, fs, ms, al = struct.unpack_from("<IIQQQQQQ", d, phoff + i * phentsize)
            segs.append((t, pa, ms, fl))
    load = [s for s in segs if s[0] == 1 and ((s[3] >> 24) & 7) != 2 and s[2]]
    lo = min(s[1] for s in load); hi = max(s[1] + s[2] for s in load)
    reloc = any((s[3] >> 27) & 1 for s in load)
    print(f"{p.split('/')[-1]:16} phys {lo:#010x}-{hi:#010x} span {hi-lo:#09x} ({(hi-lo)/1048576:.2f} MiB) relocatable={reloc} loads={len(load)}")

#!/usr/bin/env python3
"""Merge a Qualcomm split MDT firmware (adsp.mdt + adsp.bNN) into a single
ELF loadable by standard ELF tools (Ghidra, objdump, readelf).

The .mdt holds the ELF header + program headers (+ hash/verification tail).
Each non-empty LOAD segment's data lives in adsp.b{index} at the segment's
p_offset (index 1-based: phdr 1 -> adsp.b01, etc.). Empty-filesz segments
(b07/b10 here) have no file. We rebuild one file: zero-filled to the max
(p_offset + p_filesz), with the mdt at 0 and each bNN placed at its p_offset.
"""
import os, struct, sys

mdt = sys.argv[1]
out = sys.argv[2]
base = os.path.dirname(mdt)
name = os.path.basename(mdt)[: -len(".mdt")]  # e.g. "adsp"

with open(mdt, "rb") as f:
    mdt_bytes = f.read()

assert mdt_bytes[:4] == b"\x7fELF", "not an ELF"
e_phoff = struct.unpack_from("<I", mdt_bytes, 28)[0]
e_phentsize = struct.unpack_from("<H", mdt_bytes, 42)[0]
e_phnum = struct.unpack_from("<H", mdt_bytes, 44)[0]

phdrs = []
for i in range(e_phnum):
    off = e_phoff + i * e_phentsize
    p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
        struct.unpack_from("<IIIIIIII", mdt_bytes, off)
    phdrs.append((p_type, p_offset, p_filesz))

total = max(p_offset + p_filesz for _, p_offset, p_filesz in phdrs)
merged = bytearray(total)

merged[0:len(mdt_bytes)] = mdt_bytes

for idx, (p_type, p_offset, p_filesz) in enumerate(phdrs):
    if p_type != 1 or p_filesz == 0:  # PT_LOAD only, skip empty
        continue
    bfile = os.path.join(base, f"{name}.b{idx:02d}")
    if not os.path.exists(bfile):
        print(f"MISSING {bfile} for phdr {idx} (offset 0x{p_offset:x} "
              f"filesz 0x{p_filesz:x})")
        sys.exit(1)
    with open(bfile, "rb") as f:
        data = f.read()
    assert len(data) == p_filesz, \
        f"{bfile}: size {len(data)} != phdr filesz {p_filesz}"
    merged[p_offset:p_offset + p_filesz] = data
    print(f"phdr {idx:2d} <- {os.path.basename(bfile):10s} "
          f"@0x{p_offset:07x} ({p_filesz} bytes)")

with open(out, "wb") as f:
    f.write(merged)
print(f"merged -> {out} ({total} bytes)")

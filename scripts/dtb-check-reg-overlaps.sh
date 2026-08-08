#!/usr/bin/env bash
# Static check: do any two /soc@0 nodes claim overlapping MMIO?
#
# Mainline gives each device its own platform device, and
# devm_platform_ioremap_resource() calls request_mem_region(), so two
# nodes whose windows overlap will see the second one fail -EBUSY. The
# driver usually just... does not probe, and whatever depended on it
# quietly never appears. That failure is close to invisible at runtime.
#
# It cost two boots on 2026-08-07:
#   a1noc  0x1660000+0x60000 swallowed the ANOC1 SMMU at 0x1680000
#   a2noc  0x1700000+0x60000 swallowed mnoc at 0x1740000
# Both came from copying downstream's window sizes, which are fine there
# because its msm-bus driver maps the whole bus as ONE device.
#
# Run this on any DTB before booting it. It is static, free, and would
# have caught both.
#
#   usage: dtb-check-reg-overlaps.sh [path/to.dtb]
#
# Exit 0 = clean (or only known-benign overlaps), 1 = real overlap found.
set -uo pipefail
DTB="${1:-}"
[[ -n "$DTB" && -r "$DTB" ]] || { echo "usage: $0 <dtb>"; exit 2; }
command -v fdtget >/dev/null || { echo "need fdtget (device-tree-compiler)"; exit 2; }

DTB="$DTB" python3 - <<'PY'
import os, subprocess, sys, re
D = os.environ["DTB"]

def fdt(*a):
    return subprocess.run(["fdtget", D, *a], capture_output=True, text=True)

kids = fdt("-l", "/soc@0").stdout.split()
regs = []
for k in kids:
    o = fdt("-t", "x", f"/soc@0/{k}", "reg")
    if o.returncode:
        continue
    v = o.stdout.split()
    if len(v) % 2:
        continue                      # not simple (base,size) pairs
    for i in range(0, len(v), 2):
        try:
            b, s = int(v[i], 16), int(v[i + 1], 16)
        except ValueError:
            continue
        if s == 0 or b == 0:
            continue
        regs.append((k, b, b + s - 1))

regs.sort(key=lambda r: r[1])

def benign(a, b):
    # Same QUP hardware exposed as either i2c or spi at one address; at
    # most one is ever enabled, so they cannot collide.
    x, y = sorted((a[0].split('@')[0], b[0].split('@')[0]))
    same_addr = a[1] == b[1]
    return same_addr and x == "i2c" and y == "spi"

real, skipped = [], 0
for i, a in enumerate(regs):
    for b in regs[i + 1:]:
        if b[1] > a[2]:
            break
        if a[2] < b[1] or a[1] > b[2]:
            continue
        if benign(a, b):
            skipped += 1
        else:
            real.append((a, b))

print(f"  scanned {len(regs)} reg ranges across {len(kids)} /soc@0 nodes")
print(f"  benign i2c/spi alias pairs skipped: {skipped}")
if not real:
    print("  RESULT: PASS - no overlapping MMIO windows")
    sys.exit(0)
print(f"  RESULT: FAIL - {len(real)} real overlap(s)")
for a, b in real:
    print(f"    {a[0]:<28} 0x{a[1]:08x}-0x{a[2]:08x}")
    print(f"    {b[0]:<28} 0x{b[1]:08x}-0x{b[2]:08x}")
    print()
print("  A node whose window is swallowed by another will fail -EBUSY at")
print("  probe and silently not appear. Shrink the oversized one to what")
print("  its driver actually maps.")
sys.exit(1)
PY

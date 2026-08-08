#!/usr/bin/env bash
# Static check: do any two nodes claim overlapping memory?
#
# Two independent address spaces get checked, because both have bitten us
# and both fail quietly.
#
# /soc@0 -- MMIO windows.
#   Mainline gives each device its own platform device, and
#   devm_platform_ioremap_resource() calls request_mem_region(), so two
#   nodes whose windows overlap will see the second one fail -EBUSY. The
#   driver usually just... does not probe, and whatever depended on it
#   quietly never appears. That failure is close to invisible at runtime.
#
#   It cost two boots on 2026-08-07:
#     a1noc  0x1660000+0x60000 swallowed the ANOC1 SMMU at 0x1680000
#     a2noc  0x1700000+0x60000 swallowed mnoc at 0x1740000
#   Both came from copying downstream's window sizes, which are fine there
#   because its msm-bus driver maps the whole bus as ONE device.
#
# /reserved-memory -- carve-outs in DDR.
#   Firmware for the modem, ADSP, SLPI, GPU zap shader, WLAN and IPA is
#   loaded to fixed physical addresses, and OEM layouts differ from the
#   generic SoC dtsi. Overlap two carve-outs and one subsystem silently
#   scribbles on another's image; the symptom is an authentication
#   failure or a hang with nothing useful logged.
#
#   Added 2026-08-08 after enabling joan's modem: LG's layout moves
#   mpss/adsp/venus/mba as a chain, and a first draft of that patch gave
#   slpi_mem LG's full extent, which swallowed ipa_fw_mem. This check
#   caught it before the boot.
#
# Run this on any DTB before booting it. It is static, free, and would
# have caught all three.
#
#   usage: dtb-check-reg-overlaps.sh [path/to.dtb]
#
# Exit 0 = clean (or only known-benign overlaps), 1 = real overlap found,
# 2 = the check could not be run (bad args, missing tool, or too few
# regions parsed to be meaningful -- see the guard below).
set -uo pipefail
DTB="${1:-}"
[[ -n "$DTB" && -r "$DTB" ]] || { echo "usage: $0 <dtb>"; exit 2; }
command -v fdtget >/dev/null || { echo "need fdtget (device-tree-compiler)"; exit 2; }

DTB="$DTB" python3 - <<'PY'
import os, subprocess, sys
D = os.environ["DTB"]

def fdt(*a):
    return subprocess.run(["fdtget", D, *a], capture_output=True, text=True)

def collect(parent, cells):
    """Return [(name, start, end)] for children of `parent`.

    `cells` is how many 32-bit words make up one (address, size) pair:
    2 for the flat /soc@0 windows, 4 for /reserved-memory, which is
    #address-cells = <2> #size-cells = <2>.
    """
    kids = fdt("-l", parent).stdout.split()
    out = []
    for k in kids:
        o = fdt("-t", "x", f"{parent}/{k}", "reg")
        if o.returncode:
            continue                      # size-only node, or no reg at all
        v = o.stdout.split()
        if not v or len(v) % cells:
            continue
        for i in range(0, len(v), cells):
            try:
                if cells == 2:
                    b, s = int(v[i], 16), int(v[i + 1], 16)
                else:
                    b = (int(v[i], 16) << 32) | int(v[i + 1], 16)
                    s = (int(v[i + 2], 16) << 32) | int(v[i + 3], 16)
            except ValueError:
                continue
            if s == 0 or b == 0:
                continue
            out.append((k, b, b + s - 1))
    return kids, sorted(out, key=lambda r: r[1])

def benign(a, b):
    # Same QUP hardware exposed as either i2c or spi at one address; at
    # most one is ever enabled, so they cannot collide.
    x, y = sorted((a[0].split('@')[0], b[0].split('@')[0]))
    return a[1] == b[1] and x == "i2c" and y == "spi"

def scan(regs, allow_benign):
    """regs is sorted by start. For each region, compare against every
    later one and stop as soon as one starts past its end -- everything
    after that starts later still. That covers all pairs exactly once."""
    real, skipped = [], 0
    for i, a in enumerate(regs):
        for b in regs[i + 1:]:
            if b[1] > a[2]:
                break
            if a[2] < b[1] or a[1] > b[2]:
                continue
            if allow_benign and benign(a, b):
                skipped += 1
            else:
                real.append((a, b))
    return real, skipped

soc_kids, soc = collect("/soc@0", 2)
rm_kids,  rm  = collect("/reserved-memory", 4)

# Guard. An empty or near-empty parse reports "no overlaps" and looks
# exactly like a pass, which is how a first version of this check
# green-lit a DTB that had never been built. Refuse to answer instead.
if len(soc) < 20 or len(rm) < 5:
    print(f"  GUARD TRIPPED: parsed {len(soc)} /soc@0 windows from "
          f"{len(soc_kids)} nodes and {len(rm)} reserved-memory regions "
          f"from {len(rm_kids)} nodes.")
    print("  That is too few to be a real device tree. The check did NOT run.")
    print("  Usually means the DTB is missing, truncated, or not the one you think.")
    sys.exit(2)

soc_real, soc_skipped = scan(soc, allow_benign=True)
rm_real,  _           = scan(rm,  allow_benign=False)

print(f"  /soc@0:           {len(soc)} windows across {len(soc_kids)} nodes"
      f" ({soc_skipped} benign i2c/spi alias pairs skipped)")
print(f"  /reserved-memory: {len(rm)} regions across {len(rm_kids)} nodes")

if not soc_real and not rm_real:
    print("  RESULT: PASS - no overlapping MMIO windows or memory carve-outs")
    sys.exit(0)

print(f"  RESULT: FAIL - {len(soc_real)} MMIO, {len(rm_real)} reserved-memory")
for label, pairs, note in (
        ("MMIO", soc_real,
         "A node whose window is swallowed by another will fail -EBUSY at\n"
         "  probe and silently not appear. Shrink the oversized one to what\n"
         "  its driver actually maps."),
        ("reserved-memory", rm_real,
         "Two subsystems given the same DDR will overwrite each other's\n"
         "  firmware. Check the loaded image's own p_paddr (readelf -l on\n"
         "  the .mdt) before trusting either the OEM or the generic layout.")):
    if not pairs:
        continue
    print(f"\n  {label}:")
    for a, b in pairs:
        print(f"    {a[0]:<28} 0x{a[1]:08x}-0x{a[2]:08x}")
        print(f"    {b[0]:<28} 0x{b[1]:08x}-0x{b[2]:08x}")
        print()
    print("  " + note)
sys.exit(1)
PY

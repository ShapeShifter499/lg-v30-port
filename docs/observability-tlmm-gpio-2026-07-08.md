# Post-reset observability and TLMM/GPIO breakthrough — 2026-07-08

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-08

## Summary

The higher-value "observability before more fixes" path worked.
LineageOS' mounted `/sys/fs/pstore` stayed empty/misleading, but the raw
`pstore` partition was readable from LineageOS root with a read-only `dd`. The
first 256 KiB snapshot preserved the previous mainline ramoops console from K042.
That console showed K042 did **not** reach the SMMU cfg-probe path as a valid
SMMU oracle; it died much earlier in MSM8998 TLMM/GPIO registration.

The important pstore clue:

- K042 pstore: `Linux version ... #64 ...`, `ramoops: using 0x80000@0xb0000000`.
- Panic at ~0.073s: `Asynchronous SError Interrupt`.
- Stack: `gpiochip_add_data_with_key()` → `devm_gpiochip_add_data_with_key()` →
  `msm_pinctrl_probe()` → `msm8998_pinctrl_probe()`.
- Therefore the old K042 conclusion "SMMU cfg-probe is rejected" is invalid.
  K042 was pre-empted by a TLMM/GPIO abort before it could test SMMU behavior.

After that, K043-K050 isolated and bypassed the early TLMM/GPIO abort. The
current best candidate is **DTS-only**:

```dts
&tlmm {
	gpio-reserved-ranges = <0 4>, <49 4>, <81 4>;
};
```

K050 with that reserved-range set survived the classifier window: LineageOS
returned at t+123s / 111s after kernel handoff, matching the deliberate reboot
path rather than the early reset/panic path.

## Safe observability methods found

### Raw pstore partition read

Use the committed helper:

```bash
cd ~/vibe-coding-projects/coding/lg-v30-port
scripts/read-pstore-partition.sh
```

Equivalent read-only command from LineageOS root:

```bash
adb root
adb wait-for-device
adb exec-out dd if=/dev/block/platform/soc/1da4000.ufshc/by-name/pstore bs=262144 count=1 > out/pstore-first256k.bin
strings -a out/pstore-first256k.bin > out/pstore-first256k.strings.txt
```

Evidence snapshot:

- `out/lineage-root-observability-2026-07-08/pstore-partition-first256k.bin`
  sha256 `e0573c228d85349c292be545a239a6741ecb6f3965b65538805a1465024c89bc`.
- `out/lineage-root-observability-2026-07-08/pstore-partition-first256k.bin.strings.txt`
  sha256 `323df4a1e65649492ba07d9e35f717748268f7f2fa0ce2166adbf3feb02b63d8`.

Caveat: LineageOS/downstream boot can overwrite/rotate the pstore partition.
Pull it immediately after a failed mainline boot. Later full-partition pulls had
mostly current LineageOS logs and no longer contained the mainline start marker.

### `tzdbg` debugfs is present but risky

LineageOS exposes a downstream `146bf720.tz-log` / `/sys/kernel/debug/tzdbg`
interface, but attempting to read `tzdbg/general` caused adb/device disappearance
in this session. Do not casually `cat /sys/kernel/debug/tzdbg/*` until a narrower
read strategy is designed. Prefer raw pstore first.

## Test matrix

| Test | Change | Result | Interpretation |
|---|---|---|---|
| K042 | K030 + skip MSM8998 SMMU cfg-probe S2CR BYPASS quirk probe | Early LOS return; pstore later revealed TLMM/GPIO SError at ~0.073s | Not a valid SMMU rejection; pre-empted before SMMU |
| K043 | DTS: `&tlmm { status = "disabled"; }` | SURVIVOR: LOS returned at t+123s / 111s after handoff | Whole TLMM probe is in the fault path |
| K044 | Source: skip all `msm_gpio_init()` on `qcom,msm8998-pinctrl` | SURVIVOR: LOS returned at t+123s / 111s after handoff | Fault is inside GPIO setup, not basic pinctrl registration |
| K045 | Source: register gpiochip but skip TLMM IRQ-chip wiring | Early reset; pstore SError still in `gpiochip_add_data_with_key()` | IRQ-chip wiring is not required for the fault |
| K046 | DTS: remove `gpio-reserved-ranges` entirely | Early reset; pstore synchronous external abort in `msm_gpio_get_direction()` at TLMM offset `0x531000` | Direction readback of a protected/inaccessible GPIO is the concrete abort |
| K047 | Source: set `get_direction = NULL` for `qcom,msm8998-pinctrl` | SURVIVOR: LOS returned at t+123s / 111s after handoff | Avoiding direction readback is sufficient |
| K048 | DTS: reserve `<49 1>` in addition to `<0 4>` | Early reset; abort moved to TLMM offset `0x532000` / GPIO50 | Protected region starts at GPIO49 and continues |
| K049 | DTS: reserve `<49 4>` in addition to `<0 4>` | Early reset; abort moved to TLMM offset `0x151000` / GPIO81 | Next protected range starts at GPIO81 |
| K050 | DTS: reserve `<49 4>` and `<81 4>` in addition to `<0 4>` | SURVIVOR: LOS returned at t+123s / 111s after handoff | Candidate DTS-only reserved ranges avoid the observed protected GPIO reads |

## Key pstore decodes

- K046: `x3 = 0x531000`; MSM8998 pinctrl uses `NORTH = 0x500000`, so
  `0x531000 = NORTH + 49 * 0x1000` → GPIO49.
- K048: `x3 = 0x532000` → GPIO50.
- K049: `x3 = 0x151000`; `WEST = 0x100000`, so `0x151000 = WEST + 81 * 0x1000`
  → GPIO81.

## Initial source review

- Upstream mainline MSM8998 boards already commonly reserve `<81 4>` in TLMM:
  `msm8998-mtp.dts`, `msm8998-oneplus-common.dtsi`,
  `msm8998-xiaomi-sagit.dts`, and `msm8998-clamshell.dtsi` all carry
  `gpio-reserved-ranges = <0 4>, <81 4>;`. This independently supports the
  GPIO81..84 half of K050.
- Mainline joan currently has only `<0 4>`, so it likely lost the `<81 4>`
  reservation while being split away from OnePlus/common references.
- Downstream joan common pinctrl defines modes for GPIO49..52 (`i2c_9`,
  `spi_9`, `blsp_uart9_a`) and GPIO81..84 (`i2c_12`, `spi_12`), but a source
  search found no active references to those common pinctrl labels in the joan
  downstream DTS tree. One KR MME variant references GPIO81 directly.
- No mainline joan node currently consumes GPIO49..52 or GPIO81..84. K050 is
  therefore safe for the current minimal mainline boot shape, but future display,
  camera, sensor, or accessory work must not assume those lines are usable.
- `<49 4>` has the strongest evidence from pstore/device behavior, not yet from
  an obvious upstream MSM8998 precedent. Treat that half as joan/LGE-firmware
  candidate until more source evidence is found.

## Current candidate and next steps

Candidate patch artifact:

- `out/aurel-k050-clean-candidate-gpio-reserved-ranges-2026-07-08.patch`
  sha256 `6a0227897f48940fb488747f0a8d927916816140627af8a62aba289f0a7b601a`.

Before turning K050 into a real kernel commit:

1. Find stronger source evidence for GPIO49..52 if possible. GPIO81..84 is
   already supported by multiple upstream MSM8998 DTS files; GPIO49..52 is
   currently pstore/device-proven but source-weak.
2. Decide whether DTS reserved ranges are sufficient/clean or whether a
   driver-level msm8998 `get_direction` quirk is required. K047 proves the
   driver route also survives, but it is broader.
3. Convert K050 into a clean kernel commit only after review, then rerun one
   RAM-only confirmation test.
4. Keep raw-pstore capture in the harness for every future early-reset test.

## Safety / state

- All K043-K050 device tests were RAM-only `fastboot boot`; no flashing.
- Kernel worktree was reverted clean after preserving patches/artifacts.
- Do not reuse the old K042-as-negative-SMMU-result conclusion without the
  correction: K042 was superseded by pstore evidence.

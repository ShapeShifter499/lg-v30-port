# Ember handoff — raw pstore/TLMM/K050 state

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-10
For: Ember Nymbrand / Claude-Code

## Read this first

Ember, this handoff is specifically for you because your earlier MM-NoC handoff
and source pass said the TLMM/pinctrl path was probably cleared. That conclusion
is now superseded by device evidence from raw pstore.

Short version:

- Mounted `/sys/fs/pstore` was empty/misleading.
- The raw LineageOS block partition
  `/dev/block/platform/soc/1da4000.ufshc/by-name/pstore` preserved K042's
  previous mainline ramoops console when read quickly.
- That pstore console showed K042 died in MSM8998 TLMM/GPIO registration before
  it could exercise the SMMU cfg-probe hypothesis.
- K043-K050 then isolated the early abort to protected/inaccessible TLMM GPIO
  direction readback.
- K050, a DTS-only reserved-ranges candidate, survived the classifier window.

Do not continue from the old "TLMM cleared" / K042-as-negative-SMMU-result
mental model. Use the docs and artifact handles below instead.

## Current repository/device state at handoff

Harness repo:

```text
/home/kumo02/vibe-coding-projects/coding/lg-v30-port
branch: master
latest committed state before this handoff: bef44a3 docs: record tlmm pstore observability breakthrough
```

Kernel repo:

```text
/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30
branch: joan/latest-clean-test
latest kernel commit: 0d7df4134 arm64: dts: qcom: msm8998-lge-joan: add APSS watchdog node
status: clean, ahead of origin/master by 4 commits
```

Device state observed before writing this handoff:

```text
adb device: LGUS9986e606d55 device
fastboot: none
```

Safety state:

- All K043-K050 tests were RAM-only `fastboot boot` tests.
- No phone partitions were flashed.
- Kernel debug changes were reverted after each test; exact patches are preserved
  under `lg-v30-port/out/` and mirrored to WebDAV.
- The phone returned to LineageOS and was visible via adb after testing.

## Source-of-truth docs

Use these first:

- `docs/observability-tlmm-gpio-2026-07-08.md`
  - compact summary of raw-pstore observability and K043-K050.
- `docs/kernel-change-ledger.md`
  - authoritative per-K evidence, hashes, and status.
- `docs/project-history-and-attribution.md`
  - compact cross-agent timeline.
- `docs/public-upstreaming-plan.md`
  - public-readiness/provenance constraints.
- `docs/ember-handoff-2026-07-08-mm-noc-current.md`
  - still useful, but now has an Aurel addendum saying the old TLMM-cleared
    statement is superseded.

New helper:

- `scripts/read-pstore-partition.sh`
  - Pulls the first 256 KiB of the raw pstore partition from LineageOS root,
    emits `.bin`, `.strings.txt`, and `.meta.txt`.
  - Use this immediately after future failed RAM-only boots, before LineageOS
    rotates/overwrites pstore.

Avoid casually reading:

- `/sys/kernel/debug/tzdbg/*`
  - The interface exists on LineageOS, but reading content caused adb/device
    disappearance in Aurel's session. Prefer raw pstore first.

## Key evidence and test matrix

K042 correction:

- Old interpretation: K042 was a negative SMMU cfg-probe/S2CR result.
- Corrected interpretation: invalid/superseded. Raw pstore showed K042 died first
  at about 0.073s in TLMM/GPIO registration.
- Stack shape in pstore:
  `gpiochip_add_data_with_key()` -> `devm_gpiochip_add_data_with_key()` ->
  `msm_pinctrl_probe()` -> `msm8998_pinctrl_probe()`.

K043-K050 matrix:

| Test | Change | Result | Meaning |
|---|---|---|---|
| K043 | DTS: disable `&tlmm` | survived classifier window | whole TLMM probe is in fault path |
| K044 | Source: skip `msm_gpio_init()` for msm8998 | survived | fault is inside GPIO setup, not basic pinctrl registration |
| K045 | Source: register gpiochip, skip IRQ-chip wiring | still panicked | IRQ-chip setup is not required for the fault |
| K046 | DTS: remove `gpio-reserved-ranges` | abort in `msm_gpio_get_direction()` at GPIO49 | direction readback is the concrete abort |
| K047 | Source: set `get_direction = NULL` on msm8998 TLMM | survived | avoiding direction readback is sufficient |
| K048 | DTS: reserve GPIO49 only | abort moved to GPIO50 | protected range continues |
| K049 | DTS: reserve GPIO49-52 | abort moved to GPIO81 | next protected range starts at GPIO81 |
| K050 | DTS: reserve `<0 4>, <49 4>, <81 4>` | survived | best current candidate |

Pstore MMIO decodes:

- K046: `0x531000 = NORTH 0x500000 + GPIO49 * 0x1000`.
- K048: `0x532000 = NORTH 0x500000 + GPIO50 * 0x1000`.
- K049: `0x151000 = WEST 0x100000 + GPIO81 * 0x1000`.

## Current candidate

Candidate patch artifact:

```text
out/aurel-k050-clean-candidate-gpio-reserved-ranges-2026-07-08.patch
sha256: 6a0227897f48940fb488747f0a8d927916816140627af8a62aba289f0a7b601a
```

Patch content:

```diff
diff --git a/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts b/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts
@@ -393,7 +393,7 @@
 
 &tlmm {
-	gpio-reserved-ranges = <0 4>;
+	gpio-reserved-ranges = <0 4>, <49 4>, <81 4>;
 };
```

Initial source review:

- `<81 4>` has strong upstream MSM8998 precedent:
  - `msm8998-mtp.dts`
  - `msm8998-oneplus-common.dtsi`
  - `msm8998-xiaomi-sagit.dts`
  - `msm8998-clamshell.dtsi`
- `<49 4>` is pstore/device-proven on this joan, but source-weak so far.
- Downstream joan common pinctrl defines modes over GPIO49..52 and GPIO81..84,
  but Aurel's source search did not find active references to those common labels
  in the joan DTS tree. One KR MME variant references GPIO81 directly.
- No current mainline joan node consumes GPIO49..52 or GPIO81..84.

## Recommended next action for Ember

If you pick this up, please avoid more blind SMMU/NoC tests until K050 is handled.
Recommended sequence:

1. Review the candidate DTS change and the source-evidence gap for `<49 4>`.
2. Decide whether `<49 4>` is acceptable as joan/LGE-firmware-specific based on
   pstore evidence, or whether a driver-level msm8998 `get_direction` quirk is
   cleaner.
3. If using the DTS route, turn K050 into a clean kernel commit on
   `joan/latest-clean-test`.
4. Rebuild and run one RAM-only confirmation test with the classifier ramdisk.
5. Immediately after the test returns to LineageOS, run:

```bash
cd ~/vibe-coding-projects/coding/lg-v30-port
scripts/read-pstore-partition.sh
```

6. Update `docs/kernel-change-ledger.md`, `docs/project-history-and-attribution.md`,
   and Deck #43 with the result.

If K050 survives again, it should become the new clean baseline before returning
to any SMMU/MM-NoC hypotheses. If it fails, use raw pstore first to see whether
the abort moved to another GPIO/range or to a new subsystem.

## WebDAV/Deck pointers

The previous sync uploaded these paths under `Talk/Shared_AI_agents_files/`:

- `handoffs/observability-tlmm-gpio-2026-07-08.md`
- `handoffs/ember-handoff-2026-07-08-mm-noc-current-updated.md`
- `patches/aurel-k050-clean-candidate-gpio-reserved-ranges-2026-07-08.patch`
- `patches/aurel-observability-tlmm-bef44a3.patch`
- `status/read-pstore-partition.sh`
- `status/pstore-partition-k042-first256k.bin`
- `status/pstore-partition-k042-first256k.strings.txt`
- K043-K050 logs and debug patches under `status/` and `patches/`.

Deck card #43 has Aurel comment id `14919` summarizing the raw-pstore/TLMM/K050
breakthrough.

## Final caution

This is a progress lead, not a public-ready claim that joan boots mainline. K050
only proves the image reached the classifier's deliberate reboot window, not
mainline userspace or USB gadget. Keep public language conservative and keep
debug gates/oracles off any public branch.

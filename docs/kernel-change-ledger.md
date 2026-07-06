# LG V30 mainline kernel change ledger

Purpose: keep a complete, auditable trail of every kernel-side change needed to
mainline the LG V30 (`joan`) enough for modern Linux/postmarketOS and, later,
possibly a newer Android stack.

This file is the kernel-change source of truth. README carries the short current
status; detailed boot/debug evidence can live in dated handoff docs; this ledger
tracks what changed, why, where it lives, whether it should survive upstreaming,
and what evidence supports or rejects it.

## Rules for every agent

For every kernel-impacting change, add or update a ledger entry before handoff:

1. Record the exact handle:
   - committed change: commit hash and subject;
   - experiment: saved patch path under `lg-v30-port/out/` or a named branch;
   - rejected/no-code finding: dated evidence and source file / command path.
2. Mark the class:
   - `upstream-candidate` = intended to become part of the clean mainline port;
   - `bringup-local` = useful for tethered debug/bringup but not upstream as-is;
   - `debug-only` = disposable oracle/instrumentation;
   - `rejected` = tested and should not be retried without new evidence;
   - `unknown` = still under investigation.
3. Record touched files and the downstream reference, if any.
4. Record verification: build command, boot/test result, logs, timing, or why it
   could not be verified.
5. Preserve attribution: do not rewrite another agent's conclusions without
   appending a correction with `Written-by`, `Agent-harness`, and date.
6. Before a real commit intended for reuse/upstream, make sure the ledger points
   from the final commit back to the bringup evidence that justified it.

Safety invariant: all device tests stay RAM-only (`fastboot boot`) unless Lance
explicitly approves a different action. Never flash or write phone partitions as
part of a ledger experiment.

## Current kernel branch map

- Clean bringup base: `linux-mainline-v30`, branch `lge-joan-bringup`, currently
  ending at `5acce83a9`.
- Debug branch in use during watchdog/reset work: `joan/bringup-debug`, currently
  `lge-joan-bringup` + commits `93fe462d7` and `6c5f06bc8`.
- Downstream reference: `android_kernel_lge_msm8998` is read-only.

## Ledger entries

### K001 — initial joan device tree

- Handle: commit `3d3868854` — `arm64: dts: qcom: add initial LG V30 (joan) device tree`
- Class: `upstream-candidate`
- Files:
  - `arch/arm64/boot/dts/qcom/Makefile`
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Purpose:
  - Add first LG V30 / US998 `joan` board DTS for USB-proof-of-life mainline
    bringup.
  - Minimal scope: UFS, USB2 gadget path, RPM regulators, volume keys, ramoops,
    splash reservation.
- Key downstream/reference basis:
  - Downstream LG/LineageOS msm8998 joan DTS files.
  - OnePlus 5 msm8998 board files for provisional RPM rail values.
- Verification/evidence:
  - DTS compiled.
  - Later fastboot tests proved aboot accepts appended joan DTB images and enters
    the kernel.
- Open follow-up:
  - Cross-check RPM regulator voltages against downstream joan PM DTS before
    enabling more peripherals.
  - Trim `qcom,board-id` once exact target hardware revision handling is final.
- Status: keep; expected to be the base of any future mainline/pmOS work.

### K002 — match downstream ramoops layout

- Handle: commit `d75290b9e` — `arm64: dts: qcom: msm8998-lge-joan: match downstream ramoops layout`
- Class: `bringup-local` / possible `upstream-candidate` only if a useful pstore
  story is found.
- File:
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Purpose:
  - Make mainline ramoops layout byte-compatible with downstream so fallback
    Android could theoretically harvest mainline previous-boot logs.
- Verification/evidence:
  - Subsequent LOS-to-LOS and mainline-to-LOS tests showed pstore/ramoops is dead
    on this device: LG boot chain scrubs or reinitializes the region.
- Status:
  - Keep as documented history for now, but do not depend on ramoops for debug.
  - Re-evaluate before upstreaming; a dead ramoops node may not be worth carrying.

### K003 — reserve LG firmware-owned memory

- Handle: commit `5acce83a9` — `arm64: dts: qcom: msm8998-lge-joan: reserve LG firmware-owned memory`
- Class: `upstream-candidate`
- File:
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Purpose:
  - Add LG-specific reserved memory holes missing from generic mainline msm8998
    layout so Linux does not allocate pages owned/protected by firmware/XPU.
- Key regions from commit body:
  - `0x85f00000+0x100000`
  - `0x95215000+0x3eb000`
  - `0x95800000+0x500000`
  - `0xb0100000+0x1800000`
- Verification/evidence:
  - Derived from systematic downstream-vs-mainline reserved-memory comparison.
  - Addresses plausible silent reset source from XPU-protected memory access.
- Open follow-up:
  - Relocate or reconcile mainline `gpu_mem` and `wlan_msa_mem`, which currently
    overlap LG's downstream SLPI-related range.
- Status: keep; high-value for mainlining and non-Android OS boot.

### K004 — APSS watchdog DT node

- Handle: commit `93fe462d7` — `arm64: dts: qcom: msm8998-lge-joan: add APSS watchdog node`
- Class: `unknown` / possible `upstream-candidate`
- File:
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Purpose:
  - Add `watchdog@17817000` so mainline `qcom-wdt` can bind.
- Verification/evidence:
  - Node builds.
  - Probe was observed flaky across identical tethered boots in earlier work.
  - Disabling this node did not shift the reset window, so generic qcom-wdt is
    probably not the current reset source.
- Open follow-up:
  - Decide whether the node belongs in `msm8998.dtsi` or joan DTS for upstream.
  - Verify bark/bite semantics and whether downstream properties like
    `qcom,wakeup-enable` have any mainline equivalent or should be omitted.
- Status: keep on debug branch; not proven necessary for solving current reset.

### K005 — ramoops breadcrumb instrumentation

- Handle: commit `6c5f06bc8` — `JOAN DEBUG: ramoops breadcrumbs in head.S and setup_arch`
- Class: `debug-only` / `rejected` for future debugging on this device
- Files:
  - `arch/arm64/kernel/head.S`
  - `arch/arm64/kernel/setup.c`
- Purpose:
  - Write hand-crafted persistent_ram breadcrumbs before and after early kernel
    setup to prove how far boot got.
- Verification/evidence:
  - Method proved invalid on this device: even LOS-to-LOS warm reboot loses
    ramoops content.
  - Replaced by PSCI timing-oracle probes.
- Status:
  - NEVER MERGE.
  - Keep only as historical breadcrumb on debug branch until no longer useful.

### K006 — SEC_WDOG_DIS / SEC_WDOG_TRIG SCM experiments

- Handles:
  - `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-sec-wdog-scm-experiments-2026-07-06.patch`
  - `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-qcom-scm-oracle-leftover-2026-07-06.patch`
- Class: `rejected` unless new evidence shows a boot-mode-specific difference.
- Files experimented with:
  - `drivers/firmware/qcom/qcom_scm.c`
  - `drivers/firmware/qcom/qcom_scm.h`
- Purpose:
  - Try to mirror downstream watchdog secure-monitor calls:
    `SCM_SVC_BOOT`, `SEC_WDOG_DIS` cmd `0x7`, `SEC_WDOG_TRIG` cmd `0x8`.
- Verification/evidence:
  - Mainline `qcom_scm_probe()` timing oracle proved this probe is reached early
    enough before the normal reset window.
  - Mainline wrapper/raw SMC/atomic variants did not prevent the reset.
  - Downstream LineageOS runtime write to
    `/sys/devices/soc/17817000.qcom,wdt/disable` failed in downstream itself with
    `scm_call failed: func id 0x42000107, ret: -2` and
    `Failed to deactivate secure wdog`.
- Status:
  - Do not keep in kernel tree.
  - Do not retry blindly; inspect earlier downstream TZ/boot setup first.

### K007 — panic/APSS-WDT discriminators

- Handles:
  - documented in `docs/bringup-debug-state-2026-07-06.md`
  - relevant saved images in `lg-v30-port/out/` are temporary artifacts only.
- Class: `rejected` as root-cause explanations.
- Purpose:
  - Test whether the reset was a normal Linux panic or mainline `qcom-wdt`
    reprogramming the APSS watchdog.
- Verification/evidence:
  - `panic=30` image returned to LineageOS at the normal window; reset did not
    shift as expected for a normal panic path.
  - APSS watchdog DT node disabled still returned at the normal window.
- Status:
  - Panic and generic qcom-wdt-driver explanations are weaker; do not center the
    next debugging round there without new evidence.

### K008 — downstream-style APSS WDT takeover experiments

- Handles:
  - `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-downstream-style-wdt-clean-test-2026-07-06.patch`
  - `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-wdt-en3-test-2026-07-06.patch`
- Class: `rejected` as a sufficient fix; code is not for upstream.
- Files experimented with:
  - `drivers/watchdog/qcom-wdt.c`
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Purpose:
  - Emulate downstream `msm_watchdog` behavior from early mainline code while
    disabling generic qcom-wdt so it cannot write `EN=0`.
- Verification/evidence:
  - EN=1, bark=16s, bite=19s, pet every 2s: still reset/rebooted to LineageOS.
  - EN=3 (`EN|UNMASKED_INT_EN`, matching downstream `qcom,wakeup-enable`),
    bark=16s, bite=19s, pet every 2s: still reset/rebooted at the normal window
    after a clean rebuild with `qcom_scm.c` restored and force-recompiled.
- Status:
  - APSS WDT register programming alone is not the missing survival mechanism.
  - Do not keep in kernel tree.

## Current narrowed hypothesis

The blocker still looks like a secure/boot-chain/platform-state resetter, but
not one solved by the simple downstream sysfs `SEC_WDOG_DIS` path or by direct
APSS watchdog pets. Next investigation should compare very early downstream boot
setup against mainline, especially:

- CPU/Kryo errata SCM calls (`drivers/soc/qcom/scm-errata.c` downstream);
- LGE panic/restart-reason and IMEM cookie setup;
- SMEM/bootreason/restart cookies;
- other early `SCM_SVC_BOOT` / TZ setup before or around downstream
  `msm_watchdog` init;
- downstream dmesg events before ~0.4s that mainline does not mirror.

## Attribution

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

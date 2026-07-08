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
7. If a change might be pushed publicly or used in a PR/patch series, add a
   `Public/PR disposition` note: `ready`, `needs cleanup`, `blocked`, or
   `do not publish`, and point to `docs/public-upstreaming-plan.md` for the
   criteria.

Safety invariant: all device tests stay RAM-only (`fastboot boot`) unless Lance
explicitly approves a different action. Never flash or write phone partitions as
part of a ledger experiment.

## Current kernel branch map

- Latest clean tethered-test branch: `linux-mainline-v30`, branch
  `joan/latest-clean-test`, currently rebased onto fetched `origin/master`
  `8cdeaa50e` (`Linux 7.2-rc2`) plus four DTS-only joan commits now rewritten
  as `25a391c94`, `a19ca9204`, `7c906e841`, and `0d7df4134`.
- Latest debug branch: `joan/latest-kernel`, same upstream base plus the
  debug-only breadcrumb commit, currently ending at `88bf16047`.
- IMEM reset-reason oracle branch: `joan/imem-oracle`, off
  `joan/latest-clean-test`, one debug-only commit `f0d368d28`. Original Ember
  image `out/boot-joan-imem-oracle.img` remains preserved, but Aurel K026
  repackaged/tested the same kernel commit with the K023 `panic=0` null-init
  classifier as `out/boot-joan-imem-k026.img` (sha256
  `ccf08dbea0e889fa11404335d423e46e5078f37883469234694aff4d3939d035`).
- Previous debug branch preserved: `joan/bringup-debug`, currently old
  v7.2-rc1-based commits `3d3868854`, `d75290b9e`, `5acce83a9`, `93fe462d7`,
  and `6c5f06bc8`.
- Clean bringup base: `lge-joan-bringup`, currently ending at old commit
  `5acce83a9`.
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
- Public/PR disposition: `needs cleanup` — likely part of the public base, but
  commit/body/DTS should be rechecked after regulator and board-id follow-ups.

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
- Public/PR disposition: `blocked` — do not publish as a useful debug channel
  unless a new bootloader/ramoops persistence story is proven.

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
- Public/PR disposition: `needs cleanup` — likely public-worthy, but GPU/WLAN
  reserved-memory overlaps need a final explanation or follow-up split.

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
- Public/PR disposition: `blocked` — do not submit until APSS watchdog behavior
  and placement (`msm8998.dtsi` vs joan DTS) are settled.

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
- Public/PR disposition: `do not publish` except as investigation history in a
  non-kernel evidence document.

### K006 — SEC_WDOG_DIS / SEC_WDOG_TRIG SCM experiments

- Handles:
  - `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-sec-wdog-scm-experiments-2026-07-06.patch`
  - `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-qcom-scm-oracle-leftover-2026-07-06.patch`
  - `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-scm-retcode-oracle-leftover-2026-07-06.patch`
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
- Public/PR disposition: `do not publish`; rejected experiment only.

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
- Public/PR disposition: `do not publish`; evidence only.

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
- Public/PR disposition: `do not publish`; rejected experiment only.

### K009 — latest upstream rebase and RAM-only regression test

- Handles:
  - branch `joan/latest-kernel` at `88bf16047` — `JOAN DEBUG: ramoops breadcrumbs in head.S and setup_arch`
  - base `origin/master` `8cdeaa50e` — `Linux 7.2-rc2`
  - image `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-kernel.img`
  - image sha256 `2c8af0cc49b05ccd5d0c5452b5bd8f607aadbe89675fdcc6f7b92f023f32c325`
- Class: `bringup-local` branch refresh / regression evidence.
- Files changed by carried commits:
  - `arch/arm64/boot/dts/qcom/Makefile`
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
  - `arch/arm64/kernel/head.S`
  - `arch/arm64/kernel/setup.c`
- Purpose:
  - Move the joan debug stack from the old v7.2-rc1 shallow base to current
    fetched upstream `v7.2-rc2` without losing the tracked joan commits.
- Verification/evidence:
  - Before reset/replay, old tips were preserved as backup refs, including
    `backup/joan-bringup-debug-before-latest-20260706-052942`.
  - A detached dirty SCM-oracle worktree patch was preserved at
    `lg-v30-port/out/aurel-test-worktree-scm-oracle-dirty-20260706-052942.patch`
    and the test worktree was reset clean to avoid object contamination.
  - `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j6 Image.gz dtbs`
    succeeded on `joan/latest-kernel`.
  - `./make-testimage.sh` produced the RAM-only boot image above.
  - One-client RAM-only `fastboot boot out/boot-joan-latest-kernel.img` succeeded
    at the fastboot protocol layer, but the phone returned to LineageOS at
    `t+29.7s` after boot handoff; no mainline mass-storage/debug channel appeared.
- Status:
  - Latest upstream v7.2-rc2 alone does not fix the reset.
  - Keep `joan/latest-kernel` as the active tethered-test branch; do not publish
    the debug breadcrumb commit.
- Public/PR disposition: branch contains mixed upstream-candidate and debug-only
  commits; `do not publish` as-is.

### K010 — latest clean DTS-only branch fastboot baseline

- Handles:
  - branch `joan/latest-clean-test` at `0d7df4134` — `arm64: dts: qcom: msm8998-lge-joan: add APSS watchdog node`
  - base `origin/master` `8cdeaa50e` — `Linux 7.2-rc2`
  - image `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-clean.img`
  - image sha256 `47418aebd86c929b59cd09d243d93abe7ab03d85310d11015dfcd530474d47c1`
- Class: `bringup-local` baseline / public-shaping evidence.
- Files changed by carried commits:
  - `arch/arm64/boot/dts/qcom/Makefile`
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Purpose:
  - Verify the latest upstream branch with only clean DTS-side joan commits,
    excluding the known debug-only `head.S` / `setup_arch` breadcrumb commit.
  - Establish a better baseline for future public/PR-shaped work.
- Verification/evidence:
  - `git diff --check` succeeded.
  - `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j6 Image.gz dtbs`
    succeeded on `joan/latest-clean-test`.
  - `./make-testimage.sh` produced the RAM-only boot image above.
  - One-client RAM-only `fastboot boot out/boot-joan-latest-clean.img` succeeded
    at the fastboot protocol layer (`Sending` OKAY, `Booting` OKAY, total
    `5.525s`).
  - No mainline mass-storage/debug channel appeared; LineageOS adb returned at
    `t+46.7s` after boot handoff.
- Status:
  - Latest upstream v7.2-rc2 plus clean joan DTS work still does not fix the
    reset.
  - Prefer this clean branch over `joan/latest-kernel` for future baseline tests;
    the breadcrumb branch is useful only as historical debug context and returned
    at a different `t+29.7s` timing.
- Public/PR disposition: `blocked` for a bootable public claim; the branch shape
  is closer to public-ready than `joan/latest-kernel`, but individual commits
  still need cleanup/review per K001-K004.

### K011 — latest clean CPU/idle/high-memory discriminators

- Handles:
  - branch `joan/latest-clean-test` at `0d7df4134` plus command-line-only image variants;
  - image `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-maxcpus1.img`, sha256 `5bd01b0a987563027abbb968810b1b796201cbffb32e99effa4fc95d672c93e8`;
  - image `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-cpuidleoff.img`, sha256 `3f4b26656dc1af381128aa211787297ce85808e638287a1c21f7c550b5f9955d`;
  - saved patch `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-latest-highmem-reserve-test-2026-07-06.patch`;
  - image `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-highmem-reserve.img`, sha256 `c9f4545b790084dd82b139109dc29dffa516f1c3a17620a003db3b6241a886a6`.
- Class: `rejected` / `debug-only` discriminators.
- Purpose:
  - Test whether the reset is caused by secondary CPU bringup/Kryo errata, CPU
    idle/PSCI idle, or early allocator use of downstream high-memory secure/shared
    ranges.
- Verification/evidence:
  - `maxcpus=1`: one-client RAM-only `fastboot boot` protocol OKAY, total
    `5.522s`; no mainline mass-storage/debug channel; LineageOS adb returned at
    `t+29.5s`.
  - `cpuidle.off=1 nohlt`: one-client RAM-only `fastboot boot` protocol OKAY,
    total `5.520s`; no mainline mass-storage/debug channel; LineageOS adb
    returned at `t+45.8s`.
  - high-memory reservation debug patch: `git diff --check` and build succeeded;
    one-client RAM-only `fastboot boot` protocol OKAY, total `5.516s`; no
    mainline mass-storage/debug channel; LineageOS adb returned at `t+29.4s`.
  - Kernel tree was restored to clean `joan/latest-clean-test` and rebuilt after
    saving the high-memory patch.
- Status:
  - Not fixes. These weaken the secondary-CPU, cpuidle, and simple high-memory
    allocator/XPU hypotheses.
  - The `~29s` variants perturb timing and should not be reused as baselines
    unless specifically investigating their perturbation.
- Public/PR disposition: `do not publish`; keep only as negative evidence.

### IMEM reset-reason oracle (Ember 2026-07-06) — original staged artifact; repackaged/tested as K026

- Handle: branch `joan/imem-oracle` commit `f0d368d28`; patch
  `out/ember-imem-oracle-2026-07-06.patch`; image
  `out/boot-joan-imem-oracle.img`
  (sha256 `8d180d57b91aefae1d4fdbbb88cf138d76711866c7e5e3dcdceebc118fb768c7`).
- Class: `debug-only`.
- Touched files: new `drivers/soc/qcom/joan_imem_oracle.c`,
  `drivers/soc/qcom/Makefile` (`obj-y` unconditional).
- Downstream reference: `drivers/soc/qcom/lge/lge_handle_panic.c`
  (early_initcall maps `qcom,msm-imem@146bf000`, checks crash magic at 0x4c,
  writes restart-reason at 0x65c) and its header's magic table
  (`LGE_RB_MAGIC 0x6d630000`, `LGE_ERR_TZ 0x0300`,
  `LGE_ERR_TZ_WDT_BARK 0x003A`, `LGE_ERR_TZ_THERM_SEC_BITE 0x003B`).
- Rationale / why this is different from every rejected experiment: those all
  tried to PREVENT the reset. This does not try to fix anything — it READS the
  reset cause the secure boot chain records. Mainline has no imem node so it
  never touches this SRAM; IMEM survives a warm reset (its whole purpose) and,
  unlike the DDR ramoops region that LG scrubs, is READABLE FROM LINEAGEOS
  after the crash-reset. This is a debug channel that should work where ramoops
  did not.
- Verification so far: `git diff --check` clean; builds; `joan_imem_oracle_init`
  present in vmlinux as an `early` initcall; image packaged. NOT device-tested
  (Lance required).
- Device procedure (see `docs/imem-oracle-run.md` + `scripts/read-imem-reset-reason.sh`):
  RAM-only boot the oracle image, let it crash-reset to LineageOS, then read
  `busybox devmem 0x146bf65c 32` (reset reason) and `0x146bf640` (0x4a4f414e
  sentinel = our initcall ran). Decode reason against the LGE table.
- Expected discriminations:
  - reason low byte `0x3a`/`0x3b` -> TZ watchdog bark / thermal bite named at last;
  - reason `0x...0201` -> RPM; `0x...0301` -> kernel;
  - reason still our default `0x6d630300` AND sentinel present -> reset came
    from a path that records no LGE reason (suspect raw PMIC/PON/PS_HOLD);
  - sentinel absent -> reset precedes early_initcall; move probe earlier.
- Public/PR disposition: `do not publish`.


### K012 — downstream DLOAD-off SCM argument-shape oracle

- Handles:
  - patch `out/aurel-latest-dload-off-argshape-test-2026-07-06.patch`
    (sha256 `eb285f2d73b2711fa505c0938183954b18ebb125735ae69176e7311fc8f1a5a0`);
  - image `out/boot-joan-latest-dload-off-argshape.img`
    (sha256 `423d0c7f306a0d1617ade6577c8cb012df71cda6d6f8a08ab731dc4e79a26457`,
    size `15736832` bytes);
  - clean post-oracle repack `out/boot-joan-latest-clean-post-dload-oracle.img`
    (sha256 `ee952809d17b791094717eec4585ce83d14d5b1ef0e7e1a53def3a55ab4e19a3`).
- Class: `debug-only`, rejected as a fix.
- Public/PR disposition: `do not publish`.
- Touched file: `drivers/firmware/qcom/qcom_scm.c`.
- Downstream reference:
  - `drivers/power/reset/msm-poweroff.c` lines around `set_dload_mode()` and
    `msm_restart_probe()`;
  - LGE builds default `download_mode = 0`, then early probe calls
    `set_dload_mode(0)`, which invokes `SCM_DLOAD_CMD` (`0x10`) as args `(0, 0)`;
  - downstream dmesg shows `set_dload_mode(0)` around `1.031840s`.
- Mainline delta tested:
  - mainline command was already `QCOM_SCM_BOOT_SET_DLOAD_MODE` (`0x10`), but its
    disabled/off argument shape was `(0x10, 0)`;
  - oracle changed only `enable=false` argument shape to downstream's `(0, 0)`.
- Verification/evidence:
  - `git diff --check` passed;
  - kernel rebuilt and image packaged;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.516s`);
  - no mainline USB/diag channel appeared;
  - LineageOS adb returned at `t+44.3s`;
  - post-reset PON log again reported SID0 `PS_HOLD`.
- Interpretation:
  - the DLOAD-off SCM argument-shape mismatch is not the missing secure-liveness
    handshake;
  - `SET_DLOAD_MODE` is weaker as the lead hypothesis;
  - move to a single QSEE/QSEEOS-side early ping oracle (e.g. `tz_log.c` QSEE log
    buffer registration / TZ feature query) before trying more watchdog variants.


### K013 — downstream QSEE/QSEEOS log-buffer registration oracle

- Handles:
  - patch `out/aurel-latest-qsee-logbuf-oracle-2026-07-06.patch`
    (sha256 `68b0883cae085712a446475c5ae3bd723defb056ddd28e6babfe18521ce797d3`);
  - image `out/boot-joan-latest-qsee-logbuf.img`
    (sha256 `6a99c6f2c653e21d2cbba2df7ad2d392dbbcc40f0db7fef63efd599d57b7eb93`,
    size `15736832` bytes);
  - fastboot transcript `out/aurel-qsee-logbuf-fastboot-2026-07-06.txt`
    (sha256 `828c8af9af4f8a9aa457d68ea2ae534b44a816fc8b1d05cc9c93d7706d4bc0d4`);
  - PON evidence `out/aurel-qsee-logbuf-pon-2026-07-06.txt`
    (sha256 `004d16ae7d4076acce09fdb261860856f80d53fce1edb289539389f60c100115`);
  - clean post-oracle repack `out/boot-joan-latest-clean-post-qsee-oracle.img`
    (sha256 `45015e1880a65e7019abfd15de656af8253378323493a41d5563da9637e84320`).
- Class: `debug-only`, rejected as a fix.
- Public/PR disposition: `do not publish`.
- Touched file: `drivers/firmware/qcom/qcom_scm.c`.
- Downstream reference:
  - `drivers/firmware/qcom/tz_log.c` `tzdbg_register_qsee_log_buf()`;
  - ARMv8 path calls `SCM_QSEEOS_FNID(1, 6)` with args `(pa, len)` and arginfo
    `0x22` after allocating a 32 KiB QSEE log buffer;
  - downstream then queries TZ feature/version, which mainline already does in
    `qcom_scm_qseecom_init()`.
- Mainline delta tested:
  - add only the missing log-buffer registration ping during qcom_scm QSEECOM init;
  - allocate the 32 KiB buffer from mainline `qcom_tzmem`, send owner QSEE_OS
    (`50`), service `1`, command `6`, args `(phys, 0x8000)`.
- Verification/evidence:
  - `git diff --check` passed;
  - kernel rebuilt and image packaged;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.513s`);
  - no mainline USB/diag channel appeared;
  - LineageOS adb returned at `t+52.2s`;
  - post-reset PON log again reported SID0 `PS_HOLD`.
- Interpretation:
  - standalone QSEE log-buffer registration is not the missing secure-liveness
    handshake;
  - the later host return may be timing perturbation, but it is not survival;
  - next compare another first-second downstream delta, especially RPM/SMD/SMEM
    handshake or LGE/Qualcomm boot-state cookies, one oracle at a time.


### K014 — RPM `rpm_requests` rpmsg reachability timing oracle

- Handles:
  - patch `out/aurel-latest-rpm-rpmsg-reachability-oracle-2026-07-06.patch`
    (sha256 `a92efaa88f7717d5762fa71bd2d22c84510bf13c4b43a3e22f893bd25bc895f1`);
  - image `out/boot-joan-latest-rpm-rpmsg-oracle.img`
    (sha256 `d7b039b381ad83c61a4e7bfdf3005fa143a8fc5701c90dbf9faf06edfe1bed6b`,
    size `15740928` bytes);
  - fastboot transcript `out/aurel-rpm-rpmsg-fastboot-2026-07-06.txt`
    (sha256 `3261e8f38e5a3aa1128fbbd4c4a721e181c5ef435ee54cf6d65ea54540e71d79`);
  - PON evidence `out/aurel-rpm-rpmsg-pon-2026-07-06.txt`
    (sha256 `8f01740521da6b31f997ddea02e5352bedb9f3429e88bbe09d8117b04ed139e1`);
  - clean post-oracle repack `out/boot-joan-latest-clean-post-rpm-oracle.img`
    (sha256 `c3db2b91473773af0546579e846dc41f85074d750e7407f95917e1d5a7ccb5b3`).
- Class: `debug-only`, rejected as a fix; useful as reachability evidence.
- Public/PR disposition: `do not publish`.
- Touched file: `drivers/soc/qcom/smd-rpm.c`.
- Downstream reference:
  - `drivers/soc/qcom/rpm-smd.c` GLINK path for `qcom,rpm-glink`;
  - downstream dmesg logs APSS-RPM over GLINK around `0.317s` and `rpm_requests`
    link configuration around `0.332s`.
- Mainline delta tested:
  - mainline already has RPM/SMEM/SMP2P/GLINK support built in and a `rpm_requests`
    child under `qcom,glink-rpm` in `msm8998.dtsi`;
  - oracle added only a 4s-delayed PSCI reset if `qcom_smd_rpm_probe()` runs on
    `lge,joan`, to test reachability without adding RPM resource votes.
- Verification/evidence:
  - `git diff --check` passed;
  - kernel rebuilt and image packaged;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.518s`);
  - no mainline USB/diag channel appeared;
  - LineageOS adb returned at `t+58.3s`;
  - post-reset PON log again reported SID0 `PS_HOLD`.
- Interpretation:
  - reachability alone is not survival;
  - the delayed host return is consistent with the oracle being reached, so a total
    absence of RPM `rpm_requests` rpmsg setup is weaker as the blocker;
  - still compare actual downstream RPM resource votes and SMEM/boot-state cookie
    writes separately.


### K015 — RPM BOB-mode downstream default-vote oracle

- Handles:
  - patch `out/aurel-latest-rpm-bob-mode-oracle-2026-07-06.patch`
    (sha256 `eca4d41b1532903e541118e951f9dda4e366fed3b89a2feedd08915386cbd7df`);
  - image `out/boot-joan-latest-rpm-bob-mode.img`
    (sha256 `e7ccb54378f39b84a3497590844d26d504e5cc770040190bab86e5e845f7c1c9`,
    size `15736832` bytes);
  - fastboot transcript `out/aurel-rpm-bob-mode-fastboot-2026-07-06.txt`
    (sha256 `0f77a5769d905b209821f73f48d4c06926ece06b430003e6dbaede6100d1ff96`);
  - PON evidence `out/aurel-rpm-bob-mode-pon-2026-07-06.txt`
    (sha256 `8b06e8d271ce730f845a07ef79e2f3d6bf0148edd9363f1746c8d91f58cc3779`);
  - clean post-oracle repack `out/boot-joan-latest-clean-post-bob-oracle.img`
    (sha256 `9f659917f5b7bfc687a8aef56a64e391ceb2b9958b043490edce298d7af657ab`).
- Class: `debug-only`, rejected as a standalone fix; useful timing evidence for
  real RPM regulator/default-vote parity.
- Public/PR disposition: `do not publish`.
- Touched file: `drivers/soc/qcom/smd-rpm.c`.
- Downstream reference:
  - `msm8998-regulator.dtsi` / joan PM overlay enable `rpm-regulator-bobb`;
  - `pmi8998_bob` and its pin-control children carry `qcom,init-bob-mode = <2>`;
  - downstream RPM regulator driver sends `bobm` KVP defaults when configured.
- Mainline delta tested:
  - mainline joan has RPM rpmsg support but lacks the RPM regulator child nodes,
    so it never sends the downstream BOB mode default;
  - oracle sent KVP `bobm=2` to RPM resource `BOBB:1` in active and sleep sets
    directly from `qcom_smd_rpm_probe()` on `lge,joan`.
- Verification/evidence:
  - `git diff --check` passed;
  - kernel rebuilt with GCC cross toolchain and image packaged;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.515s`);
  - no mainline USB/diag channel appeared;
  - host monitor timed out at `t+108.4s` with no adb/no mainline channel;
  - follow-up host check found LineageOS adb and post-reset PON log again reported
    SID0 `PS_HOLD`.
- Interpretation:
  - a bare BOB-mode vote is not the missing liveness action;
  - the unusually long reset/return timing keeps broader downstream RPM
    regulator/default-vote parity high-value, but it needs a separate oracle.

### K016 — DT-backed PM8998 L19 downstream default-vote oracle

- Handles:
  - patch `out/aurel-latest-rpm-l19-always-on-oracle-2026-07-06.patch`
    (sha256 `41bb06f48df489e454c4d44aab7284e6990ac97367b8b8925e68cc642c95df45`);
  - image `out/boot-joan-latest-rpm-l19-always-on.img`
    (sha256 `84134c0d71c7f7eafae9e6a268c50302238a002b6c11c229baa6b52a6ee96e04`,
    size `15736832` bytes);
  - fastboot transcript `out/aurel-rpm-l19-always-on-fastboot-2026-07-06.txt`
    (sha256 `7f5de9a5c9f90f8e1603de7a832ebb7bc0c9b3a6e6bcfb961e421015f408f52a`);
  - PON evidence `out/aurel-rpm-l19-always-on-pon-2026-07-06.txt`
    (sha256 `325bc47d2dd040f34be1795d29ba642e6e5bcb21618d768f5404e54389e43dac`);
  - clean post-oracle repack `out/boot-joan-latest-clean-post-l19-oracle.img`
    (sha256 `69c820614b2e06cdc089717a7971779e35089791f1e058757c9d81cdb65221b3`).
- Class: `debug-only`, rejected as a standalone fix; useful evidence that a
  single downstream PM8998 L19 default vote is not the lone missing gate.
- Public/PR disposition: `do not publish`.
- Touched file: `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`.
- Downstream reference:
  - `msm8998-joan-common-sound.dtsi` forces `pm8998_l19` to 3.3 V with
    `qcom,init-voltage`, `qcom,vdd-voltage-level`, and `regulator-always-on`;
  - mainline joan inherited the generic MSM8998 MTP-style `l19` 3.008 V default
    and no boot/always-on flags.
- Mainline delta tested:
  - update `vreg_l19a_3p0: l19` from `3008000` uV to `3300000` uV;
  - add `regulator-boot-on` and `regulator-always-on` so regulator core applies
    the default through the existing `qcom,rpm-pm8998-regulators` path.
- Verification/evidence:
  - `git diff --check` passed;
  - kernel rebuilt with GCC cross toolchain and image packaged;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.517s`);
  - no mainline USB/diag channel appeared;
  - LineageOS adb returned at `t+57.8s`;
  - post-reset PON log again reported SID0 `PS_HOLD`.
- Interpretation:
  - a single DT-backed downstream L19 default vote is not the missing liveness
    action;
  - broader downstream PM/RPM regulator/default-vote parity still merits testing,
    but not as another single-L19-only oracle.

### K017 — DT-backed PM/RPM overlay parity oracle

- Handles:
  - patch `out/aurel-latest-rpm-pm-overlay-oracle-2026-07-06.patch`
    (sha256 `8b6d4480fe54b7ae7300ecb80b8b4091b542adadb57d1dc986851ec72dfb3c3f`);
  - image `out/boot-joan-latest-rpm-pm-overlay.img`
    (sha256 `de729e6eff09e997de15bdfb0fcf29890e86765228d691f5bb1ca1e185806365`, size `15736832` bytes);
  - fastboot transcript `out/aurel-rpm-pm-overlay-fastboot-2026-07-06.txt`
    (sha256 `ba6cefd54ace1274932cbd5a02defa52e298bc5ed0003be20afb2ec0f6f72c37`);
  - PON evidence `out/aurel-rpm-pm-overlay-pon-2026-07-06.txt`
    (sha256 `15054fdb0af310176c769e71dc31d939d7523a64b936d18e9ecf16fcc4072bdb`);
  - clean post-oracle repack `out/boot-joan-latest-clean-post-pm-overlay-oracle.img`
    (sha256 `eaddd46a1716f36a31fccfe5d9d94ba3c375b53c0ab70df28ac2fac7dca07554`).
- Class: `debug-only`, rejected as a standalone fix; useful evidence that a
  standard DT voltage/enable PM/RPM default bundle is not the sole reset gate.
- Public/PR disposition: `do not publish`.
- Touched file: `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`.
- Downstream reference:
  - common PM overlay sets `pm8998_l18` 2.704 V defaults;
  - common sound overlay sets `pm8998_l19` 3.3 V and always-on;
  - common PM overlay sets PMI8998 BOB `qcom,init-bob-mode = <2>` and pin-control
    children, but mainline lacks those downstream-specific DT/KVP semantics.
- Mainline delta tested:
  - add `regulator-boot-on` to L18;
  - set L19 to 3.3 V and add boot/always-on;
  - force BOB to fixed 3.312 V and add boot/always-on so the existing mainline
    RPM regulator framework sends standard enable/voltage votes.
- Verification/evidence:
  - `git diff --check` passed;
  - kernel rebuilt with GCC cross toolchain and image packaged;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.518s`);
  - no mainline USB/diag channel appeared;
  - LineageOS adb returned at `t+30.6s` after fastboot;
  - post-reset PON log again reported SID0 `PS_HOLD`.
- Interpretation:
  - simple PM/RPM regulator default-vote parity via standard mainline DT
    constraints is not enough;
  - the next useful delta should not be another standard voltage/enable bundle.

### K018 — TCSR DLOAD/restart-cookie oracle

- Handles:
  - patch `out/aurel-latest-tcsr-dload-cookie-oracle-2026-07-06.patch`
    (sha256 `bd4c3fc21b3d10260fe2b7c2ee96291966fdd9b7f43424c97288e876d1e86b97`);
  - image `out/boot-joan-latest-tcsr-dload-cookie.img`
    (sha256 `0ba46735f6f6fac182f3de3f67fe46f5c60c26948be7b1193f7c7147b48645dd`, size `15736832` bytes);
  - fastboot transcript `out/aurel-tcsr-dload-cookie-fastboot-2026-07-06.txt`
    (sha256 `f09b9ded76e826a195d2dc23e356f17953191b2b12b10b5b4f091e66a4d6cdff`);
  - PON evidence `out/aurel-tcsr-dload-cookie-pon-2026-07-06.txt`
    (sha256 `279334aa223eb6ad8d1620544830bee37d535f3be07d376cb0a2620e4abfcbe2`);
  - clean post-oracle repack `out/boot-joan-latest-clean-post-tcsr-dload-cookie-oracle.img`
    (sha256 `38351422d5862f87a42edd51765117fc1b6b60892f6e980c58cda6f725d283f8`).
- Class: `debug-only`, rejected as a standalone fix; useful evidence that the
  downstream TCSR boot-misc DLOAD cookie path is not the sole reset gate.
- Public/PR disposition: `do not publish` as tested. A future clean IMEM/reboot
  support patch may still be evaluated separately, but this oracle alone is not
  evidence for publication.
- Touched file: `arch/arm64/boot/dts/qcom/msm8998.dtsi`.
- Downstream reference:
  - `qcom,msm-imem@146bf000` contains restart/boot/dload children;
  - `qcom,pshold` exposes `tcsr-boot-misc-detect` at `0x1fd3000`, equivalent to
    `tcsr_regs_2 + 0x13000`.
- Mainline delta tested:
  - add `qcom,dload-mode = <&tcsr_regs_2 0x13000>` to the SCM node so mainline
    clears DLOAD bits through the same TCSR boot-misc cookie address.
- Verification/evidence:
  - `git diff --check` passed;
  - kernel rebuilt with GCC cross toolchain and image packaged;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.513s`);
  - no mainline USB/diag channel appeared;
  - LineageOS adb returned at `t+55.5s` from test start;
  - post-reset PON log again reported SID0 `PS_HOLD`.
- Interpretation:
  - the TCSR DLOAD/restart-cookie route is not enough by itself;
  - do not repeat this exact `qcom,dload-mode` phandle as another standalone
    oracle.


### K019 — DEBUG-ONLY / rejected: PM8998 PON S3 source/debounce oracle

- Status: `rejected` / `debug-only`; saved as patch artifact only.
- Branch/test base: `joan/latest-clean-test`.
- Touched files:
  - `drivers/power/reset/qcom-pon.c`
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Artifact:
  - `out/aurel-latest-pon-s3-oracle-2026-07-06.patch`
  - sha256 `e8dfba3949f4ace1d678ed94ce7e254287197ba4c6ee0d6368d4efa642dc051d`
  - config artifact `out/aurel-latest-pon-s3-oracle-config-2026-07-06.txt`, sha256 `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`
  - image `out/boot-joan-latest-pon-s3-oracle.img`, sha256 `2c83d4782aa60564c840efe5122ebfeb9aa30f8e0aea8bab10fc7d70f6fb2c31`
  - fastboot transcript `out/aurel-pon-s3-fastboot-2026-07-06.txt`, sha256 `c8222c05a1ee402d091d708bc14b31c64b7d0b1da0b3aedd99f499a34c0a5f62`
  - PON evidence `out/aurel-pon-s3-pon-2026-07-06.txt`, sha256 `c5acb2a3c56a0a1f1e0c42d5b85c04ea95033f3690cee79251ede518ef048c4d`
  - clean rebuilt image `out/boot-joan-latest-clean-post-pon-s3-oracle.img`, sha256 `7d87765d96df926cac538563dcbe1989f8990d9b784b1c0163926f5cb5f0b0ef`
- Downstream/reference basis:
  - downstream joan PM8998 PON sets `qcom,s3-debounce = <32>` and
    `qcom,s3-src = "kpdpwr-and-resin"`;
  - upstream `qcom-pon` does not consume those properties, so the oracle added a
    minimal DEBUG-ONLY property-driven programming path and joan DT override;
  - `CONFIG_POWER_RESET_QCOM_PON=y` was verified before building.
- Verification/evidence:
  - `git diff --check` passed;
  - kernel rebuilt with GCC cross toolchain and image packaged;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.510s`);
  - no mainline USB/diag channel appeared;
  - LineageOS adb returned at `t+30.5s`;
  - post-reset PON log again reported SID0 `PS_HOLD`.
- Interpretation:
  - downstream PM8998 PON S3 source/debounce parity is not enough by itself;
  - do not repeat this exact PON S3 oracle as another standalone boot test.


### K020 — DEBUG-ONLY / rejected: PM8998 PON reset-sequence/S1/S2 oracle

- Status: `rejected`
- Public disposition: `do not publish` as-is; debug oracle only.
- Touched files:
  - `drivers/power/reset/qcom-pon.c`
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Artifact:
  - `out/aurel-latest-pon-reset-seq-oracle-2026-07-06.patch`
  - sha256 `588264cfb140c0c307a57b8898f5c1c77bf8fa623da32e68ffaa7ce66f9f552c`
  - config artifact `out/aurel-latest-pon-reset-seq-oracle-config-2026-07-06.txt`, sha256 `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`
  - image `out/boot-joan-latest-pon-reset-seq-oracle.img`, sha256 `a0c0e2b6448981798d5cc5b03a4804504caaedff7705a896a42883d86786ee12`
  - fastboot transcript `out/aurel-pon-reset-seq-fastboot-2026-07-06.txt`, sha256 `71f352f65822e597d37a769d374408bb06864c6e2739a839a4cda5132b3b7fd1`
  - PON evidence `out/aurel-pon-reset-seq-pon-2026-07-06.txt`, sha256 `c643c1db1c555052bdb1da483062e86d5b5b691d16d3df8a70e7c928e83d005d`
  - clean rebuilt image `out/boot-joan-latest-clean-post-pon-reset-seq-oracle.img`, sha256 `d543f234ab848f2de12191eca3cf2df2aa87b04711e4665564da93f5cf57f418`
- Downstream/reference basis:
  - downstream joan PM8998 PON has S3 source/debounce values plus reset child
    nodes: `qcom,pon_1`/`qcom,pon_2` with `qcom,support-reset = <0>`, and
    `qcom,pon_3` with `qcom,support-reset = <1>`, `qcom,s1-timer = <6720>`,
    `qcom,s2-timer = <2000>`, and `qcom,s2-type = <PON_POWER_OFF_DVDD_HARD_RESET>`;
  - upstream `qcom-pon` has no support for these reset-sequence child nodes, so
    the oracle added a minimal DEBUG-ONLY property-driven programming path;
  - `CONFIG_POWER_RESET_QCOM_PON=y` was verified before building.
- Verification/evidence:
  - `git diff --check` passed;
  - targeted `qcom-pon.o` and joan DTB builds completed, then full `Image.gz dtbs`
    rebuild and package completed;
  - RAM-only one-client `fastboot boot` succeeded (`Sending`/`Booting` OKAY,
    total `5.522s`);
  - no mainline USB/mass-storage/diag channel appeared;
  - LineageOS adb returned at `t+57.6s` host-script time (`~46.3s` after fastboot
    boot returned);
  - post-reset PON log again reported SID0 `PS_HOLD`.
- Interpretation:
  - fuller downstream PM8998 PON reset-sequence/S1/S2 parity is not sufficient as
    a standalone survival/liveness fix;
  - do not repeat this exact PON reset-sequence oracle as another standalone boot test.


### K021 — comparison-only / no-test: downstream Kryo SCM errata helper

- Status: `comparison-only`, no RAM-boot oracle built.
- Class: rejected as a standalone downstream-parity oracle before testing.
- Touched files: none in the kernel tree.
- Downstream basis inspected:
  - `drivers/soc/qcom/scm-errata.c`
  - `drivers/soc/qcom/Kconfig`
  - `drivers/soc/qcom/Makefile`
  - `arch/arm64/configs/joan*defconfig`
- Finding:
  - downstream has an optional debugfs/hotcpu helper for SCM BOOT command `0x12`
    (`SCM_KRYO_ERRATA_ID`);
  - default booleans would make E74/E75 enable use arg `0x1`, and E76 disable use
    arg `0x100`;
  - `CONFIG_QCOM_SCM_ERRATA` depends on `DEBUG_FS` and `QCOM_SCM`, has no default
    enable, and was not present in the joan downstream defconfigs checked;
  - the helper init path creates debugfs files and registers a CPU_STARTING notifier
    but does not immediately apply the setting to already-online boot CPUs.
- Decision:
  - no debug-only mainline SMC oracle was built because this is not active default
    downstream joan boot-state parity;
  - forcing command `0x12` from mainline would be speculative rather than a direct
    downstream-parity test.
- Artifact:
  - `out/aurel-kryo-scm-comparison-2026-07-06.txt`
- Agent-harness: Hermes:gpt-5.5
- Date: 2026-07-06

### K022 — null-init discriminator (STAGED, not device-tested)

- Handle: image `out/boot-joan-nullinit-discriminator.img`
  (sha256 `ed00e7842b583eb2b12e68ef0f3f39512639590523db415a0bbea0719d837158`);
  initramfs `initramfs/root-null/`; run doc `docs/nullinit-discriminator-run.md`.
- Class: `debug-only` (discriminator; no kernel change — clean
  `joan/latest-clean-test` kernel + a do-nothing initramfs).
- Touched files: none in the kernel tree; new `initramfs/root-null/init` only.
- Premise / why it is different from K005-K021: EVERY prior oracle was booted
  with the full bring-up init, which runs `wdkill` (writes APSS watchdog regs
  at 0x17817000 via /dev/mem — round 18 showed EN=0 there PROVOKES an earlier
  reset) and brings up dwc3/PHY. So no result to date observed the phone with
  Linux userspace doing NOTHING. The large reset-timing variance across
  Aurel's runs (~30s to ~108s host cycle) is itself more consistent with a
  variable-timing userspace trigger than a fixed hw watchdog period.
- What it tests: boot the clean kernel with an init that touches no hardware,
  no /dev/mem, no gadget, and idles through the whole 0-150s window; only if
  it survives to 150s does it raise a distinct survivor beacon (18d1:5e30).
- Expected discrimination:
  - LOS returns ~30-60s -> reset is a BACKGROUND secure/firmware timer,
    independent of userspace -> the entire handshake-parity line (K006-K021)
    cannot fix it; any fix is secure-world/signed-firmware. STOP that line.
  - survivor beacon 18d1:5e30 at ~150s -> a do-nothing init SURVIVES ->
    something the normal init does (wdkill regs, or dwc3/PHY) TRIGGERS the
    reset -> next passes bisect wdkill-only vs gadget-only.
- RESULT (device-tested 2026-07-06, Lance present): **LOS RETURNED at +33s.**
  The reset happened even with a do-nothing init. Post-reset PON identical:
  `Power-off: PS_HOLD`, `PON=0x21:HARD_RESET, POFF=0x2:PS_HOLD, FAULT1=0x40:UVLO`.
  Timing (~33s host cycle) is within the same family as busy-init runs, i.e.
  removing ALL userspace activity (wdkill /dev/mem writes + gadget/UDC bring-up)
  did NOT change the reset. => the resetter is INDEPENDENT OF USERSPACE.
- Consequence: the handshake-parity line (K006-K021) is confirmed futile —
  nothing userspace does can satisfy or provoke it. The reset is either a
  secure/firmware background timer, or kernel-init-time driver behaviour that
  runs regardless of init (null-init does NOT disable kernel driver probing).
- Honest scope note: this does NOT prove "pure firmware" — it proves
  "not userspace." Splitting firmware-timer vs kernel-probe is the next step
  (K023): strip kernel driver probing (initcall_blacklist / minimal config /
  minimal DT) and/or measure whether the reset period is FIXED across runs
  (fixed => hardware/secure watchdog; variable => probe/thermal triggered).
- Public/PR disposition: `do not publish`.
- Written-by: Ember Nymbrand (agent-ember)
- Agent-harness: Claude-Code:claude-fable-5
- Date: 2026-07-06

### K023 — minimal-DTB firmware-vs-driver discriminator (INCONCLUSIVE: DTB too aggressive)

- Handle: DTS artifact `out/ember-mindtb-K023-2026-07-06.dts`; images
  `out/boot-joan-mindtb-nullinit.img`
  (sha256 `042197d1da8ad03621edb63840cf48776aa73920dff00153804041b97be98eb4`),
  proof-of-life `out/boot-joan-mindtb-pol.img` and
  `out/boot-joan-mindtb-pol2.img`. Kernel tree reverted clean after.
- Class: `debug-only`, INCONCLUSIVE.
- Goal: split K022's result further — is the userspace-independent reset a
  firmware/secure background timer, or kernel-side driver-probe behaviour?
  Method: clean kernel Image + a minimal DTB that enables NO board
  peripherals (no usb/dwc3, phy, regulators/RPM, watchdog, ufs, wifi, keys;
  only SoC skeleton + LG firmware reserves + dummy regs for 3 dangling
  msm8998.dtsi phandles) + null init.
- Result: min-DTB null-init returned LOS at +49s — but PROOF-OF-LIFE
  disproved the naive reading. An immediate-reboot init (first userspace
  act; full-DTB baseline round 12 = +26.5s) on the SAME min-DTB returned at
  +47s, i.e. the ~panic=30 window, NOT ~27s. So **the minimal DTB never
  reaches userspace — it panics early in kernel boot.** The +49s was a boot
  failure, not a reset. INCONCLUSIVE for the firmware-vs-driver question.
- Lesson (logged): a boot failure with panic=N is indistinguishable from a
  real reset by host-return timing alone; always pair a DTB/-config strip
  with an immediate-reboot proof-of-life before trusting a "still resets"
  reading. (Caught a false "firmware timer" conclusion.)
- Likely over-strip cause: removing the full &rpm_requests regulator block
  (replaced 3 phandles with a dummy fixed-reg) probably broke rpmcc/clock
  or a critical early consumer -> early panic. Do NOT repeat this strip.
- Better next design (boot-safe): start from the KNOWN-GOOD full joan DTS
  (boots to userspace) and remove ONE suspect subsystem at a time
  (USB/dwc3+phy first, since that is what we are ultimately bringing up),
  keeping regulators/RPM/clocks/UFS intact so it still boots. Each pass:
  full-DTB-minus-X + null init; if the reset stops, X's bring-up is the
  trigger. Pair each with an immediate-reboot proof-of-life if the result
  is "still resets".
- Public/PR disposition: `do not publish`.
- Written-by: Ember Nymbrand (agent-ember)
- Agent-harness: Claude-Code:claude-fable-5
- Date: 2026-07-06

### K023b — full-DTB-minus-USB (boot-safe): USB bring-up is NOT the trigger

- Handle: DTS artifact `out/ember-nousb-K023b-2026-07-06.dts`; image
  `out/boot-joan-nousb-k023b.img`
  (sha256 `fd7bb3e3da65b7d0669da15caccc86acb7d5e1453454ffd71564f701240b63de`).
  Kernel tree reverted clean after.
- Class: `debug-only`; result CONCLUSIVE (boot-confound-free).
- Method: the KNOWN-GOOD full joan DTS with only `&usb3` and `&qusb2phy`
  set `status="disabled"` (kernel never probes dwc3 / QUSB2 PHY), + a
  classifier init, booted with **panic=0** so a boot failure HANGS (silent)
  instead of masquerading as a reset. Three separable outcomes: silent =
  boot-fail; LOS ~43s = natural reset (USB not trigger); LOS ~106s (our
  90s survivor reboot) = survived => USB is trigger.
- Result: LOS returned at +49s. With panic=0 that cannot be a boot panic
  (would hang silent), and it is well before the 90s survivor reboot, so it
  is the natural PS_HOLD reset — confirmed by post-reset PON
  (`POFF=0x2:PS_HOLD, PON=0x21:HARD_RESET, FAULT1=0x40:UVLO`, identical).
- Conclusion: disabling USB does NOT stop the reset => kernel-side
  USB/dwc3/QUSB2-PHY bring-up is NOT what trips the ~27s reset. Eliminated.
- Note: this is the boot-safe subtraction method K023 recommended, and it
  worked — panic=0 removed the boot-vs-reset confound cleanly. Reuse this
  harness to subtract the next subsystem (candidates below).
- Public/PR disposition: `do not publish`.
- Written-by: Ember Nymbrand (agent-ember)
- Agent-harness: Claude-Code:claude-fable-5
- Date: 2026-07-06

### K023c — full-DTB-minus-UFS (boot-safe): UFS bring-up is NOT the trigger

- Handle: DTS `out/ember-noufs-K023c-2026-07-06.dts`; image
  `out/boot-joan-noufs-k023c.img`
  (sha256 `45564b83948eead68207cceb259e2de3ef6538f49d775b808d43f05f372c5b52`).
  Kernel tree reverted clean after.
- Class: `debug-only`; CONCLUSIVE (same panic=0 boot-safe harness as K023b).
- Method: full known-good joan DTS with only `&ufshc` + `&ufsphy`
  `status="disabled"`, panic=0 classifier init.
- Result: LOS returned at +30s — natural reset (panic=0 rules out boot-fail;
  well before the 90s survivor reboot). Reset persists.
- Conclusion: kernel UFS host-controller / UFS-PHY bring-up is NOT the ~27s
  reset trigger. Eliminated.
- Public/PR disposition: `do not publish`.
- Written-by: Ember Nymbrand (agent-ember)
- Agent-harness: Claude-Code:claude-fable-5
- Date: 2026-07-06

### K023d/e — RPM eliminated; capstone: trigger is in the SoC core/firmware

- K023d (RPM): full joan DTS with `&rpm_requests` disabled, panic=0. LOS at
  +47s (real reset) => RPM/regulator bring-up is NOT the trigger.
  Artifact `out/ember-norpm-K023d-2026-07-06.dts`,
  image `out/boot-joan-norpm-k023d.img`
  (sha256 `0153fbb599e8d3979032c2d90d0966dd2ef3041da10be1056a8f67ede121daed`).
- K023e (CAPSTONE): full joan DTS with ALL removable board peripherals
  disabled at once (usb3, qusb2phy, ufshc, ufsphy, wifi, pm8005_regulators),
  keeping only the un-removable SoC core (clocks, RPM, SCM/PSCI, GIC, timer),
  panic=0. LOS at +31s (real reset). Artifact
  `out/ember-corestrip-K023e-2026-07-06.dts`,
  image `out/boot-joan-corestrip-k023e.img`
  (sha256 `22a6a640c6c3f13f955a709ecc92a3097116fa11d59af4b94fb92d6b723248f3`).
- CONCLUSION of the subtraction line (K022, K023b/c/d/e): the ~27-31s
  PS_HOLD reset is triggered by the **SoC core / firmware**, NOT by any
  removable board peripheral bring-up (USB, UFS, RPM/regulators, wifi, PMIC
  regs all eliminated) and NOT by userspace. It fires regardless of what
  Linux brings up. A RAM-booted STOCK LG kernel does NOT reset, so it is a
  real mainline-vs-downstream kernel difference at the core/secure level.
- Timing note: LOS-return times are bimodal (~31 vs ~48s) across otherwise-
  identical runs — unexplained; may be reset-moment or LG-boot bimodality.
- Class: `debug-only`, both CONCLUSIVE. Public/PR: `do not publish`.
- Written-by: Ember Nymbrand (agent-ember)
- Agent-harness: Claude-Code:claude-fable-5
- Date: 2026-07-06

### K024 — kernel-side APSS watchdog pet: reset PERSISTS => secure/TZ watchdog

- Handle: patch driver `drivers/soc/qcom/joan_wdt_pet.c` (reverted; see
  git history / this entry); image `out/boot-joan-wdtpet-k024.img`
  (sha256 recorded in build). DEBUG-ONLY, reverted clean.
- Class: `debug-only`; CONCLUSIVE.
- Method: device_initcall (~1-2s) that maps the APSS watchdog at 0x17817000
  and pets it (WDT_RST=0x4) every 500ms from KERNEL space, with max
  bark/bite, never writing EN=0 (round 18 showed EN=0 provokes a reset).
  Full joan DTB, null classifier init, panic=0.
- Result: LOS at +49s — reset PERSISTS. Kernel-side petting of the
  non-secure APSS watchdog does NOT stop the reset (matches wdkill's earlier
  userspace-pet failure, but now from early boot with kernel privilege).
- Conclusion: the ~27-31s PS_HOLD reset is NOT the pettable non-secure APSS
  watchdog. It is a SECURE / TZ-side watchdog (or its pet writes are
  XPU-blocked from non-secure world). Non-secure Linux cannot service it by
  petting, and (Aurel) SEC_WDOG_DIS SCM is unimplemented (-2). 
- IMPORTANT nuance (keeps this from being "needs signed TZ, give up"): a
  RAM-booted STOCK LG KERNEL (also unsigned) SURVIVES (rounds 15-16). So
  downstream's KERNEL software keeps this secure watchdog alive via some
  secure/SCM interaction that mainline does not replicate — i.e. likely
  fixable from the kernel once that interaction is found. Prime place to
  look: downstream `drivers/soc/qcom/watchdog_v2.c` secure-watchdog handling
  and any early SCM/qseecom/tz-app bring-up beyond SEC_WDOG_DIS.
- Public/PR disposition: `do not publish`.
- Written-by: Ember Nymbrand (agent-ember)
- Agent-harness: Claude-Code:claude-fable-5
- Date: 2026-07-06


### K025 — secure-interface archaeology / watchdog_v2-QSEECOM comparison (NO BOOT ORACLE)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Aurel followed Ember's session-2 handoff by inspecting downstream early
secure/TZ/SCM paths before spending another boot cycle. Goal: find exactly one
active downstream-default, early, state-changing secure call that mainline lacks
and that is safe enough to test as a debug oracle.

Sources compared:

- downstream `drivers/soc/qcom/watchdog_v2.c`
- downstream `drivers/misc/qseecom.c`
- downstream `drivers/soc/qcom/qsee_ipc_irq_bridge.c`
- downstream `include/soc/qcom/qseecomi.h`
- downstream MSM8998/joan DT and joan defconfigs
- mainline `drivers/firmware/qcom/qcom_scm.c`
- mainline `drivers/firmware/qcom/qcom_qseecom.c`
- mainline `drivers/firmware/qcom/Kconfig`
- mainline MSM8998/joan DT and active `.config`

Findings:

- `SEC_WDOG_DIS` is still the only obvious secure-watchdog disable path in
  downstream `watchdog_v2.c`. It was already rejected, and downstream LineageOS's
  own sysfs disable path fails on this device with `0x42000107 ret=-2`.
- The other secure call visible in `watchdog_v2.c`, `SCM_SVC_UTIL` /
  `SCM_SET_REGSAVE_CMD` (`cmd 0x2`), registers a CPU register-save page for
  watchdog-bite dump collection. Failure only means registers will not be dumped
  on a dog bite. It is crashdump setup, not a pet/ack/keepalive.
- Current mainline already has `CONFIG_QCOM_SCM=y`, `CONFIG_QCOM_TZMEM=y`, and
  `CONFIG_QCOM_QSEECOM=y`, and `qcom_scm_probe()` already calls
  `qcom_scm_qseecom_init()`. That function performs the QSEECOM version query
  before applying the machine allowlist, so repeating the version query is not a
  new oracle.
- Mainline skips creating the `qcom_qseecom` platform device on joan because
  `lge,joan` is not in the QSEECOM allowlist. Enabling it would currently mainly
  add a `qcom.tz.uefisecapp` app lookup, which is not downstream joan default
  liveness parity and should not be the next reset oracle.
- Downstream `qseecom_probe()` can send `QSEOS_APP_REGION_NOTIFICATION`, but the
  downstream MSM8998 qseecom node sets `qcom,appsbl-qseecom-support`; with that
  property true, downstream treats appsbl/boot firmware as already handling the
  region/commonlib state and skips the region notification path. Joan variant
  DTs only resize `qseecom_mem` to `0x1800000`; they do not remove the property.
- `qsee_ipc_irq_bridge.c` is char-device/IRQ/SSR notification plumbing and does
  not issue an SCM/QSEE liveness call at probe.
- `CONFIG_QCOM_EARLY_RANDOM=y` appears in joan defconfigs, but source search in
  this tree only found config references, not a concrete implementation to
  transplant or compare.

Decision:

- No K025 boot image was built.
- No K025 fastboot boot was run.
- This path is recorded as comparison-only / no-test so future agents do not
  waste a boot on inactive or already-covered calls.

Artifact:

- `out/aurel-secure-interface-archaeology-k025-2026-07-06.txt`
- sha256 `f1a47398089fd7640179a042a8f3016005c3526b5d498fad58cbed5f4f06b630`

Next better targets:

- downstream LGE panic/restart-reason plus IMEM/SMEM boot-cookie setup, kept
  distinct from the already-rejected TCSR DLOAD phandle oracle;
- any early `SCM_SVC_BOOT` or TZ setup before/around downstream `msm_watchdog`
  init that is not `SEC_WDOG_DIS` and not dump-only;
- stock-RAM-boot/downstream dmesg diffs around the first second, especially
  secure monitor, qseecom, msm_watchdog, and restart-reason lines.


### K026 — LGE IMEM default restart-reason oracle: reset PERSISTS; returned bootreason is TZ-class 0x6D630309

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Downstream/mainline comparison:

- Downstream joan enables `CONFIG_LGE_HANDLE_PANIC=y`.
- Downstream MSM8998 defines `qcom,msm-imem@146bf000` with `restart_reason@65c`.
- Downstream `drivers/soc/qcom/lge/lge_handle_panic.c` maps IMEM in an
  `early_initcall` and writes `LGE_RB_MAGIC | LGE_ERR_TZ` (`0x6d630300`) to
  restart_reason.
- Mainline MSM8998 has no LGE panic handler and no msm-imem/restart_reason node.

Oracle:

- Reused existing debug-only branch `joan/imem-oracle`, commit `f0d368d28`, rather
  than creating a duplicate patch.
- Rebuilt/repackaged with the K023 `panic=0` null-init classifier so a boot fail
  cannot fake a reset/survival result.
- Patch artifact: `out/aurel-lge-imem-default-reason-k026-2026-07-06.patch`
  sha256 `d68baabab6c1b82d0b976b826de49a5aed621747893bf5fe40fa98fba8a89f62`.
- Boot image: `out/boot-joan-imem-k026.img`
  sha256 `ccf08dbea0e889fa11404335d423e46e5078f37883469234694aff4d3939d035`.
- Result artifact: `out/aurel-lge-imem-k026-result-2026-07-06.txt`.

Device result:

- `fastboot boot` was RAM-only and completed normally: Sending OKAY `[0.410s]`,
  Booting OKAY `[5.095s]`, total `5.513s`.
- No mainline USB/survivor beacon appeared.
- LineageOS adb returned at `t+49.1s` after fastboot returned.
- Classification: `lineageos_returned_reset_not_fixed`.
- Post-reset PON remained SID0 `PS_HOLD` (`PON=0x21:PON1:HARD_RESET`,
  `POFF=0x2:PS_HOLD`).
- Returned downstream kernel reported `androidboot.product.lge.bootreasoncode=0x6D630309`
  and `LGE BOOT REASON: 0x6d630309`.

Interpretation:

- K026 is rejected as a survival/liveness fix: simply matching downstream's early
  LGE IMEM default restart-reason write does not stop the reset.
- K026 is useful forensic evidence: the returned boot chain/downstream kernel now
  exposes an LGE/TZ-class bootreason (`0x6D630309`).
- From `lge_handle_panic.h`, `0x6d630000` is `LGE_RB_MAGIC` and `0x0300` is
  `LGE_ERR_TZ`; subreason `0x0009` is not defined in this downstream kernel
  header. It is not the named TZ non-secure watchdog bark (`0x3a`) or thermal
  secure bite (`0x3b`).
- Future work should chase where LG/XBL/TZ defines or emits TZ subreason `0x09`,
  or compare the early secure-world handshake that causes that private TZ reset.
  Do not repeat K026 as another liveness test.

## Current narrowed hypothesis

The blocker still looks like a secure/boot-chain/platform-state resetter, but
not one solved by the simple downstream sysfs `SEC_WDOG_DIS` path, direct APSS
watchdog pets, CPU-idle changes, single-core boot, simply reserving the observed
downstream high-memory secure/shared pools, matching downstream's DLOAD-off SCM
argument shape, registering a downstream-style QSEE log buffer, merely reaching
RPM `rpm_requests` rpmsg setup, sending a bare downstream BOB `bobm=2` RPM
vote, forcing downstream joan's PM8998 L19 3.3 V always-on default through the
mainline regulator framework, forcing a broader standard DT-backed PM/RPM
L18+L19+BOB voltage/enable bundle, routing SCM DLOAD-mode clearing through
the downstream-observed TCSR boot-misc cookie (`qcom,dload-mode = <&tcsr_regs_2
0x13000>`), programming downstream joan's PM8998 PON S3 source/debounce
(`qcom,s3-debounce = <32>`, `qcom,s3-src = "kpdpwr-and-resin"`), matching
the fuller downstream PM8998 PON reset-sequence/S1/S2 setup, forcing the
optional downstream Kryo SCM errata debugfs helper, retesting the obvious
downstream `watchdog_v2`/QSEECOM probe paths checked in K025, or repeating the
LGE IMEM default restart-reason write tested in K026. The Kryo helper is
not active joan default boot-state parity, and K025 did not find an active
downstream-default QSEECOM/watchdog secure call that mainline lacks, so no boot
oracle was built for either; K026 then showed the LGE IMEM default restart-reason
write does not stop the reset but does expose TZ-class bootreason `0x6D630309`.
Next investigation should compare another very early downstream state-changing
path against mainline, especially:

- the source/meaning of LG/TZ subreason `0x09` in XBL/TZ/bootloader-visible logs;
- broader downstream RPM regulator/default votes / clocks / power-domain requests;
- SMEM/bootreason/restart cookies;
- other early `SCM_SVC_BOOT` / TZ setup before or around downstream
  `msm_watchdog` init;
- downstream dmesg events before ~0.4s that mainline does not mirror.

## Attribution

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## Aurel follow-up — K027 decoded as TZ CONF_NOC_ERR; clk/power-retention attempt inconclusive

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

K026's returned downstream bootreason `0x6D630309` is now decoded using a public
older LG/QCOM header from the bullhead msm kernel:

- URL: `https://android.googlesource.com/kernel/msm.git/+/android-msm-bullhead-3.10-n-preview-1/include/soc/qcom/lge/reboot_reason.h?format=TEXT`
- Preserved artifact: `out/aurel-k027-public-bullhead-reboot_reason.h`
- Header hash: `90e24ee46dfedef922c02a55f492b01af460bbbdae1a1c9c3bd40e4fdb8b0355`
- Relevant define: `LGE_ERR_TZ_CONF_NOC_ERR = 0x0009`

Therefore `0x6D630309 = LGE_RB_MAGIC | LGE_ERR_TZ | LGE_ERR_TZ_CONF_NOC_ERR`.
The reset is specifically being reported by the downstream boot chain/kernel as a
TrustZone Config NoC error, not only a generic TZ-class event.

Comparison notes:

- Downstream MSM8998 includes Qualcomm legacy `msm_bus`/NoC/BIMC fabric plumbing
  and many `qcom,msm-bus` vote tables (`qseecom-noc`, `qcrypto-noc`,
  `qcedev-noc`, `msm-rng-noc`, UFS, USB, IPA, PCIe, Venus, TSIF, etc.).
- Mainline MSM8998/joan has generic QCOM interconnect support enabled in `.config`,
  but no MSM8998 ICC provider and no MSM8998/joan interconnect votes in the active
  DT.
- A cheap cmdline-only discriminator was built to keep bootloader-enabled clocks and
  power domains from being disabled: `clk_ignore_unused pd_ignore_unused`, retaining
  the K023 `panic=0` classifier.

Artifacts:

- Result: `out/aurel-k027-conf-noc-decode-and-clkpd-attempt-2026-07-06.txt`
- Image: `out/boot-joan-clkpd-k027.img`, sha256
  `60f5484be2aaa8616681dd09130b47decc8684bf6d1e3feb96df2fc90f08bb0e`
- Cmdline artifact: `out/aurel-k027-clkpd-cmdline-2026-07-06.txt`, sha256
  `cd7ec2fb23b86cc00fcd34f433f1bfbfcaee4573f2be24833cadb3588f400ace`
- Fastboot/attempt log: `out/aurel-k027-clkpd-fastboot-2026-07-06.txt`, sha256
  `92fd7bec7355c4cb62978904186e013ec976bd7a3dc6a7225c0a4e455af491df`
- Passive post-timeout observation: `out/aurel-k027-post-timeout-observe-2026-07-06.txt`,
  sha256 `bf7dad650ef88d18b97a4e784b6980e33ddf68d523722f68d694d85176adedb1`

Device result:

- **Inconclusive / not a valid device test.**
- No `fastboot boot` `Sending`/`Booting` OKAY was captured.
- Normal-user `fastboot boot out/boot-joan-clkpd-k027.img` timed out after 45s;
  immediate diagnostics first saw a fastboot USB device with `no permissions`, then
  the phone disappeared from adb/fastboot/USB entirely.
- A 224s passive observation loop saw no adb device, no fastboot device, and no
  LG/Google/Qualcomm phone USB device.
- No PON readback was possible.

Interpretation:

- K027's source decode is useful and should be carried forward: the clue is
  `TZ_CONF_NOC_ERR`.
- The clk/power-retention image is neither accepted nor rejected; it still needs a
  valid one-client sudo-fastboot retry after physical phone recovery.
- Do not spend more remote attempts while the phone is absent from USB. After
  recovery, either retry the exact K027 image once or move to a better-supported
  NoC/config-fabric oracle based on downstream MSM8998 bus/ICC parity.

## K028 (prep) — CONF_NOC mechanism identified in source: late unused-clock/genpd sweeps (no device test)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Source-only session; phone absent from USB throughout (no device contact).
Full analysis: `docs/k028-conf-noc-sweep-hypothesis-2026-07-07.md`.

Mechanism (best fit for `LGE_ERR_TZ_CONF_NOC_ERR`):

- `clk_disable_unused()` (late_initcall_sync) + genpd power-off-unused
  (late_initcall) gate every XBL-left-on GCC branch clock/GDSC that our
  driverless mainline boot never claims. A later register-path access into a
  gated block — most plausibly TZ's periodic PRNG entropy reseed — fails on
  the Config NoC; LG TZ policy logs `TZ|CONF_NOC_ERR` and pulls PS_HOLD.
- Explains: all K022–K024 resets (every config ran the sweeps; each had
  victims), K023d no-RPM reset (victims are GCC-side, built-in), the jittery
  +27–31s timing (event-driven TZ access, not a watchdog period), and the
  stock-kernel survival (downstream sweeps too — `clock_late_init()` — but
  its full driver set claims nearly everything first: msm_rng, qseecom,
  mdss cont-splash, msm_bus keepalives).

Key source facts (verified this session, mainline v7.2-rc2 vs LOS 4.4):

- gcc-msm8998.c: **zero** `CLK_IGNORE_UNUSED`; only 3 `CLK_IS_CRITICAL`
  (gpu_cfg_ahb, mmss_noc_cfg_ahb, mss_q6_bimc_axi). All other boot-on
  branches sweepable (prng_ahb, boot_rom_ahb, mmss_sys_noc_axi, mmss_qm_*,
  aggre1_noc_xo, cfg_noc_usb3_axi, bimc_hmss_axi, …).
- PRNG standout: downstream `qrng@793000` claims `gcc_prng_ahb_clk` + votes
  `msm-rng-noc` + `qcom,no-qrng-config` (TZ owns config). Mainline
  msm8998.dtsi has **no rng node**; no qcom-rng driver in .config → clock
  swept every boot while TZ still uses the block.
- RPM fabric clocks are NOT sweepable (msm8998_icc_clks never registered in
  CCF; INT_MAX handoff votes persist; no 8998 ICC provider exists) —
  consistent with K023d.
- OnePlus 8998 precedent: their simplefb node holds 8 MDSS clocks +
  MDSS_GDSC explicitly "due to unused clk cleanup". (MMCC=m ⇒ MDSS clocks
  never registered in our RAM boots ⇒ not suspects for current resets.)
- LGE error taxonomy separates MM/PERIPH/SYS/CONF NoC codes ⇒ 0x09 pins the
  failure to the register path, not display/data traffic, not XPU.

Consequence: K027 (`clk_ignore_unused pd_ignore_unused`) is exactly the
class discriminator. Its single valid retry after physical phone recovery
classifies the whole hypothesis: survive ⇒ bisect (K028a clk-only ⇒ K028b
mark prng_ahb+boot_rom `CLK_IGNORE_UNUSED` ⇒ durable fix = msm8998.dtsi rng
node + `CONFIG_CRYPTO_DEV_QCOM_RNG=y`); valid reset ⇒ entire sweep class
eliminated in one boot ⇒ fall back to TZ-affirmative-keepalive line.

No kernel or DTS changes committed; no images built. Predictions recorded in
the analysis doc before any device test.

## K027 (valid retry) — REJECTED, and the reset re-labeled itself: MM NoC error, not Config NoC

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Phone physically recovered by Lance (was in LineageOS, adb visible). Valid
one-client pass, script `$CLAUDE_JOB_DIR/tmp/k027-run.sh`, full log
`out/ember-k027-valid-retry-2026-07-07.log`:

- Sending OKAY 0.409s, Booting OKAY 5.096s (sudo -n fastboot, adb-entered).
- Handoff t+12s; LineageOS adb back at t+42s (+30s after handoff).
- **RESET PERSISTS with `clk_ignore_unused pd_ignore_unused`.**
- PON: PS_HOLD as always. But the boot chain self-labeled the crash:
  `androidboot.product.lge.bootreasoncode=0x6D630306` =
  `LGE_RB_MAGIC | LGE_ERR_TZ |` **`LGE_ERR_TZ_MM_NOC_ERR (0x0006)`**.

Two consequences:

1. **TZ/XBL labels every reset on its own** — K026's kernel-side IMEM write
   was not needed for labeling. Every future pass gets a free reason code;
   read it back every time (runner already does).
2. **K027 changed the failure**: with the late clk/genpd sweeps disabled the
   Config-NoC error (K026, 0x09) is GONE and a **Multimedia-NoC** error
   surfaces instead. So the K028-prep sweep analysis was not wrong but
   incomplete: the sweeps were implicated in the CNoC layer; beneath it
   something else kills the MM NoC ~5-15s after handoff. Prediction 1/3 of
   the prep doc falsified as written (survival), prediction 2 falsified in
   the useful direction (code changed, not stayed).

Method upgrade adopted: **onion-peel by bootreason** — one variable per
pass; each reset's LGE subcode names the stratum that fired first.

Suspect ranking for MM_NOC under retention: (a) RPM stratum — OnePlus-derived
regulator votes applied at ~2s (never cross-checked vs LG downstream, per
project memory), rpmcc INT_MAX handoff + enable_scaling; (b) XBL-left-live
display/QM hardware interacting with retained-but-unmanaged state; (c) SMMU
global resets (weakened: mmss_smmu defers forever on &mmcc clocks, MMCC=m —
display translations never touched; anoc1/2/lpass/adreno smmus feed other
NoCs).

Next: **K028 = K027 cmdline + `&rpm_requests` disabled** (proven K023d DTS
edit) — removes the whole RPM stratum under retention. Survive ⇒ split
regulators vs clk-handoff next. Reset ⇒ RPM stratum innocent; read the new
label and peel the next stratum (SMMU blacklist pass is staged as K029).

## K028 — RPM disabled (on top of K027) REGRESSES to Config NoC; RPM must stay enabled

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Onion-peel step 2. Built `&rpm_requests { status = "disabled"; }` (K023d
pattern) on top of K027's DTS+cmdline (full joan DTS otherwise,
`clk_ignore_unused pd_ignore_unused`). DTS: `out/ember-k028-norpm-clkpd-
2026-07-07.dts`, DTB via cpp+dtc (kernel Image.gz unchanged, Jul 6 16:39
build). Image `out/boot-joan-norpmclkpd-k028.img`, sha256
`068fee7299dcfafa90de5ede5b92f35240b2b5d61497c7a01f28467b246b1ecf`. Runner
`out/ember-k028-valid-retry-2026-07-07.log`.

Result: **reset persists**, LOS returned t+61s (49s after handoff), PON
PS_HOLD. Bootreasoncode: **`0x6D630309` (TZ_CONF_NOC_ERR) — back to K026's
code, NOT K027's `0x6D630306` (TZ_MM_NOC_ERR).**

Interpretation: removing RPM regresses past the point K027 had reached.
RPM's `clk-smd-rpm` icc_clks handoff (one-shot INT_MAX vote to RPM firmware
for aggre1/aggre2 NoC, BIMC, SNoC, **CNoC**, MMSS NoC AXI at probe, never
lowered, never CCF-registered so unsweepable) is load-bearing scaffolding:
with it gone, boot re-hits the same Config NoC wall K026 hit. With it
present (K027) AND the late clk/genpd sweeps also held off, boot gets
further and a **different, MM-specific** NoC fault surfaces instead —
implying the Config NoC failure needs BOTH an RPM bus/QoS vote AND a
clock the late sweep would otherwise kill; removing either one re-exposes
it. **Binding: keep `&rpm_requests` ENABLED in all further tests}** — this
is scaffolding to preserve, not a suspect.

Ledger correction to K023d: that earlier no-RPM-alone test (default
cmdline, sweeps ON) also showed "reset persists" — now understood as
*also* hitting the Config NoC wall (RPM removed = its own separate route
to the same CNoC failure), not evidence RPM/regulators are unrelated to
NoC health as originally read.

Next (K029, queued/running): keep K027's base (RPM enabled, clk/pd
retained) and peel a component specifically on the **MM** side. Candidate
selected: `anoc1_smmu` (iommu@1680000) — the only SMMU in msm8998.dtsi
with zero `iommus=` consumers anywhere in the tree and no `clocks=`
property at all, yet `status` defaults enabled, so arm-smmu-v2 still
probes/touches it with nothing voting for its fabric segment. anoc2
(wifi), adreno_smmu (gpu), mmss_smmu (video, inert since MMCC=m defers it)
are left untouched.

## K029 — anoc1_smmu disabled (on top of K027) ALSO regresses to Config NoC

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Onion-peel step 3. Built `&anoc1_smmu { status = "disabled"; };` on top of
K027's DTS+cmdline (RPM left enabled per the K028 lesson). Rationale:
anoc1_smmu is the only SMMU in msm8998.dtsi with zero `iommus=` consumers
anywhere in the tree AND no `clocks=` property at all, yet defaults to
`status = "okay"`, so arm-smmu-v2 still probes/touches it every boot.
DTS: `out/ember-k029-noanoc1-2026-07-07.dts`. Image
`out/boot-joan-noanoc1clkpd-k029.img`, sha256
`72b88d1e079fbc06493b6650216971e23cd3d2b75b1d265fa19e7d40b1edb363`. Kernel
Image.gz unchanged (Jul 6 16:39 build) — DTS/cmdline-only test. Runner
`out/ember-k029-valid-retry-2026-07-07.log`.

Result: **reset persists**, LOS returned t+52s (40s after handoff), PON
PS_HOLD. Bootreasoncode: **`0x6D630309` (TZ_CONF_NOC_ERR) — regressed from
K027's `0x6D630306` MM_NOC, same as K028's regression.**

Interpretation: this is now a *pattern*, not a coincidence. Two independent
"remove one thing" experiments (K028: disable RPM; K029: disable
anoc1_smmu) have both fallen back to the exact same Config NoC code, while
the *only* configuration that has ever reached the deeper MM NoC fault is
K027 — RPM enabled, clk/pd retained, and the **full, unmodified** board
file otherwise. Disabling `anoc1_smmu` doesn't remove a harmless orphan; it
removes something the boot chain needs, exactly like disabling RPM did.
Best current read: `anoc1_smmu`'s arm-smmu-v2 probe (global ID/config
register reads, SMMU reset) touches shared aggregator-NoC infrastructure
in a way that keeps the Config NoC alive for later accesses, even with no
translation consumer — plausibly because its missing `clocks=` property is
itself a mainline DT omission (the block may need an explicit clock this
node doesn't model), and the *symptom* of that omission is masked rather
than fixed by disabling the node outright.

Method correction: stop hypothesizing "orphan nodes are safe to cut."
Test *additions*/*corrections* against K027's untouched full DTS instead
of further subtractions until the MM NoC fault is reproduced past K027's
own baseline. Next candidate (K030): check downstream DT for the
anoc1-equivalent SMMU's `clocks=` property (mainline may simply be missing
one) rather than disabling the mainline node again.

## K030 — SMMU skip-reset patch: the specific TZ NoC-fault signature is GONE

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Root-cause lead, not a subtraction test. Downstream
`arch/arm/boot/dts/qcom/msm-arm-smmu-8998.dtsi` marks `anoc1_smmu`
(`arm,smmu-anoc1@1680000`) `qcom,skip-init` + `qcom,register-save`: real
Qualcomm properties meaning TZ/XBL already owns and configured this SMMU
instance, and the downstream driver deliberately never runs a global
reset on it. Mainline's `arm_smmu_device_reset()`
(`drivers/iommu/arm/arm-smmu/arm-smmu.c`) has no equivalent concept — it
unconditionally clears sGFSR, forces every SMR invalid and every S2CR to
bypass, and invalidates the TLB on every probed SMMU, every boot.

Added a debug-only kernel patch gating that entire sequence behind a new
`ember,debug-skip-reset` DT boolean (patch saved to
`out/ember-k030-skip-smmu-reset-debug.patch`, applied then built into a
fresh `Image.gz`; `strings vmlinux` confirmed the new warn string before
testing). DTS: K027's **untouched** baseline (RPM enabled, full DTS
otherwise, `clk_ignore_unused pd_ignore_unused` retention) with only
`&anoc1_smmu { ember,debug-skip-reset; };` added — node stays enabled,
unlike K029. `out/ember-k030-skipreset-2026-07-07.dts`, image
`out/boot-joan-skipreset-k030.img`, sha256
`207bae675b32e4f4598c46df62d746c818753ea7867e0abd63b9c003f546cf43`. Runner
`out/ember-k030-valid-retry-2026-07-07.log`.

Result: **reset still occurs** (LOS returned t+42s, 30s after handoff — same
timing as K027, PON still PS_HOLD/Hard-Reset-cold-boot, identical
electrical signature). But the reported reason **changed namespace
entirely**:

- Every prior test (K022 through K029) reported
  `lge.bootreason=<crash-ish>` / `hiddenreset=1` and an
  `LGE_RB_MAGIC | LGE_ERR_TZ | subcode` code (`0x6D630309` CONF_NOC or
  `0x6D630306` MM_NOC).
- K030 reports `lge.bootreason=NORMAL`, **`hiddenreset=0`**, and
  `androidboot.product.lge.bootreasoncode=0x20` — no `LGE_RB_MAGIC`
  prefix at all. Cross-checked against the preserved public header
  (`out/aurel-k027-public-bullhead-reboot_reason.h`): `0x20` is
  `UNDEFINED_CRITICAL_ERROR` in the **older, separate** `pon_restart_reason`
  enum (0x00-0x37 range: `TZ_MM_NOC_ERROR=0x2D`, `TZ_CONF_NOC_ERROR=0x30`
  live in this same enum, confirming it's the low-level counterpart of the
  LGE_RB_MAGIC subcodes we'd been reading). `hiddenreset=0` in particular
  had never appeared before this test.

Reading: the specific TZ NoC-fault detector that fired on every previous
test (whatever hardware/firmware logic recognizes "Config NoC" or "MM
NoC" specifically) **did not fire this time**. Skipping the SMMU global
reset on `anoc1_smmu` removed that exact fault signature. The boot chain
fell back to reporting only a generic, undetailed "undefined critical
error" — meaning something *else* still forces PS_HOLD at roughly the
same ~30s mark, now unclassified rather than NoC-specific. This is
forward progress (a real, named fault class eliminated) but not yet a
fix. Do not report this as solved.

Next (K031, staged): downstream marks ALL FIVE msm8998 SMMU-v2 instances
(`anoc1`, `anoc2`, `lpass_q6`, `mmss`, `kgsl`/adreno) with the same
`qcom,skip-init` + `qcom,register-save` pair — a blanket SoC policy, not
an anoc1-only quirk. `out/ember-k031-allsmmu-skipreset-2026-07-07.dts` is
staged (K027 baseline + `ember,debug-skip-reset` on all five nodes) to
test whether extending the same patch removes the residual generic
reset too.

## K031 — all-5-SMMU skip-reset: identical to K030, anoc1 alone is sufficient

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Same kernel binary as K030 (patch is generic, keyed off a DT property —
no rebuild needed). DTS: K027 baseline + `ember,debug-skip-reset` on all
five msm8998 SMMU-v2 instances (`anoc1_smmu`, `anoc2_smmu`, `adreno_smmu`,
`lpass_q6_smmu`, `mmss_smmu`), matching downstream's blanket policy.
`out/ember-k031-allsmmu-skipreset-2026-07-07.dts`, image
`out/boot-joan-allsmmuskipreset-k031.img`, sha256
`a836f695460d93b9be92802bc69db1326b359c1706c3a446519b58b8c518ffdb`.
Runner `out/ember-k031-valid-retry-2026-07-07.log`.

Result: **reset persists**, LOS returned t+47s (35s after handoff, same
ballpark as every test in this chain), PON PS_HOLD. Bootreasoncode:
**identical to K030** — `0x20` (`UNDEFINED_CRITICAL_ERROR`),
`hiddenreset=0`, `lge.bootreason=NORMAL`.

Interpretation: tagging the other four SMMUs changed nothing observable.
`anoc1_smmu` alone was sufficient to eliminate the NoC-fault signature;
the other four aren't contributing a distinguishable effect on this
classifier boot. Since skipping the reset on a real consumer's SMMU
(anoc2/wifi, adreno/GPU, lpass_q6/audio) also skips setting up the
default bypass/stream-mapping state those consumers would eventually
need — a real correctness risk once their drivers actually attach and
map, which our spin-only classifier ramdisk never exercises — **the
broader K031 patch is not preferred**. Going forward, treat K030's
anoc1-only patch as the accepted, safer baseline; do not carry the other
four `ember,debug-skip-reset` tags forward without a specific reason to
re-test them.

Standing question after K030/K031: **what produces the residual
`UNDEFINED_CRITICAL_ERROR` (0x20)?** This code is generic/undetailed
(unlike the NoC-specific codes), so the bootreason-as-classifier method
that drove K027-K031 has no further signal to peel by itself. Next probe
should re-establish a sharper oracle for this new, still-unnamed failure
— e.g. re-run the K023-style board-peripheral subtraction *on top of*
the confirmed anoc1 skip-reset baseline (previous K023 eliminations were
proven under the old NoC-fault regime and may not all transfer), or look
for other PON/QSEE-log detail that distinguishes `UNDEFINED_CRITICAL_ERROR`
from a plain unhandled watchdog.

## K032 — clk/pd retention is NOT load-bearing; anoc1 skip-reset alone is the real fix

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Same DTB/kernel as K030 (anoc1-only skip-reset), cmdline changed to
**plain default** (`androidboot.hardware=joan panic=0 ignore_loglevel`,
no `clk_ignore_unused pd_ignore_unused`). Image
`out/boot-joan-skipreset-defaultcmdline-k032.img`, sha256
`2d172bdde1fdcbce6fcc18701a696b556d028ea67d8a18eb2781f9c063820d30`.
Runner `out/ember-k032-valid-retry-2026-07-07.log`.

Result: **identical to K030/K031** — LOS returned t+48s (37s after
handoff), PON PS_HOLD, bootreasoncode `0x20`
(`UNDEFINED_CRITICAL_ERROR`), `hiddenreset=0`. The cmdline change made
no observable difference whatsoever.

**Correction to the K027-era hypothesis (docs/k028-conf-noc-sweep-
hypothesis-2026-07-07.md and the K027/K028/K029 readings that built on
it):** the late clk/genpd sweep retention was never actually the fix.
It was a coincidental correlation — present in K027 when the deeper
MM_NOC fault first surfaced, absent when K028/K029's *subtractions*
regressed things, which read as "retention matters." It doesn't. The
real, load-bearing fix the whole time was `anoc1_smmu`'s reset being
skipped; K032 proves the cmdline flags contribute nothing once that's
in place. **Confirmed clean baseline going forward: full, otherwise-
untouched joan DTS + `&anoc1_smmu { ember,debug-skip-reset; };` (the
K030 kernel patch) + plain default cmdline.** No cmdline workaround
needed.

This simplifies the standing question from K030/K031: with cmdline
noise eliminated, the only remaining unknown is what produces
`UNDEFINED_CRITICAL_ERROR` (0x20). Next: re-run the K023e capstone
(disable every removable board peripheral: `usb3`, `qusb2phy`, `ufshc`,
`ufsphy`, `wifi`, `pm8005_regulators` — RPM stays enabled, matching
K023e's original list) on top of this new confirmed baseline, to learn
whether the residual fault is peripheral-side or core/firmware-side,
same question K023e answered for the old NoC fault.

## K033 — capstone re-run on the fixed baseline: residual fault is ALSO core/firmware, not peripheral

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Confirmed clean baseline (K032: full DTS + anoc1_smmu skip-reset + default
cmdline) plus the K023e capstone peripheral list re-applied verbatim
(`usb3`, `qusb2phy`, `ufshc`, `ufsphy`, `wifi`, `pm8005_regulators`
disabled; RPM stays enabled as core scaffolding — same set K023e used
against the old NoC fault). `out/ember-k033-skipreset-corestrip-
2026-07-07.dts`, image `out/boot-joan-skipreset-corestrip-k033.img`,
sha256 `2aae7771a60e8f21cd74ee49dafdd5fd32a142c22059b8b315c08737a85b0342`.
Runner `out/ember-k033-valid-retry-2026-07-07.log`.

Result: **reset persists**, LOS returned t+56s (44s after handoff, within
the previously-noted bimodal ~31-58s spread), PON PS_HOLD, bootreasoncode
still `0x20` (`UNDEFINED_CRITICAL_ERROR`), `hiddenreset=0` — identical
classification to K030/K031/K032 despite every removable peripheral being
gone.

Conclusion: the residual fault, like the original NoC fault before it,
is **SoC core/firmware-level, not peripheral bring-up**. Stripping every
board peripheral changes nothing. The search space narrows to what's
left enabled in this "core" configuration: RPM (required scaffolding,
do not touch again — K028), the un-removable architectural blocks
(GIC, arm,armv7-timer-mem, SCM/PSCI), and — notably — the
`watchdog@17817000` APSS node, which K023e/K033 both leave enabled
(it's part of joan's `&soc` peripheral enable, not in the removable
list) and which K024 only *petted* from the kernel under the OLD fault
regime, never *disabled outright*. `pm8998_gpios`, `pm8998_resin`,
`tlmm`, `blsp2_uart1` remain enabled too but are basic/low-suspicion.

Next (K034): disable the APSS watchdog node entirely (`status =
"disabled"` on the joan `&soc` watchdog override, not a pet) on top of
this same confirmed baseline, as a genuinely new manipulation distinct
from K024's kernel-side pet.

## K035 — IMEM oracle test INCONCLUSIVE: device landed in an unfamiliar stuck state, session paused

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Reintroduced Ember's 2026-07-06 IMEM-oracle initcall
(`drivers/soc/qcom/joan_imem_oracle.c`, originally commit `f0d368d28` on
branch `joan/imem-oracle`, not present on `joan/latest-clean-test` until
now) on top of the confirmed K030 baseline (anoc1_smmu skip-reset). The
oracle writes a deliberately distinctive seed (`0x6D6303EE`, chosen to be
unmistakable against any real LGE subcode) to the IMEM restart-reason
offset (`0x146bf000 + 0x65c`) from an `early_initcall`, before whatever
causes the reset. Combined debug patch saved to
`out/ember-k035-imem-oracle-plus-smmu-debug.patch`. Verified both
`"joan-imem:"` strings and the K030 SMMU string present in `vmlinux`
before testing. Image `out/boot-joan-imemoracle-k035.img`, sha256
`d95be8064b8b09b27f4f9c84a5a3c611ae886ed0de7b773b235fd2961f3bffed`.

`fastboot boot` succeeded normally (`Sending`/`Booting` OKAY, handoff at
t+11s). But **no LineageOS return within the 300s cap** — the runner
correctly stopped itself (`out/ember-k035-valid-retry-2026-07-07.log`,
exit 12) rather than guessing. Immediate passive check found: `adb
devices` empty, `fastboot devices` empty, but `lsusb` showing a **new,
unfamiliar USB identity** — `1004:6340 LG Electronics, Inc. LGE Android
Phone` (vendor `0x1004` is LG's own, distinct from the normal ADB
identity `18d1:4ee7` every prior successful return has shown). A further
215-second **passive, read-only** observation window (`adb devices`,
`fastboot devices`, `lsusb` only — no commands sent to the device) showed
**zero change** — this is not a slow boot, the device is sitting in some
LG-specific mode (possibly LAF/diagnostic/download) that neither `adb`
nor `fastboot` currently reaches.

**No further remote device commands attempted past this point** per the
standing safety rules (device work requires Lance physically present;
avoid guessing against unfamiliar LG modes; the project has already hit
this exact "phone vanishes from USB mid-test" shape of problem once
before, during Aurel's original K027 attempt).

Working theory (recorded as a hypothesis, not a conclusion): this is the
**9th consecutive** RAM-boot-then-abnormal-PS_HOLD-reset cycle this
session (K027 retry through K035). Many Android/LG bootloaders implement
a boot-loop counter that deliberately falls back to a diagnostic/download
mode after N consecutive abnormal resets, as a *protective* measure, not
damage. If correct, a normal boot into LineageOS (which this phone has
reached cleanly after every single prior test) should reset that
counter, and the device should recover with a plain forced restart
(Power + Volume-Down, the same safe, storage-non-destructive recovery
already used on the H932 in this project). This has NOT been confirmed —
it is the leading hypothesis, offered for Lance's judgment when he is
next available, not an instruction to act on unilaterally.

The K035 test itself (does the seed survive unmodified?) is therefore
**not yet answered** — it must be retried once the device is confirmed
responsive again, ideally with a longer test-side timeout margin (the
300s cap was fine for every prior test's ~30-60s returns, but should
probably grow to account for any future slow-boot variance) and with
Lance present.

## SESSION PAUSE — awaiting physical device recovery

State at pause:
- Harness repo (`lg-v30-port`): clean, all findings through K034 + this
  K035 entry committed.
- Kernel repo (`linux-mainline-v30`): **dirty** — both debug patches
  still applied (`arm-smmu.c` skip-reset gate, new
  `joan_imem_oracle.c` + Makefile line). Deliberately left in place
  (not reverted) so testing can resume immediately once the device
  recovers, rather than losing K035's setup. Full patch saved at
  `out/ember-k035-imem-oracle-plus-smmu-debug.patch` regardless.
- Device: unresponsive to `adb`/`fastboot`, `lsusb` shows `1004:6340`.
  **Needs Lance's physical attention** (a normal forced restart is the
  expected, safe recovery — no flashing, no storage write, matches the
  device's own established recovery pattern).
- Confirmed, load-bearing result from this session, independent of the
  pause: **`anoc1_smmu` skip-reset (K030) is a real fix for a real, named
  TrustZone Config/MM-NoC fault.** That finding is solid and already
  fully documented regardless of what happens next with the device.

## K035 pause — root cause confirmed: USB 3.0 port undercharging, not boot-loop protection

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Lance identified the actual cause of the K035 pause: the USB 3.0 port the
phone was tethered to did not keep it charged through 9 consecutive
RAM-boot-then-reset cycles, and the resulting low-battery state produced
the unfamiliar `1004:6340` USB identity / unreachable adb+fastboot state
— **not** a bootloader boot-loop protection counter (that theory, recorded
in this file and the README/handoff at pause time, is superseded and
should not be repeated). Fix: moved the phone to a USB 2.0 port. Lance
will confirm when it's back online; no further device action until then.

This is a useful standing caution for future long device-test sessions:
watch for the phone's charge state across many consecutive tethered
`fastboot boot` cycles, and prefer a USB 2.0 port (or otherwise-verified
adequate charging) for extended runs.

## K035 result (from device photo): MM_NOC fault confirmed still present; IMEM write likely triggered a separate firmware bug

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

K035 (anoc1_smmu skip-reset baseline + IMEM-oracle seed write at
`0x146bf000+0x65c`) did not return to LineageOS or produce a normal
Android-property bootreason. Lance photographed the phone's screen and
uploaded it (`Talk/Shared_AI_agents_files/20260708_051750.jpg` and
`...051754.jpg`). It shows LG's **UEFI-level "LGE Crash Handler" screen**
— a diagnostic surface never seen before in this project, one level
below Android/LineageOS entirely (offers "connect USB + QPST raw dump"
or "Press Volume Down and Hold a Second" to reboot; the device was
sitting in Sahara mode, explaining why neither `adb` nor `fastboot`
could reach it).

Transcribed precisely by cropping the photo into a grid at full
8160x6120 resolution and reading each region closely (displayed size
alone was too small to trust for hex values):

- Early boot-stage block (`JOAN_NAO board_rev: 1.0`, msm/ufs serials):
  `reboot_reason 0x6d630600` (`LGE_RB_MAGIC|LGE_ERR_LK`, generic
  bootloader-stage attribution) and **`tzbsp_reason: 0x6d630301`**
  (`LGE_RB_MAGIC|LGE_ERR_TZ|0x01` = **TZ_NON_SEC_WDT**, TrustZone's own
  classification of the non-secure/APSS watchdog). `gcc_reset_status:
  0x203`, `dload_entry_cnt: 1` (first time, not a cumulative counter —
  weighs against any "boot-loop protection after N resets" theory).
- Later, near `Loader Build Info` / `OS Loader` stage: **`tzbsp_reason:
  0x6D630306`** (`LGE_ERR_TZ|0x06` = **MM_NOC**, identical to K027's
  original finding) with the same `gcc_rst_sts: 0x203`. The value
  genuinely differs from the earlier block's `0x301` — read at two
  different points in the same boot sequence, meaning something
  actively rewrote it in between.
- Immediately following: `DXE_ASSERT!: [ResetRuntimeDxe] String.c
  (199): String != (void *) 0`, then `Enter Sahara Mode.0`.

**Interpretation (reasoned from this evidence, not certain without XBL
source access):**

1. The underlying kernel-level fault behind this test was still
   **MM_NOC (`0x6D630306`) — the same fault first found in K027**, not
   a new independent failure mode.
2. This retroactively reframes K033/K034's residual, "generic" Android-
   property `bootreasoncode=0x20` (`UNDEFINED_CRITICAL_ERROR`, which
   downstream logged as "not handled, defaulting to Normal Boot"): it
   was very likely **Android's own property-generation code
   mis-reporting/genericizing this same MM_NOC value**, not evidence of
   a third, distinct fault. The K033/K034 conclusions themselves
   (peripherals and the APSS watchdog are not the cause) likely still
   hold, but the framing "residual reset is a different, unnamed fault"
   in the K033/K034 ledger entries and the README should be read as
   "residual reset is still MM_NOC, misreported by Android as 0x20" —
   corrected here rather than rewriting those entries.
3. **The DXE_ASSERT/Sahara-mode crash is most likely a side effect of
   the IMEM-oracle write itself**, not a new discovery about the
   MM_NOC cause. This exact firmware crash never appeared in any prior
   test this project (including several that also hit MM_NOC/Config
   NoC resets) — the one new variable in K035 was writing a
   deliberately-distinctive marker (`0x6D6303EE`) to
   `0x146bf000+0x65c`. The strong circumstantial read: that offset sits
   close enough to (or overlaps) some string/pointer structure XBL's
   `ResetRuntimeDxe` module also reads while formatting/handling the
   reset reason, and our write corrupted it, causing the NULL-pointer
   assertion on this boot. Not proven without XBL source, but well
   supported by "this exact crash only ever appeared once, and only in
   the one test that added this exact write."

**Consequences for method going forward:**

- Do not reuse a raw, unverified IMEM write at this offset again. If
  restart-reason instrumentation is needed later, treat `0x65c` as
  unsafe to write arbitrary marker values to — only the specific
  `LGE_RB_MAGIC`-shaped values the boot chain already expects should be
  written there, if anything.
- The real, standing target is unchanged and clarified rather than
  widened: **MM_NOC (`0x6D630306`)** is still not fixed. K033
  (peripherals stripped) and K034 (APSS watchdog disabled) both still
  hit it, so neither is the cause. The search continues from the same
  "SoC core, not peripheral, not the non-secure watchdog" narrowing —
  the K035 detour does not change that, it just corrects what the
  residual code actually was.
- Device needs a physical Volume-Down (held ~1s) to recover, per the
  crash screen's own instructions — not a generic Power+VolDown forced
  restart, and definitely not USB+QPST raw-dump (no reason to pull a
  raw memory dump for this).

## K036 — sibling MMSS-NoC-bridge clocks marked CLK_IS_CRITICAL (built, not yet device-tested)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Concrete, well-precedented next hypothesis for the standing MM NoC
fault (`0x6D630306`, confirmed still present per K035's device photo).

`drivers/clk/qcom/gcc-msm8998.c` already marks `gcc_mmss_noc_cfg_ahb_clk`
(register `0x9004`) `CLK_IS_CRITICAL` with an explicit upstream comment:
*"Any access to mmss depends on this clock. Gating this clock has been
shown to crash the system when mmssnoc_axi_rpm_clk is inited in
rpmcc."* `mmssnoc_axi_rpm_clk` is literally one of RPM's `icc_clks`
(`clk-smd-rpm.c`'s `msm8998_icc_clks[]`, voted once at rpmcc probe,
never CCF-registered, never swept) — this comment describes our exact
configuration (RPM enabled + this clock gated = documented crash).
Three sibling clocks in the *same* register bank (`0x9000`-`0x9030`,
same MMSS NoC bridge hardware block) lack the same protection:
`gcc_mmss_sys_noc_axi_clk` (`0x9000`), `gcc_mmss_qm_core_clk` (`0x900c`),
`gcc_mmss_qm_ahb_clk` (`0x9030`).

Patch: marks all three `CLK_IS_CRITICAL`, matching the exact,
already-proven-safe pattern mainline uses for their sibling. Saved to
`out/ember-k036-mmnoc-critical-clocks.patch`, applied on top of the
confirmed K030 anoc1_smmu fix (kernel tree now carries both patches).
Kernel rebuilds clean (`strings vmlinux` shows the K030 string, no
`joan-imem` — confirms the K035 revert held). DTB unchanged from the
K030 baseline (`out/ember-k030-skipreset-2026-07-07.dtb`). Image built:
`out/boot-joan-mmnoc-critical-k036.img`, sha256
`f80be59ae31695bcf41425a989721ee09b2e92ec0210d87c417503992ba5e8f3`.
Cmdline: plain default (`androidboot.hardware=joan panic=0
ignore_loglevel` — K032 already proved retention flags aren't needed).

This is a narrower, more conservative test than the K035 IMEM write: it
reuses an existing, upstream-proven mechanism (`CLK_IS_CRITICAL`) on
clocks in the identical register family as one already fixed for the
identical documented reason, rather than inventing a new one. If
confirmed, it may be close to upstream-shaped as-is, unlike the
`ember,debug-skip-reset` hack from K030 which needs a real binding
design before it could ever be proposed upstream.

**Not yet device-tested at time of writing** — Lance is recovering the
phone (Volume-Down hold, per K035's crash screen instructions) after
the K035 firmware crash. Test command:

```bash
scripts/tethered-test.sh out/boot-joan-mmnoc-critical-k036.img 300
```

Survives (>=90s) → MM NoC likely fixed by this specific clock family;
move to the real bring-up initramfs for a true USB-enumeration test.
Resets early → check the reported bootreasoncode: same `0x20`/MM NoC
family → this hypothesis is wrong or incomplete, look for a different
MM-NoC-adjacent block; something else entirely → new information,
follow it.

## K036 result — REJECTED, sibling MMSS-NoC-bridge clocks are not the cause

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Device-tested with Lance present (phone recovered from K035's crash
screen via Volume-Down hold, confirmed healthy before testing).
`scripts/tethered-test.sh out/boot-joan-mmnoc-critical-k036.img 300`.

Result: **reset persists**, LOS returned t+43s (30s after handoff, same
ballpark as every test in this arc), PON PS_HOLD, bootreasoncode still
`0x20` (`UNDEFINED_CRITICAL_ERROR`, understood since K035 as almost
certainly MM_NOC in Android's generic mis-reporting). Marking
`gcc_mmss_sys_noc_axi_clk`, `gcc_mmss_qm_ahb_clk`, and
`gcc_mmss_qm_core_clk` `CLK_IS_CRITICAL` — matching their sibling
`gcc_mmss_noc_cfg_ahb_clk`'s existing, documented protection — made no
observable difference.

**Rejected.** These three specific clocks are not the (sole) cause of
the MM NoC fault. The hypothesis was well-motivated (same register bank,
same documented RPM-interaction crash class as an already-protected
sibling) but wrong, or at best incomplete. Reverted from the kernel tree
(patch remains saved at `out/ember-k036-mmnoc-critical-clocks.patch` for
reference; do not reapply without new evidence). Kernel tree returns to
carrying only the confirmed K030 `anoc1_smmu` skip-reset fix.

Standing target unchanged: **MM NoC (`0x6D630306`) still not fixed.**
Eliminated so far: board peripherals (K033), APSS watchdog (K034), RPM
removal (K028, regresses), anoc1_smmu removal (K029, regresses), the
other 4 SMMUs' reset behavior (K030 vs K031, identical), cmdline/sweep
retention (K032), and now these 3 sibling GCC clocks (K036). Next
candidates to consider: other sweepable GCC clocks feeding NoC segments
(`gcc_aggre1_noc_xo_clk` — same "aggre1"/anoc1 NoC segment as the
already-fixed SMMU, but the XO reference clock rather than the SMMU
itself, a genuinely different mechanism worth checking; `gcc_boot_rom_ahb_clk`;
`gcc_cfg_noc_usb3_axi_clk`; `gcc_bimc_hmss_axi_clk`), or reconsider
whether `mmss_smmu` is truly fully inert (verify `&mmcc` really never
resolves in this exact boot rather than continuing to trust the
K023-era read), or look for a missing NoC/BCM bandwidth vote analogous
to `anoc1_smmu`'s downstream `qcom,msm-bus` entry but for whatever block
actually triggers MM_NOC specifically.

## Methodological correction — the whole "unclaimed/sweepable clock" theory class is ruled out for MM NoC

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

K036's rejection prompted a re-check of what evidence actually
constrains MM NoC, rather than reaching for the next individual clock
to test. Result: the entire "an unclaimed clock gets gated by the late
`clk_disable_unused`/genpd sweep, causing the fault" theory class —
which correctly explained the *original* Config NoC fault's mechanism
— **cannot be the explanation for MM NoC**, and this was already
provable from existing data without a new test:

- K027 (`clk_ignore_unused pd_ignore_unused`, sweep effectively
  disabled, clocks retained) hit MM NoC.
- K032 (plain default cmdline, sweep runs normally, after the anoc1
  fix) hit the identical fault.

Since MM NoC occurs whether the late sweep runs or is suppressed, no
clock whose *only* mechanism of being turned off is that generic sweep
can be the cause — if it were, retaining it (K027) should have
prevented the fault, and it didn't. This retroactively invalidates the
"next candidates" list at the end of the K036 entry above
(`gcc_aggre1_noc_xo_clk`, `gcc_boot_rom_ahb_clk`,
`gcc_cfg_noc_usb3_axi_clk`, `gcc_bimc_hmss_axi_clk`, and by the same
logic `gcc_prng_ahb_clk` from the original, already-superseded K028-prep
hypothesis) — **do not test these individually on the strength of "it's
an unclaimed GCC clock," that reasoning is now known to be
insufficient.** A systematic check (`comm` between every `GCC_*_CLK`
defined in the driver and every one referenced anywhere in
`msm8998.dtsi`/`msm8998-lge-joan.dts`) turned up dozens of unclaimed
clocks; none of them are worth testing on this basis alone anymore.

**The lens that actually worked for the original Config NoC fault
(anoc1_smmu, K030) was different in kind**: a specific *driver's own
unconditional reset/init sequence* touching a TZ-owned block on every
probe, independent of any clock-retention state — not a clock being
swept. K030 vs K031 already extended this same lens to rule out the
other four SMMU instances' own reset sequences too. **The productive
next step is to find another driver (not necessarily SMMU-family) that
does something similarly unconditional to a TZ-owned block**, not
another clock to flag critical. Candidates not yet considered:
pinctrl-msm's TLMM probe (does it reconfigure pin muxing
unconditionally, potentially clobbering TZ-owned pin config?), the QUP/
GENI/BLSP serial-controller family (`blsp2_uart1` is enabled; do its
siblings' probes touch anything unconditionally even when not
`status = "okay"`?), or a fresh secure/SCM-archaeology pass in Aurel's
established strength area — genuinely different investigative angles
rather than more DTS/clock subtraction, which has been pushed about as
far as reasoning without new device data can take it this session.

No further device test was run against this reasoning alone (per the
project's own discipline: don't guess blind, and don't spend more
passes without a specific reason to believe a candidate is right).

## Source-only check: pinctrl-msm/TLMM probe does not match the anoc1_smmu pattern

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Quick source check (no device involved) of one candidate raised in the
K036 methodological correction above. `msm_pinctrl_probe()`
(`drivers/pinctrl/qcom/pinctrl-msm.c`) does not touch hardware
unconditionally the way `arm_smmu_device_reset()` does: it only
ioremaps its own register tile, registers the pinctrl framework, and
applies whatever `pinctrl-0` states consumer nodes explicitly declare
via DT — no "walk every pin/group and force a default state"
sweep. `msm_pinctrl_setup_pm_reset()` registers a kernel restart/
poweroff handler that writes a `PS_HOLD` pin directly (interesting
given our whole fault surfaces as a `PS_HOLD` reset) but only if the
SoC's own pin-function table defines a function literally named
`"ps_hold"` — `pinctrl-msm8998.c` defines no such function, so this
path is a confirmed no-op on joan. **Cleared: TLMM/pinctrl-msm is not a
match for the "unconditional TZ-block touch" pattern.** Remove it from
the candidate list; the QUP/GENI/BLSP serial family and a secure/SCM
archaeology pass from the TrustZone side remain the live candidates.

## Source-only check: QUP/GENI/BLSP family also does not match the anoc1_smmu pattern

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Second and final source-only check of the K036 correction's candidate
list. MSM8998 predates Qualcomm's GENI/QUP peripheral IP entirely (that
generation starts around sdm845) — it uses the older BLSP (Blsp Serial
Processor) design, where each UART/I2C/SPI instance is a fully
independent platform device with its own dedicated driver, and there is
no shared BLSP-wide wrapper/bus controller node in `msm8998.dtsi` that
would probe regardless of which individual peripherals a board enables.
Only `blsp2_uart1` is enabled in joan's board file; every sibling
instance defaults `status = "disabled"` and never probes at all. There
is no cross-instance shared infrastructure here analogous to arm-smmu's
five instances sharing one driver. **Cleared: no match.**

Both Linux-side driver-family candidates raised in the K036 correction
(pinctrl-msm/TLMM, QUP/GENI/BLSP) are now checked and cleared without
a device test needed for either. This strengthens the case for the
remaining candidate: **a secure/SCM archaeology pass from the
TrustZone side is the most promising next direction**, not further
Linux-driver subtraction.

## Community research + K037 (watchdog timeout test) — non-secure watchdog CLEARED as the tunable cause

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-sonnet-4-5
Date: 2026-07-08

First systematic look at how OTHER msm8998 mainline ports handle this,
instead of pure joan-side subtraction. Findings:

**1. OnePlus 5/5T BOOTS mainline** (JamiKettunen/linux-mainline-oneplus5,
~40s boot) using the SAME shared `msm8998.dtsi` — same `anoc1_smmu`, same
arm-smmu-v2 unconditional reset. So the SMMU reset is NOT inherently fatal
on msm8998; joan's fault is device/firmware-specific. Their documented
gotchas: `clk_ignore_unused` for clock spam, `modprobe.blacklist=ipa` (IPA
module panics without firmware), only one appended DTB or it won't boot.
None is our MM_NOC.

**2. The CoreSight-on-retail pattern (KEY conceptual find).** postmarketOS/
OnePlus doc: *"a built kernel doesn't boot ... tracked down to CoreSight
tracing activating, which seems to cause kernel panics on retail hardware
- simply delete the etf, etm*, etr, funnel*, replicator1 & stm nodes."*
This establishes that on RETAIL/secure msm8998, TZ-owned debug blocks fault
when Linux touches them — the same class as our anoc1_smmu fix. NOT our
direct cause though: joan's 17 coresight nodes are all `status=disabled` in
the DTB and `CONFIG_CORESIGHT=m` never loads in bring-up. Cleared, but the
lens is validated and real.

**3. Mainline msm8998.dtsi has NO watchdog node** — joan is the ONLY
msm8998 device that added one (to try to get the mainline qcom-wdt driver
to pet LG's bootloader-armed watchdog). OnePlus/yoshino boot with no
watchdog node at all.

**4. Watchdog deep-dive → K037 test → CLEARED.** The mainline qcom-wdt
driver: default timeout `min(max_timeout, 30U)` = 30s (matches our reset
window), `CONFIG_QCOM_WDT=y` + `HANDLE_BOOT_ENABLED=y`, but does NOT set
`max_hw_heartbeat_ms` (so the core won't auto-pet a HW_RUNNING watchdog
before userspace opens `/dev/watchdog`; bare bring-up initramfs never
does). `sleep_clk` is a fixed-clock (always available → driver binds).
This looked like a perfect fit for a 30s NON_SEC_WDT reset.

K037 test (device): joan baseline (anoc1 skip-reset) + `timeout-sec = <60>`
on the watchdog node. Image `out/boot-joan-wdt-timeout60-k037.img` sha256
`04e561b1033f817ebb202a609d05f5d72343ca9ae332ddb155e9907c4cb08a1c`.
**Result: reset UNCHANGED at ~30s (t+43, handoff t+13), bootreasoncode
0x20.** timeout-sec had zero effect.

Interpretation: if the mainline non-secure watchdog driver were biting at
its configured timeout, 60s would have moved the reset to ~60s. It didn't.
So the mainline `qcom,kpss-wdt`@0x17817000 is NOT the effective control
surface for whatever resets joan (its `is_running()` likely reads
WDT_EN=0 and never engages, or a different/secure watchdog is involved).
Downstream `watchdog_v2.c` uses the IDENTICAL register offsets (RST 0x04,
EN 0x08, BARK 0x10, BITE 0x14) — so NOT an offset bug — with bark 11s /
pet 10s (would bite ~14s unpetted, not 30s). Our jittery 30-49s timing
across all runs argues against a fixed HW-watchdog bite anyway (those are
rock-steady). **The NON_SEC_WDT code on K035's crash screen was most
likely from a different boot in the sequence; this reset is the
event-driven MM_NOC fabric fault.** K037 cleanly retires the "unpetted
mainline watchdog" hypothesis (the one joan's own DTS comment proposed).

Consequence: joan's added `watchdog@17817000` node is not helping and
could arguably be dropped. The standing target remains MM_NOC, and the
strongest direction remains a secure/SCM/TZ-side pass — now further
supported by the community finding that retail msm8998 specifically faults
when Linux touches TZ-owned blocks (CoreSight was one instance; anoc1_smmu
another; MM_NOC is a third, still-unidentified block on the MM fabric).

K037 debug DTS is in out/ (untracked); no kernel change (DTB-only test),
tree stays at the confirmed anoc1-only baseline.

## Scoping: msm8998 interconnect provider feasibility for MM_NOC (source-only)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Scoped whether a mainline msm8998 interconnect (NoC) provider is a feasible
test for the MM_NOC fault, prompted by Lance's "why not just apply what
makes 4.4 boot" — the most direct instance of that being: downstream has a
full msm_bus/NoC stack (`msm8998-bus.dtsi`, fab-mnoc et al.), mainline has
ZERO msm8998 interconnect support (no provider file, no CONFIG), and the
fault is literally an MM-NoC error.

Feasibility (WRITE): **feasible, bounded.** `drivers/interconnect/qcom/
sdm660.c` (by AngeloGioacchino Del Regno, who also did mainline Sony
yoshino msm8998) is a near-perfect template — same `icc-rpm` framework,
same SoC family, ~1700 lines, 77 QoS nodes. The RPM interconnect CLOCK
plumbing already exists in mainline (`clk-smd-rpm.c` `msm8998_icc_clks[]` +
the `icc_smd_rpm` platform device); what's missing is only the
topology/QoS provider. Downstream `msm8998-bus.dtsi` supplies every
master/slave ID and link. A "minimal MM-NoC-only" shim is actually HARDER
than the full port (the ICC framework models end-to-end master→slave paths
across fabrics, not single NoCs).

Feasibility (FIX MM_NOC): **uncertain — de-prioritized.** What qnoc_probe
actually does: (1) `clk_bulk_prepare_enable` the NoC interface clocks, and
(2) program per-master QoS (NOC_QOS_MODE_FIXED) via regmap. Neither
obviously prevents a NoC transaction FAULT: the MM-NoC clocks are already
held (RPM INT_MAX handoff vote + `gcc_mmss_noc_cfg_ahb_clk` is
CLK_IS_CRITICAL; K036 tested the siblings), and QoS is arbitration
priority, not fault gating. Logical point against: mainline currently has
NO msm8998 ICC provider, so it never touches the MM-NoC QoS registers —
the MM NoC keeps the bootloader's config untouched. So the fault is NOT
mainline mis-programming the MM NoC; adding a provider is a gamble that
could help or hurt, for real effort.

Better-fitting theory the scoping surfaced (display underflow): the
bootloader leaves the DSC command-mode panel + MDP (`mdss@c900000`)
actively scanning out `cont_splash_mem@9d400000` over the MM NoC — the LG
splash Lance sees on screen during our boot. Mainline never refreshes or
tears it down (`CONFIG_DRM_MSM=m`, `CONFIG_MSM_MMCC_8998=m` — neither loads
in the bare bring-up initramfs; display-subsystem node is disabled anyway,
but the bootloader-left hardware runs independently of DT status). A
command-mode panel with no refresh/TE kicks, or an MDP whose DMA underflows
after a timeout, faults on the MM NoC. This fits ALL evidence: MM
specificity (display is the big MM consumer), the jittery ~30-49s
(timeout/underflow event, NOT a fixed watchdog — matches K037's finding
that it's not a fixed HW bite), why OnePlus 5 differs (its panel/simplefb
holds the display; OnePlus common dtsi even carries a simplefb "necessary
due to unused clk cleanup & no panel driver yet"), and why downstream boots
(its DRM/MDP driver takes over the cont_splash handoff cleanly).

Recommendation: before writing a full ICC provider (real effort, uncertain
payoff), test the display-underflow theory — cheaper and better-fitting.
Discriminating test: quiesce the bootloader-left MDP early (small debug
initcall mapping the mdss/MDP region ~0xc900000 and stopping the display
DMA/interface — display regs are non-secure, unlike the SMMU/IMEM that bit
us). If stopping the MDP stops the ~30s reset → display underflow confirmed;
the real fix path is then cont_splash handover / clean early teardown (or,
long-term, the DSC panel driver — joan's known hardest problem). If it
still resets → display cleared, revisit the ICC provider gamble. No device
test run yet; this is a strategic fork for Lance to choose.

## K038 — display-quiesce test: bootloader-left display CLEARED as the MM_NOC cause

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Tested the display-underflow theory (from the interconnect-scoping entry)
directly. Debug initcall `joan_disp_quiesce.c` (device_initcall, runs ~3s,
well before the reset) writes 0 to: both DSI controllers' CTRL register
(DSI0 0xc994000+0x0, DSI1 0xc996000+0x0) and the DPU INTF timing-engine
enables (INTF_1/DSI0 at mdp+0x6a800, INTF_2/DSI1 at mdp+0x6b000). Offsets
authoritative (dsi.xml CTRL=0x0; dpu_3_0_msm8998.h INTF bases;
dpu_hw_intf.c TIMING_ENGINE_EN=0x0). All non-secure display regs; MDSS
clocks left on by bootloader (MMCC=m) so they're accessible. On the
confirmed anoc1-fix baseline. Patch `out/ember-k038-disp-quiesce-debug.patch`,
image `out/boot-joan-disp-quiesce-k038.img` sha256
`7e9b12deda7f4a39d77c9b277acfa18421bda7dd37069272e1da854f1ed573be`.

Result: **reset persists**, LOS returned t+57s (44s after handoff, normal
jittery range), bootreasoncode `0x20`. Quiescing the display output path
did NOT stop the MM_NOC reset. **The bootloader-left display is CLEARED as
the cause** — confirming, empirically, the mechanical doubt raised while
building it (msm8998's panel is command-mode, so the MDP goes idle after
the bootloader's last kickoff; it isn't continuously DMAing the splash to
underflow). Minor caveat: no mainline console, so the writes-landed can't
be positively confirmed, but the offsets are authoritative and the block
is clocked, so confidence is high.

Reverted from the kernel tree; tree back to the confirmed anoc1-only
baseline.

## Session tally: Linux-side driver leads for MM_NOC are now exhausted

This session (research + K037 + K038) eliminated, empirically or by
analysis: the non-secure watchdog (K037), the bootloader display (K038),
and — via the interconnect scoping — established that **no mainline driver
touches the MM subsystem at all in bring-up** (DRM_MSM=m, MSM_MMCC_8998=m,
no GPU — none load from the bare initramfs). Combined with the earlier
eliminations (board peripherals K033, clock-sweep class K036, SMMUs beyond
anoc1 K030/K031, RPM-is-scaffolding K028/K029), there is no remaining
"a mainline Linux driver/DTS touches an MM block" candidate.

Therefore MM_NOC is one of exactly two things, both requiring a different
kind of effort than this session's Linux-side subtraction:
1. **Systematic missing NoC configuration** — downstream's msm_bus programs
   QoS/config for ALL fabrics (a1noc,a2noc,bimc,cnoc,mnoc,snoc); mainline
   has zero msm8998 interconnect support. The Config-NoC-then-MM-NoC
   *layering* (each fix reveals the next fabric fault) is consistent with a
   whole missing subsystem. Test = write the full msm8998 ICC provider
   (sdm660.c template, bounded but real; scoping entry above).
2. **A TZ-side secure handshake mainline omits** — the CoreSight-on-retail
   finding validates that touching/failing-to-service a TZ-owned block on
   this secure SoC causes exactly this class of reset. Needs secure/SCM
   archaeology (Aurel's domain; prior K025 pass is the starting point).

No cheap Linux-side test remains; the next move is a commitment to one of
these two larger efforts.

## Interconnect path — recon + ATTRIBUTION plan + honest payoff concerns (source-only)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Scoped writing an msm8998 interconnect (NoC) provider. Findings:

VALIDATED it's a real intervention: `qnoc_probe` (icc-rpm.c) calls
`qcom_icc_qos_set()` for every ap_owned node AT PROBE (not just on bw
request), and the framework has a `keep_alive` min-bw-vote mechanism — so
adding the provider DOES program NoC QoS + can hold an RPM bandwidth vote
at boot, the way downstream msm_bus does. NOC QoS regs: PRIORITYn @
0x8+n*0x1000, MODEn @ 0xc+n*0x1000, per qos_port; mnoc base-name
"mnoc-base", qos-off 0x1000. No msm8998 ICC provider exists upstream
(searched; only msm8996/sdm660/msm8974/msm8909) — it's FROM SCRATCH.

**ATTRIBUTION PLAN (Lance directive 2026-07-08 — track borrowed code +
who did the work):** any msm8998 provider would be DERIVED from existing
GPL-2.0 upstream drivers, primarily:
- `drivers/interconnect/qcom/sdm660.c` — Copyright AngeloGioacchino Del
  Regno (SoMainline / Sony Xperia mainlining project). Closest same-family
  template.
- `drivers/interconnect/qcom/msm8996.c` — Yassine Oudjana. Same
  BIMC+NoC-QoS icc-rpm framework.
- Topology/QoS VALUES from downstream `android_kernel_lge_msm8998`
  `msm8998-bus.dtsi` (Copyright Qualcomm / LGE).
Requirements when writing it: keep the original authors' Copyright lines +
SPDX-License-Identifier GPL-2.0, add a "based on <file> by <author>" note,
do NOT present it as original work; commit trailers = Signed-off-by: Lance,
Assisted-by: Claude-Code:claude-fable-5. This is a provenance record per
kernel.org policy and matters especially if ever upstreamed.

HONEST PAYOFF CONCERNS (surfaced during recon, before committing to ~1700
lines):
1. **No MM master is active in bring-up.** K038 disabled the display and it
   STILL MM-NoC-faulted; DRM/MMCC are =m (never load). So there's no active
   MM master whose QoS arbitration would matter — and QoS is arbitration,
   not fault-gating. The QoS-register angle is doubtful.
2. **BUT a more promising sub-mechanism:** the fault's timeout-like jitter
   (~30-49s) + MM-NoC specificity fits "the MM NoC expects an RPM bandwidth
   vote / keepalive that downstream's msm_bus provides and mainline never
   does." The ICC provider's `keep_alive`/RPM-bw-vote path (not QoS) is the
   part that could actually matter. This is worth a FOCUSED test.
3. **Executability risk:** joan bring-up has NO console (ramoops scrubbed,
   panic=0) — a complex new driver that fails to probe (wrong clock name,
   bad QoS, topology error) produces a SILENT boot-fail with zero
   diagnostic. Writing 1700 lines and debugging silent probe failures blind
   is very hard. Argues for the smallest testable increment first.

RECOMMENDATION: don't write the full provider blind. Test the promising
sub-mechanism cheaply first — a minimal debug initcall (the proven pattern:
anoc1/display/imem) that sends the MM-NoC RPM bandwidth vote (+ optionally
programs the MM-NoC QoS mode), replicating what downstream's msm_bus does
for the mnoc fabric. If that stops the fault, THEN write the full,
properly-attributed provider. If not, the interconnect path is likely a
dead end and we saved the big build.

## K039 (interconnect small pass) — MMCC=y (MM clock/power management) does NOT change the fault

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

The interconnect QoS programming requires the MMSS clocks/GDSC up (per
downstream `node-qos-clks` on each MM master), so MMCC being built-in is a
PREREQUISITE for the interconnect path. Tested that prerequisite alone as
the small pass: `CONFIG_MSM_MMCC_8998=y` (was =m, never loaded in bring-up)
+ anoc1-fix DTB + `clk_ignore_unused pd_ignore_unused` (so the now-registered
MMSS clocks aren't swept). Image `out/boot-joan-mmcc-k039.img` sha256
`d7a74484398518e334921038616e9f0a783f13bd4988dba8a492347d9a837f31`.

Result: **reset persists at ~30s (t+43, handoff t+13), 0x20, unchanged.**
Bringing up MM clock/power management (with clocks held) does not affect
the MM_NOC fault. Caveat: with clk_ignore_unused the MMSS clocks stayed on
either way (MMCC=m left them on too), so the hardware state was similar —
this weakly tests "MM management present" but doesn't exercise active MM
QoS/vote programming. Not a strong negative, but no signal.

Reverted MMCC back to =m (clean baseline). MMCC=y is available to
re-enable for the larger pass (the full ICC provider needs it).

## Interconnect path — honest status before the larger pass (decision point)

The small-pass explorations have not produced a signal:
- MMCC=y (K039): no change.
- QoS programming: doubtful (no active MM master — K038; QoS is arbitration
  not fault-gating) AND requires precise blind NoC register pokes (hang
  risk, no console).
- RPM bw-vote: risky (RPM comms, blind), and NoC errors aren't obviously
  "vote timeouts."

The larger pass (full msm8998 ICC provider, ~1700 lines derived from
sdm660.c/msm8996.c) remains the definitive test, BUT:
1. It's a big blind build — joan has no console, so a probe failure is a
   silent boot-fail indistinguishable from "didn't fix it." Very hard to
   develop correctly blind.
2. It's a substantial adaptation of AngeloGioacchino Del Regno's /
   Yassine Oudjana's GPL work (attribution plan recorded in
   docs/public-upstreaming-plan.md).
3. Confidence it fixes MM_NOC is LOW — no mechanistic theory survives
   scrutiny (no active master; QoS/vote don't cleanly explain a NoC error).

Recommendation: this is a genuine fork for Lance. The full provider is a
days-scale, low-confidence, hard-to-debug-blind effort. The alternative is
to accept the Linux side is exhausted and take the TZ-side secure route
(Aurel), where the fault detail actually lives. Recorded for the decision.

## TZ/SCM pass + K040 — missing secure handshake: scm_restore_sec_cfg for MM SMMU devices

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Ember's own TZ/SCM archaeology pass (Lance directed it after both
observability upgrades — screen-verbose and serial UART — turned out
blocked/specialized; see below). Builds on Aurel's K025.

Observability answers (why this pass instead of getting a log):
- **Screen verbose (fbcon/simplefb):** BLOCKED by joan's SW43402 panel
  being DSI COMMAND-mode + DSC. Command-mode panels don't continuously
  scan a framebuffer; each new frame needs an active DSI kickoff from a
  panel driver. Mainline has none for SW43402, so fbcon writes land in a
  buffer that never reaches the panel — invisible (this is exactly why
  joan has no simplefb). The screen shows the frozen last bootloader frame.
- **Serial UART:** joan DTS already enables blsp2_uart1 @0xc1b0000; adding
  `earlycon console=ttyMSM0` would stream the full boot log. But it needs
  SPECIALIZED HARDWARE: a 1.8V USB-UART adapter on the USB-C SBU pins via a
  resistor-ID "Qualcomm debug cable", or internal test pads — and it's
  unverified LG routes UART to USB-C on the V30. Physical-access dependent.

TZ/SCM finding (the payoff): downstream `drivers/iommu/arm-smmu.c` calls
`scm_restore_sec_cfg(smmu->sec_id, 0)` — a secure SCM call asking TZ to
(re)program a device's SECURE SMMU config. **Mainline's arm-smmu-v2 driver
(handles msm8998's SMMUs) NEVER calls it** — only the unrelated
`qcom_iommu.c` driver does, and that doesn't bind to msm8998. So mainline
never does the POSITIVE secure handshake downstream does; the K030 anoc1
fix only skipped the bad non-secure reset. `qcom_scm_restore_sec_cfg(u32
device_id, u32 spare)` IS present + EXPORT_SYMBOL_GPL in mainline
(qcom_scm.c), CONFIG_QCOM_SCM=y, with a `_available()` guard. Downstream's
`tz_smmu_device_id` enum gives the MM-subsystem device ids: VIDEO=0,
MDSS=1, MDSS_BOOT=3, ROT=21, VFE=22, CPP=26, JPEG=27.

Not the SMMU_PROGRAM/ATOS path (that's active-translation, per-CB) nor
static-cb restore (msm8998 SMMUs aren't static-cb). This is the plain
device-level secure-config restore.

K040 test: debug initcall (late_initcall) calling
`qcom_scm_restore_sec_cfg()` for the 7 MM-subsystem device ids on the
anoc1-fix baseline. Patch `out/ember-k040-scm-restore-sec-cfg-debug.patch`.
If the MM_NOC fault is because the MM subsystem's secure SMMU config was
never established from the non-secure side, restoring it via TZ should
stop the reset. Build in progress; result pending device test.

## K040 result — scm_restore_sec_cfg for MM devices: negative (but blunted by no observability)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Device-tested. Image `out/boot-joan-scm-restore-k040.img` sha256
`7dba1a9ca0e3b0df3ff3b4241b51628f84b16d1bae96a2c9c813d3645a2d1067`.
Result: **reset persists at ~34s (t+47, handoff t+13), 0x20, unchanged.**
Calling `qcom_scm_restore_sec_cfg()` for the 7 MM-subsystem TZ device ids
(VIDEO/MDSS/MDSS_BOOT/ROT/VFE/CPP/JPEG) did not stop the MM_NOC fault.

IMPORTANT caveat — the negative is BLUNTED by no observability: joan has no
console, so I can't see whether the SCM calls (a) hit the `_available()`
guard and no-op'd, (b) ran but returned errors from TZ (likely, since these
devices aren't attached), or (c) ran successfully but didn't help. All
three produce the same "reset at ~30s, 0x20." Downstream DOES use
scm_restore_sec_cfg so the TZ supports it, which argues the calls ran — but
their return values are invisible. This is the same observability wall that
has limited the whole port: a clean negative needs to SEE the SCM returns.

TZ/SCM pass status: found a genuine mainline gap (arm-smmu-v2 never calls
scm_restore_sec_cfg for the msm8998 SMMUs; only the unrelated qcom_iommu.c
does), tested the most-obvious form of it, negative-but-inconclusive. Other
secure calls remain (qseecom listener registration, the RPM/AOP master
handshake, SCM_SVC_BOOT setup) but each faces the same "can't see the
result" limit. Reverted; tree back to anoc1-only.

CONCLUSION reinforced: the serial UART console (blsp2_uart1, needs the 1.8V
USB-C SBU debug cable) is now the highest-leverage unblock — with it, every
TZ/SCM test becomes a clean read (SCM return values, probe order, the exact
last message before the TZ reset) instead of an ambiguous survive/reset
binary. Without it, TZ/SCM archaeology can propose but not cleanly confirm.

## LEAD: edk2-msm8998 UEFI (Renegade Project) — boots joan past 30s, open-source reference

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Lance surfaced the Windows-on-ARM UEFI angle. Investigated:
`github.com/edk2-porting/edk2-msm8998` (Renegade Project) — EDK2 UEFI for
Snapdragon 835. **LG V30 (joan) is a supported target** with ACPI/Windows
boot. Also `github.com/lumingyu0423/edk2-MSM8998`.

KEY architectural insight: the edk2 UEFI is loaded by ABL in the EXACT same
position as our mainline kernel — it disguises itself as a Linux kernel
(magic header + appended DTB) and is launched via `fastboot boot
boot_joan.img` (RAM-only, same as our tests), running in the normal world
after XBL+ABL. It is NOT getting special early treatment. Yet it boots
Windows, which takes far longer than 30s. **Therefore the ~30s MM_NOC/TZ
reset is AVOIDABLE from exactly the boot position our kernel runs in** —
the UEFI does (or periodically services) something our null-init kernel
(K022) does not.

Why this is the best lead in a while:
1. **Cheap definitive test:** `fastboot boot` the prebuilt joan UEFI image
   (non-destructive, RAM-only). If it survives past 30s (it must, to boot
   Windows), that PROVES the reset is fixable from our position and reframes
   the whole problem from "is it possible?" to "read the UEFI to see how."
   Bonus: the UEFI uses the XBL framebuffer + a UEFI shell — a potential
   OBSERVABILITY channel we lack.
2. **Open-source reference, far more tractable than the Android kernel:**
   edk2-msm8998 is small, focused C. Its main dispatch loop / SoC init /
   watchdog + SCM handling shows exactly the keepalive/handshake that keeps
   msm8998 alive past 30s — the thing our kernel is missing. This is likely
   a periodic secure/watchdog service (fits: K022 null-init still resets =>
   something must be serviced within 30s; the UEFI services it).
3. **Possible bypass:** if the edk2 UEFI can chainload a mainline Linux
   EFI-stub kernel, boot mainline FROM the UEFI (already-inited SoC) —
   uncertain (Linux boot via this UEFI is undocumented / "terribly broken"
   per its own docs), but would sidestep the reset entirely.

NEXT: (a) read the edk2-msm8998 source for its watchdog/SCM/periodic
service and NoC/SMMU init (software, doable now); (b) Lance test-boots the
prebuilt joan UEFI to confirm it survives 30s (huge data point). Caveat:
project self-describes as "terribly broken," Windows-focused; Linux-via-UEFI
may not work OOTB, but the survival test + source read are valuable
regardless.

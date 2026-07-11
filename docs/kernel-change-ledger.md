# LG V30 mainline kernel change ledger

Purpose: keep a complete, auditable trail of every kernel-side change needed to
mainline the LG V30 (`joan`) enough for modern Linux/postmarketOS and, later,
possibly a newer Android stack.

This file is the kernel-change source of truth. README carries the short current
status; `docs/project-history-and-attribution.md` carries the one-glance
who-worked-on-what timeline; detailed boot/debug evidence can live in dated
handoff docs; this ledger tracks what changed, why, where it lives, whether it
should survive upstreaming, and what evidence supports or rejects it.

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
  - `~/vibe-coding-projects/coding/lg-v30-port/out/aurel-sec-wdog-scm-experiments-2026-07-06.patch`
  - `~/vibe-coding-projects/coding/lg-v30-port/out/aurel-qcom-scm-oracle-leftover-2026-07-06.patch`
  - `~/vibe-coding-projects/coding/lg-v30-port/out/aurel-scm-retcode-oracle-leftover-2026-07-06.patch`
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
  - `~/vibe-coding-projects/coding/lg-v30-port/out/aurel-downstream-style-wdt-clean-test-2026-07-06.patch`
  - `~/vibe-coding-projects/coding/lg-v30-port/out/aurel-wdt-en3-test-2026-07-06.patch`
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
  - image `~/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-kernel.img`
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
  - image `~/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-clean.img`
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
  - image `~/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-maxcpus1.img`, sha256 `5bd01b0a987563027abbb968810b1b796201cbffb32e99effa4fc95d672c93e8`;
  - image `~/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-cpuidleoff.img`, sha256 `3f4b26656dc1af381128aa211787297ce85808e638287a1c21f7c550b5f9955d`;
  - saved patch `~/vibe-coding-projects/coding/lg-v30-port/out/aurel-latest-highmem-reserve-test-2026-07-06.patch`;
  - image `~/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-highmem-reserve.img`, sha256 `c9f4545b790084dd82b139109dc29dffa516f1c3a17620a003db3b6241a886a6`.
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
uploaded it (`internal-mirror:/20260708_051750.jpg` and
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

## edk2 UEFI source read — TWO big findings (passivity + on-screen console is possible)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Cloned edk2-porting/edk2-msm8998 (branch new) to
`~/vibe-coding-projects/coding/edk2-msm8998` (read-only). Two findings:

**FINDING 1 — the reset is caused by our kernel's AGGRESSIVE SoC re-init,
NOT a missing keepalive/handshake.** The edk2 UEFI's msm8998 SoC library is
just PlatformMemoryMapLib + PlatformPeiLib — it has NO clock, SMMU, NoC,
interconnect, SCM, or hardware-watchdog driver at all (verified: joan.dsc /
family dsc include none; QcomPkg/Library has only those two). It leaves the
SoC exactly as XBL configured it, pets no watchdog, does no secure
handshake — and SURVIVES to boot Windows (far past 30s). So no positive
keepalive is required; the ~30s reset is provoked by something our Linux
kernel DOES during its aggressive re-init that the passive UEFI does not.
This VALIDATES the subtraction approach (anoc1 skip-reset was one such
suppression) and casts serious doubt on the TZ/SCM "add a handshake"
direction (K040) — the UEFI proves none is needed. Next: find the remaining
aggressive init that provokes MM_NOC (beyond the anoc1 SMMU reset), using
the passive UEFI as the "minimal that works" reference.

**FINDING 2 — on-screen kernel console should ACTUALLY WORK (contradicts
joan DTS's "simplefb invisible" assumption).** The UEFI's SimpleFbDxe.c
does ZERO display-HW register access (MmioWrite/Read count = 0). It only
blits pixels into the framebuffer (FrameBufferBlt) + WriteBackInvalidate
cache flush, reading base/1440x2880 from PCDs. And it displays scrolling
console text on screen (FrameBufferSerialPortLib is the UEFI's serial/
console output). So XBL leaves joan's display actively scanning the
framebuffer (0x9d400000, joan's cont_splash), and a PLAIN framebuffer
write shows up — no DSI kickoff, no panel driver needed. Therefore a
mainline `simple-framebuffer` node + fbcon SHOULD give on-screen kernel
boot logs — the observability we've lacked, and exactly what Lance
originally asked for ("kernel verbose to screen"). The earlier
command-mode "silently invisible" reasoning appears WRONG; the UEFI is the
proof. NEXT TEST: add a simplefb node (0x9d400000, 1440x2880, a8r8g8b8) to
joan's DTS + fbcon, boot, and read kernel logs off the screen (Lance
photographs). If it works, every future test becomes observable.

## K041 — on-screen console test (simplefb + fbcon + heartbeat), watched on-device

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Testing FINDING 2 from the edk2 read: add a mainline `simple-framebuffer`
node at 0x9d400000 (1440x2880 a8r8g8b8, no clocks — exactly like the UEFI's
SimpleFbDxe) + CONFIG_FB_SIMPLE + fbcon, so the kernel prints its boot log
ON SCREEN. Heartbeat init prints ">>>> JOAN-ALIVE t=Ns <<<<" to the console
every 1s so the last count on screen = the reset time.

Config: +CONFIG_FB_SIMPLE (VT/FB/fbcon already =y). DTS:
`out/ember-k041-simplefb-2026-07-08.dts` (joan + chosen/simple-framebuffer
+ anoc1 fix). Initramfs: `out/initramfs-k041-heartbeat.cpio.gz`. Image
`out/boot-joan-simplefb-k041.img` sha256
`b98655d370d7484a9448457aaf2d0822e3ffed231b88249b6cf7e60eed3e1a97`. Cmdline
adds `console=tty0 fbcon=nodefer`. Lance watching/recording the screen.

RESULT (device, Lance watching): **NOTHING appeared on screen** — stayed on
the frozen LG logo, phone reset to LOS at ~37s (0x20, unchanged as expected).
Address/format were correct (UEFI PcdMipiFrameBufferAddress = 0x9d400000,
1440x2880, verified in the edk2 repo), so NOT an address bug.

Likely cause + correction to edk2 Finding 2 (it was too optimistic): by the
time Linux's simplefb + fbcon come up (device_initcall, ~several seconds
into boot), joan's display is in the command-mode FROZEN state — showing the
GRAM-held last XBL frame (the frozen LG logo Lance always sees), NOT actively
scanning the framebuffer. So CPU writes to 0x9d400000 aren't scanned out =
invisible. Two flaws in the Finding-2 reasoning: (a) the on-screen UEFI
crash/logo screens Lance photographed are LG's OWN ABL (which IS UEFI-based
-- "LGE Crash Handler: UEFI Crash" -- and actively manages the display),
NOT proof a plain framebuffer write works; (b) even if the edk2 UEFI's plain
write works, it runs right after XBL (early, possibly still-scanning window),
while Linux fbcon is much later (frozen window). So joan's original DTS
"simplefb would be silently invisible" comment was RIGHT after all.

Cannot easily debug further blind (need a console to see if simplefb even
bound -- chicken/egg). On-screen console via late-Linux simplefb is a dead
end for joan's command-mode panel. Observability paths that remain:
1. UART cable (hardware, reliable) -- Lance exploring.
2. Boot the edk2 UEFI ITSELF (fastboot boot the prebuilt joan image): it has
   its own working on-screen console; if it boots + shows a shell, that's an
   observable env, and if it can chainload mainline Linux we might inherit a
   live display. Software-testable, non-destructive.
Reverted config (FB_SIMPLE) + DTS to clean anoc1-only baseline.

## K042 — MSM8998 Qualcomm SMMU cfg-probe S2CR quirk-probe subtraction (tested, later superseded by pstore)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-08

Class: `debug-only` / `superseded`; Public/PR disposition: `do not publish`.

Purpose: follow Ember's K041/edk2 conclusion that the remaining reset is more
likely caused by aggressive Linux re-initialization than by a missing positive
secure-world keepalive. K030 already showed that suppressing mainline's global
`arm_smmu_device_reset()` on `anoc1_smmu` removes a named TrustZone
Config/MM-NoC reset class, but K030 does not cover earlier Qualcomm-specific
SMMU cfg-probe code. Mainline's `qcom_smmu_cfg_probe()` unconditionally performs
an S2CR BYPASS write/read quirk probe for every `qcom,msm8998-smmu-v2` instance
before the later reset hook. Downstream 4.4's MSM8998 arm-smmu path has no
equivalent Qualcomm `cfg_probe` S2CR write and marks the MSM8998 SMMUs
`qcom,skip-init` + `qcom,register-save`. K042 is a narrow subtraction oracle:
skip only that MSM8998 S2CR bypass-quirk probe while leaving the node enabled
and leaving the later SMR readback loop intact.

Handles/evidence:

- Saved dirty kernel patch:
  `out/aurel-k042-smmu-cfgprobe-wip-2026-07-08.patch`
- Final tested/rejected patch copy:
  `out/aurel-k042-smmu-cfgprobe-tested-rejected-2026-07-08.patch`
- Patch sha256 (both copies):
  `e7fe6b0b3f1dd336f5180c92d1ce60da58a91ea1644e2ef5e67ae77c62ed6704`
- Build log:
  `out/aurel-k042-build-2026-07-08.log`
- Build log sha256:
  `e81c6d94ecf3124100009838b4405cd92a223bacb23d5972560c91ecef1b7a20`
- Packaged RAM-only boot image:
  `out/boot-joan-smmu-cfgprobe-k042.img`
- Boot image sha256:
  `bc8099c241dc18865079e4fffce95d13cb9f3885705ae67ac2f570ec3fd85c4f`
- Packaged cmdline:
  `androidboot.hardware=joan panic=0 ignore_loglevel`
- Touched files in the saved patch:
  - `drivers/iommu/arm/arm-smmu/arm-smmu.c` — carries Ember K030 debug
    `ember,debug-skip-reset` gate in `arm_smmu_device_reset()`;
  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts` — adds the K030
    `&anoc1_smmu { ember,debug-skip-reset; };` baseline property;
  - `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` — adds the Aurel K042
    MSM8998-only skip around the S2CR BYPASS quirk probe.
- Attribution/provenance: K042 code is original debug instrumentation, but the
  hypothesis is derived from comparing upstream Linux `qcom_smmu_cfg_probe()`
  with Qualcomm/LGE downstream `qcom,skip-init` / `qcom,register-save` policy.

Verification/state at record time:

- `git diff --check` passed after the K042 patch and the corrected DTS placement.
- Build attempt 1 accidentally omitted `ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-`
  and failed with host GCC rejecting arm64 flags (`-mlittle-endian`,
  `-msign-return-address=non-leaf`).
- Build attempt 2 was interrupted by the session before completion, after Kconfig
  prompted for new upstream symbols.
- Final build settled config noninteractively with
  `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig`, which reported
  `No change to .config`, then built successfully with
  `make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image.gz
  qcom/msm8998-lge-joan.dtb`.
- Built artifact hashes:
  - `Image.gz`: `c1571e4e6c4d0282815ff3ebf1901965c904db1a69e161e0a807854386186a77`
  - `msm8998-lge-joan.dtb`: `29ff3d3e31d495e3b0c82205b2362e03d6f875372df8c3af63da2261165fbda5`
  - `vmlinux`: `f496cd27ba8807dcaf0fd81d037ce4ab48e7f0255ea3beca90b0d39b954d3ca5`
- `strings vmlinux | grep -E 'EMBER K030|AUREL K042'` verified both debug
  strings are present:
  - `EMBER K030 DEBUG: skipping global SMMU reset`
  - `AUREL K042 DEBUG: skipping MSM8998 S2CR bypass quirk probe`
- Device test log:
  `out/tethered-test-2026-07-08T173429Z.log`
- Device test log sha256:
  `8220325ab2249f92425342d172a71de31dba052157706d3061a9add4f9745772`
- Test command:
  `./scripts/tethered-test.sh out/boot-joan-smmu-cfgprobe-k042.img 420`
- Test result:
  - `adb reboot bootloader` succeeded.
  - one-client `fastboot boot` succeeded: `Sending 'boot.img' ... OKAY`,
    `Booting ... OKAY`, total fastboot time `5.444s`.
  - kernel handoff at `t+12s`.
  - LineageOS adb returned at `t+60s`, **48s after handoff**.
  - Classifier result: `RESET PERSISTS (early LOS return)`.
- PON/bootreason readback after the early return:
  - Android bootreason property: `androidboot.product.lge.bootreasoncode=0x20`.
  - PMIC SID0 power-off reason: `PS_HOLD`.
  - PMIC SID2 power-off reason: `GP1 (Keypad_Reset1)`.
  - PON lines include `PON=0x21:PON1:HARD_RESET` / `POFF=0x2:PS_HOLD` and
    `POFF=0x8:GP1`.
- Original classification at test time was **tested and rejected** based only on
  early LineageOS return. This is now corrected by K043/K046 raw-pstore evidence:
  K042 died in MSM8998 TLMM/GPIO registration at ~0.073s before it could reach
  the SMMU cfg-probe path under test.
- Current live phone state after K042: LineageOS adb visible as
  `LGUS9986e606d55` and USB `18d1:4ee7`.
- Kernel worktree state after recording: K042/K030 debug source changes reverted;
  artifacts above preserve the exact tested diff.

Conclusion correction (Aurel, 2026-07-08): K042 does **not** rule out the SMMU
cfg-probe write/read. It is superseded by pstore evidence that exposed an
earlier TLMM/GPIO abort. Do not cite K042 as a valid negative SMMU result.


### K043-K050 — raw-pstore observability and MSM8998 TLMM/GPIO reserved-ranges narrowing

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-08

Class: mixed `debug-only` oracles plus one `unknown`/candidate DTS result;
Public/PR disposition: K043-K049 `do not publish`; K050 `needs cleanup`.

Purpose: follow the user's "observability before more fixes" direction. Instead
of another blind SMMU/SCM test, read post-reset persistent evidence from
LineageOS and use it to identify the actual early fault.

Observability finding:

- Mounted `/sys/fs/pstore` was empty/misleading, but the raw pstore partition
  `/dev/block/platform/soc/1da4000.ufshc/by-name/pstore` preserved the K042
  mainline ramoops console when read quickly from LineageOS root. The helper
  `scripts/read-pstore-partition.sh` now captures the first 256 KiB plus strings
  and metadata.
- Evidence:
  - `out/lineage-root-observability-2026-07-08/pstore-partition-first256k.bin`
    sha256 `e0573c228d85349c292be545a239a6741ecb6f3965b65538805a1465024c89bc`
  - `out/lineage-root-observability-2026-07-08/pstore-partition-first256k.bin.strings.txt`
    sha256 `323df4a1e65649492ba07d9e35f717748268f7f2fa0ce2166adbf3feb02b63d8`
- K042 pstore showed `Asynchronous SError Interrupt` at ~0.073s in
  `gpiochip_add_data_with_key()` / `msm_pinctrl_probe()`, invalidating the old
  SMMU-cfg-probe rejection.
- `/sys/kernel/debug/tzdbg` exists but content reads are risky: reading
  `tzdbg/general` caused adb/device disappearance in this session. Do not use
  broad `tzdbg/*` cats casually.

Test matrix:

| Test | Handle | Change | Result | Evidence |
|---|---|---|---|---|
| K043 | `out/aurel-k043-tlmm-disabled-debug-2026-07-08.patch` | DTS debug: `&tlmm { status = "disabled"; }` | **SURVIVOR** (`t+123s`, 111s after handoff) | `out/tethered-test-2026-07-08T181424Z.log` sha256 `def3e144ea58140815a1767e4feb5b6b7f6f9122f674f3fb19b0e7779e5be1b9` |
| K044 | `out/aurel-k044-msm8998-skip-gpio-init-debug-2026-07-08.patch` | Source debug: skip `msm_gpio_init()` on msm8998 | **SURVIVOR** (`t+123s`, 111s after handoff) | `out/tethered-test-2026-07-08T181914Z.log` sha256 `6b69bdaac61158b8f43c7ce16701f7d7a201fc9e722965cdc5c909e516fbcf12` |
| K045 | `out/aurel-k045-msm8998-gpiochip-no-irq-debug-2026-07-08.patch` | Source debug: register gpiochip without TLMM IRQ chip | Early reset; pstore still panicked in `gpiochip_add_data_with_key()` | `out/tethered-test-2026-07-08T182336Z.log` sha256 `80b82ca63e8c154e0b1e3047a7910f9688bc9843d2db0f8e0378b4b586158316` |
| K046 | `out/aurel-k046-drop-gpio-reserved-ranges-debug-2026-07-08.patch` | DTS debug: remove `gpio-reserved-ranges` | Pstore synchronous external abort in `msm_gpio_get_direction()` at offset `0x531000` = GPIO49 | `out/tethered-test-2026-07-08T182655Z.log` sha256 `5aeb7c9bb4bcd8238757b6dd5fbfa52776c28bae092de0f2dba7fda25c59f590` |
| K047 | `out/aurel-k047-msm8998-no-get-direction-debug-2026-07-08.patch` | Source debug: set `get_direction = NULL` on msm8998 TLMM | **SURVIVOR** (`t+123s`, 111s after handoff) | `out/tethered-test-2026-07-08T183330Z.log` sha256 `e7618f19b8cdc011d8b383f6c921132cd6f8d3c864add79820c312a4b694bc1e` |
| K048 | `out/aurel-k048-reserve-gpio49-debug-2026-07-08.patch` | DTS debug: reserve `<49 1>` in addition to `<0 4>` | Abort moved to `0x532000` = GPIO50 | `out/tethered-test-2026-07-08T183742Z.log` sha256 `8a4ff5c3257cf5f827f381a899a40f75861d1878512c1d42cec7abbf93689c32` |
| K049 | `out/aurel-k049-reserve-gpio49-52-debug-2026-07-08.patch` | DTS debug: reserve `<49 4>` | Abort moved to `0x151000` = GPIO81 | `out/tethered-test-2026-07-08T184003Z.log` sha256 `dd9cf4176fe1e31eb10c588670835a785e9f6e77a2485abeceb768e76de5a605` |
| K050 | `out/aurel-k050-reserve-gpio49-52-81-84-debug-2026-07-08.patch` | DTS debug/candidate: reserve `<49 4>` and `<81 4>` plus existing `<0 4>` | **SURVIVOR** (`t+123s`, 111s after handoff) | `out/tethered-test-2026-07-08T184221Z.log` sha256 `ed68d29ed4cd5b586f33347db739f1be3655f2c0e1c160f7d07292184f09e138` |

Candidate patch:

- Clean candidate artifact:
  `out/aurel-k050-clean-candidate-gpio-reserved-ranges-2026-07-08.patch`
  sha256 `6a0227897f48940fb488747f0a8d927916816140627af8a62aba289f0a7b601a`.
- Candidate DTS content:

```dts
&tlmm {
	gpio-reserved-ranges = <0 4>, <49 4>, <81 4>;
};
```

Interpretation:

- `0x531000 = NORTH 0x500000 + GPIO49 * 0x1000`.
- `0x532000 = NORTH 0x500000 + GPIO50 * 0x1000`.
- `0x151000 = WEST 0x100000 + GPIO81 * 0x1000`.
- The failure is a protected/inaccessible TLMM direction read during gpiolib's
  initial direction readback, not an SMMU cfg-probe failure.
- Reserving the observed inaccessible ranges makes gpiolib skip those direction
  reads and lets the kernel reach the classifier's deliberate reboot path.

Initial source review after K050:

- Upstream MSM8998 boards `msm8998-mtp.dts`, `msm8998-oneplus-common.dtsi`,
  `msm8998-xiaomi-sagit.dts`, and `msm8998-clamshell.dtsi` already reserve
  `<81 4>`, independently supporting GPIO81..84.
- Downstream joan common pinctrl defines modes over GPIO49..52 and GPIO81..84,
  but a source search found no active references to those labels in the joan DTS
  tree; one KR MME variant references GPIO81 directly.
- No current mainline joan node consumes GPIO49..52 or GPIO81..84.
- GPIO49..52 is still source-weak but pstore/device-proven on this phone.

Open follow-up before public commit:

1. Find stronger source evidence for GPIO49..52 if possible, or explicitly justify
   it as joan/LGE-firmware-specific behavior.
2. Decide whether DTS reserved ranges are sufficient/clean or whether a
   driver-level msm8998 `get_direction` quirk is required. K047 proves the
   driver route also survives, but it is broader.
3. Convert K050 into a clean kernel commit only after review, then rerun one
   RAM-only confirmation test.
4. Keep raw-pstore capture in the harness for every future early-reset test.

Kernel worktree after this session: clean `joan/latest-clean-test` at
`0d7df4134`; all K043-K050 debug changes reverted/preserved as `out/*.patch`.

### K051 — K050 converted to clean commit + RAM-only confirmation (SURVIVOR)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-10

- Source review outcome (handoff follow-ups 1+2): DTS `gpio-reserved-ranges`
  route chosen over a driver-level msm8998 `get_direction` quirk. Rationale:
  the protection is per-board LG TrustZone/XPU policy, not an SoC erratum —
  a driver quirk would disable direction readback for every MSM8998 board;
  `gpio-reserved-ranges` is the established binding (5 mainline 8998 boards
  already reserve `<81 4>` this way).
- `<49 4>` source evidence strengthened: downstream
  `msm8998-joan-common-pinctrl.dtsi` muxes GPIO49-52 as `blsp_spi9`
  (`spi_9_active`/`spi_9_sleep`) with NO downstream HLOS consumer of those
  labels anywhere in the joan tree, and joan's fingerprint node
  (`msm8998-fingerprint-fpc1022.dtsi`) carries only reset/IRQ GPIOs (27/121)
  with no SPI bus reference — the fpc1022's SPI traffic runs inside the TEE.
  A TZ-owned secure SPI on BLSP9 explains the per-pin direction-read aborts.
  Classified as joan/LGE-firmware-specific, documented as such in the commit.
- Clean kernel commit: `950cf8554` on `joan/latest-clean-test`
  ("arm64: dts: qcom: msm8998-lge-joan: reserve TZ-protected TLMM GPIO
  ranges"), trailers `Signed-off-by: Lance`, `Assisted-by: Hermes:gpt-5.5`
  (Aurel's K043-K050 isolation) + `Assisted-by: Claude-Code:claude-fable-5`
  (review/commit). Branch now ahead of origin/master by 5.
- Rebuilt incrementally, repackaged with K023b classifier ramdisk, cmdline
  `androidboot.hardware=joan panic=0 ignore_loglevel`:
  `out/boot-joan-k050-clean-950cf8554.img` sha256
  `e33c2b61aa0a95182ee4bf1b44decc394fbce7039b55953833bac186930f2aa2`.
- Result: **SURVIVOR** — LOS returned at t+124s (111s after handoff),
  identical window to Aurel's original K050 run.
  Log: `out/tethered-test-2026-07-10T142008Z.log`.
- Raw pstore read immediately after
  (`out/pstore-partition-2026-07-10T142231Z.{bin,strings.txt,meta.txt}`):
  contains ONLY the stale Jul-8 crash record (build #69, abort at 0.067s) —
  no new crash record, consistent with clean survival + deliberate
  classifier reboot.
- Class: `upstream-candidate` (commit 950cf8554); K050 ledger disposition
  "needs cleanup" is now RESOLVED.
- Lance authorization note: tethered tests this session run without physical
  presence per Lance's explicit go-ahead (2026-07-10, sleeping in next room,
  accepts wedge risk).

New clean baseline: `joan/latest-clean-test` @ `950cf8554`.

### K052-K053 — MILESTONE 1: mainline userspace + USB gadget + network + shell

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-10

- K052: gadget-initramfs image from clean baseline `950cf8554`
  (`out/boot-joan-gadget-k052-950cf8554.img` sha256
  `e6912a005119428c176c3583f5066dc2783943443094ed07cf97c172eba0365d`,
  make-testimage.sh, cmdline `androidboot.hardware=joan panic=5
  ignore_loglevel`). RAM-only boot: **phone enumerated as 18d1:4e26
  "V30 mainline bring-up" (ECM+ACM)**, host ping 172.16.42.1 OK, live
  busybox root shell over ttyACM0 (`/proc/uptime` readback). First
  mainline userspace + working USB gadget on joan. Init's 15-min
  self-recovery rebooted to LOS on schedule; raw pstore after
  (`out/pstore-partition-2026-07-10T144053Z.*`) shows successful boots
  leave NO new console record in the partition (crash-path-only
  preservation).
- K053: repeat boot with persistent host-side serial logger
  (`out/k053-gadget-capture.sh`, log `out/k053-serial-2026-07-10T144230Z.log`,
  runner log `out/tethered-test-k053-gadget-2026-07-10T144230Z.log`).
  `touch /keep` held the boot; full diag dump pulled over the ECM link
  via busybox `nc -l` on the phone (host ufw drops phone→host SYNs; a
  temporary host iptables accept on the usb if was used and removed):
  `out/k053-diag-2026-07-10.bin` sha256
  `d2400d5c41d5de163c065801e33a74b7ef320200744a8d6b463c4089f6e1099b`
  (75264 B: WDT log, version, cmdline, UDC, ip addr, /proc/interrupts,
  clk_summary, regulator_summary, full dmesg).
- Diag ground truth: running kernel `7.2.0-rc2-g950cf8554050 #70`
  (clean, non-dirty). `wdkill`: WDT EN=0 at entry — APSS watchdog was
  never armed on this boot path. dmesg failures ONLY: `efi: UEFI not
  found` (expected), `psci: failed to set PC mode: -3` (known), and
  deferred-probe timeout -110 on the two TZ-owned SMMUs
  (`5040000.iommu`, `cd00000.iommu`) — no other subsystem errors.
  The K030 anoc1 skip-reset debug patch was NOT needed: mainline
  tolerates the SMMU probe failures once TLMM no longer aborts.
- Gadget quirks noted: init's mass-storage diag LUN did not attach on
  K053 (ECM+ACM only on re-bind; 4-day-old host dmesg had confused an
  earlier check) — diag came over network instead. ACM serial sessions
  survive the re-bind; interact after ~t+75s.
- Class: milestone evidence, `bringup-local` (initramfs/tooling);
  kernel tree unchanged from `950cf8554`.
- NEXT (Lance directive 2026-07-10): backup boot/recovery partitions
  BEFORE any flash. Flashing now authorized EXCEPT anything that could
  brick or block recovery (never xbl/abl/tz/hyp/rpm/modem/laf).
  Goal: postmarketOS with wifi+BT (cellular later).

Correction (Lance, 2026-07-10, after K051-K053 entry): the no-touch list
drops `laf` — the download-mode partition is designated as the pmOS boot
slot (recovery stays intact instead). Preconditions: laf+lafbak backups
verified (done today); restore paths = fastboot flash laf / recovery /
dd from LOS root. xbl/abl/tz/hyp/rpm/modem remain absolutely no-touch.

### K054 — M2 STORAGE: UFS + microSD both up; SD ext4 mount+write verified

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

- Root cause of K053's dead UFS: NOT the DTS (joan's &ufshc/&ufsphy supplies
  already matched oneplus-common) — `CONFIG_SCSI_UFS_QCOM` and
  `CONFIG_PHY_QCOM_QMP(_UFS)` were `=m` and the bringup initramfs carries no
  modules. Forced `=y` (plus EXT4/VFAT already in).
- New kernel commit `ce78c1369` "enable SD card slot": &sdhc2 with downstream
  regulators (vdd=l21, vdd-io=l13), joan-local `sdc2_cd_joan` pinctrl state
  (CD = GPIO 40 ACTIVE_LOW per downstream `cd-gpios = <&tlmm 40 0x1>`;
  SoC-level sdc2_cd assumes MTP GPIO 95). Pushed to public fork.
- Test: RAM-only gadget boot `out/boot-joan-gadget-k054-storage.img` sha256
  `4f27c685544871384334e0196926a5ab11694c98c25da30de0abd7b32fe18825`
  (runner `out/k054-gadget-capture.sh`; evidence in
  `out/k054-serial-2026-07-11T013605Z.log` +
  `out/tethered-test-k054-gadget-2026-07-11T013605Z.log`).
- Results:
  - **UFS fully probes: /dev/sda..sdg (all 7 LUNs), 86 /proc/partitions
    entries.** Read-only discipline held — no UFS device was mounted or
    written.
  - **microSD: `sdhci_msm c0a4900.mmc` probes, CD GPIO found, card
    enumerates as mmc0 SDR104: `mmcblk0 SD200 183 GiB`, partition p1.**
    (Card: SanDisk Ultra 200GB provided by Lance 2026-07-11, fresh ext4,
    disposable.)
  - **ext4 on SD: mount + write (`hello-from-mainline.txt`) + readback +
    clean umount all OK; 179.4G usable.** pmOS rootfs path is proven.
- Class: `upstream-candidate` (ce78c1369); config change = bringup-local
  (defconfig fragment TBD for the pmOS APKBUILD).
- M2 (storage) COMPLETE per docs/ember-handoff-2026-07-10-milestone1-pmos-plan.md.
  Next = M3: pmOS rootfs on SD (pmbootstrap image), kernel via fastboot boot,
  later laf-partition flash per owner's boot-slot decision.

### K055 — M3: postmarketOS image built + written to SD (verified), resize gap found

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

- pmbootstrap built + exported a pmOS rootfs for `lge-joan`:
  `/tmp/postmarketOS-export/lge-joan.img` (1206910976 B = exactly 1151 MiB;
  GPT: p1 243 MiB EFI/boot, p2 906 MiB Linux root ext4). sha256
  `2d6b73ece751848dc1aa9ec87713566b83e4077655512e9210b9106595cde336`.
  boot.img sha256 `66d7baea279eff4d0e92b6d8ebec7e24db9a5f6a48b128a93b477a9016275672`.
- Written to the SanDisk 200GB microSD (mmcblk0) over the phone's USB link.
  IMPORTANT transfer lesson: busybox `nc -l | dd` truncates. With stdin from
  `</dev/null` it half-closes after ~73 KB; with `tail -f /dev/null` holding
  stdin it never signals EOF to dd. RELIABLE METHOD = HTTP: host
  `python3 -m http.server`, phone `wget -O /dev/mmcblk0 http://172.16.42.2:PORT/img`
  (content-length → deterministic, WGET_RC=0, "/dev/mmcblk0 saved").
  Needs a temporary host iptables ACCEPT on the usb-if for phone→host
  (ufw drops it); removed after (confirmed no leftover rule).
- VERIFIED: phone `dd if=/dev/mmcblk0 bs=1M count=1151 | sha256sum` ==
  host image hash, byte-for-byte match.
- **RESIZE GAP (answer to "use the whole 200GB?"): NO by default.** pmOS
  initramfs `resize_root_partition()` only grows p2 to 100% when the kernel
  cmdline has `pmos.force-partition-resize` (else it hits the else-branch:
  "Unable to resize root partition"). Our deviceinfo cmdline lacks it, so
  root would stay 906 MiB on the 200 GB card. FIX PENDING: add
  `pmos.force-partition-resize` to `deviceinfo_kernel_cmdline`, rebuild
  boot.img; first boot then runs parted resizepart 2 100% + resize2fs
  (idempotent, gated on has_unallocated_space).
- NEXT: apply the resize cmdline, rebuild+re-export boot.img, then first
  pmOS boot via `fastboot boot` and watch for USB-network + sshd.

### K056 — first pmOS boot attempt FAILED: boot.img kernel/ramdisk load overlap (diagnosed+fixed, phone wedged pending physical reset)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

- Applied resize: `deviceinfo_kernel_cmdline += pmos.force-partition-resize`
  (needs pkgrel bump on device-lge-joan to actually reinstall into rootfs —
  a checksum update alone does NOT rebuild an installed pkg). Verified the
  flag is in the boot.img header cmdline before booting.
- UUID note: every `pmbootstrap install` regenerates the rootfs image with
  fresh partition/fs UUIDs; boot.img references root by fs UUID, so boot.img
  and the SD image MUST come from the same build. Re-wrote the SD with the
  matching rebuild (fs UUID 9a5df9d1…), verified byte-for-byte (sha
  `0dcecdb8…`).
- First `fastboot boot` of the pmbootstrap-built boot.img: LG aboot showed
  transient `18d1:d00d`, then USB disconnected and the phone went fully dark
  (no fastboot/adb/gadget, no serial bytes). NOT a slow boot — the kernel
  never ran.
- ROOT CAUSE (measured from the boot.img headers): kernel_offset 0x8000 +
  kernel 18,981,009 B ends at 0x1222091 (~19.0 MiB), but ramdisk_offset was
  0x01000000 (16.0 MiB). **The ramdisk load address sits INSIDE the kernel
  image** → aboot copies the ramdisk over the kernel tail → corrupt kernel →
  hang. Our working bringup images never hit this because that kernel is
  14.8 MiB (fits under 16 MiB). The pmOS kernel is bigger largely due to the
  BTF/DWARF5 debug info pmOS's kconfig check requires.
- FIX (two forms):
  1. Immediate, ready-to-test with the CURRENT SD (same UUID): manually
     repackaged `out/boot-joan-pmos-ramdiskfix.img` (sha
     `9bdc4a58…`) — extracted the pmOS kernel+ramdisk+cmdline from the
     pmbootstrap boot.img and re-`mkbootimg` with `--ramdisk_offset
     0x02000000` (32 MiB). Verified overlap=False.
  2. Durable: `deviceinfo_flash_offset_ramdisk` 0x01000000 -> 0x02000000 in
     pmaports device-lge-joan (pkgrel=2, pushed). Future full builds are
     correct (they will churn UUIDs and need an SD rewrite).
- DEVICE STATE: **WEDGED, needs a physical Power+VolDown ~8s hold** (Lance) to
  reset — RAM-only boot corrupted, aboot did not fall back to LOS within
  ~8 min of watching. No partitions were flashed; LineageOS on the boot
  partition is untouched and will return after the manual reset.
- NEXT (when phone is back): `fastboot boot out/boot-joan-pmos-ramdiskfix.img`
  and watch for pmOS USB network + sshd (172.16.42.1). If it boots, first-boot
  resize grows root to ~199 GB.

### K057 — M3 COMPLETE: postmarketOS boots on joan (SSH over USB, full 200GB root)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

- `fastboot boot out/boot-joan-pmos-ramdiskfix.img` (sha `9bdc4a58…`) after
  Lance's physical reset: clean OKAY in 5.8s (vs the K056 wedge) — the
  ramdisk_offset 0x02000000 fix was the complete answer.
- pmOS initramfs gadget enumerated (18d1:d001), ping 172.16.42.1 OK, sshd up:
  `Linux lge-joan 7.2.0-rc2 #2-lge-joan`, "postmarketOS edge", key auth via
  id_pi_migration.
- **First-boot resize worked: / = /dev/mmcblk0p2 at 180.5G** (was 906M in the
  image) — pmos.force-partition-resize did its job on the 200GB SanDisk.
- Internal UFS (sda, 118.8G LineageOS) visible, unmounted, untouched.
- Vitals: 3.6G RAM seen, load nominal, 499-line dmesg with only 5
  fail/error lines (evidence: `out/pmos-firstboot-dmesg-2026-07-11.txt`).
- MILESTONE M3 (headless postmarketOS) COMPLETE. Remaining: M4 display/touch,
  M5 wifi/BT, laf-partition flash for cable-free boot, pmaports upstream MR.

### K058 — M4 begins: SW43402 panel driver + display DTS (builds; on-device blocked on mmss SMMU)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

- P2/P3 docs landed first (panel-sw43402.md, display-path.md,
  downstream-refs/) — verdict: mainline DPU1 (dpu_3_0_msm8998.h has both DSC
  1.1 blocks), NOT MDP5.
- New driver `drivers/gpu/drm/panel/panel-lg-sw43402.c` (kernel commit
  `6d7550d4a`): adapted from in-tree panel-lg-sw43408.c (same LG family,
  DSC 1.1). Real DV3.1 data: 1440x2880 cmd-mode, DSC 720x16/2-slice/8bpc/
  8bpp/block-pred, 19-cmd init sequence, PPS pack + compression-mode-ext.
  Kconfig+Makefile added. **Compiles clean** (panel-lg-sw43402.o built).
- DTS commit `86fbeea5b`: &mdss/&mdss_mdp/&mdss_dsi0/&mdss_dsi0_phy enabled,
  panel@0 node (reset TLMM35, vddio/vpnl = new gpio fixed-regulators on
  TLMM92/69), dsi0_out 4-lane + te-source. **DTB compiles clean.**
- NOT on-device yet: MDSS masters through mmss SMMU `cd00000.iommu` (TZ-owned,
  -110 deferred-probe). That SMMU is now the M4 gate. Next: get the mmss SMMU
  to probe (qcom smmu stream-mapping handoff quirks, not K030 skip), then a
  display-enabled bringup image + on-device DPU/DSI/panel probe test.
- Provenance: downstream panel dtsi copied verbatim to docs/downstream-refs/
  (GPL-2.0), cited in the driver commit + dependency-tracker.

### K059 — M4 diagnostic boot: display chain sound, blocked exactly at mmss SMMU

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

- Built a display-enabled bringup image (DRM/DRM_MSM/DPU/DSI + panel forced
  built-in; QCOM_LLCC/OCMEM also forced =y to allow DRM_MSM=y;
  `out/boot-joan-k059-display.img`, ramdisk_offset 0x02000000 per K056) and
  RAM-booted it. Evidence: `out/k059-dmesg-2026-07-11.txt` (465 lines, pulled
  over USB net via phone `nc -l`).
- RESULT (as predicted, clean): DTS parses fully, all display nodes present,
  panel driver does NOT crash. The "Fixed dependency cycle" lines are normal
  fw_devlink resolution, not errors. Chain reaches msm-mdss probe.
- Single blocker confirmed:
  `arm-smmu cd00000.iommu: probe ... failed with error -110` →
  `msm-mdss c900000.display-subsystem: probe ... failed with error -110`.
  MDSS times out waiting for its (TZ-owned) mmss SMMU. Nothing else in the
  display path fails. K058 driver+DTS are structurally validated on device.
- CONCLUSION: mmss SMMU (`cd00000`) is the sole M4 gate. Next session:
  make the mmss SMMU probe — qcom SMMU stream-mapping/handoff quirks
  (qcom_smmu, `qcom,adreno-smmu`-style or the -500 impl-def bypass), NOT the
  K030 blanket skip. Once it probes, MDSS→DPU→DSI→panel should cascade.

### K060 — display dependencies built in; SMMU now probes, but boot resets

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- K059 could not fairly test the module-less display chain: its effective
  config had `MSM_GPUCC_8998` disabled, while MSM8998 MMCC, the SW43402 panel,
  and backlight support were not all built in. Enabled
  `CONFIG_MSM_GPUCC_8998=y`, `CONFIG_MSM_MMCC_8998=y`,
  `CONFIG_DRM_PANEL_LG_SW43402=y`, and built-in backlight support, then rebuilt
  Image.gz + DTBs.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k060-clockctrl-builtins.img`, sha256
  `ac6739c33a7dba577a50252ab78090b2d5b8fbbe18d998175f269621d4e39269`.
  Fastboot transcript:
  `out/k060-clockctrl-builtins-ramboot-20260711T144700Z.log`.
- The screen stayed black and LineageOS eventually returned. Raw pstore was
  extracted immediately afterward; evidence:
  `out/k060-clockctrl-builtins-pstore-20260711T1452Z.strings.txt`, sha256
  `9be28fa8feab7fb3434e24676c8913b2e51b862ab6d8909d8648e8d480e5289e`.
  No panic/oops/SError signature was present.
- K060 changed the diagnosis: with the missing clock-controller/display
  drivers built in, both MSM8998 SMMUs can probe. The reset moved later into
  the active display path. The K059 `-110` was therefore a missing built-in
  dependency symptom, not the final display blocker.
- Class: `bringup-local` config correction; no kernel source change.

### K061 — MMCC-only isolation exposes the first decisive fault

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- Disabled GPUCC again while keeping MMCC, SW43402, and backlight built in.
  This one-variable test separated the display/mmss path from the adreno SMMU
  and GPU clock-controller path.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k061-mmcc-only.img`, sha256
  `2e7780ae575ab067aa7724e2e801042cb7e0625569731dac40d53a084577aa6a`.
  The boot reset and LineageOS returned 47 seconds after handoff; transcript:
  `out/k061-mmcc-only-ramboot-20260711T145639Z.log`.
- Raw pstore evidence:
  `out/k061-mmcc-only-pstore-20260711T1500Z.strings.txt`, sha256
  `6cc3c6c22a5095834e5aca8a394c7126ceb0751491b925443c7820a799bcc3ef`.
  The decisive sequence is:
  `cd00000.iommu` probes, reports zero preserved boot mappings,
  `c900000.display-subsystem` joins IOMMU group 0, then SID 0 immediately
  raises a stage-1 translation fault at boot-framebuffer IOVA `0x9ddaaa00`
  (`FSR=0x402`, `FSYNR0=0x21`, context bank 0).
- Interpretation: device-core default-domain attachment enabled translation
  before drm/msm had taken over the display and installed its own paging
  domain. Bootloader display DMA was still using a physical/identity address,
  so the default translated domain faulted immediately. K061 also disproves
  GPUCC/adreno as the necessary reset trigger.
- Class: diagnostic isolation; no kernel source change.

### K062 — MSM8998 MDSS identity-domain fix survives and reaches DRM fb0

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- Added `qcom,msm8998-mdss` to `qcom_smmu_client_of_match[]` in
  `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c`. This follows the existing
  Qualcomm MDSS policy: DRM display clients start in an identity domain, then
  drm/msm attaches its own paging domain at the controlled takeover point.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k062-msm8998-mdss-identity.img`, sha256
  `f5b2f95539c8f1fcb6cf41047663c85b0e4007b06effa93fb79a0602a40db7b1`.
  Result: **SURVIVOR** — mainline gadget `18d1:4e26` appeared eight seconds
  after fastboot handoff; transcript:
  `out/k062-msm8998-mdss-identity-ramboot-20260711T150134Z.log`.
- Live dmesg:
  `out/k062-dmesg-2026-07-11.txt`, sha256
  `5d28e85ca28c1f9d4dc095a8b247440a7fa5a1b210bb1fec4a5c970ecf7f7943`.
  MDSS binds DSI, DPU initializes, DRM registers, and fbcon reports
  `fb0: msmdrmfb frame buffer device`. This confirms the identity-domain
  change passes K061's early-fault/reset point.
- The internal panel still showed no visible output. Live DRM diagnostics
  (`out/k062-live-display-diag-2026-07-11.txt`, sha256
  `22df69232cf970fc62796ff035d090dffd39d6bc480f6f9f36df261d70577170`)
  report DSI-1 connected with the 1440x2880 mode active, but MMCC warns that
  `pclk0_clk_src` and `byte0_clk_src` did not update. Clock summary shows
  stale half-rate values (`57036853` and `42777639` Hz), followed by command
  mode commit/vblank timeouts. Later SID0 faults from the boot framebuffer
  remain visible during controlled DRM domain takeover, but unlike K061 they
  no longer reset the machine.
- Clean verified kernel commit:
  `7ff461605d7f71b528785913cee116e1e49ecb00` (`iommu/arm-smmu-qcom: Add
  MSM8998 MDSS identity domain`).
- Class: `upstream-candidate`; survival/DRM initialization verified, visible
  display explicitly not yet achieved.

### K063 — DSI clock parent-enable experiment REJECTED

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- Hypothesis: the MMCC RCG update warnings meant the DSI PLL parent was not
  enabled while changing the byte/pixel rates. Added
  `CLK_OPS_PARENT_ENABLE` to active `byte0_clk_src` and `pclk0_clk_src` on top
  of K062.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k063-dsi-parent-enable.img`, sha256
  `f928d549c2465759a7420c20c4cae7ce50b7aee493a8fde4aa24fabd90e3248a`.
  Mainline still survived and enumerated, but Lance confirmed the screen
  remained completely black. Evidence:
  `out/k063-dsi-parent-enable-ramboot-20260711T151526Z.log` and
  `out/k063-dmesg-2026-07-11.txt` (sha256
  `334e3f3b5ebfb9753199574808a3f302c735d99bc60c41570ec1058283a6c4a7`).
- K063 is a clear regression: dmesg adds zero-divisor warnings for the DSI PLL
  clocks, repeated `DSI PLL(0) lock failed`, clock disable/unprepare imbalance
  warnings, RCG update failure, and repeated DPU commit/vblank timeouts.
  The patch was fully reverted and must not be carried forward.
- A serial-triggered reboot subsequently left the phone absent from USB;
  physical Power+Volume-Down recovery was requested. No partition was flashed.
- Class: `rejected-experiment`.

### K064 — MSM8998 no-rate-cache clock fix tested: NO CHANGE

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- Source comparison against the public `msm8998-mainline/linux` tree found
  commit `878adc31071b02c1511e8908974a78dcb8d3dff0`, which adds
  `CLK_GET_RATE_NOCACHE` to MSM8998 byte0/byte1 and pclk0/pclk1. Its stated
  rationale matches one plausible K062 failure mode: a VCO shutdown can clear
  frequency setup while CCF's cached rate prevents reprogramming it.
- RAM-only image (K062 identity fix + that four-clock patch):
  `out/boot-joan-20260711-aurel-k064-dsi-rate-nocache.img`, sha256
  `1880b11f42d2f30f482f39a589547a36bc2bf8fbb6eea8aa3d0f5e7ccaaa8983`.
  Patch artifact:
  `out/20260711-aurel-k064-dsi-rate-nocache.patch`, sha256
  `44ca62d58616b82adde68d645c33ceddf3bb568cbb55ac23377a39b55c5a8366`.
- After physical recovery from K063, healthy authorized LineageOS ADB was
  reconfirmed and K064 was RAM-booted. Mainline gadget appeared eight seconds
  after handoff, but Lance again observed a completely black/off screen.
  Transcript: `out/k064-dsi-rate-nocache-ramboot-20260711T154301Z.log`.
- Dmesg `out/k064-dmesg-2026-07-11.txt` (sha256
  `64c9fe547dfaa3a806f034fed181a28a9acf61c44fcd29fec3755d2212b1d17e`)
  still has the same four pclk0/byte0 RCG update warnings. Live diagnostics
  `out/k064-live-display-diag-2026-07-11.txt` (sha256
  `67a11ec5cd6b4dcfb875e9ecd1089bf969a3076fdae15a81d66eb2cd7abe45e0`)
  show the exact same 57,036,853-Hz pixel and 42,777,639-Hz byte rates as
  K062. Connector/mode/CRTC remain connected, 1440x2880, enabled, and active.
- Result: `CLK_GET_RATE_NOCACHE` is not sufficient for this first takeover;
  it neither clears the RCG update failure nor changes the hardware rates.
  The source change remains absent from the clean kernel baseline.
- Class: `source-backed diagnostic`, no improvement.

### K065 — 10nm VCO calculation fix doubles VCO correctly, but panel remains black

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- A second public MSM8998 reference commit, `707f3fc86f6a24e9f710887eb028bd8d0df82580`
  (`drm/msm/dsi_phy_10nm: Fix bad VCO rate calculation`), changes the 10nm PLL
  set/recalc formulas from a `ref_clk * 2` model to the physical reference
  clock and stops overwriting `vco_current_rate` during recalc.
- K064's observed outputs were mathematically exact half-rates. From the
  1440x2880 DSC mode, the expected pixel/byte/VCO chain is approximately
  114,073,709 / 85,555,281 / 684,442,248 Hz; K064 reported 57,036,853 /
  42,777,639 / 342,221,118 Hz (all 0.5 within rounding). This made the
  reference commit a strong one-variable diagnostic rather than a blind quirk.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k065-10nm-vco-rate.img`, sha256
  `cfe1e802c28087ded8c03d8318bd2b28ee930734c69a48fad2d87def54fbb993`.
  Patch artifact:
  `out/20260711-aurel-k065-10nm-vco-rate.patch`, sha256
  `241d550e563e0691b6e32bfd449530d63b5827bb94b14734b7560138a5fb2d8b`.
- Mainline survived and the gadget appeared eight seconds after handoff, but
  Lance again observed a completely black/off panel. Transcript:
  `out/k065-10nm-vco-rate-ramboot-20260711T155141Z.log`.
- K065 did make the predicted low-level change: live clock summary now reports
  `dsi0vco_clk = 1,368,884,472 Hz`, exactly double K064's programmed VCO-side
  value. Evidence: `out/k065-live-display-diag-2026-07-11.txt`, sha256
  `a71c9bdebbe4534efc62ca0d676e5637585bedbddb394b3818ee94e5f938f71a`.
- However, the PLL output divider and MMCC RCGs did not latch new divisors:
  `dsi0_pll_out_div_clk` remained 342,221,118 Hz and pixel/byte outputs stayed
  57,036,853 / 42,777,639 Hz. Dmesg
  `out/k065-dmesg-2026-07-11.txt` (sha256
  `1fccf1e87e3ef602e2023a22abd8bbdbf61b9f71579980151cd1738e7992e1e5`)
  still contains the same four pclk0/byte0 RCG update warnings.
- Interpretation: the 10nm VCO formula fix is source-backed and demonstrably
  corrects one factor-of-two error, but is insufficient alone. The next root
  cause is the stale PLL output-divider/MMCC RCG programming or takeover
  sequencing, not the panel mode declaration itself.
- K065 recovered cleanly to authorized LineageOS with `reboot -f`; nothing was
  flashed. The exact public patch is now preserved in local kernel commit
  `5306416d22b41dbf64d04887cdaa368fe6388e3e`, with original author/date
  retained and Lance's sign-off added.
- Class: `source-backed partial correction`, visible display not achieved.

### K066 — clk_ignore_unused does not clear the clock-programming failure

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- The public MSM8998 issue tracker records that disabling unused clocks can
  blank working OnePlus/F(x)tec displays. Repacked the K065 binary with only
  `clk_ignore_unused` added to the command line; no source or DT change.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k066-vco-clk-ignore-unused.img`, sha256
  `8c6100b2842a75b513cf8a79202d23b44df4ae1f04c6e7abfa817cf780f6102f`.
  Mainline survived; transcript:
  `out/k066-vco-clk-ignore-unused-ramboot-20260711T160138Z.log`.
- Dmesg `out/k066-dmesg-2026-07-11.txt`, sha256
  `1cf6f933e726176e7e24046fce4588d3198e3b37caad2f65354a29aba5fb64ad`,
  confirms the flag took effect (`clk: Not disabling unused clocks`) but the
  same four pclk0/byte0 RCG update warnings occur before the unused-clock
  sweep. Thus this known workaround does not solve the active programming
  failure. Lance was not present to supply a reliable screen observation.
- K066 recovered cleanly to authorized LineageOS; nothing was flashed.
- Class: `source-backed cmdline diagnostic`, no technical improvement.

### K067 — real DSI VDD supply removes dummy regulator; physical result unobserved

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- Source audit found K062-K066 consistently logged
  `msm_dsi c994000.dsi: supply vdd not found, using dummy regulator`.
  Joan already supplied the controller's 1.2-V `vdda` rail and the PHY's
  0.875-V `vdds` rail, but omitted the controller's `vdd-supply`.
- This is not speculative: mainline `dsi_cfg.c` declares MSM8998 DSI `vdd`
  (0.9 V) and `vdda` (1.2 V) regulators; downstream `msm8998-mdss.dtsi`
  maps them to PM8998 L1/L2; and the public working MSM8998 OnePlus DTS maps
  `vdd` to L1 and `vdda` to L2. Added exactly
  `vdd-supply = <&vreg_l1a_0p875>;` to joan's `&mdss_dsi0`.
- K067 combined that one-line DT correction with K065's exact VCO formula
  fix. RAM-only image:
  `out/boot-joan-20260711-aurel-k067-dsi-vdd-vco.img`, sha256
  `f5aceb687f12b172f137e21882d8f4b695d7a8c13c0d672a5a24e3c0e1792b52`.
  Full patch artifact sha256
  `2988e0abb4d29e821826c9299d5013dc5b20af90b975b8a7042ce6da03fc80cd`.
- The harness process was interrupted with exit 130 after `fastboot boot`, but
  passive USB/ACM inspection proved K067 had completed the transition and was
  running live mainline. Transcript:
  `out/k067-dsi-vdd-vco-ramboot-20260711T161252Z.log`, sha256
  `fb269634c6c09bbb4ba779c6845d550846e23a28fb2f75598da0b2915a540687`.
- No reliable physical screen observation was captured before the clarification
  prompt expired and the session moved to checkpointing. Silence is not treated
  as a display result. K067 dmesg
  `out/k067-dmesg-2026-07-11.txt`, sha256
  `e537ef8776cf008725104785c06d9c017896a6fa1bb39054267110574019e0e2`,
  confirms the missing-`vdd` dummy-regulator warning is gone, while the same
  pclk0/byte0 RCG update warnings and commit/vblank timeout path remain.
- Live display diagnostics:
  `out/k067-live-display-diag-2026-07-11.txt`, sha256
  `42000a10b001d94bcb03b82b4845b8ba6a3adf8a788e370d07fad75edc1450ef`.
  The VCO remains corrected near 1.369 GHz but downstream divider/MMCC rates
  remain stale.
- Live framebuffer/KMS diagnostics:
  `out/k067-live-fb-kms-diag-2026-07-11.txt`, sha256
  `f17a57925e23b5877f7aa30e4af4f9a5fc625b8631d42e48c71c533bea31f59d`.
  DRM mapped the active framebuffer at fresh IOVA `0x2000`, and active
  `sspp_8`/DMA0 latched source address `0x2000`. Bootloader splash addresses
  in the reserved `0x9d400000..0x9f7fffff` range appeared only in inactive
  SSPPs. Therefore the recurring SID0 boot-splash faults explain loss of the
  inherited splash during handoff but do not explain the previously observed
  persistent black output after DRM owns and maps a fresh framebuffer.
- K067 recovered cleanly to fully booted authorized LineageOS; nothing was
  flashed.
- The exact public VCO change is now preserved in local kernel commit
  `5306416d22b41dbf64d04887cdaa368fe6388e3e`, retaining original author
  AngeloGioacchino Del Regno. The joan DSI VDD correction is local commit
  `b549c9f5b32a42dfa4a100d33df804e8ed042287`. Both remain unpushed.
- Class: `source-backed partial corrections`; regulator and VCO state improved,
  but K067's physical display outcome is unobserved. The earliest evidenced
  remaining failure is the DSI PLL output-divider/MMCC RCG programming or
  takeover sequence.

### K068 — parent-enable retest clears RCG update warnings but regresses PLL locking

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol-pro (hypothesis, patch, and build)
Agent-harness: Hermes:gpt-5.6-sol (device test, analysis, and documentation)
Date: 2026-07-11

- K063 had tested `CLK_OPS_PARENT_ENABLE` before the later VCO-rate and DSI-VDD
  corrections. K068 repeated the exact active-DSI0 byte/pixel RCG change on the
  K067 baseline to answer one bounded question: were K063's PLL failures only
  consequences of the then-unfixed VCO math or missing real DSI supply?
- RAM-only image:
  `out/boot-joan-20260711-aurel-k068-parent-enable-retest.img`, sha256
  `6794ab253be6132d39bdb5b1b13bd6e4bb3ac30963318b4ff553c30d6c0a05f4`.
  Exact debug patch:
  `out/20260711-aurel-k068-dsi-parent-enable-retest.patch`, sha256
  `8edde358256330c1f9b09cc674b32cdd8f54f36b535a469cf2eb051d7d3919a3`.
- The first transfer attempt hung in LG aboot at `Sending 'boot.img'` and never
  reached `OKAY`/`Booting`; it is transport-only evidence, not a kernel result.
  Log: `out/k068-parent-enable-retest-ramboot-20260711T1802Z.log`, sha256
  `91f70eb0b752e210299ccbdb6427d97e6d814eb2a419106b0420aefc716d89f7`.
  Lance physically recovered LineageOS before explicitly approving one retry.
- The approved retry completed (`OKAY`, `Booting`) and mainline USB/ACM appeared
  eight seconds after handoff. Transcript:
  `out/k068-parent-enable-retry2-ramboot-20260711T1808Z.log`, sha256
  `f2643d5aa8c991955a9c41e897e9651e9d5e7ed3792afadb607fc8c2c2976498`.
  Lance observed the panel as **completely black/off**.
- Dmesg `out/k068-live-dmesg-2026-07-11.txt`, sha256
  `a3e60679e531871b059dc67539779e98f2eac2ad039997c9168a44d2ca6238be`,
  contains zero `rcg didn't update its configuration` messages (K067 had four),
  but adds DSI PLL0 lock failures and clock-disable imbalance warnings. Thus
  parent enabling does let MMCC reprogram its RCGs, but it prepares the PLL at
  an invalid/stale divider point and is not a usable fix by itself.
- Live diagnostics `out/k068-live-display-diag-2026-07-11.txt`, sha256
  `e569b749de873ef6561c368800a2d9ecac3cad5e2f0a4dbf4d6235bea9769496`,
  still report DSI-1 connected at 1440x2880. VCO remains corrected at
  1,368,884,472 Hz, but PLL out-div remains `/4` at 342,221,118 Hz. The byte
  path remains 42,777,639 Hz; the pixel RCG now accepts 171,110,559 Hz rather
  than K067's 57,036,853 Hz, still not the required ~114,073,709 Hz.
- The downstream LG/Qualcomm 4.4 driver gives the now-leading sequencing clue.
  `drivers/clk/msm/mdss/mdss-dsi-pll-8998.c::dsi_pll_enable()` explicitly writes
  `PLL_PLL_OUTDIV_RATE` before starting/locking the PLL because its logical
  output-divider selection otherwise arrives after VCO rate setup. Current
  mainline `dsi_pll_10nm_vco_prepare()` starts and polls the PLL without that
  pre-lock write; its generic divider and handoff-state restoration can retain
  joan's inherited `/4` state.
- K068 was recovered to fully booted authorized LineageOS. An initial malformed
  ACM recovery command did not execute; the corrected literal `reboot -f`
  recovered the phone in 31 seconds. Nothing was flashed.
- The K068 debug change was reverted. A clean `Image.gz dtbs` rebuild completed;
  the clean source worktree is restored. Clean `Image.gz` sha256:
  `4e150748be1caafa5a0bacb8f2bf6dda8e23159a3e47a36d135c72ff04a02fa8`.
- Class: `source-backed diagnostic`, **rejected as a standalone fix**. Do not
  retain `CLK_OPS_PARENT_ENABLE` alone. The smallest next discriminator is the
  downstream pre-lock out-divider ordering on top of the K068 control, not
  another unrelated clock flag.

### K069 — forced pre-lock `/2` output divider does not persist or light the panel

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- K069 kept K068's parent-enable control and added one debug-only MSM8998 action
  based on downstream 4.4: force `PLL_PLL_OUTDIV_RATE=1` (`/2`) immediately
  before starting and polling PLL lock. The override was restricted to the
  MSM8998 old-timings 10nm PHY quirk.
- The target rates are independently reproduced from the panel mode and current
  mainline DSC formulas: pixel 114,073,709 Hz, byte 85,555,281 Hz, and bit clock
  684,442,248 Hz. `/2` is therefore the intended divider for the corrected
  1,368,884,472-Hz VCO in this mode.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k069-parent-enable-prelock-outdiv.img`, sha256
  `3d261ef3f3ce055dedbd264e59dac1a8e00ed955be13ccca8b4bd3bc19bff653`.
  Exact debug patch:
  `out/20260711-aurel-k069-parent-enable-prelock-outdiv.patch`, sha256
  `beefd96f87286224f305b9dc69f4b9515f0f7918ad50e029cfac25d3334326cc`.
- The single approved fastboot command completed normally. Mainline USB appeared
  11 seconds after handoff. Transcript:
  `out/k069-parent-enable-prelock-outdiv-ramboot-20260711T1837Z.log`, sha256
  `e5042a81c367a09fda45312d188c7fe74cd51ef082ec736f296a32fd5c652dec`.
  Lance observed the screen as **completely black/off**.
- Dmesg `out/k069-live-dmesg-2026-07-11.txt`, sha256
  `a10a0968de5afca65d0977fe34d1f1ba41a3f26bc39e0c6dcdb478a5d8e93eae`,
  still has a PLL0 lock failure and clock-disable imbalance warning, while the
  MMCC RCG update-warning count remains zero.
- Live diagnostics `out/k069-live-display-diag-2026-07-11.txt`, sha256
  `5f74cfbfc3335eadd517200cb48e3462b203197eadb2ba865377cb4c257e2d85`,
  are effectively identical to K068: connector connected at 1440x2880, VCO
  1,368,884,472 Hz, final PLL output still `/4` at 342,221,118 Hz, pixel
  171,110,559 Hz, and byte 42,777,639 Hz.
- Interpretation is deliberately narrow: a blind `/2` write in VCO prepare is
  insufficient and does not remain reflected in the final clock tree. This does
  not reproduce downstream's full logical-divider sequencing, where the chosen
  divider is cached and reapplied during enable. Mainline's handoff-state restore
  or later generic-divider programming can overwrite the debug value; K069 did
  not directly log those register transitions, so do not claim which one yet.
- K069 recovered cleanly to fully booted authorized LineageOS via ACM
  `reboot -f`; nothing was flashed. The debug patch was reverted and a clean
  `Image.gz dtbs` rebuild completed. Clean `Image.gz` sha256:
  `eb9c96519b05e09be77115f7d5853ed5a61d5ffa56c273b7ed95cbff3c1e6fea`.
- Class: `source-backed diagnostic`, **rejected as implemented**. Before another
  behavioral fix, instrument VCO prepare plus handoff save/restore to record the
  requested VCO, cached divider, live `PLL_OUTDIV_RATE`, `CLK_CFG0`, and
  `CLK_CFG1` in exact order.

### K070 — instrumentation finds zero initial VCO rate, not a bad saved divider

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- K070 retained the K069 control only to instrument the exact 10nm PLL ordering.
  It logged VCO rate, live/saved `PLL_OUTDIV_RATE`, `CLK_CFG0`, and `CLK_CFG1`
  during initial handoff save, every VCO prepare/lock poll, and restore.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k070-pll-order-instrumentation.img`, sha256
  `e5bf730b50559ae790ab127b3d1c8bafdf86c69ddc9aa62c01b639153c2b387f`.
  Exact debug patch:
  `out/20260711-aurel-k070-pll-order-instrumentation.patch`, sha256
  `b548040e10ec74ca306c44f229743b3dfdb2eeced019a7f09dbf06aa2437ca99`.
- The approved RAM-only boot completed normally and mainline USB appeared.
  Transcript `out/k070-pll-order-instrumentation-ramboot-20260711T1852Z.log`,
  sha256 `c91580fc710470c339c15d671dad211c463b1fc6654d68ccaedc07211d221bee`.
  Lance observed the screen as **completely black/off**.
- Dmesg `out/k070-live-dmesg-2026-07-11.txt`, sha256
  `b27c6e5b252f70b8683fe7a31d3c363b7ed615a19b03cd7d8239921799e8103d`,
  resolves the ordering question:
  - bootloader handoff state is already correct: outdiv `0x1` (`/2`), bit
    divider `0x1`, pixel divider `0x3`, and pixel mux `0x1`;
  - `vco_current_rate` is nevertheless **zero** at initial save and the first
    parent-enable prepares;
  - one zero-rate prepare reaches lock with inherited state, but the next enters
    with VCO zero and fails lock (`-110`) even after K069 forces `/2`;
  - handoff restore correctly reapplies `/2`, bit 1, pixel 3, mux 1;
  - after normal rate propagation sets VCO to ~1.3688845 GHz, all logged PLL lock
    polls succeed with `/2`.
- Live clock diagnostics:
  `out/k070-live-display-diag-2026-07-11.txt`, sha256
  `6c9ae15e2ca08206841030d3ed6d1538c09bd495a5fb0cdf932ad7303044bb7f`.
- Root cause is an interaction between two changes. Local/public-reference commit
  `707f3fc86f6a` corrected the VCO math and removed the recalc callback's
  `vco_current_rate` assignment. Upstream commit
  `8a48e35becb214743214f5504e726c3ec131cd6d` (`drm/msm/dsi/dsi_phy_10nm: Fix
  missing initial VCO rate`) added the initial recalc call specifically so
  handoff restore would not use VCO zero; that upstream call relies on recalc
  storing the result. Combining both patches leaves the member zero and exposes
  the failure as soon as K068 parent-enables the PLL.
- Current upstream source again assigns `vco_current_rate = vco_rate` in the
  10nm recalc path. The smallest K071 discriminator is therefore the one-line
  restored assignment on top of K068's parent-enable control, with no hardcoded
  output-divider override.
- K070 recovered cleanly to fully booted authorized LineageOS. Nothing was
  flashed. Instrumentation was reverted and a clean `Image.gz dtbs` rebuild
  completed; clean `Image.gz` sha256
  `5d10ff584fcccf70a05642124053ec48e382eed07b4d543b279b44b17f01ba9c`.
- Class: `diagnostic instrumentation`, **rejected from production source**;
  result identifies a source-backed one-line fix candidate for K071.

### K071 — recalc side-effect restoration collapses the live clock tree to zero

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- K071 dropped K069's hardcoded divider and all K070 instrumentation. It kept
  K068's `CLK_OPS_PARENT_ENABLE` control and restored exactly one line removed by
  public-reference commit `707f3fc86f6a`:
  `pll_10nm->vco_current_rate = vco_rate` in the 10nm VCO recalc callback.
- RAM-only image:
  `out/boot-joan-20260711-aurel-k071-vco-state-parent-enable.img`, sha256
  `0d07f16366da832b3334499e1bbf8a3be9f5c7b02c576684effb489ac7ac2c58`.
  Exact patch:
  `out/20260711-aurel-k071-vco-state-parent-enable.patch`, sha256
  `48fbaf902e4f6ccec347b2750235c7e166ec3f828af1605fbfdb933d16d946d5`.
- The approved RAM-only boot completed normally; mainline USB appeared after
  18 seconds. Transcript:
  `out/k071-vco-state-parent-enable-ramboot-20260711T1903Z.log`, sha256
  `7cb49ce7d91ccd31d6f57824042bd391f964cac30c9430f420586fa98c04cb6e`.
  Lance observed the screen as **completely black/off**.
- K071 is worse than K068-K070. Dmesg
  `out/k071-live-dmesg-2026-07-11.txt`, sha256
  `7e5b41325483ea1e6d8df5801f810253eafcfa98b3631dc84f343c46822a317b`,
  records four PLL-lock failure events, one byte0 RCG update failure, three
  clock-disable imbalance warnings, and 31 vblank timeouts.
- Live diagnostics `out/k071-live-display-diag-2026-07-11.txt`, sha256
  `a9dc7d577677c0abdc63e71ec6ea75d8f85c9eafc31290669332d120a81e34f2`,
  show the entire DSI0 VCO/output/bit/pixel/byte clock hierarchy at **0 Hz**.
- Interpretation: restoring recalc's global side effect is not safe in this local
  combination. A recalc that observes inaccessible/unprepared PLL registers can
  overwrite `vco_current_rate` with zero, and K071 does not preserve the valid
  value seen later in K070. The result rejects the simple one-line side-effect
  restoration even though current upstream carries it in a different patch
  context.
- If this path continues, preserve a pure recalc callback and initialize
  `vco_current_rate` once in `dsi_pll_10nm_init()` from a nonzero recalc result,
  falling back to `min_pll_rate` only when zero. Instrument that assignment before
  treating it as a fix; do not stack another blind divider change.
- K071 recovered cleanly to fully booted authorized LineageOS via ACM
  `reboot -f`; nothing was flashed. The patch was reverted and a clean
  `Image.gz dtbs` rebuild completed; clean `Image.gz` sha256
  `95575b5f2fe87133a936c1ca8355011c39f97dc98d8524016771137babae610a`.
- Class: `source-backed interaction test`, **rejected as implemented**.

### K072 — init-only nonzero VCO seed: PLL LOCKS, panel still dark (RCG-didn't-update is the remaining wall)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

Built on Aurel's clean tip b549c9f5b (NO K068 parent-enable). Change: in
`dsi_pll_10nm_init()`, capture `dsi_pll_10nm_vco_recalc_rate()` once and store
it into `vco_current_rate` when in [min,max], else fall back to min_pll_rate;
recalc kept pure (no K071 side-effect). Plus bounded logs (init seed, prepare
entry vco, lock result). Root cause it fixes: the stock `if (!recalc) seed=min`
DISCARDS a valid nonzero readback because the imported pure recalc no longer
stores it — leaving vco_current_rate=0 → set_rate(0) → -110.

Artifacts: patch `out/20260711-ember-k072-init-vco-seed.patch`; image
`out/boot-joan-20260711-ember-k072-init-vco-seed.img` sha256
`57d7d3cd58a0edc0c8cccf89027dbfbbe4038f9bf0111e7e049a2efe1eb2157a`; dmesg
`out/k072-live-dmesg-2026-07-11.txt`; serial `out/k072-serial-20260711T193513Z.log`.

RESULTS (RAM boot, Lance present + approved, recovered to LOS):
- `K072 init: recalc=684431762 seed=1000000000 (fallback)` — init readback was
  below min (684 MHz), so fallback 1 GHz used; the point is it is NONZERO.
- `K072 prepare entry: vco_current_rate=1368884480` then
  `K072 lock result: rc=0` — **PLL LOCKS, 0 lock failures** (K070 -110, K071 x4).
- **0 vblank timeouts** (K071 had 31). fb0 registered
  (`msm_dpu ... [drm] fb0: msmdrmfb`), DPU bound c994000.dsi.
- Panel: **still fully black/off** (Lance visual).
- Remaining wall: 4x `byte0_clk_src: rcg didn't update its configuration`
  (clk-rcg2.c:136) during `dsi_link_clk_set_rate_6g`. The MMCC byte/pixel RCGs
  do not latch → DSI link byte/pixel clocks wrong → panel gets no valid signal.

KEY INSIGHT: K068's `CLK_OPS_PARENT_ENABLE` is exactly what made these
RCG-didn't-update warnings DISAPPEAR (Aurel K068), but K068 alone had the
vco=0 PLL failure that K072 now fixes. **The two are complementary.**
NEXT CANDIDATE K073 = K068 parent-enable + K072 init seed together: should
give PLL lock (K072) AND RCG latch (K068). Class: K072 = debug-only as-is
(instrumentation); the init-seed core is upstream-shaped once proven. Kernel
reverted to clean b549c9f5b, patch preserved. Nothing pushed.

### K073/K074 — parent-enable hangs; working-reference NOCACHE config staged (K074 UNTESTED)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

- K073 = K068 parent-enable + K072 seed. RAM-booted (Lance present/approved).
  Panel BLACK (Lance visual). Userspace unreachable for dmesg; ramoops did NOT
  survive the Power+VolDown hard reset (pulled stale #75 g86fbeea5b, not K073).
  Conclusion: CLK_OPS_PARENT_ENABLE on byte0/pclk0 deadlocks once the PLL can
  actually lock (its forced parent-prepare re-enters the PLL lock under clk
  locks). Reject the parent-enable approach.
- ROOT-CAUSE REFERENCE (dependency-tracker): the WORKING msm8998-mainline port
  (/tmp/msm8998-mainline-linux-ref) uses on byte0_clk_src AND pclk0_clk_src:
  `.flags = CLK_SET_RATE_PARENT | CLK_GET_RATE_NOCACHE` — NOT parent-enable.
  Our stock 7.2 tree has plain CLK_SET_RATE_PARENT. That NOCACHE flag is the
  proven-config difference.
- CAPTURE FIX (initramfs, all future display tests): removed the sleep-15
  mass_storage UDC re-bind that re-enumerated ACM+network and broke every
  post-~15s dmesg pull this session. Init now serves dmesg on tcp/9600 and
  clk/regulator diag on tcp/9601 persistently, no re-bind. New ramdisk
  `out/initramfs-bringup-v2.cpio.gz`.
- K074 (STAGED, UNTESTED — awaiting Lance boot approval): clean b549c9f5b +
  K072 vco seed + CLK_GET_RATE_NOCACHE on byte0/pclk0 (working-ref config,
  no parent-enable) + v2 capture init. Patch
  `out/20260711-ember-k074-k072seed-plus-nocache.patch`; image
  `out/boot-joan-20260711-ember-k074-nocache.img` sha256
  `d31ae627b5bb...` (full hash beside image). Kernel tree reverted clean.
- Status of the display: NOT working. Best-founded next test = K074. If K074
  still black WITH clean dmesg, inspect: byte0/pclk0 live rates + RCG-update,
  panel prepare (regulator enable + DSI cmd ACK), then compare enable ORDER
  against the working ref's dsi_host clock sequence.

### K074 — NOCACHE config: PLL locks, no hang, but byte clock at HALF rate (out_div /4 not /2) + splash SMMU faults; panel still black

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

Config: clean b549c9f5b + K072 vco seed + CLK_GET_RATE_NOCACHE on
byte0/pclk0 (working-msm8998-reference config, NOT K068 parent-enable) +
v2 stable-capture init. RAM-boot, Lance present/approved, recovered to LOS.
Artifacts: patch `out/20260711-ember-k074-k072seed-plus-nocache.patch`,
image sha256 `d31ae627b5bb...` (full beside image), dmesg
`out/k074-live-dmesg-2026-07-11.txt`, clk `out/k074-clk-2026-07-11.txt`.

RESULTS:
- PLL locks (K072 lock result rc=0, vco=1.368884480 GHz). 0 vblank timeouts.
  fb0 registered, DPU bound c994000.dsi. **No hang** (confirms the K073 hang
  was purely K068's CLK_OPS_PARENT_ENABLE; NOCACHE is safe).
- CLK_GET_RATE_NOCACHE alone did NOT clear `rcg didn't update its
  configuration` (still 4x, on byte0/pclk0 during msm_dsi_host_power_on).
- Panel STILL BLACK (Lance visual).
- **Two concrete leads found (capture now reliable):**
  1. Live DSI clock rates too LOW: byte0=42.78 MHz, pclk0=57.04 MHz; VCO
     1.369 GHz with out_div=/4 (dsi0_pll_out_div_clk=342 MHz). For
     1440x2880 60Hz DSC-8bpp/4-lane the byte clock should be ~2x higher
     (~70 MHz), i.e. out_div should be /2. This is the same /4-vs-/2
     divider issue Aurel chased in K069/K070. STRONG suspect for black:
     half-rate DSI link => panel gets no valid signal.
  2. Bounded burst of 10x `arm-smmu cd00000.iommu: Unhandled context
     fault iova=0x9d400000` during handoff — that IOVA is our
     cont_splash_mem (bootloader framebuffer). Bootloader display still
     scanning out through the mmss SMMU during mainline takeover; the
     MDSS identity domain (7ff461605) passes through until the DPU
     attaches its translating domain for fb0, then the old splash addr
     faults. Bounded (stops after ~10), not a storm.

NEXT (see handoff docs/ember-handoff-2026-07-11-k074-clock-divider.md):
primary = make the PLL out_div /2 (correct byte/pixel rate) in a way that
STICKS with K072's seed — the RCG can't latch because the target rate
math/divider is off, not because the parent is disabled. Compare our
dsi_phy_10nm out_div/postdiv programming against the working reference.
Secondary = the splash handoff fault. Kernel reverted clean; nothing pushed.

### K075 — panel-prepare instrumentation (BUILT, ready-to-boot, NOT yet tested)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

Base = K074 clock config (K072 seed + CLK_GET_RATE_NOCACHE) + dev_info logs
in sw43402_prepare() to answer the one open question the K074 clock analysis
could not: does the panel init sequence actually reach the panel?
- Logs: "K075 panel prepare: enabling supplies", supply-enable failure,
  "reset done, sending init seq", and "K075 panel prepare DONE, accum_err=%d".
- The `accum_err` value is decisive: it accumulates errors from every
  mipi_dsi_*_multi() call. accum_err != 0 => the DSI command transfers
  FAILED (link/clock not ready) => init never reached the panel, so the
  half-rate byte clock (K074 finding) is the direct cause. accum_err == 0
  but still black => commands went out fine; the problem is DPU scanout /
  command-mode TE kickoff, not the panel init.
Artifacts: patch `out/20260711-ember-k075-panel-instrumentation.patch`;
image `out/boot-joan-20260711-ember-k075-panel-instr.img` sha256
`18f0d9b9675c3a88085208532c0ac290cacfb4ef2226a86216e391a651561bf3` (uses the
v2 stable-capture initramfs; pull dmesg from tcp/9600). BUILT and packaged,
kernel tree reverted clean; awaiting a device boot (Lance present/approved).
This is the first thing to boot next session — it partitions the remaining
problem in one shot.

### K076 — divider writer trace + panel instrumentation (TESTED, black/off)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11

Base = K075/K074 behavior plus filtered instrumentation in the generic divider
and 10 nm DSI PLL save/set/prepare/restore paths. RAM-only boot succeeded;
serial, live dmesg, clock summary, regulators, interrupt snapshots, and the
panel helper status were captured before returning to LineageOS.

Direct evidence:
- Every transfer first programmed `dsi0_pll_out_div_clk` to encoding 1 (`/2`,
  684.442248 MHz) and then programmed encoding 2 (`/4`, 342.221120 MHz).
- Final framework clocks were half-rate: pixel 57.036853 MHz and byte
  42.777639 MHz.
- `K075 panel prepare DONE, accum_err=0` proves only that the host-side write
  helper calls returned successfully. These were write-only transfers without
  validated ACK/readback, so it does not prove the panel received or accepted
  the commands. This corrects the over-strong K075 interpretation above.
- No PLL-lock, MMCC RCG-update, or vblank-timeout message was captured.

Source tracing identified the second 342.221120 MHz request as the
`byte_intf_clk` rate operation. Mainline parents both MSM8998 byte branches
directly to `byte0_clk_src`, so requesting byte-interface rate 42.777640 MHz
propagates through the shared byte source and PHY byte /8 chain, forcing the
PLL output divider to `/4`. Downstream MSM8998 instead models a dedicated
byte-interface divider at MMCC register `0x237c`.

Artifacts: `out/boot-joan-20260711-aurel-k076-divider-panel-instrumentation.img`,
`out/20260711-aurel-k076-divider-panel-instrumentation.patch`,
`out/k076-live-dmesg-2026-07-11.txt`, and
`out/k076-live-serial-diag-2026-07-11.txt`.

### K077 — skip byte-interface set_rate discriminator (TESTED, rejected as fix)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11

Exactly one behavior changed from K076: `dsi_link_clk_set_rate_6g()` temporarily
skipped `clk_set_rate(byte_intf_clk, byte_intf_clk_rate)`. This is a diagnostic
bypass, not a production/upstream candidate.

The host capture process was interrupted by the agent/tool reset after
`fastboot boot` had already returned `OKAY`. The phone remained in the known
mainline USB gadget state (`18d1:4e26`); evidence was subsequently salvaged
through `/dev/ttyACM0`, then the phone was rebooted with the exact serial
`reboot -f` command. LineageOS returned with `sys.boot_completed=1` in 31 s.

Direct K077 evidence:
- 13 output-divider writes all selected encoding 1 (`/2`); there were zero
  encoding-2 (`/4`) writes.
- Final clock summary: VCO 1.368884472 GHz, PLL out 684.442236 MHz, pixel
  114.073706 MHz, byte 85.555279 MHz. Thus the K076 source attribution and
  half-rate-clock diagnosis are confirmed.
- `mdss_byte0_intf_clk` also remained 85.555279 MHz instead of its intended
  42.777640 MHz, which is why skipping the rate call cannot be the real fix.
- DRM state was active at 1440x2880@60: fbcon framebuffer 86 on plane 0,
  CRTC enabled/active, DSI-1 attached, dual mixers/DSC assigned.
- No PLL-lock failure, RCG-update failure, or vblank timeout was captured.
- The SMMU context-fault IRQ count was 2448 in both samples five seconds
  apart (delta 0); three textual fault reports were present, but no active
  steady-state fault storm was proven.
- Panel helper status remained `accum_err=0`.
- Lance's physical observation: screen completely black/off.

Disposition: K077 proves that the byte-interface rate request caused the `/4`
half-rate state, and that correcting the pixel/byte clock rates alone is not
sufficient for visible output. Reject the skip as a fix. The source-correct
clock follow-up is the dedicated MSM8998 byte-interface `/2` divider; after
that, investigate panel receipt/acceptance and the DSI video/command sequence
rather than returning to the already-correct active DPU scanout state.

Artifacts and hashes:
- image `out/boot-joan-20260711-aurel-k077-skip-byteintf-rate.img`, SHA-256
  `5c90e6ed619b909c8643c605d79a9940131630bf851e6533342e67c2d1d68af5`;
- patch `out/20260711-aurel-k077-skip-byteintf-rate.patch`;
- recovered serial evidence `out/k077-live-serial-diag-2026-07-11.txt`;
- interrupted runner transcript `out/k077-ramboot-20260711T214307Z.log`;
- manifest `out/k077-hashes.txt`.

Kernel experiment tree remains dirty and uncommitted; nothing was pushed.

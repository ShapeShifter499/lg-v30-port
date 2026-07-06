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
  `joan/latest-clean-test`, one debug-only commit `f0d368d28`. STAGED, not yet
  device-tested (needs Lance). Image `out/boot-joan-imem-oracle.img`
  (sha256 `8d180d57b91aefae1d4fdbbb88cf138d76711866c7e5e3dcdceebc118fb768c7`).
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

### IMEM reset-reason oracle (Ember 2026-07-06) — STAGED, not device-tested

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

## Current narrowed hypothesis

The blocker still looks like a secure/boot-chain/platform-state resetter, but
not one solved by the simple downstream sysfs `SEC_WDOG_DIS` path, direct APSS
watchdog pets, CPU-idle changes, single-core boot, simply reserving the observed
downstream high-memory secure/shared pools, matching downstream's DLOAD-off SCM
argument shape, registering a downstream-style QSEE log buffer, merely reaching
RPM `rpm_requests` rpmsg setup, or sending a bare downstream BOB `bobm=2` RPM
vote. Next investigation should compare very early downstream boot setup against
mainline,
especially:

- CPU/Kryo errata SCM calls (`drivers/soc/qcom/scm-errata.c` downstream);
- LGE panic/restart-reason and IMEM cookie setup;
- broader downstream RPM regulator/default votes / clocks / power-domain requests;
- SMEM/bootreason/restart cookies;
- other early `SCM_SVC_BOOT` / TZ setup before or around downstream
  `msm_watchdog` init;
- downstream dmesg events before ~0.4s that mainline does not mirror.

## Attribution

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

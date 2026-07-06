# V30 mainline bringup — debug state handoff (2026-07-06)

Session: Ember on nym-nest, ~18 tethered boot rounds with Lance at the
device. Read this TOP TO BOTTOM before touching the phone — half of
this session's cost went to instruments that silently lie.

## Where the bug hunt stands

Mainline kernel (v7.2-rc1 + `lge-joan-bringup`, config = arm64
defconfig + forced-builtin USB/PSTORE/QCOM_WDT) on LG V30 US998
(hw rev 1.0, board-id 0xc08, bootloader unlocked, LineageOS 20
installed, TWRP on recovery):

| Boot stage | Status | Evidence |
|---|---|---|
| aboot accepts + enters our kernel | ✔ proven | PSCI-reset timing probe at `primary_entry`: ~15s cycle vs ~42s watchdog baseline |
| `start_kernel` completes | ✔ proven | same probe before `rest_init()`: fast |
| userspace `/init` runs | ✔ proven | sysrq-b as first init act: reset at ~11s post-handoff |
| USB UDC (dwc3) probes | ✘ never seen | no `/sys/class/udc` entry within ~16s of userspace (window limited by the resetter) |
| **~27s: something resets the SoC** | **UNSOLVED** | consistent ~42s host-side cycle (27s + ~15s LOS boot); happens even with init idling + `/dev/watchdog` pets |

The ~27s resetter is the blocker: kill it and dwc3 gets unlimited
deferred-probe time AND the mass-storage diag mule can deliver
mainline's own dmesg (the mule is proven — see below).

`/dev/watchdog` (qcom-wdt on our added DT node) is **flaky across
identical boots** — present some rounds, absent others; unexplained.
**wdkill rounds 18+19 RESULTS (the session's key finding):**
- Round 18, pet + `EN=0` via /dev/mem: reset came EARLIER (~15s
  post-handoff vs the 27s baseline) — writing EN=0 to the armed block
  PROVOKES an immediate response.
- Round 19, pet-only (`RST=1` every 2s, EN untouched): baseline ~27s
  reset unchanged — pets of the non-secure counter don't help.

Conclusion: the ~27s resetter is almost certainly the **TZ secure
watchdog**. TZ reacts to non-secure EN meddling and ignores
non-secure pets. NEXT MOVE: early kernel-side SCM call mirroring
downstream `drivers/soc/qcom/watchdog_v2.c:265`:
`scm_call2(SCM_SIP_FNID(SCM_SVC_BOOT=0x1, SCM_SVC_SEC_WDOG_DIS=0x7))`
with arg[0]=1 (SMC convention on 8998; mainline qcom_scm has no
wrapper — add a bringup-branch initcall using __qcom_scm_call or a
raw arm_smccc_smc: fnid owner=SIP(2), svc 0x1, cmd 0x7 →
smc id 0x82000107? — verify encoding against downstream scm.h before
firing). Secondary suspect if that fails: a panic (redo the panic=30
vs panic=5 A/B cleanly, now that instruments are trustworthy).

## Debug channels — what WORKS and what LIES

- ✔ **fastboot boot (RAM-only)**: works, ~3.5min/cycle, BUT ONLY from
  fastboot entered via `adb reboot bootloader`. Fastboot entered from
  the power-menu ("restart into fastboot") answers getvar with EMPTY
  values and hangs on image download. If wedged: phone screen offers
  power off/restart → "restart" boots LOS → re-enter via adb.
- ✔ **Timing oracle**: PSCI SYSTEM_RESET (`smc` x0=0x84000009) at a
  chosen point; measure handoff→re-enumeration on host. ~15s+LOS =
  probe reached; ~42s = watchdog got there first. One bit per boot,
  brutal but reliable.
- ✔ **Mass-storage diag mule** (proven under downstream kernel,
  round 16): init writes diag file, exposes as read-only
  mass_storage LUN, host reads `/dev/sdX` raw. Needs a working UDC,
  so useless on mainline until the resetter dies. Captured downstream
  ground truth lives in `docs/downstream-diag-2026-07-06.txt` (full
  LOS dmesg, /proc/interrupts, regulator summary — P1 material!).
- ✘ **ramoops/pstore: DEAD ON THIS DEVICE.** Even LOS→LOS warm
  reboot loses it (LG boot chain scrubs the region). All layouts
  byte-matched to downstream — irrelevant. Do not spend cycles here;
  the breadcrumb code on `joan/bringup-debug` is kept for reference.
- ✘ **busybox in initramfs had NO telnetd, NO devmem** — silent
  no-ops behind `2>/dev/null`. Alpine's busybox-static also lacks
  both. The M1 "telnet shell" needs busybox rebuilt from source
  (toolchain on nym-nest: `aarch64-linux-gnu-gcc`) or dedicated
  static tools like wdkill. VERIFY APPLETS with `grep -ac NAME bin`
  before trusting any of them.
- ✘ **ACM serial + RNDIS data under downstream 4.4 gadget**: enumerate
  but don't pass data (rndis TX wedges, ttyGS0 shell silent). The
  mule is the only proven data-out path so far.

## Host-side pitfalls that cost real time

1. **ONE fastboot client at a time.** Two watcher scripts racing the
   same fastboot device interleave the protocol and wedge LG's aboot
   (needs on-phone button to recover). Before arming ANY watcher:
   confirm none is running. This burned three cycles + two wedges.
2. **`pkill -f` self-match**: the harness wraps commands so the
   pattern matches the wrapper's own argv even with the `[b]racket`
   trick, if the same string appears elsewhere in the command. Kill
   by PID, in a separate call from anything referencing the path.
3. Phone-side: diagnostic initramfs now self-reboots after 15min
   (`/keep` to cancel) so dead-end boots don't need the power button.

## Repos/branches (all nym-nest)

- kernel `coding/linux-mainline-v30`:
  - `lge-joan-bringup` = clean bringup work (3 commits: DTS scaffold,
    ramoops match, LG memory carve-outs).
  - `joan/bringup-debug` (CURRENT) = + watchdog DT node commit
    (`93fe462d7`, upstreamable later) + NEVER-MERGE breadcrumb commit
    (`6c5f06bc8`).
- harness `coding/lg-v30-port`: init v3 (wdkill + tolerant gadget +
  self-reboot), wdkill src+bin, this doc, downstream diag capture.
- Test images in `lg-v30-port/out/` (gitignored):
  `boot-joan-mainline.img` = round-19 (pet-only wdkill),
  `boot-joan-hybrid-stockkernel.img` = stock kernel + our initramfs
  (the diag-mule vehicle, proven).

## Suggested next moves (in order)

1. Park-state check: phone in LOS, adb authorized for nym-nest, adb
   root enabled (LOS "Rooted debugging").
2. TZ sec-wdog SCM disable hack in kernel (see key finding above for
   the exact call); retest with a SINGLE watcher.
4. If alive but no UDC: hybrid-mule a mainline diag by waiting — with
   the resetter dead, check UDC at 5min; if absent, the diag mule
   can't carry — fall back to timing-encoding WHY (probe
   /sys/bus/platform/drivers/dwc3-qcom presence etc., one bit each).
5. Once ANY mainline USB works: mule delivers mainline dmesg and this
   stops being archaeology.

Do not flash anything. Do not write to phone storage. Lance present
for all device work.

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-06

## Aurel follow-up — SCM/discriminator tests (2026-07-06)

Aurel + Lance retested from LineageOS via `adb reboot bootloader` with a
single `fastboot boot` client. No packages were installed. All tests were
RAM-only and returned to LineageOS; no phone storage was written.

New evidence:

| Test image / change | Result |
|---|---|
| `qcom_scm_probe()` wrapper for `SEC_WDOG_DIS` (svc 0x1 cmd 0x7 arg 1, mainline `qcom_scm_call`) | Still reset/rebooted to LineageOS at the normal host-side window (~46-50s). |
| early raw SMC variants (`std64`, `fast64`, `std32`, `fast32`) | Did not fix; the broader convention spray shortened the reboot window (~30s host-side), so it is likely noisy/unsafe as a fix. |
| exact raw downstream fnid `0x02000107` + arg 1 | Did not fix; returned to LineageOS at ~30s host-side. |
| clean kernel with cmdline `panic=30` | Returned to LineageOS at ~46.5s, same as panic=5 baseline; this argues against a normal Linux panic + `panic=5` reboot. |
| APSS watchdog DT node disabled (`status = "disabled"`) | Returned to LineageOS at ~46.6s; this argues against mainline `qcom_wdt` probing/reprogramming the non-secure APSS WDT as the reset source. |
| timing oracle: PSCI reset at `qcom_scm_probe()` entry | Returned to LineageOS at ~29.7s host-side, proving `qcom_scm_probe()` is reached early enough to run before the normal reset window. |
| direct `0x42000107` + QCOM A6 quirk at `qcom_scm_probe()` entry, followed by non-secure WDT `EN=0` | Still returned to LineageOS at ~44.5s; no evidence that the attempted secure watchdog disable made `EN=0` safe. |
| `SEC_WDOG_TRIG` (svc 0x1 cmd 0x8) via `qcom_scm_call_atomic()` after `__get_convention()` | Did not produce an earlier reset than baseline, suggesting the current mainline SCM invocation path/command form is not doing what downstream's watchdog code does for these commands. |

Interpretation update: `qcom_scm_probe()` timing is not the blocker, and
panic/APSS-WDT-driver explanations are now weaker. The remaining hard problem
is why the downstream `SEC_WDOG_DIS`/`SEC_WDOG_TRIG` command path is not taking
effect from mainline despite apparently matching the obvious svc/cmd IDs. Next
work should stop piling on boot attempts and inspect the downstream SCM calling
convention/preconditions in more detail (version probing, A6 quirk, atomic bit,
argument convention, return-value handling, and whether downstream's watchdog
path depends on additional TZ/SCM setup before these commands are accepted).

Temporary experimental patches were not left in the kernel tree. The attempted
SCM patch was saved for reference only at
`lg-v30-port/out/aurel-sec-wdog-scm-experiments-2026-07-06.patch`.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## Aurel follow-up — post-SCM watchdog-path analysis (2026-07-06)

Additional work after comparing downstream and mainline SCM paths:

- Downstream LineageOS runtime check: writing `1` to
  `/sys/devices/soc/17817000.qcom,wdt/disable` invokes downstream's own
  `SCM_SVC_BOOT` / `SCM_SVC_SEC_WDOG_DIS` path and fails with
  `scm_call failed: func id 0x42000107, ret: -2` followed by
  `Failed to deactivate secure wdog`. This is important: the downstream
  `SEC_WDOG_DIS` sysfs path is not a known-good runtime path on this phone.
- Downstream's normal survival path is instead the `msm_watchdog` thread:
  it programs APSS WDT bark/bite, enables the WDT, then logs
  `pet_watchdog [enable : 1 ...]` every ~10s on LineageOS.
- A clean mainline test emulated downstream's APSS WDT programming from an
  early joan-gated kernel thread while disabling the generic `qcom-wdt` DT
  node so it could not write `EN=0`. Two variants were tried:
  - EN=1, bark=16s, bite=19s, pet every 2s: still rebooted to LineageOS.
  - EN=3 (`EN|UNMASKED_INT_EN`, matching downstream `qcom,wakeup-enable`),
    bark=16s, bite=19s, pet every 2s: still rebooted to LineageOS at the
    normal host-side window (~45.5s after `fastboot boot` completed).
- These APSS tests were rebuilt with `qcom_scm.c` clean and force-recompiled
  after a leftover SCM timing-oracle patch was discovered and removed. The
  contaminated earlier WDT result should be ignored; the clean EN=3 result is
  the valid one.

Interpretation update: the simple explanations are now weaker:

1. `SEC_WDOG_DIS` is not obviously a supported runtime path even downstream.
2. Direct APSS WDT pets/programming from early mainline do not keep the device
   alive, even when matching downstream's bark/bite/enable values more closely.
3. The reset source still looks like secure/boot-chain state that downstream
   clears or services through some other early path, not the generic APSS WDT
   register sequence alone.

Suggested next investigation before more boots:

- Compare the very early downstream boot sequence before/around
  `msm_watchdog` init for other SCM/boot-service calls that mainline lacks,
  especially CPU/Kryo errata, LGE panic/restart-reason init, IMEM/SMEM boot
  cookies, and any TZ/app/secure monitor setup that happens before 0.4s in
  the downstream dmesg.
- Treat `SEC_WDOG_DIS` as an attempted-but-invalid lead unless a boot-mode
  difference proves it works only under `fastboot boot`.
- If another timing test is needed, make it a single clean oracle with the
  kernel tree first reset to `git status` clean and `qcom_scm.o` explicitly
  rebuilt, to avoid mixed-object false signals.

Artifacts saved under `lg-v30-port/out/`:

- `aurel-qcom-scm-oracle-leftover-2026-07-06.patch`
- `aurel-downstream-style-wdt-clean-test-2026-07-06.patch`
- `aurel-wdt-en3-test-2026-07-06.patch`

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## Aurel follow-up — latest upstream branch test (2026-07-06)

Aurel refreshed the active tethered-test kernel branch without losing tracked
work:

- fetched upstream Linux `origin/master` to `8cdeaa50e` (`Linux 7.2-rc2`);
- preserved the old debug tip with backup refs, including
  `backup/joan-bringup-debug-before-latest-20260706-052942`;
- saved a dirty detached SCM-oracle worktree patch to
  `lg-v30-port/out/aurel-test-worktree-scm-oracle-dirty-20260706-052942.patch`
  and reset that worktree clean to avoid stale-object contamination;
- created/refreshed branch `joan/latest-kernel` by replaying the five joan/debug
  commits onto `v7.2-rc2`, producing new head `88bf16047`.

Build/test evidence:

| Item | Result |
|---|---|
| Build | `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j6 Image.gz dtbs` succeeded. |
| RAM-only image | `out/boot-joan-latest-kernel.img` |
| Image sha256 | `2c8af0cc49b05ccd5d0c5452b5bd8f607aadbe89675fdcc6f7b92f023f32c325` |
| Fastboot command | one client only: `sudo -n fastboot boot out/boot-joan-latest-kernel.img` |
| Fastboot protocol result | `Sending 'boot.img' ... OKAY`; `Booting ... OKAY`; total time `5.525s` |
| Host classifier result | no mass-storage/debug channel; LineageOS adb returned at `t+29.7s` after boot handoff. |

Interpretation: current upstream `v7.2-rc2` alone does not fix the reset. The
active branch for further tethered tests is now `joan/latest-kernel`, but it still
contains debug-only breadcrumb instrumentation and is not publishable as-is.

Suggested next work: continue root-cause comparison of very early downstream boot
setup versus mainline, especially early SCM/boot-service, restart/IMEM/SMEM, CPU
errata, and firmware-state paths. Avoid another blind boot until a single
hypothesis produces a testable timing oracle or a clean upstream-candidate patch.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## Aurel follow-up — latest clean branch test (2026-07-06)

Aurel then created a cleaner latest-kernel tethered-test branch without the
known debug-only ramoops breadcrumb commit:

- base: fetched upstream `origin/master` `8cdeaa50e` (`Linux 7.2-rc2`);
- branch: `joan/latest-clean-test`, four DTS-only commits ahead of upstream;
- head: `0d7df4134` — `arm64: dts: qcom: msm8998-lge-joan: add APSS watchdog node`;
- carried commits: initial joan DTS, downstream-compatible ramoops layout,
  LG firmware-owned reserved memory, and APSS watchdog node;
- excluded: `JOAN DEBUG: ramoops breadcrumbs in head.S and setup_arch`.

Build/test evidence:

| Item | Result |
|---|---|
| Build | `git diff --check` and `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j6 Image.gz dtbs` succeeded. |
| RAM-only image | `out/boot-joan-latest-clean.img` |
| Image sha256 | `47418aebd86c929b59cd09d243d93abe7ab03d85310d11015dfcd530474d47c1` |
| Fastboot command | one client only: `sudo -n fastboot boot out/boot-joan-latest-clean.img` |
| Fastboot protocol result | `Sending 'boot.img' ... OKAY`; `Booting ... OKAY`; total time `5.525s` |
| Host classifier result | no mass-storage/debug channel; LineageOS adb returned at `t+46.7s` after boot handoff. |

Interpretation: the clean DTS-only latest branch is the better baseline for
future public/PR-shaped testing, but it still reboots before mainline can expose
USB diagnostics. The earlier `joan/latest-kernel` debug-branch result returned at
`t+29.7s`; because that branch includes dead ramoops breadcrumb instrumentation,
prefer `joan/latest-clean-test` for baseline work and keep breadcrumb code out of
public candidates.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## Aurel follow-up — latest clean CPU/idle/high-memory discriminators (2026-07-06)

Aurel kept the public-shaped branch as `joan/latest-clean-test` and tested three
new hypotheses from the earlier handoff notes. All tests were RAM-only
`fastboot boot`; no flashing, no phone-storage writes, and no package installs.
The phone returned safely to LineageOS after each failed boot.

Hypotheses tested:

1. **Secondary CPU / Kryo errata discriminator.** Downstream enables the ARM64
   845719 workaround for Kryo2xx Silver during early boot. Mainline has
   `CONFIG_ARM64_ERRATUM_845719=y`, but Aurel tested whether avoiding secondary
   CPU bringup changes the reset by using `maxcpus=1`.
2. **CPU idle / PSCI idle discriminator.** Downstream passes
   `lpm_levels.sleep_disabled=1` and uses Qualcomm idle plumbing. Aurel tested
   whether disabling generic mainline CPU idle changes the reset with
   `cpuidle.off=1 nohlt`.
3. **High-memory firmware/XPU discriminator.** Downstream allocates high
   `qseecom`, `secure_region`, `sp_region`, `adsp_region`, and default CMA pools
   during early reserved-memory setup. Aurel tested a debug-only DTS patch that
   reserves the observed downstream physical ranges as `no-map` to see whether
   mainline was tripping a secure/XPU reset by allocating memory firmware expects
   to own.

| Test | Artifact | Result |
|---|---|---|
| `maxcpus=1` latest clean image | `out/boot-joan-latest-maxcpus1.img`, sha256 `5bd01b0a987563027abbb968810b1b796201cbffb32e99effa4fc95d672c93e8` | Fastboot protocol OKAY (`5.522s`); no mainline USB/diag; LineageOS adb returned at `t+29.5s`. |
| `cpuidle.off=1 nohlt` latest clean image | `out/boot-joan-latest-cpuidleoff.img`, sha256 `3f4b26656dc1af381128aa211787297ce85808e638287a1c21f7c550b5f9955d` | Fastboot protocol OKAY (`5.520s`); no mainline USB/diag; LineageOS adb returned at `t+45.8s`. |
| downstream high-memory reservation debug patch | saved patch `out/aurel-latest-highmem-reserve-test-2026-07-06.patch`; image `out/boot-joan-latest-highmem-reserve.img`, sha256 `c9f4545b790084dd82b139109dc29dffa516f1c3a17620a003db3b6241a886a6` | Build OK; fastboot protocol OKAY (`5.516s`); no mainline USB/diag; LineageOS adb returned at `t+29.4s`. |

Interpretation:

- Single-core boot did not survive, so the reset is not simply caused by
  secondary CPU bringup or a missing secondary-CPU erratum step.
- Disabling mainline CPU idle did not shift the clean baseline window, so idle
  entry/PSCI cpuidle is unlikely to be the primary trigger.
- Reserving the downstream high-memory secure/shared pools as `no-map` did not
  help, so the reset is unlikely to be caused only by mainline allocating those
  high physical ranges before the diag gadget appears.
- The faster `~29s` host-side returns for `maxcpus=1` and high-memory reserve are
  evidence that these debug variants perturb timing/boot flow; do not publish
  them as fixes. The kernel tree was restored to clean `joan/latest-clean-test`
  and rebuilt after saving the high-memory patch.

Next likely path: inspect downstream early IMEM/restart/memory-dump setup,
including `memory_dump_v2.c` (`MSM Memory Dump base table set up` at downstream
`0.115s`) and LGE panic/restart-reason code, but test it as a single explicit
oracle rather than bundling it with watchdog or CPU-idle changes.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06


## Aurel follow-up — secure-liveness DLOAD-off SCM argument oracle (2026-07-06)

Focus from the PS_HOLD handoff: diff downstream first-second secure-liveness
setup against mainline. The first concrete delta tested here was download-mode
setup in the secure monitor path.

Downstream evidence:

- `drivers/power/reset/msm-poweroff.c` uses `pure_initcall(msm_restart_init)`.
- On LGE builds (`CONFIG_LGE_HANDLE_PANIC`), `download_mode` defaults to `0`.
- Probe still calls `set_dload_mode(download_mode)`, so early boot sends an
  explicit DLOAD-off request.
- Downstream's ARMv8 path calls `SCM_DLOAD_CMD` (`SCM_SVC_BOOT`, command `0x10`)
  with args `(0, 0)` for that off request.
- Mainline `drivers/firmware/qcom/qcom_scm.c` also uses command `0x10`, but its
  off request encoded args as `(QCOM_SCM_BOOT_SET_DLOAD_MODE, 0)`, i.e.
  `(0x10, 0)`.

Oracle tested:

- Saved patch:
  `out/aurel-latest-dload-off-argshape-test-2026-07-06.patch`
- Touched file:
  `drivers/firmware/qcom/qcom_scm.c`
- Change:
  make `__qcom_scm_set_dload_mode(enable=false)` send downstream's `(0, 0)`
  shape while leaving the rest of `qcom_scm_probe()` unchanged.
- Image:
  `out/boot-joan-latest-dload-off-argshape.img`
- Image sha256:
  `423d0c7f306a0d1617ade6577c8cb012df71cda6d6f8a08ab731dc4e79a26457`
- Patch sha256:
  `eb285f2d73b2711fa505c0938183954b18ebb125735ae69176e7311fc8f1a5a0`
- Size:
  `15736832` bytes

Verification:

- `git diff --check` passed.
- Kernel rebuilt with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j6
  Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.516s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+44.3s` after boot handoff.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- The downstream-vs-mainline DLOAD-off argument-shape difference is not enough to
  satisfy the secure-side liveness/reset policy.
- This weakens `qcom,scm` `SET_DLOAD_MODE` as the missing first-second handshake.
- The reset remains a controlled PS_HOLD path, not a PMIC fault.
- The next secure-liveness delta to test should be a QSEE/QSEEOS-side early ping,
  especially downstream `drivers/firmware/qcom/tz_log.c` registering the QSEE log
  buffer (`SCM_QSEEOS_FNID(1, 6)`) and/or querying TZ feature/version. Test as a
  single explicit oracle; do not bundle with watchdog, CPU-idle, or DLOAD changes.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-dload-oracle.img`, sha256
  `ee952809d17b791094717eec4585ce83d14d5b1ef0e7e1a53def3a55ab4e19a3`.
- Phone parked back in LineageOS; no fastboot client left running.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## Aurel follow-up — QSEE/QSEEOS log-buffer oracle (2026-07-06)

Focus from the PS_HOLD handoff after the DLOAD-off rejection: test one concrete
QSEE/QSEEOS-side early ping from downstream `tz_log.c`, without bundling any
watchdog, CPU-idle, DLOAD, or memory-reservation changes.

Downstream evidence:

- `drivers/firmware/qcom/tz_log.c` calls `tzdbg_register_qsee_log_buf()` from
  `tz_log_probe()`.
- The ARMv8 path allocates a 32 KiB QSEE log buffer and calls
  `SCM_QSEEOS_FNID(1, 6)` with args `(pa, len)` and arginfo `0x22`.
- Downstream then calls `tzdbg_get_tz_version()`; mainline already performs the
  matching TZ feature/version query inside `qcom_scm_qseecom_init()`, so this
  oracle intentionally tested only the missing log-buffer registration ping.

Oracle tested:

- Saved patch:
  `out/aurel-latest-qsee-logbuf-oracle-2026-07-06.patch`
- Touched file:
  `drivers/firmware/qcom/qcom_scm.c`
- Change:
  add a debug-only `qcom_scm_probe()`/QSEECOM-init call that allocates a 32 KiB
  `qcom_tzmem` buffer, sends owner `QSEE_OS` (`50`), service `1`, command `6`,
  arginfo `QCOM_SCM_ARGS(2, QCOM_SCM_RW, QCOM_SCM_VAL)`, args `(phys, 0x8000)`,
  then logs the QSEE response.
- Image:
  `out/boot-joan-latest-qsee-logbuf.img`
- Image sha256:
  `6a99c6f2c653e21d2cbba2df7ad2d392dbbcc40f0db7fef63efd599d57b7eb93`
- Patch sha256:
  `68b0883cae085712a446475c5ae3bd723defb056ddd28e6babfe18521ce797d3`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-qsee-logbuf-fastboot-2026-07-06.txt`
- PON evidence:
  `out/aurel-qsee-logbuf-pon-2026-07-06.txt`

Verification:

- `git diff --check` passed.
- Kernel rebuilt with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j6
  Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.513s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+52.2s` after boot handoff.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- A standalone downstream-style QSEE log-buffer registration ping is not enough
  to satisfy the secure-side liveness/reset policy.
- The `t+52.2s` host return is later than the latest clean baseline, so the
  oracle may perturb timing, but it still did not expose mainline USB/diag and
  still ended in controlled SID0 `PS_HOLD`.
- Mainline already performs the downstream TZ feature/version query, so repeating
  that query is not a useful next standalone oracle.
- The next secure-liveness comparison should move away from DLOAD and QSEE-log
  setup toward another first-second downstream delta, especially RPM/SMD/SMEM
  handshake or LGE/Qualcomm boot-state cookies, again as one oracle at a time.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-qsee-oracle.img`, sha256
  `45015e1880a65e7019abfd15de656af8253378323493a41d5563da9637e84320`.
- Phone parked back in LineageOS; `adb root` was used only for the PON readback
  and then `adb unroot` returned adbd to normal mode.
- No fastboot client left running.


## Aurel follow-up — RPM `rpm_requests` reachability oracle (2026-07-06)

Focus after DLOAD and QSEE-log rejection: check whether mainline ever reaches the
same early APSS-RPM `rpm_requests` path that downstream brings up around 0.3s,
without adding any RPM votes, watchdog changes, or boot-cookie writes.

Downstream/mainline comparison:

- Downstream `drivers/soc/qcom/rpm-smd.c` probes `qcom,rpm-glink`, opens GLINK
  edge `rpm`, channel `rpm_requests`, then logs `APSS-RPM communication over
  GLINK` and later `glink config params: transport=(null), edge=rpm,
  name=rpm_requests`.
- Downstream dmesg has those messages at roughly `0.317s` / `0.332s`.
- Mainline `msm8998.dtsi` already describes `qcom,glink-rpm` with child
  `rpm_requests` compatible `qcom,rpm-msm8998`, `qcom,glink-smd-rpm`.
- Mainline config has `CONFIG_RPMSG_QCOM_GLINK_RPM=y`,
  `CONFIG_QCOM_SMD_RPM=y`, `CONFIG_QCOM_SMEM=y`, and `CONFIG_QCOM_SMP2P=y`.

Oracle tested:

- Saved patch:
  `out/aurel-latest-rpm-rpmsg-reachability-oracle-2026-07-06.patch`
- Touched file:
  `drivers/soc/qcom/smd-rpm.c`
- Change:
  add a debug-only `lge,joan` timing oracle in `qcom_smd_rpm_probe()`: if the
  `rpm_requests` rpmsg driver probes, log a marker, wait 4 seconds, then call
  PSCI `SYSTEM_RESET` (`0x84000009`).
- Image:
  `out/boot-joan-latest-rpm-rpmsg-oracle.img`
- Image sha256:
  `d7b039b381ad83c61a4e7bfdf3005fa143a8fc5701c90dbf9faf06edfe1bed6b`
- Patch sha256:
  `a92efaa88f7717d5762fa71bd2d22c84510bf13c4b43a3e22f893bd25bc895f1`
- Size:
  `15740928` bytes
- Fastboot transcript:
  `out/aurel-rpm-rpmsg-fastboot-2026-07-06.txt`, sha256
  `3261e8f38e5a3aa1128fbbd4c4a721e181c5ef435ee54cf6d65ea54540e71d79`
- PON evidence:
  `out/aurel-rpm-rpmsg-pon-2026-07-06.txt`, sha256
  `8f01740521da6b31f997ddea02e5352bedb9f3429e88bbe09d8117b04ed139e1`

Verification:

- `git diff --check` passed.
- Kernel rebuilt with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
  Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.518s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+58.3s` after `adb reboot bootloader`.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- The oracle did not produce survival or a mainline diagnostic channel.
- The later `t+58.3s` host return is consistent with the RPM `rpm_requests` rpmsg
  probe being reached and then deliberately reset after the 4s delay, although
  no on-target logs are available before the reset.
- This weakens “mainline never reaches RPM rpmsg setup” as the blocker, but does
  not rule out missing/late downstream RPM resource votes or SMEM/boot-state
  cookies.
- Next test should avoid reachability-only pings and instead compare a concrete
  downstream RPM vote, SMEM boot-state write, or boot/restart cookie that differs
  from mainline and happens before the reset window.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-rpm-oracle.img`, sha256
  `c3db2b91473773af0546579e846dc41f85074d750e7407f95917e1d5a7ccb5b3`.
- Phone parked back in LineageOS; `adb root` was used only for the PON readback.
- No fastboot client left running.


## Aurel follow-up — RPM BOB-mode state-changing oracle (2026-07-06)

Focus after RPM reachability rejection: test one concrete downstream RPM default
vote rather than another ping. Downstream joan enables the PMI8998/PM8998 BOB
regulator path and sets `qcom,init-bob-mode = <2>` (`AUTO`) for the BOB resource;
mainline joan has the RPM channel, but no `rpm-pmi8998-regulators` / BOB child
nodes, so it never sends that default through the regulator framework.

Downstream/mainline comparison:

- Downstream `msm8998-regulator.dtsi` defines `rpm-regulator-bobb` with resource
  `bobb`, id `1`, and `qcom,init-bob-mode = <2>`.
- Downstream joan PM overlay keeps `pmi8998_bob` and the BOB pin-control children
  enabled with the same init BOB mode.
- Mainline `qcom_smd-regulator.c` supports `qcom,rpm-pmi8998-regulators` and BOB
  resource `QCOM_SMD_RPM_BOBB`, but `msm8998-lge-joan.dts` currently has no BOB
  RPM regulator children.

Oracle tested:

- Saved patch:
  `out/aurel-latest-rpm-bob-mode-oracle-2026-07-06.patch`
- Touched file:
  `drivers/soc/qcom/smd-rpm.c`
- Change:
  after `qcom_smd_rpm_probe()` binds on `lge,joan`, send KVP `bobm=2` to RPM
  resource `BOBB:1` in both active and sleep sets, then continue normal child
  population.
- Image:
  `out/boot-joan-latest-rpm-bob-mode.img`
- Image sha256:
  `e7ccb54378f39b84a3497590844d26d504e5cc770040190bab86e5e845f7c1c9`
- Patch sha256:
  `eca4d41b1532903e541118e951f9dda4e366fed3b89a2feedd08915386cbd7df`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-rpm-bob-mode-fastboot-2026-07-06.txt`, sha256
  `0f77a5769d905b209821f73f48d4c06926ece06b430003e6dbaede6100d1ff96`
- PON evidence:
  `out/aurel-rpm-bob-mode-pon-2026-07-06.txt`, sha256
  `8b06e8d271ce730f845a07ef79e2f3d6bf0148edd9363f1746c8d91f58cc3779`

Verification:

- `git diff --check` passed.
- Initial accidental `LLVM=1` build attempt failed because `clang` is not
  installed; no packages were installed. Rebuilt with the documented toolchain:
  `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.515s`.
- No mainline USB/mass-storage/diag channel appeared.
- Host monitor timed out at `t+108.4s` with no adb and no mainline channel; a
  follow-up host check then found LineageOS adb visible.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- The oracle did not produce survival or a mainline diagnostic channel.
- It delayed failure far beyond prior ordinary returns, so actual RPM regulator
  defaults remain interesting, but a single BOB `bobm=2` active/sleep vote is not
  sufficient.
- Next test should either add a minimal DT-backed RPM regulator/default-vote
  parity set from an existing MSM8998 mainline device plus downstream joan BOB
  overrides, or pick another concrete early state write with downstream evidence.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-bob-oracle.img`, sha256
  `9f659917f5b7bfc687a8aef56a64e391ceb2b9958b043490edce298d7af657ab`.
- Phone parked back in LineageOS; `adb root` was used only for the PON readback.
- No fastboot client left running.


## Aurel follow-up — DT-backed RPM L19 default-vote oracle (2026-07-06)

Focus after the BOB-mode timing result: test one concrete downstream joan PM
override through mainline's own RPM regulator framework rather than another raw
`qcom_smd_rpm` debug write.

Downstream/mainline comparison:

- Downstream `msm8998-joan-common-sound.dtsi` forces `pm8998_l19` to 3.3 V with
  `qcom,init-voltage = <3300000>`,
  `qcom,vdd-voltage-level = <3300000 3300000>`, and `regulator-always-on`.
- Mainline joan currently inherits the generic MSM8998 MTP-style `l19` default
  in `msm8998-lge-joan.dts`: `3008000`/`3008000` uV with no
  `regulator-boot-on` or `regulator-always-on`.
- Mainline `qcom_smd-regulator.c` already supports `qcom,rpm-pm8998-regulators`,
  and regulator core applies fixed min/max constraints plus boot/always-on
  enable during regulator registration. This makes L19 a good minimal DT-backed
  oracle for “does one missing downstream RPM default vote matter?”.

Oracle tested:

- Saved patch:
  `out/aurel-latest-rpm-l19-always-on-oracle-2026-07-06.patch`
- Touched file:
  `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Change:
  update `vreg_l19a_3p0: l19` from `3008000` uV to `3300000` uV and mark it
  `regulator-boot-on` plus `regulator-always-on` so mainline emits the default
  through the existing RPM regulator framework during boot.
- Image:
  `out/boot-joan-latest-rpm-l19-always-on.img`
- Image sha256:
  `84134c0d71c7f7eafae9e6a268c50302238a002b6c11c229baa6b52a6ee96e04`
- Patch sha256:
  `41bb06f48df489e454c4d44aab7284e6990ac97367b8b8925e68cc642c95df45`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-rpm-l19-always-on-fastboot-2026-07-06.txt`, sha256
  `7f5de9a5c9f90f8e1603de7a832ebb7bc0c9b3a6e6bcfb961e421015f408f52a`
- PON evidence:
  `out/aurel-rpm-l19-always-on-pon-2026-07-06.txt`, sha256
  `325bc47d2dd040f34be1795d29ba642e6e5bcb21618d768f5404e54389e43dac`

Verification:

- `git diff --check` passed.
- Kernel rebuilt with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
  Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.517s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+57.8s`.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- This minimal DT-backed default vote did not produce survival or a mainline
  diagnostic channel.
- Because it used the existing mainline RPM regulator framework instead of a raw
  debug write, it strengthens the conclusion that one missing L19 default alone
  is not the sole reset gate.
- Broader downstream PM/RPM regulator parity still looks worthwhile, but do not
  repeat single-L19-only testing as if it were a likely standalone fix.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-l19-oracle.img`, sha256
  `69c820614b2e06cdc089717a7971779e35089791f1e058757c9d81cdb65221b3`.
- Phone parked back in LineageOS; `adb root` was used only for the PON readback.
- No fastboot client left running.

## Aurel follow-up — DT-backed PM/RPM overlay parity oracle (2026-07-06)

Focus after single-L19 failure: test one broader downstream joan PM/RPM overlay
bundle through mainline's existing RPM regulator framework, without adding new
regulator driver code or repeating the raw BOB-mode write.

Downstream/mainline comparison:

- Downstream common PM overlay sets `pm8998_l18` to 2.704 V via
  `qcom,init-voltage` / `qcom,vdd-voltage-level` and keeps it enabled for the
  RPM resource definition.
- Downstream common sound overlay sets `pm8998_l19` to 3.3 V and marks it
  `regulator-always-on`.
- Downstream common PM overlay sets the PMI8998 BOB path to `qcom,init-bob-mode =
  <2>` plus pin-control children. Mainline does not support the downstream BOB
  mode/pin-control KVPs in DT, but it can send a standard BOB enable/voltage vote.
- Mainline joan had L18 at the same fixed 2.704 V but no boot vote, L19 at 3.008
  V with no boot/always-on flags, and BOB at 3.312-3.6 V with no forced enable.

Oracle tested:

- Saved patch:
  `out/aurel-latest-rpm-pm-overlay-oracle-2026-07-06.patch`
- Touched file:
  `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Change:
  add a DEBUG-ONLY PM overlay bundle: `l18` fixed 2.704 V + `regulator-boot-on`,
  `l19` fixed 3.3 V + `regulator-boot-on`/`regulator-always-on`, and BOB fixed
  3.312 V + `regulator-boot-on`/`regulator-always-on`.
- Image:
  `out/boot-joan-latest-rpm-pm-overlay.img`
- Image sha256:
  `de729e6eff09e997de15bdfb0fcf29890e86765228d691f5bb1ca1e185806365`
- Patch sha256:
  `8b6d4480fe54b7ae7300ecb80b8b4091b542adadb57d1dc986851ec72dfb3c3f`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-rpm-pm-overlay-fastboot-2026-07-06.txt`, sha256
  `ba6cefd54ace1274932cbd5a02defa52e298bc5ed0003be20afb2ec0f6f72c37`
- PON evidence:
  `out/aurel-rpm-pm-overlay-pon-2026-07-06.txt`, sha256
  `15054fdb0af310176c769e71dc31d939d7523a64b936d18e9ecf16fcc4072bdb`

Verification:

- `git diff --check` passed.
- Kernel rebuilt with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
  Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.518s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+30.6s` after fastboot completion.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- This broader DT-backed PM/RPM default-vote bundle did not produce survival or a
  mainline diagnostic channel.
- It also did not preserve the much longer timing from the raw BOB-mode oracle;
  host return was back near the early failure class.
- Simple PM8998/PMI8998 regulator default-vote parity is now weaker as the sole
  reset gate. If continuing RPM work, compare unsupported downstream-specific KVP
  semantics or real consumers, not another standard DT voltage/enable bundle.
  Otherwise pivot to SMEM/restart/boot-state cookies or PMIC/PON setup.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-pm-overlay-oracle.img`, sha256
  `eaddd46a1716f36a31fccfe5d9d94ba3c375b53c0ab70df28ac2fac7dca07554`.
- Phone parked back in LineageOS; `adb root` was used only for the PON readback.
- No fastboot client left running.

## Aurel follow-up — TCSR DLOAD/restart-cookie oracle (2026-07-06)

Focus after rejecting standard PM/RPM voltage/enable parity: compare downstream
restart/boot-state cookie setup against current mainline MSM8998, then test one
state-changing cookie delta.

Downstream/mainline comparison:

- Downstream MSM8998 defines `qcom,msm-imem@146bf000` with `restart_reason@65c`,
  `boot_stats@6b0`, `diag_dload@c8`, and `dload_type@1c` children.
- Downstream `qcom,pshold` also carries a `tcsr-boot-misc-detect` resource at
  physical `0x1fd3000`, which is `tcsr_regs_2 + 0x13000`.
- Mainline MSM8998 had SMEM and RPM/SMP2P nodes but no IMEM/restart-reason node,
  no `qcom,pshold` node, and no SCM `qcom,dload-mode` phandle for the TCSR
  DLOAD cookie path.
- Mainline SCM therefore fell back to the secure `SET_DLOAD_MODE` call, whose
  argument-shape variants were already rejected. This oracle tested only the
  missing TCSR boot-misc DLOAD-cookie route.

Oracle tested:

- Saved patch:
  `out/aurel-latest-tcsr-dload-cookie-oracle-2026-07-06.patch`
- Touched file:
  `arch/arm64/boot/dts/qcom/msm8998.dtsi`
- Change:
  add DEBUG-ONLY `qcom,dload-mode = <&tcsr_regs_2 0x13000>` to the MSM8998 SCM
  node so `qcom_scm_set_download_mode(0)` clears the downstream-observed TCSR
  DLOAD bits at `0x1fd3000` instead of using the secure-call fallback.
- Image:
  `out/boot-joan-latest-tcsr-dload-cookie.img`
- Image sha256:
  `0ba46735f6f6fac182f3de3f67fe46f5c60c26948be7b1193f7c7147b48645dd`
- Patch sha256:
  `bd4c3fc21b3d10260fe2b7c2ee96291966fdd9b7f43424c97288e876d1e86b97`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-tcsr-dload-cookie-fastboot-2026-07-06.txt`, sha256
  `f09b9ded76e826a195d2dc23e356f17953191b2b12b10b5b4f091e66a4d6cdff`
- PON evidence:
  `out/aurel-tcsr-dload-cookie-pon-2026-07-06.txt`, sha256
  `279334aa223eb6ad8d1620544830bee37d535f3be07d376cb0a2620e4abfcbe2`

Verification:

- `git diff --check` passed.
- Kernel rebuilt with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
  Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.513s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+55.5s` from test start.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- The downstream-observed TCSR DLOAD/restart-cookie path is not sufficient as a
  standalone survival/liveness fix.
- Because the outcome remained a controlled SID0 `PS_HOLD` reset with no mainline
  diagnostics, do not repeat this TCSR `qcom,dload-mode` phandle as another
  standalone boot test.
- The remaining restart-cookie area should be the fuller IMEM/reboot-mode/normal
  restart-reason model only if tested as a clearly separate oracle; otherwise
  pivot toward PMIC/PON setup or another first-second downstream state transition.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-tcsr-dload-cookie-oracle.img`, sha256
  `38351422d5862f87a42edd51765117fc1b6b60892f6e980c58cda6f725d283f8`.
- Phone parked back in LineageOS; `adb root` was used only for the PON readback.
- No fastboot client left running.


## Aurel follow-up — PM8998 PON S3 source/debounce oracle (2026-07-06)

Focus after rejecting the TCSR DLOAD/restart-cookie phandle: compare downstream
joan PMIC/PON setup against current mainline and test one concrete unsupported
PON delta.

Downstream/mainline comparison:

- Downstream joan sets PM8998 PON root properties `qcom,s3-debounce = <32>` and
  `qcom,s3-src = "kpdpwr-and-resin"`.
- Downstream also configures `pon_1`/`pon_2` support-reset `0` and `pon_3`
  support-reset `1` with `s1-timer = <6720>`, `s2-timer = <2000>`, and
  `s2-type = <PON_POWER_OFF_DVDD_HARD_RESET>`.
- Mainline `qcom-pon` for PM8998 only handles reboot-mode spare bits and child
  population; the upstream binding does not model those downstream PON S3/reset
  properties.
- Therefore a pure DTS oracle would not exercise the downstream S3 delta. The
  minimal test needed a DEBUG-ONLY driver extension plus a joan DT override.

Oracle tested:

- Saved patch:
  `out/aurel-latest-pon-s3-oracle-2026-07-06.patch`
- Touched files:
  `drivers/power/reset/qcom-pon.c` and
  `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Change:
  add property-driven S3 source/debounce programming to `qcom-pon` at probe and
  add joan `&pm8998_pon` values matching downstream (`32`, `kpdpwr-and-resin`).
- Config artifact:
  `out/aurel-latest-pon-s3-oracle-config-2026-07-06.txt`, sha256 `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`
- Required config verified:
  `CONFIG_POWER_RESET_QCOM_PON=y`
- Image:
  `out/boot-joan-latest-pon-s3-oracle.img`
- Image sha256:
  `2c83d4782aa60564c840efe5122ebfeb9aa30f8e0aea8bab10fc7d70f6fb2c31`
- Patch sha256:
  `e8dfba3949f4ace1d678ed94ce7e254287197ba4c6ee0d6368d4efa642dc051d`
- Size:
  `15740928` bytes
- Fastboot transcript:
  `out/aurel-pon-s3-fastboot-2026-07-06.txt`, sha256 `c8222c05a1ee402d091d708bc14b31c64b7d0b1da0b3aedd99f499a34c0a5f62`
- PON evidence:
  `out/aurel-pon-s3-pon-2026-07-06.txt`, sha256 `c5acb2a3c56a0a1f1e0c42d5b85c04ea95033f3690cee79251ede518ef048c4d`

Verification:

- `git diff --check` passed.
- The active kernel `.config` was restored from `.config.old` and refreshed with
  `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig` because the
  live config had drifted enough that `CONFIG_POWER_RESET_QCOM_PON` did not stay
  enabled. Verified `CONFIG_ARM64=y`, `CONFIG_MFD_SPMI_PMIC=y`, and
  `CONFIG_POWER_RESET_QCOM_PON=y` before building the oracle.
- Kernel rebuilt with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
  Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.510s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+30.5s` after the fastboot boot monitor began.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- The downstream PM8998 PON S3 source/debounce setup is not sufficient as a
  standalone survival/liveness fix.
- Do not repeat the exact `qcom,s3-debounce`/`qcom,s3-src` PON S3 oracle as
  another standalone test.
- Remaining PMIC/PON work, if any, must target a different unsupported state
  change, such as the fuller downstream PON reset-sequence/S1/S2 setup, or pivot
  away from PMIC/PON toward another first-second downstream state transition.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-pon-s3-oracle.img`, sha256
  `7d87765d96df926cac538563dcbe1989f8990d9b784b1c0163926f5cb5f0b0ef`.
- Phone parked back in LineageOS; `adb root` was used only for the PON readback
  and `adb unroot` returned adbd to ordinary shell mode.
- No fastboot client left running.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06


## Aurel follow-up — PM8998 PON reset-sequence/S1/S2 oracle rejected

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Hypothesis:

- The prior PON S3-only oracle matched only `qcom,s3-debounce` and `qcom,s3-src`.
  Downstream joan also configures a fuller PM8998 PON reset sequence: disable S2
  reset for `pon_1`/`pon_2`, and enable `pon_3` (`KPDPWR_N AND RESIN_N`) with
  S1 timer `6720`, S2 timer `2000`, and S2 reset type `0x08`
  (`PON_POWER_OFF_DVDD_HARD_RESET`).

Oracle:

- Saved patch:
  `out/aurel-latest-pon-reset-seq-oracle-2026-07-06.patch`
- Touched files:
  `drivers/power/reset/qcom-pon.c` and
  `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
- Change:
  add DEBUG-ONLY property-driven PON S3 plus reset-sequence/S1/S2 programming to
  upstream `qcom-pon`, and add joan `&pm8998_pon` child nodes matching downstream
  `qcom,pon_1`, `qcom,pon_2`, and `qcom,pon_3` values.
- Config artifact:
  `out/aurel-latest-pon-reset-seq-oracle-config-2026-07-06.txt`, sha256 `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`
- Required config verified:
  `CONFIG_POWER_RESET_QCOM_PON=y`
- Image:
  `out/boot-joan-latest-pon-reset-seq-oracle.img`
- Image sha256:
  `a0c0e2b6448981798d5cc5b03a4804504caaedff7705a896a42883d86786ee12`
- Patch sha256:
  `588264cfb140c0c307a57b8898f5c1c77bf8fa623da32e68ffaa7ce66f9f552c`
- Size:
  `15740928` bytes
- Fastboot transcript:
  `out/aurel-pon-reset-seq-fastboot-2026-07-06.txt`, sha256 `71f352f65822e597d37a769d374408bb06864c6e2739a839a4cda5132b3b7fd1`
- PON evidence:
  `out/aurel-pon-reset-seq-pon-2026-07-06.txt`, sha256 `c643c1db1c555052bdb1da483062e86d5b5b691d16d3df8a70e7c928e83d005d`

Verification:

- `git diff --check` passed.
- Targeted `drivers/power/reset/qcom-pon.o` compiled successfully.
- Joan DTB rebuilt successfully.
- Full kernel rebuild completed with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image.gz dtbs`.
- Boot image packaged with `make-testimage.sh`.
- One-client RAM-only `fastboot boot` was used; no flashing, no phone-storage
  writes, no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.522s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+57.6s` host-script time, about `46.3s` after the
  fastboot boot command returned.
- Post-reset LineageOS dmesg again showed:
  `PMIC@SID0: Power-off reason: Triggered from PS_HOLD` and
  `PON=0x21 ... POFF=0x2:PS_HOLD`.

Interpretation:

- The fuller downstream PM8998 PON reset-sequence/S1/S2 setup is not sufficient
  as a standalone survival/liveness fix.
- Do not repeat the exact PM8998 PON reset-sequence oracle as another standalone
  test.
- The longer host return time may be noted as a timing perturbation, but it did
  not expose diagnostics or change the reset cause.

Cleanup:

- The debug patch was saved under `out/` and then reverted.
- Kernel branch `joan/latest-clean-test` was rebuilt clean after the revert.
- Clean post-oracle package:
  `out/boot-joan-latest-clean-post-pon-reset-seq-oracle.img`, sha256 `d543f234ab848f2de12191eca3cf2df2aa87b04711e4665564da93f5cf57f418`.
- Phone parked back in LineageOS; `adb root` was used only for the PON readback
  and `adb unroot` returned adbd to ordinary shell mode.
- No fastboot client left running.


Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06


## Aurel follow-up — Kryo SCM errata comparison cancelled before boot

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Aurel compared the suggested CPU/Kryo errata SCM path before building another
boot image.

Downstream source checked:

- `drivers/soc/qcom/scm-errata.c`
- `drivers/soc/qcom/Kconfig`
- `drivers/soc/qcom/Makefile`
- `arch/arm64/configs/joan*defconfig`

Finding:

- Downstream contains a `scm-errata.c` helper for SCM BOOT command `0x12`.
- Its default state would enable Kryo E74/E75 workaround (`arg 0x1`) and leave
  E76 disabled (`arg 0x100` if explicitly written).
- The helper is optional debugfs support: `CONFIG_QCOM_SCM_ERRATA` depends on
  `DEBUG_FS` and `QCOM_SCM` and has no default enable.
- The joan defconfigs checked enable `CONFIG_QCOM_SCM=y` but did not include
  `CONFIG_QCOM_SCM_ERRATA`.
- Its init path creates debugfs files and registers a `CPU_STARTING` notifier;
  it does not immediately apply the calls to already-online boot CPUs.

Decision:

- No CPU/Kryo SCM errata oracle was built or booted.
- This was rejected at comparison time because it is optional debug/runtime
  infrastructure, not active downstream joan boot-state parity.
- A forced command-`0x12` call in mainline would be speculative and less valuable
  than the previous downstream-parity oracles.

Artifact:

- `out/aurel-kryo-scm-comparison-2026-07-06.txt`

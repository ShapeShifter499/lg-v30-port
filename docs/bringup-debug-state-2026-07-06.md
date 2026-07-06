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

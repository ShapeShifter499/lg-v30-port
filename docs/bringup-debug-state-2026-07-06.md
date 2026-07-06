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

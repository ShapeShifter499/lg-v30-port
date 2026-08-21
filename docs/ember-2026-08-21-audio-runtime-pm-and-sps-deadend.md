# V30 audio — lead #1 (SPS/BAM) is a dead end; the runtime-PM suspend path is the live lead

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-21

Source-only analysis. No boots consumed. Trees read:
`android_kernel_lge_msm8998` (downstream) and
`linux-mainline-v30-usb-otg` @ `0d00bab2b`.

## 1. Lead #1 (port downstream's SPS/BAM pipe setup) — REJECTED, with proof

Aurel's handoff lists as the top lead: "downstream slim-msm.c
`msm_slim_connect_pipe_port()` configures the SPS/BAM pipes AND the PGD
ports when the stream's connects go out ... Mainline has the USR-connect
remap but no SPS/BAM setup."

That is true as a statement about the two source trees, but it does not
apply to our playback path. Downstream only runs that function for
connects addressed to the **apps' own PGD**:

`drivers/slimbus/slim-msm-ngd.c:655-661` (gate at :658)

```c
if (txn->mt == SLIM_MSG_MT_DEST_REFERRED_USER &&
    (txn->mc == SLIM_USR_MC_CONNECT_SRC ||
     txn->mc == SLIM_USR_MC_CONNECT_SINK ||
     txn->mc == SLIM_USR_MC_DISCONNECT_PORT) && txn->wbuf &&
    wbuf[0] == dev->pgdla) {                 /* <-- the gate */
        if (txn->mc != SLIM_USR_MC_DISCONNECT_PORT)
                dev->err = msm_slim_connect_pipe_port(dev, wbuf[1]);
```

and `wbuf[0]` is the connect's target logical address, set 81 lines
earlier at `slim-msm-ngd.c:577`:

```c
wbuf[i++] = txn->la;
la = SLIM_LA_MGR;
```

Our stream's connects target the **codec** (LA 0xcf / 0xce), not the apps
PGD (0xc4), because mainline `slim_stream_prepare()` addresses
`stream->slim->laddr`. So on the same hardware, running the vendor
driver, `msm_slim_connect_pipe_port()` **never runs for this path either**.
Downstream reaches it only when the apps processor is itself a SLIMbus
data endpoint (its own PGD ports) — which mainline's ADSP-hosted
playback never asks for.

Corollary: the apps' BAM data pipes are *not* "unconfigured while the
ADSP pulls data", because the ADSP never pulls data through them. The
audio data path is ADSP <-> codec; the apps NGD carries control messages
only.

Second corollary, for the same reason: `qcom_slim_ngd_joan_pipe_bringup()`
(the 12 USR connects to pgdla 0xc4 at bus re-activation) has no
downstream counterpart on this path. Boots 20e (zero connects) and 20h
(twelve clean connects) both died, which already said it is not the
missing piece; this says it is not a piece at all. Recommend gating it
off (`joan_pipes=0`) so it stops adding bus traffic inside the kill
window.

## 2. The autosuspend ruling-out is invalid

Aurel ruled autosuspend out on two grounds. Both fail.

**(a) "the sysfs `autosuspend_delay_ms` file errors EIO on this device
anyway".** The path read was
`/sys/devices/platform/soc@0/171c0000.slim-ngd/power/autosuspend_delay_ms`.
That is the **parent controller** device — the DT node is
`slim-ngd@171c0000` (msm8998.dtsi:3669), so the platform device is
`171c0000.slim-ngd`, bound by `qcom_slim_ngd_ctrl_probe()`, which never
calls `pm_runtime_use_autosuspend()`.

`autosuspend_delay_ms_show()` in `drivers/base/power/sysfs.c` returns
`-EIO` exactly when `!dev->power.use_autosuspend`. The EIO is the
expected answer for that node and says nothing about the NGD.

Autosuspend lives on the **child** platform device, allocated as
`QCOM_SLIM_NGD_DRV_NAME` = `"qcom,slim-ngd"` at
`qcom_slim_ngd_alloc_pdev()`, and set up in `qcom_slim_ngd_probe()`:

```c
pm_runtime_use_autosuspend(dev);
pm_runtime_set_autosuspend_delay(dev, 100);
```

Correct path to read/write: `.../171c0000.slim-ngd/qcom,slim-ngd.*/power/`.
The 100 ms timer was live in every boot.

**(b) "r4 did NOT [have a second power_up]".** Absence of a *wake* is not
absence of a *suspend*. The suspend is the half that does the damage;
a run that suspends and never wakes is precisely the fatal ordering,
not the control. No boot so far has instrumented `runtime_suspend`, so
whether it ran in r4 is simply unmeasured.

Reference for the general trap: `[[feedback-absence-is-not-zero]]`.

## 3. What mainline's runtime suspend actually does — three deltas from downstream

`qcom_slim_ngd_runtime_suspend()`:

```c
qcom_slim_ngd_exit_dma(ctrl);          /* unconditional, first thing */
if (!ctrl->qmi.handle) return 0;
ret = qcom_slim_qmi_power_request(ctrl, false);
```

`qcom_slim_ngd_exit_dma()` does `dmaengine_terminate_sync()` +
`dma_release_channel()` on the rx and tx msgq channels. In
`drivers/dma/qcom/bam_dma.c`, `dma_release_channel()` lands in
`bam_free_chan()`, which calls `bam_reset_channel()`:

```c
writel_relaxed(1, bam_addr(bdev, bchan->id, BAM_P_RST));
writel_relaxed(0, bam_addr(bdev, bchan->id, BAM_P_RST));
```

and then masks `BAM_IRQ_SRCS_MSK_EE` and writes `BAM_P_IRQ_EN = 0`.
There is no `controlled_remotely` guard on any of that. The target is
the slimbus BAM at 0x17184000, declared **`qcom,controlled-remotely`**
in msm8998.dtsi:3659 — i.e. the ADSP owns it.

So, 100 ms after the last apps-side control message, mainline resets BAM
pipes inside an ADSP-owned BAM and then tells the ADSP to drop the
SLIMbus power vote — while the ADSP is mid-stream-setup on that same
bus.

Downstream, at the same moment, does three things differently:

| | mainline | downstream |
|---|---|---|
| autosuspend delay | 100 ms (`qcom_slim_ngd_probe`) | 1000 ms (`MSM_SLIM_AUTOSUSPEND`, slim-msm.h:44) |
| pending-TID guard | none | `ngd_slim_power_down()` returns `-EBUSY` if any `ctrl->txnt[i]` is outstanding (slim-msm-ngd.c:1485-1502) |
| pipes on suspend | `exit_dma()` -> `BAM_P_RST` | untouched; `power_down()` only issues the QMI power request |

Three independent deltas, all inside the one window where the phone dies.

This also fits the evidence better than "the second power_up kills it":
- 20e r3 died right after a wake, 20e r4 died with no wake at all. A
  suspend happens in both; only r3 got far enough to wake.
- 20e (zero pipe connects) and 20h (twelve clean ones) both died, at the
  same point. Nothing in this mechanism involves the pipe connects.
- The signature — silent SoC reset, no panic, no RCU stall, no
  "crash detected in adsp" — is what a NoC/BAM wedge plus watchdog bite
  looks like. It is the same class as Boot X's finding that one MMIO read
  of an ADSP-owned register (0x171c0200) wedged the whole system.

Note: mainline already guards the NGD *interrupt* handler against the
suspended state (`qcom_slim_ngd_interrupt()` bails on
`pm_runtime_suspended()`), which is the same bug class caught upstream in
the IRQ path but not in the suspend path.

## 4. Experiment (build #38, image 21a)

One knob, one prediction, previous boots as control.

Kernel change (instrumentation only, no behavioural change at defaults):
- `slim_qcom_ngd_ctrl.autosuspend_ms=<int>` (default 100 = today)
- `slim_qcom_ngd_ctrl.keep_dma=<bool>` (default 0; skips `exit_dma()` on
  runtime suspend and the matching re-`init_dma()` on resume)
- `slim_qcom_ngd_ctrl.pm_dbg` (default 1): breadcrumbs on entry/exit of
  `runtime_suspend`, `runtime_resume`, `init_dma`, `exit_dma`, and around
  the QMI power request

Boot cmdline for the run: `slim_qcom_ngd_ctrl.autosuspend_ms=60000`
(and `joan_pipes=0`, per §1).

Predictions:
- **If the suspend path is the killer:** no `JOAN-PM: runtime_suspend
  enter` in the kill window, and playback proceeds past the AFE port
  config to the PCM trigger.
- **If it is not:** the breadcrumbs prove no suspend occurred and the
  phone still dies at the same point — which retires runtime PM as a
  whole and says the kill is ADSP-side, independent of anything the apps
  driver does after stream setup. That is the more valuable negative,
  because it is the first clean cut in this lane that does not depend on
  a guess about which write hangs.

Either way the breadcrumbs also answer the still-open question from §2:
did r4 suspend at all?

Rig unchanged from Aurel's (it works): SD root `remount,rw,sync`,
incremental `dmesg -c` logger, detached `setsid` audio sequence. Suggest
tightening the logger cadence from 0.2 s to 0.05 s — the last flush
before the reset is the resolution limit on where the log ends.

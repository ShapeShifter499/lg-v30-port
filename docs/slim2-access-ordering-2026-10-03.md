# slim2 (second NGD engine / WCN3990) access-ordering analysis and safe-off fix

- Date: 2026-10-03
- Written by: Lance, assisted by ZCode:GLM-5.3-Flash
- Branch: `joan/slim2-safe-off` (worktree
  `~/vibe-coding-projects/coding/linux-mainline-v30-slim2`), commit
  `0f648bc9c5d1c1bca53080c977bb116ffbe0b115`, parent `eeb0335090a2`
  (= merged `joan/latest-clean-test` line at the btfm-fm-audio merge;
  the branch tip has since advanced past it with unrelated work).
- Trees cited: mainline
  `~/vibe-coding-projects/coding/linux-mainline-v30-slim2` (drivers,
  at the branch point), downstream LG/Lineage msm8998
  `~/vibe-coding-projects/coding/android_kernel_lge_msm8998`.

## 1. Summary

With `slim2`/`slimbam2` enabled in the joan DTB and the
downstream-correct NGD instance-base rule (commit `89e9162796a5`), the
phone hard-hangs ~10 s into boot: the first read of the second
engine's register block (0x17241000) stalls the bus. The hang happens
*after* the ADSP has ACKed both SLIMBUS QMI requests that the mainline
driver completes before its first MMIO (select-instance(1) and
power-on). Mainline already has the "QMI first, registers second"
order; what it does not have is any proof that the engine block is
clocked before that read, and the msm8998 ADSP firmware evidently
ACKs instance-1 requests without (or long after) actually powering
the block for an apps-side client. Until an engine bring-up sequence
is proven, the only bench-safe configuration is "no engine-3 MMIO",
so the fix makes the DT the gate: slim2/slimbam2 stay disabled on
joan, the WCN3990 slim devices and the FM Capture backend are removed,
and the FM route is deferred with a documented re-enable recipe.

## 2. Root-cause chain (file:line evidence)

Mainline `drivers/slimbus/qcom-ngd-ctrl.c` (line numbers at
`eeb0335090a2`):

1. Parent ctrl probe (`qcom_slim_ngd_ctrl_probe`, L1641+) ioremaps
   `0x17240000` (L1655 region), requests the NGD IRQ
   (`devm_request_irq` L1663, `enable_irq` L1719) and registers the child
   platform device in `of_qcom_slim_ngd_register`, which computes the
   engine base with the downstream NGD_BASE_V2 rule
   `ngd->base = ctrl->base + ((ngd->id % 2) ? data->offset : 2 * data->offset)`
   (L1601-1602; `offset = 0x1000`, L113-116). For the joan child
   `reg = <3>` this is 0x17241000 -- the *real* engine-3 block, as
   opposed to the pre-`89e9162796a5` formula
   `id*offset + (id-1)*size` which mapped it to the harmless
   non-existent +0x5000 block (bisect branch `joan/ngd-bisect-oldbase`,
   commit `0bee0898a680`: boots).
2. Nothing touches `ngd->base` until the ADSP comes up: the child
   probe (`qcom_slim_ngd_probe`) only sets up QMI service lookup and
   runtime PM. On ADSP power-up the SSR/PDR notifiers
   (`qcom_slim_ngd_ssr_pdr_notify`, L1509) or the QMI new-server
   callback (L1402) schedule `qcom_slim_ngd_up_worker` (L1489), which
   calls `qcom_slim_ngd_enable(ctrl, true)` (L1505).
3. `qcom_slim_ngd_enable` (L1358) runs the full QMI handshake BEFORE
   any MMIO: `qcom_slim_qmi_init(ctrl, false)` (L1361) connects to the
   ADSP slimbus service and sends
   `SLIMBUS_QMI_SELECT_INSTANCE_REQ_V01` with
   `req.instance = id >> 1` = 1 (L478, L489), 3 s timeout (L70). Any
   failure returns before a single register access (L497-503, L1366).
   Only then: `complete(qmi_comp)` and the runtime-resume path
   (L1369-1377).
4. `qcom_slim_ngd_power_up` (L1198) sends the QMI power-on request
   (`qcom_slim_qmi_power_request(ctrl, true)`, L1214; failure ->
   return, L1218) and only then performs the first MMIO:
   `readl_relaxed(ctrl->base)` (L1222 -- parent block 0x17240000,
   non-stalling: r36 reads it fine), then the first ENGINE-block
   access `readl_relaxed(ngd->base + NGD_STATUS)` (L1226). With the
   correct base this read stalls the bus and the phone dies
   (~10 s = ADSP up + service arrival + two fast QMI round trips).

Conclusion: select-instance(1) and the power request both returned
QMI_RESULT_SUCCESS on the hang boot (any failure would have skipped
the MMIO), yet the block was still not accessible. QMI ACK != engine
clocked, for instance 1 on this firmware/mainline combination. (The
only other `ngd->base` access outside this path is the IRQ handler,
L787/795/803, gated by `pm_runtime_suspended()` (L790) -- unreachable before
a successful enable.)

Downstream `android_kernel_lge_msm8998` does the same thing in the
same order and does NOT hang on this phone (stock V30 runs the WCN3990
on `slim_qca`, cell-index 3, `msm8998.dtsi` L640-655):

- `ngd_slim_enable` (slim-msm-ngd.c L1459) calls
  `msm_slim_qmi_init` first (L1463) -- identical ordering.
- `msm_slim_qmi_init` (slim-msm.c L1493) sends the byte-identical
  select-instance message with `req.instance = nr >> 1` (L1510), same
  3 s timeout (slim-msm.h L99), then `ngd_slim_power_up` does the
  power request (L1320-1345, with 3 retries, `hw_init_retry` L1328),
  the ver read (L1355) and the NGD_STATUS read at
  `dev->base + NGD_BASE(nr, ver)` (L1359; V1/V2 rule L43-45).

The remaining deltas are peripheral, not ordering: downstream retries
the power request and the capability exchange 3x (L1328/L1417), picks
V1 vs V2 base offsets from the version register, and -- the one
difference that plausibly matters for engine power state -- registers
its PDR client PER ENGINE as `appsngd%d`
(slim-msm-ngd.c `ngd_dom_init` L268-283) against service "avs/audio",
while mainline registers one shared `("avs/audio", "msm/adsp/audio_pd")`
lookup for both parents (L1706) plus a global "lpass" SSR notifier
(L1713). Downstream's engine-3 enable is therefore driven by the
audio-PD state machine for *that* engine's servreg entry; mainline
enables both parents on the same global events. Whether the joan ADSP
firmware even publishes an `appsngd3` servreg entry (i.e. whether it
has an apps-side client slot for the second engine at all) is the
first thing to check on the bench.

Also relevant: on the booting r36 kernel, engine 1 still prints one
`"QMI wait timeout"` at ~12 s (`qcom_slim_ngd_up_worker` L1489, message
1 s wait for the slimbus QMI service) and WCD audio works; the
re-schedule on late server arrival (L1415-1416) absorbs it. That
transient is unrelated to the hang.

## 3. Why the QMI-gate candidates are not fixes here

- (a) "Gate the register access on the select-instance result": this
  is already the implemented behavior (section 2, step 3). The hang
  boot passed the gate; select-instance(1) was ACKed.
- (b) "Select-instance + power request first, then registers": also
  already the implemented order (L1361 before L1222/L1226).
- (c) DT gate: the only option backed by bench evidence (r32/r36 boot
  with zero valid engine-3 mapping; hang exactly when the real block
  is first touched). Chosen.

Keeping the downstream-correct base formula in the driver is
deliberate: reverting to the old formula would only recreate the
accidental "harmless wrong address" state, and the DT gate means the
formula is never exercised on joan until someone re-enables slim2 on
purpose.

The FM Capture dai-link had to go with the slim devices: its codec
dai (`wcn3990_btfm`) would never register, so the sound card probe
would defer forever and the working WCD audio links would come down
with it. The `q6afedai` `dai@152` (SLIMBUS_8_TX) port declaration
stays; it is inert without the link.

## 4. The fix

`joan/slim2-safe-off` commit `0f648bc9c5d1`
("arm64: dts: qcom: msm8998-lge-joan: keep the second NGD engine off"):

- `&slimbam2` / `&slim2` status overrides removed -- both keep the
  `msm8998.dtsi` `status = "disabled"`.
- WCN3990 `slim@3` bus devices (`slim217,220` PGD + IFD) removed.
- `FM Capture` dai-link removed; explanatory comment left in the sound
  node and a full re-enable recipe left at the (now disabled) slim2
  wiring site, including the sequencing candidates below.
- No driver changes: `drivers/slimbus/qcom-ngd-ctrl.c` stays at the
  `eeb0335` state (correct NGD_BASE_V2 base, QMI-gated MMIO).

## 5. Build validation (object level only)

```
make -C .../linux-mainline-v30-slim2 O=$HOME/kernel-builds/slim2-check \
  ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 olddefconfig \
  drivers/slimbus/qcom-ngd-ctrl.o qcom/msm8998-lge-joan.dtb
```

- `CC [M] drivers/slimbus/qcom-ngd-ctrl.o` clean
  (`CONFIG_SLIM_QCOM_NGD_CTRL=m`, config
  `pmaports-lg-v30-clean/device/testing/linux-lge-joan/config-lge-joan.aarch64`).
- `DTC msm8998-lge-joan.dtb` clean; dtb contains `slim-ngd@17240000`
  (disabled node from msm8998.dtsi) and zero `slim217,220`
  compatibles / no "FM Capture" link.

## 6. Bench validation (one RAM boot, when scheduled)

1. Build/pack boot image from `joan/slim2-safe-off` = `0f648bc9c5d1`
   the usual way (package build + boot-deploy; this repo change is
   dts-only, so the delta vs r36 is one dtb).
2. `fastboot boot` the image (RAM boot, no flash).
3. Expect: boot identical to r36 (`0bee0898a680`) in every observable
   -- same reachability of userspace/USB ssh gadget, WCD sound card
   probes with the same links minus "FM Capture" -- plus:
   - no probe activity for `17240000.slim-ngd` / `slimbam2` at all
     (no QMI select-instance for instance 1, no second "SLIM controller
     Registered");
   - btfm-slim never binds (no slim217,220 device on any bus);
   - the known tolerated engine-1 transient ("QMI wait timeout",
     once, ~12 s) may still appear; it is unchanged by this commit.
4. Pass = dmesg diff vs r36 contains only absent slim2/btfm lines.
   Any new stall/hang = fail (would indicate a path to the engine
   block that bypasses the DT).

## 7. FM-audio path follow-ups

To re-enable slim2 later, the open problem is: prove the engine-3
register block is clocked before the first MMIO. Candidates to try on
the bench, in order:

1. Firmware capability check (read-only, safe): dump the ADSP servreg
   / PDR locator listing on the bench kernel and look for an
   `appsngd3` entry (downstream client naming,
   slim-msm-ngd.c L276-281). No entry => this firmware has no
   apps-side client for the second engine and no driver-side ordering
   can fix it; the route would need the audio-PD fw story settled
   first.
2. Per-instance PDR gating: port downstream's per-engine client name
   ("appsngd%d" + get_service_location) so each NGD parent enables
   only when ITS servreg entry reports SERVREG_SERVICE_STATE_UP,
   instead of the shared "avs/audio" lookup (mainline L1706) + global
   "lpass" SSR notifier (L1713).
3. Retry/lazy-enable: port downstream's power-request retries
   (`hw_init_retry`, 3x) and capability-exchange retries, and/or delay
   the NGD_STATUS read until the engine is needed (btfm probe) rather
   than at controller enable.
4. If (1)-(3) fail, the fallback is measuring whether the engine block
   becomes readable only after a BT stack power-on of the WCN3990
   (downstream powers the chip via the BT driver, and the ADSP-side
   slimbus master for engine 3 may only spin up with the slave
   present).

Whatever sequence works must land with the same boot-safety property
as this commit: a failed/timeout select-instance or power request
leaves the device disabled with zero engine MMIO, and a stall cannot
occur before a positive fw-side signal for THAT instance.

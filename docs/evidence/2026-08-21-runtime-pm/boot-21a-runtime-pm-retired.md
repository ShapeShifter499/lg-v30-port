# Boot 21a — runtime PM RETIRED as the audio killer (clean negative)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-21
Kernel: 7.2.0-rc2-g0d00bab2b7ce-dirty (base `0d00bab2b` + runtime-PM instrumentation)
Image: boot-joan-qmidbg21a.img
(sha256 e1b27b8357a87c9638c92d1bcee9c3433fa30b14efc84265d2d209859c8804a0)
Cmdline delta vs 20i: `slim_qcom_ngd_ctrl.autosuspend_ms=600000
slim_qcom_ngd_ctrl.joan_pipes=0`
Local logs: /tmp/joanrun/boot21a/ on nym-nest
Analysis this tested: docs/ember-2026-08-21-audio-runtime-pm-and-sps-deadend.md

## Result

The bus never suspended and the phone died in exactly the same place.
**Runtime PM is not the killer.** The 100 ms autosuspend, the
`exit_dma()` -> `BAM_P_RST` teardown of the ADSP-owned BAM, and the QMI
power-down vote are all retired together.

## What the run proved on the way

**1. The sysfs-node diagnosis was correct.** The seq script surveyed every
candidate node:

```
/sys/devices/platform/soc@0/171c0000.slim-ngd/power/autosuspend_delay_ms
  delay=cat: read error: I/O error      control=auto status=unsupported
.../171c0000.slim-ngd/dma:rx/power/autosuspend_delay_ms      -> I/O error
.../171c0000.slim-ngd/dma:tx/power/autosuspend_delay_ms      -> I/O error
.../171c0000.slim-ngd/qcom,slim-ngd.1/power/autosuspend_delay_ms
  delay=600000   control=auto  status=active
  suspended_time=83950  active_time=22498
```

The parent (and both dma children) return `-EIO` because they never call
`pm_runtime_use_autosuspend()`. The 20f-20i glob `*/*slim-ngd/power/`
matched only those, so every attempt to raise the delay to 5000 ms wrote
nothing. The live node is `qcom,slim-ngd.1`.

**2. The knob took effect.** `delay=600000`, and
`/sys/module/slim_qcom_ngd_ctrl/parameters/` read back
`autosuspend_ms=600000 keep_dma=N pm_dbg=Y joan_pipes=N pgd_enable=N`.

**3. No suspend occurred in the run.** `status=active` at aplay time;
`suspended_time=83950 / active_time=22498` sums to the 106 s clock at seq
start, i.e. the controller was suspended from probe until the ADSP brought
it up and has been continuously active since. **Zero `JOAN-PM:` breadcrumbs
appear anywhere in the crash log** — no `runtime_suspend enter`, no
`exit_dma`, no `runtime_resume`.

That also settles the open question from Boot 20e r4: with the bus pinned
awake the phone still dies, so whether or not r4 suspended is now moot.

**4. It died anyway, in the same window.** Last 33 lines of dmesg:

```
[108.176936] JOAN-DBG: posting mc=0x60 mt=0x0 la=0xce      (codec IFD reads)
[108.177324] JOAN-DBG: posting mc=0x68 mt=0x0 la=0xce      (codec IFD writes)
[108.177426] JOAN-DBG: q6slim_hw_params dai id 2 rate 48000 fmt 2
[108.177519] JOAN-DBG: q6afe_dai_prepare dai id 2 started 0
[108.177552] JOAN-DBG: slim port 16384 cfg: dev 1 rate 48000 width 16
                       ch 1 fmt 0 map 144/0/0/0
[108.177729 .. 108.203955]  apr_audio_svc glink traffic, liid 1..7,
                       len 36-40, every one rx_done sent AND rx_done
                       received from remote
<log ends; SoC resets to Android>
```

aplay's own `-v` dump (stderr, unbuffered, so every line reached the SD
card) shows it got through `hw_params` and `prepare` — buffer_size 24960,
period_size 6240, `appl_ptr 0 / hw_ptr 0` — and then died. No
`aplay1 rc=` line. So the kill is at or immediately after the PCM trigger,
i.e. when the ADSP actually starts the AFE SLIMbus port.

## Two new observations from this log

**(a) The AFE slim port is configured for ONE channel on a stereo stream.**
`ch 1 ... map 144/0/0/0` while aplay negotiated `channels: 2`. Only
`SLIM RX0 MUX` is set, so the codec exposes a single SLIMbus channel and the
CPU DAI channel map has one entry. Not a candidate for a SoC reset, but it
means even a surviving stream could not be stereo. Stereo needs RX1 routed
as well.

**(b) wcd934x's `slim_stream_prepare()` never runs before the death.** No
`mc=0x2c/0x2d` (CONNECT_SRC/SINK) breadcrumbs appear — only `0x60/0x68`
(REQUEST_VALUE / CHANGE_VALUE) to the IFD at 0xce. In mainline wcd934x the
slim stream is prepared and enabled from the DAI **trigger**, not from
`.prepare`. So the ADSP is being told to start the AFE SLIMbus port
*before* the codec has defined or activated the channel it is supposed to
drive. Whether that ordering is legal on this manager is now the open
question.

## What this changes

The kill is not in anything the apps SLIMbus driver does after stream
setup — the driver is idle and the bus is pinned awake through the whole
window. Combined with the earlier retirements (PGD register writes,
unanswered QMI indications, pipe connects, autosuspend), the remaining
space is:

1. the ADSP faulting on the AFE port start itself, with a hardware watchdog
   resetting the SoC (no "crash detected in adsp" print ever appears, so the
   remoteproc fatal path is not what fires);
2. a bus/NoC wedge caused by the SLIMbus data lanes starting while the codec
   side is not yet activated (observation (b));
3. an apps-side MMIO access we have not identified, in some other driver.

Distinguishing (1)/(2) from (3) needs to know whether the apps CPU outlives
the ADSP's last message. That is Boot 21b.

## Rig note — a debug channel that was dead the whole time

The donor cmdline pins the netconsole target to nest's usb0 MAC
`92:e9:43:17:eb:60`. pmOS randomises the CDC host MAC every boot; nest's
was `9a:0d:a2:dd:68:63` this session. Netconsole has therefore been
transmitting to a MAC nobody answers to, and its silence carried no
information. Boot 21b repacks with `ff:ff:ff:ff:ff:ff` and
positive-controls the channel (a marker through `/dev/kmsg` must land in
the capture) before spending the audio run. See
[[feedback-validate-debug-channels]].

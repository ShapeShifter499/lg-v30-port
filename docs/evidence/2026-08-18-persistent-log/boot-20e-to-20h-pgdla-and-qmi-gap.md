# Boots 20e r3/r4, 20f, 20g, 20h — from PGD-write kill to pgdla discovery

Written-by: Aurel Nymvale (agent-aurel) / Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-18
Kernel: 7.2.0-rc2-gf173f039457e-dirty (builds #33-#37)
Images: boot-joan-qmidbg20e.img (93f755d2...), boot-joan-qmidbg20f.img
(21cee03b...), boot-joan-qmidbg20g.img (3229286c...), boot-joan-qmidbg20h.img
(7545489b...)
Local logs: /tmp/joan-aplay-20er3.log, -20er4.log, -20f.log, -20g.log, -20h.log
Evidence rig: SD root mount -o sync + incremental dmesg -c logger + detached
phone-side audio sequence (setsid). Full-buffer dumps proved too slow to
reach the crash point; incremental captured it.

## What each boot established

### 20e r3/r4 (PGD writes removed; plain stream attempt)

- Stream setup completes: power_up (state 2) -> codec IFC elemental traffic
  (la=0xce, SLIM PGD port interrupt enables) -> q6slim_hw_params ->
  q6afe_dai_prepare -> AFE slim port 16384 config -> APR acks.
- Death: silent SoC reset ~0.3-1.3 s later, BEFORE the PCM trigger ever
  runs. No panic/RCU/watchdog print. Phone falls back to Android.
- r3 had a second bus power_up at 54.44 (autosuspend, 100 ms delay, fired
  mid-setup); r4 did NOT -- the autosuspend is a red herring for the kill
  (the sysfs autosuspend write fails with EIO on this device anyway:
  "cat: read error: I/O error" on
  /sys/devices/platform/soc@0/171c0000.slim-ngd/power/autosuspend_delay_ms).
- The ADSP's QMI indication (IPCRTR, liid 1 len 48) arrives right after
  the stream setup and goes UNANSWERED -- mainline registers no rx handler
  for it -- after which the system dies.

### 20f (wake-time pipe bring-up, first attempt)

- Hook placed in power_up's tail was UNREACHABLE: the wake power_up takes
  the NGD_STATUS LADDR-bit early-return path, skipping the reconf-wait
  tail. Worker never fired. Moved the hook to runtime_resume with a
  prev_state != DOWN guard (deferred to ngd_master workqueue; direct call
  would deadlock: power_up runs under RPM_RESUMING and the bring-up's
  ADDR_QUERY does pm_runtime_get_sync).

### 20g (wake-time bring-up via worker)

- Worker fired; pgdla came back 0x0 and every pipe connect drew
  "Error Interrupt received 0x82000000". Two bugs: the bring-up read
  slim_get_logical_addr()'s RESULT CODE (0 = success) as the address, and
  the core path short-circuits on the freshly allocated device's cached
  is_laddr_valid state (slim_get_device() ALLOCATES an unregistered device
  for an unmatched EA -- slim_alloc_device -- and no ADDR_QUERY ran).

### 20h (direct get_laddr query)

- Bring-up now calls ctrl->get_laddr() directly (downstream does the same
  via dev->ctrl.get_laddr). The ADSP answered: pgdla = 0xc4. All 12 USR
  pipe connects (SRC+SINK, pn 0..5) posted cleanly -- ZERO bus errors.
- Death STILL follows ~0.1-0.3 s later (silent reset) -- so the pipe
  connects are not the missing piece either (20e died with zero connects;
  20h with twelve clean ones).
- The last event before every death remains the unanswered ADSP QMI
  indication on IPCRTR.

## Where this leaves the bring-up

Working: bus enumeration, codec + IFD regmaps, mixer routing (BE links
when the mixer is set), stream hw_params/prepare, AFE port config, PGD
laddr discovery (0xc4), pipe connect messages (accepted, no bus errors).

Killing: an ADSP-side wedge ~0.2-0.3 s after stream setup, silent SoC
reset ~1.3 s later, racing ahead of the PCM trigger.

Top remaining leads, in order:
1. Port downstream's QMI rx handling for SLIMBUS_QMI_SVC (0x0301):
   mainline's qcom-ngd-ctrl.c registers only select-instance/power/
   framer-status (send-only). The ADSP's stream-time indication (len 48)
   is dropped unhandled. Downstream slimbus also only handles those three
   -- so the killer may be an indication mainline's QMI layer NAKs/drops
   in a way the ADSP dislikes; verify what the 48-byte message is.
2. The codec's SLIM PGD port interrupt-enable writes (wcd934x
   enable_slim / wcd934x.c:4090ish) -- the codec-side pipe configuration
   happens at stream setup; wrong values could wedge the ADSP's manager.
3. Capture the ADSP's own state: the reset is silent (no
   "crash detected in adsp" print), suggesting a hardware watchdog rather
   than the remoteproc recovery path. A netconsole/netcat capture of the
   exact last ADSP traffic is still worth one attempt.
4. Compare the downstream full stream-start order (slim-msm-ngd.c):
   downstream intercepts the stream's USR connects in xfer_msg, calls
   msm_slim_connect_pipe_port (SPS/BAM pipe setup + PGD port programming
   + port_b rewrite) BEFORE posting. Mainline has the remap but none of
   the SPS/BAM setup. If the ADSP's wedge is the apps' BAM pipes being
   unconfigured when the ADSP starts pulling data, the SPS setup is the
   missing piece -- and the PGD register writes inside it are the part
   that hangs on pmOS (would need gating while keeping the SPS part).

# Boot 20e r3 — death moves to the second bus power_up

Written-by: Aurel Nymvale (agent-aurel) / Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-18
Kernel: 7.2.0-rc2-g29234a4d22a0-dirty, build #33 (commit f173f0394)
Image: boot-joan-qmidbg20e.img (sha256 93f755d2d0055d2688d16cded2033673fd16b549d8958729a9d652106a349726)
Local logs: /tmp/joan-aplay-20er3.log, /tmp/joan-mixer2-20er3.txt

## Evidence rig (v3)

SD root mounted with -o sync (every write committed instantly, defeats the
ext4 journal rollback that ate the first two 20e evidence pulls), plus an
INCREMENTAL `dmesg -c` logger (0.2 s cadence). Full-buffer dumps were too
slow to reach the crash point; incremental captured it.

## Sequence (54.0-54.44 s, then silent death)

- 54.067 power_up (state 2=ASLEEP): aplay1's open wakes the bus
- 54.075-54.082: codec IFC elemental traffic (la=0xce, enable_slim /
  SLIM PGD port interrupt enables)
- 54.082: q6slim_hw_params (dai id 2) + q6afe_dai_prepare + AFE slim
  port 16384 config -- the BE links (mixer routing works)
- 54.083-54.110: APR audio-service traffic (AFE commands to the ADSP)
- 54.198: IPCRTR/QMI round trip (slim QMI power response, ~130 ms)
- ~54.2-54.44: apps side idle -> runtime PM autosuspend fires -> bus
  ASLEEP mid-stream-setup
- 54.442: SECOND power_up (state 2) + apr rx_done; LOG ENDS. Silent
  death (no panic/RCU/watchdog print), SoC resets to Android.

No USR CONNECT posts, no pipe bring-up, no ADDR_QUERY: the stream never
reached slim_stream_prepare/trigger -- the kill is now BEFORE that.

## Interpretation

1. The 20d PGD-write kill is GONE (fix verified): the bring-up no longer
   touches PGD registers and the stream gets further.
2. The new (and now common) killer: the slimbus controller auto-suspends
   ~250 ms after the last bus access (pm_runtime_mark_last_busy in the
   rx path + short autosuspend delay) while the ADSP is still setting up
   the stream, and the SECOND power_up (wake) during ADSP activity kills
   the system silently -- the same signature as the 20c 55.5 s death.
3. Candidate fixes (next session):
   a. Bump the slimbus controller's pm_runtime autosuspend delay
      (e.g. 250 ms -> 2-5 s) so the bus stays awake through stream
      setup.
   b. In qcom_slim_ngd_power_up, skip the full re-init sequence
      (NGD_INT_EN / RX_MSGQ_CFG writes + setup + capability exchange)
      when waking from a brief ASLEEP with the ADSP still up --
      only do the QMI power request.
   c. Investigate whether the ADSP itself wedges on the wake (its
      watchdog then resets the SoC) -- the silent signature matches.

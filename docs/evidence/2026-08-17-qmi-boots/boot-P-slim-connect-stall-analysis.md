# Boot P crash analysis: SLIMbus CONNECT_SINK stall (2026-08-17)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17

## TL;DR

First netconsole-captured crash evidence. Boot P (qmidbg11p = Boot N config +
netconsole, MODULES=y) boots clean, ADSP comes up, playback start triggers a
SLIMbus NGD controller TX stall on the CONNECT_SINK user message, and the
system dies silently ~1s later (no panic text reached netconsole — the USB
gadget can't transmit with IRQs off; dmesg stream was lost to a missing local
dir, see pitfalls).

## Evidence

`boot-P-netconsole-crash.txt` (banked alongside this doc). Key lines:

```
[  824.559858] netconsole: network logging started
[  826.362943] JOAN-DBG: slim port 16384 cfg: dev 1 rate 48000 width 16 ch 1 fmt 0 map 144/0/0/0
[  827.423465] qcom,slim-ngd qcom,slim-ngd.1: TX timed out:MC:0x2d,mt:0x2
[  827.423621] qcom,slim-ngd qcom,slim-ngd.1: Tx:MT:0x2, MC:0x2d, LA:0xcf failed:-110
```

- MC 0x2d = SLIM_USR_MC_CONNECT_SINK, mt 0x2 = SLIM_MSG_MT_DEST_REFERRED_USER,
  LA 0xcf = the WCD934x codec's logical address.
- The message is the NGD rewrite of the core CONNECT_SINK that the codec
  driver (slim_stream_enable → stream.c) sends when the RX path powers up.
- The DMA TX transfer for this message never completed (1s HZ timeout in
  qcom_slim_ngd_xfer_msg), i.e. the NGD hardware never drained the message
  queue entry.
- Control-plane SLIM traffic (codec probe, mixer writes) works fine; only the
  stream-connect USR message stalls.

## Why the system dies after the timeout

- The timed-out TX descriptor is never re-prepared: the NGD TX queue stays
  wedged. Every later SLIM message waits 1s on the tx_lock and fails, while
  the audio DAPM path holds its own locks. Evidence ends at the -110 print,
  then the phone warm-resets into LineageOS (aboot fall-through). Silent
  panic (netconsole can't transmit post-panic over the USB gadget) or
  watchdog/lockup — needs pstore to discriminate (Boot Q plan below).

## Root-cause candidates (both are 8998-relevant)

### Candidate A: port_b rewrite + PGD port programming (downstream delta)

Downstream slim-msm-ngd.c, when sending CONNECT_SRC/SINK to the codec
(`wbuf[0] == dev->pgdla`):

1. `msm_slim_connect_pipe_port(dev, wbuf[1])` — programs the NGD's PGD port
   registers (SPS/BAM pipe connect; 4.4-only infrastructure, not portable
   as-is to mainline dmaengine).
2. `puc[1] = (u8)dev->pipes[wbuf[1]].port_b;` — rewrites the port number in
   the outgoing message to the MANAGER-side port number.
   port_b derivation (slim-msm.c msm_slim_data_port_assign): for i in 7..32,
   if (apps_pipes >> i) & 1: pipes[n].port_b = i - 7.

Mainline has neither: no pgdla tracking, no pipes[], no PGD register
definitions (PGD_PORT_CFGn_V2 = 0x14000, stride 0x1000 per port on NGD v2.0).

### Candidate B: mainline drops the reconfigure sequence

qcom_slim_ngd_xfer_msg() filters out ALL core messages with
MC in [SLIM_MSG_MC_BEGIN_RECONFIGURATION (0x40) .. RECONFIGURE_NOW (0x5F)]:

```c
if (txn->mt == SLIM_MSG_MT_CORE &&
    (txn->mc >= SLIM_MSG_MC_BEGIN_RECONFIGURATION &&
     txn->mc <= SLIM_MSG_MC_RECONFIGURE_NOW))
    return 0;
```

So NEXT_DEFINE_CHANNEL/NEXT_ACTIVATE_CHANNEL/RECONFIGURE_NOW never reach the
bus. Upstream works on db845c (sdm845, NGD v2.0 too) with this filter, so it
is not universally wrong — but the joan ADSP firmware may expect the manager
to drive the reconfigure. Untested on 8998 until now.

### Open question: why did Boots K/L "aplay complete"?

K/L completed `aplay` with no real proof of audible sound (never verified by
ear — no speaker-side evidence). If the SLIM data channel was never truly
configured, aplay can still complete ALSA-side while the codec DAC never
receives data. The K/L teardown crash is consistent with the disconnect path
hitting the same stall. First real audible-sound check is still pending.

## Boot Q plan (next session)

1. **Breadcrumbs** in qcom_slim_ngd_xfer_msg (gated by module_param, JOAN-DBG):
   - dump wbuf[0..2], txn->la/mc/mt for the connect/disconnect USR path
   - read PGD_PORT_CFGn/STATn/PARAMn (0x14000/0x14004/0x14008 + p*0x1000)
     for ports 0..7 at the stall
   - read NGD_STATUS + tx ring index + msgq state at timeout
2. **Candidate A/B toggles** (module_params, cmdline-settable):
   - `reconf_passthrough=1` — stop dropping the 0x40..0x5F messages
   - `portb_rewrite=1` — rewrite puc[1] to manager-side port (needs the
     apps_pipes value from downstream joan board data — grep board files,
     not DT, for `apps_pipes`/`eapc`)
3. **Unwedge on timeout** (always-on): re-prep the timed-out DMA descriptor
   (mainline-shaped slim_reinit_tx_msgq) so one stall doesn't kill the bus.
4. **pstore/ramoops**: CONFIG_PSTORE + PSTORE_RAM + PSTORE_CONSOLE, DT
   reserved-memory node (1 MB, TBD address — check msm8998 downstream
   reserved-memory layout) so the next boot can read the previous panic.
5. Re-run the mixer+playback sequence with netconsole + (this time) a
   mkdir'd dmesg stream dir.

## Pitfalls (this session)

- **mkdir the output dir before background redirects**: the dmesg stream
  redirect failed silently because /tmp/joanrun didn't exist locally.
- **pkill -f self-match**: killing a nest-side script by name from an ssh
  command whose own cmdline contains that name kills the ssh session itself
  (exit 255). Use `[b]racket` patterns or PIDs.
- **fastboot wedges on re-enumeration**: after a crash-to-bootloader, the
  phone may re-enumerate mid-`fastboot boot`; the client hangs on a dead
  handle. Guard with `timeout 90` and re-check `fastboot devices`.
- **18d1:d001 ambiguity**: lsusb shows "fastboot" for that VID:PID, but
  `lsusb -t` is truth — after boot it's the cdc_ncm gadget, not fastboot.
- **nest usb0 needs manual ip**: `ip addr add 172.16.42.2/24 dev
  enp0s29u1u5; ip link set enp0s29u1u5 up` after each gadget re-enumeration.
- **phone SSH**: user@172.16.42.1 with `sshpass -f /tmp/pmos-pass`; sudo via
  SUDO_ASKPASS helper (no -S pipe per house convention).

## Boot matrix (RAM-only, nothing flashed)

| Boot | Image | Result |
|---|---|---|
| O qmidbg10o | + netconsole, MODULES=n sweep | logo hang (632 m->y flips; config regression) |
| P qmidbg11p | Boot N config + netconsole only | boots; ADSP up; playback start = SLIM CONNECT_SINK stall -> silent death |

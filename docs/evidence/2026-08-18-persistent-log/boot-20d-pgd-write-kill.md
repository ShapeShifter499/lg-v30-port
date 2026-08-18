# Boot 20d — kill mechanism identified: app-side PGD register write

Written-by: Aurel Nymvale (agent-aurel) / Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-18
Kernel: 7.2.0-rc2-g29234a4d22a0-dirty (linux-mainline-v30-usb-otg)
Image: boot-joan-qmidbg20d.img
sha256: 6eb7e474d6e9f537b16249625b4a9c8832356c95c9ed53b676bfda1d0a64c68b
Local logs: /tmp/joan-aplay-20d.log, /tmp/joan-mixer2-20d.txt

## Method

Same persistent SD-root logger as 20c, plus:
- dump_stack() in qcom_slim_ngd_get_laddr() (joan_slim_dbg)
- DAPM path-connect dump in the soc-pcm.c no-BE block
- breadcrumbs in wcd934x_codec_enable_slim, q6slim_hw_params,
  q6afe_dai_prepare
- phone-side detached audio sequence (sets mixer, verifies with amixer
  cget, two aplay bursts 15 s apart), USB-death-proof

## Findings

### 1. BE routing is fine once the mixer is set (not a bug)

At 41.13 s the desktop daemon opened MultiMedia1 BEFORE the test set the
mixer: the DPCM walk found the path disconnected
(MM_DL1 -> SLIMBUS_0_RX Audio Mixer, connect 0). After the seq script
set "SLIMBUS_0_RX Audio Mixer MultiMedia1" = on (56 s), aplay1's open
linked the BE: q6slim_hw_params (dai id 2), q6afe_dai_prepare, and the
AFE slim port 16384 config all fired at 56.84 s. The "no backend DAEs"
error is ordering-only (daemon before mixer); UCM/PulseAudio would
normally set this routing.

### 2. The kill: app-side PGD port register write at stream trigger

dump_stack captured at 56.87 s (first stream trigger):

    qcom_slim_ngd_get_laddr+0x160
    slim_device_alloc_laddr+0x58
    slim_get_logical_addr+0x24
    qcom_slim_ngd_xfer_msg+0x3a4   <- joan_pipe_bringup on first CONNECT
    slim_do_transfer
    slim_stream_prepare+0x1d0
    wcd934x_trigger+0x68
    ...
    dpcm_be_dai_trigger
    snd_pcm_start (aplay ioctl)

Sequence: stream trigger -> slim_stream_prepare sends the first USR
CONNECT -> qcom_slim_ngd_xfer_msg calls joan_pipe_bringup -> PGD laddr
discovery (ADDR_QUERY, posted and replied fine at 56.876-56.879) ->
then the bring-up's FIRST writel_relaxed(PGD_PORT_CFGn, 0x14000) hangs
the CPU. No "pgd port cfg wr" or "pipe conn" breadcrumbs ever printed;
log ends ~0.3 ms after the ADDR_QUERY completion. Silent death, no
panic, phone reboots to Android (same signature as 20c's 55.5 s death,
which was the same mechanism: the daemon's post-resume stream trigger).

The app CPU CANNOT write the PGD port registers while the ADSP's audio
machinery is live — the PGD block is ADSP-owned (consistent with the
Boot X MGR_CFG read wedge). The ADSP programs its own PGD ports; the
app side only sends USR connect messages over the bus.

## Fix shipped in Boot 20e

joan_pipe_bringup no longer writes PGD_PORT_CFG/BLK/TRAN registers.
It still discovers pgdla (ADDR_QUERY, safe) and posts the
USR CONNECT_SRC/SINK messages per port. Breadcrumb added:
"pipe bringup pgdla=%#x".

## Retired for good

- The z1 "PGD port programming before first codec connect" approach
  (app-side PGD register writes): hangs the CPU at stream time.
- Any future app-side access to the PGD block (0x14000+) and the
  component-level blocks (0x0-0xfff) during ADSP activity.

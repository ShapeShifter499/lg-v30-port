# Boot L (qmidbg8l): playback path opened — and a teardown crash

Date: 2026-08-17
Kernel: 7187fbbb5675 + q6core.skip_versions gate + DAPM breadcrumbs + q6afe
        slimbus_dev_id fix (v9 patch, sha256 2b19d41f...)
Image: boot-joan-qmidbg8l.img (sha256 19e6d50db4ffafdb46a33d83ead5fbbc9027c7733181cf5a9a1fe3de7610b12a)
Boot mode: RAM-only fastboot boot, ADSP firmware staged manually.

## Result

`aplay -D hw:0,0 -d 3 -f S16_LE -c 2 -r 48000 /dev/zero` **completed**
without error — the first fully-open FE -> BE -> AFE path on mainline for
this device. The phone then dropped off the USB net and re-enumerated as
the bootloader (kernel panic, panic=5 auto-reboot); the teardown path is
the suspect, evidence lost with the RAM boot.

## What unlocked the FE open ("no backend DAIs enabled")

Two independent gates, found via v6/v7 DAPM breadcrumbs (route-add, dai
widget link, dpcm_path_get):

1. The intercon routes (q6routing) ARE present: the routing component is
   the platform of every dai-link (`platform { sound-dai = <&q6routing>; }`),
   so it is probed and its static routes are added. The FE walk stops at
   the MM AIF widgets because the mixer input paths start disconnected:
   `dapm_connect_mixer` sets `path->connect = (i == item)` and the walk
   only follows connected paths. Enabling the routing mixer creates the
   FE->BE DAPM path:

       amixer -c 0 cset name='SLIMBUS_0_RX Audio Mixer MultiMedia1' 1

   This is the "possibly missing ALSA mixer-based routing or UCM profile"
   the kernel has been printing all along. A UCM profile (alsa-ucm-conf
   sdm845/db845c) automates this; on the bare phone it is manual.

2. An `aux-devs = <&q6routing>` DTS experiment was tried and REVERTED —
   redundant, since the platform matching already probes the component.

## What unlocked the AFE port start (cmd 0x100e5 error 0x9)

Two fixes, in order:

1. Kernel: `q6afe_slim_port_prepare()` never set `slimbus_dev_id` (stayed
   0). The 8998 ADSP firmware validates it (downstream sets
   AFE_SLIMBUS_DEVICE_1). Patch in q6afe.c sets dev id 1 + logs the full
   slim cfg payload (`JOAN-DBG: slim port N cfg: ...`).

2. Userspace: the codec only populates its SLIM channel list for an AIF
   when the RX port mux selects that AIF (wcd934x_slim_rx_mux_put). With
   the mux at ZERO the machine's sdm845_slim_snd_hw_params got 0 channels
   from the codec, so the CPU dai map stayed empty and the firmware
   rejected the port (ch 0 in the breadcrumb). Fix:

       amixer -c 0 cset name='SLIM RX0 MUX' AIF1_PB

With both: breadcrumb shows `dev 1 rate 48000 width 16 ch 1 ...` and the
port start succeeds.

## The DAC question (ES9218P)

Not involved in any of the walls so far. The ES9218P sits only in the
headphone path (a separate I2S/MI2S link from the ADSP on downstream);
the speaker path is codec-only. Mainline ships sound/soc/codecs/es9218p.c
with a compatible and dai driver, so a later headphone lane is feasible
without new driver work. Orthogonal to the current bring-up.

## Remaining (next session)

1. Investigate the post-playback crash (likely the BE shutdown / q6afe
   port stop / slimbus teardown; the aplay close path). Capture dmesg
   aggressively around the close.
2. Codec-side DAPM for actual sound: joan DT lacks `audio-routing`
   (db845c has it); add it + the codec mixer sequence (SLIM RX0 MUX ->
   RX INT0_1 MIX1 INP0 = RX0 -> RX INT0 DEM MUX = CLSH_DSM_OUT -> SPK PA)
   for the speaker path.
3. Then: actual tone playback + (separately) the ES9218P headphone lane.

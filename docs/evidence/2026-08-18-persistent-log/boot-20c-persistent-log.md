# Boot 20c — persistent-log kill evidence and decoded SLIMbus timeline

Written-by: Aurel Nymvale (agent-aurel) / Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-18
Kernel: 7.2.0-rc2-g29234a4d22a0-dirty (linux-mainline-v30-usb-otg)
Image: boot-joan-qmidbg20c.img
sha256: 888beb63669c1c90e2131fb2a1db21738deb54fde8b7572a9f1ecd4b29b77d2b

## Retrieval

The Boot 20c persistent SD-root dmesg log was recovered by RAM-booting the
same image and pulling `/var/log/joan-aplay.log` (1,263,220 bytes, 13,073
lines, sync-per-line logger). Local copy: /tmp/joan-aplay-20c-persistent.txt.

First adb attempt from LineageOS failed (no root/su on that build); the
pmOS readback boot (sshpass user@172.16.42.1) succeeded.

## Message-code decoding (important correction)

The log's `posting mc=0x60/0x68/0x0d` lines were misread in earlier notes
as downstream-style CONNECT_SOURCE/SINK/NEXT_ACTIVE_FRAMER. In THIS tree:

- include/linux/slimbus.h: SLIM_MSG_MC_REQUEST_VALUE = 0x60,
  SLIM_MSG_MC_CHANGE_VALUE = 0x68 (elemental read/write).
- drivers/slimbus/slimbus.h: CONNECT_SOURCE=0x10, CONNECT_SINK=0x11
  (upstream codes).
- qcom-ngd-ctrl.c local USR codes: CONNECT_SRC=0x2C, CONNECT_SINK=0x2D,
  DISCONNECT_PORT=0x2E, ADDR_QUERY=0xD, ADDR_REPLY=0xE.

So the traffic was: codec elemental register access (0xcf) and
IFD/interface-device elemental access (0xce), plus one USR ADDR_QUERY
(0x0d, mt=2, la=0xff) at the very end.

## Device identities (resolved)

The joan DTS declares TWO slim devices under slim@1, both
compatible "slim217,250":

- wcd9340_ifd: ifd@0,0, reg <0 0>   -> EA 217:250:0:0 -> LA 0xce
- wcd9340:     codec@1,0, reg <1 0> -> EA 217:250:1:0 -> LA 0xcf

The codec driver (wcd934x.c:5812) resolves the "slim-ifc-dev" phandle,
gets the IFD slim device and builds a SECOND regmap on it
(if_regmap, wcd934x.c:5822) used for WCD934X_SLIM_PGD_PORT_INT_EN* and
other interface registers. LA 0xce traffic = if_regmap access from the
codec driver (IRQ handler, wcd934x_codec_enable_slim and the
SLIM PGD port interrupt-enable helper around wcd934x.c:4090).

## Boot-time timeline (from the persistent log)

- 33.5-33.7: ADSP comes up; APR services 4:3 (ASM), 4:4 (ADM), 4:7 (AFE),
  4:8 register; SLIMbus QMI server appears (node 5 port 11).
- 33.72: controller up_worker proceeds; power_up (state 3=DOWN).
- 33.735: satellite handshake: master capability -> REPORT_SATELLITE (0x1).
- 33.792: ADDR_QUERY #1 -> codec LA 0xcf; chip-id read "WCD934x chip id
  major 0x108, minor 0x1" (33.796); codec probe writes ~40 regs (0xcf).
- 33.809: ADDR_QUERY #2 -> IFD LA 0xce (from codec_parse_data via
  slim_get_logical_addr(wcd->sidev)); if_regmap created.
- 34.47-34.51: codec DAPM mux "has no paths" warnings (component probe).
- 34.817: card0 "LG-V30" probes: Headset Jack registered (input4).
- 34.822: "SLIM controller Registered"; up_worker re-enters wait
  (state 1=IDLE); 35.848 "QMI wait timeout" (3 s wait, expected).
- 38.569: power_up (state 2=ASLEEP) — first bus wake by aplay stream.
- 38.577+: codec elemental writes (0xcf) — aplay stream start codec
  configuration (no q6afe AFE port config at this point!).
- 40.911: "ASoC: no backend DAEs enabled for MultiMedia1" +
  dpcm_path_get debug: playback path found ONLY MM_DL1 (1 widget);
  capture path found MM_UL1 + MultiMedia1 Mixer (2 widgets).
- aplay blocks (buffer never consumed, BE never linked).
- ~44-46: SSH/USB becomes unreachable (test script reports
  PHONE_UNREACHABLE) while the kernel keeps running.
- 53.5: rfkill event; 54.89: EXT4 "re-mounted" (SD card power cycle —
  system suspend/resume).
- 55.527: power_up (state 2=ASLEEP) — bus wake after the suspend cycle.
- 55.5346-55.536: 4 elemental messages to 0xce (2 reads + 2 writes) —
  codec DAPM re-power: SLIM PGD port interrupt enables via if_regmap.
- 55.536: q6afe "slim port 16384 cfg: dev 1 rate 48000 width 16 ch 1
  fmt 0 map 144/0/0/0" (AFE port config for SLIMBUS_0_RX).
- 55.5659: ADDR_QUERY (mc=0xd mt=0x2 la=0xff) posted; completed at
  55.5662 (reply received in ~0.3 ms via bus RX path).
- LOG ENDS. No panic, no RCU stall, no NMI, no ADSP crash print.
  Silent death; phone falls back to Android (SoC reset).

## Conclusions

1. The kill is NOT the ADDR_QUERY itself: the reply arrived and the
   completion fired (time_left=250). The death follows within ~1 s.
2. The 55.5 s burst is the audio stack REPLAYING after a system
   suspend/resume cycle (SD remount -> bus power_up -> codec DAPM
   re-power -> AFE port reconfig -> ADDR_QUERY). Signature matches the
   earlier ADSP-watchdog SoC-reset pattern (silent, no kernel output).
3. The PRIMARY blocker for sound is the DPCM BE routing: the FE
   MultiMedia1 playback path stops after MM_DL1 — the "MultiMedia1"
   input of the SLIMBUS_0_RX Audio Mixer was disconnected at walk time
   (40.9 s) despite the amixer set at ~37 s. No BE = no data path.
4. The aplay never reached stream-enable, so the z1 pipe bring-up
   (PGD pipe connects) never ran in this boot.

## Instrumentation added for Boot 20d (this commit's build)

- qcom_slim_ngd_get_laddr(): dump_stack() when joan_slim_dbg — identify
  the 55.5659 ADDR_QUERY caller.
- soc-pcm.c no-BE block: dump the FE widget's outgoing DAPM paths and
  their connect states (1st and 2nd hop) — show which hop is broken.
- wcd934x_codec_enable_slim(): entry breadcrumb (event id).
- q6afe-dai.c: q6slim_hw_params() and q6afe_dai_prepare() entry
  breadcrumbs (dai id, port-started state).
- Test script 20d adds amixer cget verification of both mixer controls
  before aplay.

# 2026-10-06 — Venus works; boot-log sweep; CPU/thermal audit (Ember)

Bench: US998, pmOS on SD, kernel `linux-lg-joan` 7.2.0_rc2 r46 rebuilt from
`joan/latest-clean-test-merged`. Every boot was a RAM boot with the **armed
send**: start `fastboot boot <img>` first, then reboot into the bootloader.
That worked first time on all six boots.
Ledger entry: `kernel-change-ledger.md` → "Venus works on msm8998 + boot-log sweep".

## Venus (video decode/encode) — WORKING

| Check | Result |
|---|---|
| probe + firmware auth/boot | `pas_auth 0`, `venus_boot 0`, hw version 3.43.709 |
| nodes | `qcom-venus-decoder`, `qcom-venus-encoder` (the number changes per boot; pick nodes by name) |
| H.264 decode 640x480 | 57 frames **byte-identical** to ffmpeg software decode |
| H.264 encode 640x480 | valid stream, 26 frames, avg luma PSNR 31.7 dB |
| bus votes | `mas-venus`, `slv-cnoc-mnoc-mmss-cfg` carry `cc00000.video-codec` |
| decoder formats | H264, HEVC, VP8, VP9, MPEG-2/4, H.263, VC-1, XviD |

The fix was the subcore GDSC mode (`HW_CTRL` → `HW_CTRL_TRIGGER`). LG
downstream marks these GDSCs `qcom,support-hw-trigger`. Giuseppe Maggio's
porthole series already had the same change. The `venus/`-only fold-in had
dropped it.

Repro (on the phone):

    D=$(for v in /sys/class/video4linux/video*; do [ "$(cat $v/name)" = qcom-venus-decoder ] && echo /dev/${v##*/}; done)
    v4l2-ctl -d $D --set-fmt-video-out=width=640,height=480,pixelformat=H264 \
      --set-fmt-video=pixelformat=NV12 --stream-mmap --stream-out-mmap \
      --stream-from=test.h264 --stream-to=out.nv12 --stream-count=60

**Always set the resolution on the OUTPUT format.** Without it the bitstream
buffer is 8 KiB. The firmware reads 0x84 bytes past the end, the mmss SMMU
faults (SID 0x40a), the firmware raises an exception, recovery fails 5 times and
the **SoC resets** (the phone comes back in LineageOS). Open items: a minimum
compressed-buffer size in the driver, and making a firmware crash survivable.
Encoder EOS drain reports HFI 0x1006/0x1004 (non-fatal).

## Boot-log sweep: 127 → 46 err/warn lines

Fixed:
- venus `video_subcore0_clk stuck at 'off'` + WARN trace → GDSC fix above
- `stmfts error code: 0x00dec000d0ba` ×5 → type 0xba is a firmware debug
  message (LG `touch_ftm4.c` names types 0x01-0x0b only); now `dev_dbg`
- `fb0: sys_imageblit/sys_fillrect: framebuffer is not in virtual address
  space` → msm fbdev was missing `FBINFO_VIRTFB` (system-memory GEM vmap)

Triaged, harmless (with the reason):
- `Kernel image misaligned`: LG ABL loads the Image at DDR base + 0x80000,
  while mainline arm64 has text_offset 0. RELOCATABLE handles it. A real fix
  needs a bootloader (edk2 path).
- ath10k `vdd-3.3-ch1 not found`: LG wires only ch0 (L25) on msm8998.
- ath10k `board-2.bin` miss: board-2.bin has
  `variant=LG_joan_{us998,h930,h932}` entries, but the single DTB sets no
  `qcom,calibration-variant`, so ath10k falls back to the per-model `board.bin`
  from `firmware-lg-joan-<model>`. Wi-Fi works. A clean fix needs per-model
  DTBs (the single DTB also says "US998" on an H932). **Lance decision.**
- arm-smmu 16c0000 SID 0x1900 faults: WLAN MSA, Deck #183.
- wcd934x "mux … has no paths", the duplicate GPU debugfs nodes, remoteproc
  "handover already happened", `ITS: No ITS`, UFS inline-crypto disable,
  `wcd934x-gpio DMA mask`, adreno `vddcx` dummy: upstream-generic.
- PMIC fuel-gauge `cleanup_irq apid=58` + one `bad_chained_irq` dump at 2.2 s:
  this happened once and was absent on later boots (timing-dependent).

Open, and part of feature work:
- `qcom-qmp-usbc-phy: PHY is configured for USB, can not enable DP` +
  `phy init failed -16` + `phy_power_on before phy_init`: DisplayPort alt-mode
  (USB-C display) needs QMP USB/DP serialization.
- `slim-ngd QMI wait timeout`: race with ADSP/modem bring-up. Audio works.
  Revisit with the FM-audio (slim2) work.
- `tfa989x vddd` dummy, `EXT4 mounting unchecked fs` (pmOS_boot on SD).

## CPU (OSM/CPRh) — rated maximum reached

- Speed bin **2** (qfprom 0x130 = 0x5002005e). Lineage agrees.
- Gold runs at 2361.6 MHz all-core, which is bin 2's rated all-core maximum.
  LG did not cap it.
- **Missing: the single-core boost** to 2419.2/2438.4/2457.6 MHz. LG
  `msm8998-v2.dtsi` perfcl-speedbin2 has these as the 1-active-core rows (LUT
  word bits [18:16] = 1) at corners 28-30, the same corners and voltages as
  their 4-core twins. Our `qcom-cpufreq-osm` writes core_count = 4 on every
  row and uses the row index as the virtual corner, so the boost needs
  row ≠ corner support in the OSM LUT and the CPRh corner map. It is a careful
  dedicated pass: a wrong corner means a wrong voltage. Never exceed the fused
  bin.
- Governor: schedutil on both clusters. GPU: 257-710 MHz (7 OPPs),
  simple_ondemand.

## Thermal — in place

- cpu0-7 zones: passive 85 °C → that cluster's cpufreq, critical 110 °C.
- gpu-top/bottom: passive 85 °C → GPU devfreq. mem: passive 85 °C → gold.
- skin: LG-style ladder 37/38/38.5/39/41/42.5/44/46 °C stepping GPU and
  both clusters.
- LMh hardware limiting active (REL algorithm on).
- modem, wlan, camera, multimedia, L2, mhm: `hot` trips only (no cooling knob).
- TODO: compare the skin ladder with LG `thermal-engine` config.

## Feature status for a default install

| Feature | Kernel | Userspace / default app |
|---|---|---|
| Calls / SMS | modem + VoLTE packages | calls, chatty (via Phosh) |
| Voice recorder | audio works | gnome-sound-recorder (in device pkg) |
| Volume panel | — | pwvucontrol (in device pkg) |
| NFC | nxp-nci (PN5xx) | neard daemon only; no GUI reader/writer app packaged |
| Video decode/encode HW | **Venus working (this doc)** | GStreamer v4l2codecs / ffmpeg v4l2m2m |
| FM tuner | `radio-qca-fm` tunes 76-108 MHz, RSSI, RDS, seek | **no FM audio PCM yet** (btfm slim2), so no app |
| FM transmitter | — | WCN3990 is RX only in LG's stack; not planned |
| Camera | CAMSS + imx351 + bu24235 subdevs register | no working pipeline/app yet |
| USB-C display | DP PHY refuses (see above) | — |

## Bench gotchas from today

- Positive-control sysfs probes: two broken loops (`case *_*` matched the `_`
  in `thermal_zone`) reported "no cooling bindings" before a raw `ls` showed
  the bindings.
- `/lib` is merged into `/usr` on pmOS: `apk info -W /lib/...` says "no owner"
  for packaged files; query `/usr/lib/...`.
- Plain `scp` to the phone fails (sshd penalty); use the `jssh scp` wrapper.

Assisted-by: Claude-Code:claude-opus-5-5

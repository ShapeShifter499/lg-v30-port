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
| NFC | nxp-nci (PN5xx); neard now D-Bus activated (r22) | nfctool CLI; no GUI reader/writer app exists in Alpine |
| Video decode/encode HW | **Venus working (this doc)** | GStreamer v4l2codecs / ffmpeg v4l2m2m |
| FM tuner | `radio-qca-fm` tunes 76-108 MHz, RSSI, RDS, seek | **no FM audio PCM yet** (btfm slim2), so no app |
| FM transmitter | **not in hardware** (firmware probe, see below) | — |
| Camera | CAMSS + imx351 + bu24235 subdevs register | no working pipeline/app yet |
| USB-C display | DP PHY refuses (see above) | — |
| TV tuner | **not fitted on US998** (KR/JP boards only) | — |

## Bench gotchas from today

- Positive-control sysfs probes: two broken loops (`case *_*` matched the `_`
  in `thermal_zone`) reported "no cooling bindings" before a raw `ls` showed
  the bindings.
- `/lib` is merged into `/usr` on pmOS: `apk info -W /lib/...` says "no owner"
  for packaged files; query `/usr/lib/...`.
- Plain `scp` to the phone fails (sshd penalty); use the `jssh scp` wrapper.

Assisted-by: Claude-Code:claude-opus-5-5

## Second pass, same day (02:00-02:40)

### Venus: unsized streams no longer reset the SoC — `6c9d1bca`
Measured first: the firmware's own `HFI_BUFFER_INPUT` requirement for an
unsized session is **6144 bytes**, so it is no floor (8 KiB already overflows).
LG `msm_vdec.c` `get_frame_size_compressed()` sizes every bitstream buffer from
the codec's *maximum* macroblocks per frame. Fix: floor the compressed
sizeimage at the driver formula's 1280x720 value (708608 B for H.264), in
try_fmt and queue_setup. Bench: the unsized decode that reset the phone now
decodes all 57 frames, byte-identical to ffmpeg.

### Charger float voltage above the battery maximum — `75307f90` (upstream bug)
`qcom_smbx` programmed `FLOAT_VOLTAGE_CFG = (vmax - 3487500) / 7500 + 1`. The
register means 3487.5 + 7.5·n mV, so it rounded **up**. For the 4400 mV cell the
register read 0x7a = 4402.5 mV, and the charger tripped `battery overvoltage
detected` at full (vbat 4.396 V, health "Over voltage", charging stopped).
Qualcomm downstream `smblib_set_charge_param()` rounds down. Now 0x79 =
4395.0 mV, health Good. This affects every PMI8998 device on mainline: an
upstream candidate.

### NFC: neard could never start — device-lg-joan r22
Alpine's `neard.service` has only `Alias=dbus-org.neard.service` (meant to be
bus-activated) and no activation file, so the `enable neard.service` preset
did nothing. The device package now ships
`/usr/share/dbus-1/system-services/org.neard.service`. Bench: neard inactive at
boot; an *unprivileged* `busctl get-property org.neard /org/neard/nfc0 …`
starts it. Adapter powers; protocols Felica/MIFARE/Jewel/ISO-DEP/NFC-DEP/
ISO-15693; `StartPollLoop(Initiator)` works. **Physical tag read untested.**
No GUI NFC reader/writer app is packaged in Alpine. `nfctool` (neard) is the
CLI.

### FM transmitter: not possible on this hardware (measured)
Debug-only probe through `radio-qca-fm` (since dropped), with positive
controls:

| opcode | meaning | firmware reply |
|---|---|---|
| 0x4c0a | GET_STATION (real) | idle: status 0x0c "disallowed" + data; RX on: 0x00 + data |
| 0x4c3f | bogus OCF in RX group | silence |
| 0x7c01 | bogus OGF 0x1f | silence |
| 0x5003 | GET_TRANS_CONF (TX group) | **silence**, identical to bogus |

The firmware answers commands it has, even ones it refuses, and drops unknown
ones. The transmit group behaves as unknown. Qualcomm's helium HAL
(`radio_helium_hal.c`, `HCI_FM_HELIUM_STATE`) only implements FM_RECV and
FM_OFF. The TX defines are left over from the older iris (WCN36xx) stack. The FM
core is mask ROM plus a Qualcomm patch (`crbtfw21.tlv`, BTFM.CHE.2.1.2), and
the board has no FM-TX RF path. "Enable transmit" (0x5001) was deliberately
not sent.
Bands: helium defines 76-108 MHz only. **AM is impossible** (VHF-only front
end, no AM demodulator). OIRT 65.8-74 MHz is untested and would be a
receive-only driver band change.

### TV tuner: not fitted on the US998
LG trees: KR (`joan_kr`) = T-DMB `lge,tdmb` on BLSP1 QUP2 **SPI** (GPIO
31-34), INT GPIO 95, EN GPIO 96, LDO28 1.8 V, ln_bb_clk3. JP (`dcm_jp`,
`kddi_jp`) = ISDB-T **Telechips TCC3535 @ I2C 0x58** on the same QUP (GPIO
32/33), EN GPIO 31, RST GPIO 34, LDO28 1.8 V, plus TSIF. The tuner driver is
built only in the KR/JP (and non-perf global_com) defconfigs, never in
`joan_nao_us`. The US998 DT references none of these resources, and live they
are all UNCLAIMED.
Active test (DT-swap RAM boot): LDO28 enabled at 1.8 V. GPIO 32/33 stay low
against the internal pull-down both before and after, so **there are no I2C
pull-ups and no I2C tuner bus is populated**. Not tested: a KR-style SPI tuner
(SPI has no pull-ups; it would need GPIO 96 driven plus an SPI ID read).

### Open: one unexplained reset into LineageOS
It happened a few minutes after the final-r47 checks (idle, 02:13-02:16). It
did not reproduce in 10+ min of idle plus the same tests under a live `dmesg
-w` stream, and pstore was empty. The charger OV trip happened on the next
boot but only stops charging. Keep a live stream running on bench sessions
until it recurs.

### FM audio (slim2): where it stands and the next bench plan (needs Lance present)
The FM tuner works (`radio-qca-fm`). FM **audio** needs the second SLIMbus
NGD engine (`slim2` @ 0x17240000, cell-index 3, ADSP instance 1) for the
WCN3990 `slim217,220` device and the SLIMBUS_8_TX "FM Capture" backend.
- History (Fulgor 10-02/03): with the downstream-correct NGD base (odd
  instance → +0x1000, `89e91627`), enabling slim2 **hard-hangs the SoC ~10 s
  into boot, with no watchdog recovery**. The phone stays off until someone
  power-holds it. The old wrong base pointed at an unused window and only
  "worked" because it touched nothing real.
- Desk comparison 2026-10-06: mainline `qcom_slim_ngd_power_up()` matches
  downstream `ngd_slim_power_up()` step for step (wait for QMI, power request
  ACTIVE, read the version at base, then NGD_STATUS). Downstream gives slim_qca
  **no clocks or power domains** (ADSP-managed via QMI), same as mainline. So
  the hang is not in the power-up ordering itself.
- Remaining suspects, in test order:
  1. `slimbam2` (BAM @ 0x17204000, controlled-remotely): channel setup writes
     BAM registers when the NGD enables DMA. Downstream maps BAM as a second reg
     range of the same NGD device and never runs a separate bam_dma probe.
  2. The QMI power ACK for instance 1 is honoured late: add a delay/poll of a
     harmless register via the *first* engine's view before the first slim2 MMIO.
  3. The per-engine PDR name (`appsngd%d`) vs the shared audio PD.
- Safe method: `CONFIG_SLIM_QCOM_NGD_CTRL=m` and gate slim2 with a module
  parameter (default off), so that each stage can be armed after boot with a
  live `dmesg -w` stream to nest. **Only with Lance at the phone**, since a hang
  needs a power-hold.

### Fresh default install from pmaports — PASS (2026-10-06 03:50, Lance-approved)
`pmbootstrap install --sector-size 512` from this pmaports tree (linux-lg-joan r47 =
`75307f90`, device-lg-joan r22, Phosh), written to the bench microSD from LineageOS
(`adb exec-in dd`, then read back; the tail-2 KiB drop was caught and fixed, so the card
md5 equals the image). RAM-booted that install's own boot.img. Result: root grown to
182.9 GB, system `running`, no failed units, Phosh up, **cellular data connected with
no manual setup**, Venus decode bit-exact, FM receiver + sound card + modem present,
neard D-Bus activation works. Wi-Fi needed only its credentials. Not tested here:
calls/SMS, camera (not working yet), FM audio (slim2), USB-C display.

### Calls / SMS on a fresh install (2026-10-06 04:00)
Installed by default: `calls`, `chatty`, `snapshot`, `gnome-sound-recorder`,
`pwvucontrol`, `neard`, `feedbackd`, `lg-joan-volte`, `joan-imsd`. Modem: LTE,
T-Mobile, home, packet attached, SMS storage supported, voice not emergency-only.
- **Calls app cannot place calls on T-Mobile US.** It uses ModemManager CS voice;
  T-Mobile has no CS. VoLTE is the separate `joan-ims` UA (`joan-ims dial`).
  Making Calls work means a ModemManager IMS voice path (large project).
- **VoLTE is not automatic on a fresh install:** there is no IMS PDN (only bearers
  0 and 1 exist), `joan-imsd` stays inert until `/etc/joan-imsd/isim.env` exists, and
  the UA hard-codes `mmcli -b 2`, `qmapmux0.1`, a `2607:` (T-Mobile) address
  prefix and a fixed WDS QRTR port. All of these need fixing before auto-start.
- **Fixed now (joan-imsd r5, `9f0b2b452b`):** register mode auto-answered every
  incoming call with 200 OK (a silent call the user never sees). It now declines
  with 480 so callers reach voicemail. Offline-tested; live incoming call untested.
- **SMS:** untested. It may work over SGs without IMS; it needs a test message from
  Lance (sending is outward-facing, so not done unattended).

## CPU / GPU / hardware acceleration pass (2026-10-06 05:00-07:15)

### CPU — gold 2457.6 MHz single-core rows: DONE (`56b9e9e5`, bench-verified)
LG's bin-2/3 gold table has five 1-core rows sharing their 4-core twin's corner
(2265.6/2342.4/2419.2/2438.4/2457.6). No mainline msm8998 device ever ran them; the
OSM/CPRh lineage wrote core count 4 and used row = corner. Getting there exposed three
bugs that bit in sequence, each found on the bench:
1. the APM/MEM-ACC sequencer crossovers were written as **row** counts (vendor
   clock-osm.c uses the **corner** count; LG CPRh dump: 30 corners + APM 31 + MEM-ACC
   32). Rows ≠ corners crashed or hard-hung early boot;
2. the LUT read-back ended the table on two equal frequencies (the comment said
   "same core counts"), which cut the table at 2265.6 MHz;
3. `dev_pm_opp_add()` of a dynamic OPP on a table with required-opps oopses in
   `_required_opps_available()` (NULL required_opps[0]), which hard-hung boot. The fix
   uses a real turbo-mode DT OPP after its twin (CPR maps a corner to the first OPP
   requiring it).
schedutil never targets cpufreq "boost" entries (capacity_freq_ref is taken before
boost is applied), so 2457.6 is offered as the top regular frequency, as LG does.
Measured (OSM operating point sampled from a silver core): 1 task → 2457 MHz @ 1136 mV
(55 s soak, 39 °C after); 4 tasks → 1.9-2.0 GHz (LMh); silver 1 task → 1900 MHz.
Corner 28-30 voltage = 1136 mV = LG's CPR ceiling. The skin ladder (37 °C) throttles
gold under bench heat plus charging, by design.

### GPU — Adreno 540: working, one bandwidth limitation open
- freedreno FD540, Mesa 26.2.4, **OpenGL ES 3.1 / GL 3.1**. **No Vulkan:** turnip
  supports a6xx/a7xx only, so vkmark and Vulkan apps won't run on the a540.
- 257-710 MHz devfreq (simple_ondemand); 710 MHz = LG v2 max.
- glmark2-es2-drm @ 1440x2880: **score 119**, GPU at 710 MHz for 84% of samples.
  Weakest scenes are memory-heavy (refract 11, terrain 19, desktop-blur 45 FPS).
- **Open:** the GPU's only DDR vote is the fixed adreno placeholder `fast_rate*8` =
  5.68 GB/s; LG votes per level up to 14.43 GB/s (bus index 12). Adding LG's
  `opp-peak-kBps` (in the joan GPU OPP override; msm8998.dtsi's table is replaced
  there) made the **first GPU submit lock up** (hangcheck, fence 0/1) and the SoC
  reset. Suspect: high BIMC/DDR votes through our locally patched msm8998 icc BIMC
  QoS (mas-oxili, bypass, qport 1). Not shipped. Next: bisect the vote level with
  CONFIG_INTERCONNECT_DEBUG's test client, compare BIMC QoS with downstream.

### Hardware acceleration in apps
- **Firefox 154** (installed for the test, not yet a default dependency): about:support
  via Marionette `Troubleshoot.snapshot()` under a GPU-backed headless sway:
  **WebRender (hardware), WebGL1/2 = "freedreno -- FD540", accelerated Canvas2D,
  DMABUF**, no failures. Codec table: H264/VP8/VP9/HEVC = SWDEC+HWDEC, AV1 SW only
  (it matches Venus). Firefox's v4l2test finds the Venus decoder.
- **Firefox HW video decode: not working yet.** It is off by default on Linux for
  non-allowlisted drivers. With `media.hardware-video-decoding.force-enabled=true` it
  initialises the V4L2-DRM FFmpeg decoder (h264_v4l2m2m), gets one frame with
  pts=AV_NOPTS_VALUE, then flushes and falls back to software. The FFmpeg CLI decodes
  the same file through h264_v4l2m2m with correct pts, so the suspect is Firefox's
  timebase setup for the V4L2 path. Needs a Firefox source dive.
- **GStreamer (Showtime, the default video player):** v4l2h264dec decodes 593/600
  frames of a 720p clip on Venus, then **EOS fails**: firmware session error 0x1001
  with the placeholder EOS address 0xdeadb000. A NULL EOS address (the SM8250 quirk)
  makes this firmware assert (`vbuffer.c:1219`, VIDEO.VE.4.4-00058) and reset the
  SoC. Encoder drain has the same problem. Fix design: EOS on a real, mapped,
  zero-length buffer, as LG's msm_vidc does. Not yet done.

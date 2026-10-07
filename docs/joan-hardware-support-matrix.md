# LG V30 (joan) hardware support matrix — mainline pmOS

Goal: everything the V30 has works on a default pmaports install. This is the
tracking table. Update it in place and date what changes.

Status: **✅ works** (observed on the phone, source given) · **🟡 partial** ·
**❌ missing** (hardware is known to be there, nothing drives it) · **❓ untested**.
Evidence without a path is from `evidence/2026-09-26-r27/` (the r27 default
install, 2026-09-26, US998).

Last full pass: 2026-09-26 (Ember, Claude-Code:claude-opus-5-5). Rows marked
**(10-07)** were re-measured on 2026-10-06/07 (kernel `b3dc8621`, pmaports
`linux-lg-joan` r55); details in `ember-2026-10-06-venus-and-boot-log.md` and
`ember-2026-10-07-osm-bootlog-ipa.md`.

**Default install status (2026-10-06):** a fresh `pmbootstrap install --no-split --sector-size 512`
(r47) written to the bench SD booted to Phosh with 0 failed units, cellular data connected out of
the box, Venus, FM tuner, sound card and modem present (`docs/handoff-2026-10-06-ember.md`).

**Earlier (2026-09-26):** `pmbootstrap install --no-split --sector-size 512` from
pmaports-lge-joan → microSD → fastboot RAM boot: sshd in 25 s, systemd `running`, 0 failed
units. Blockers found and fixed on the way: 4096-byte image on SD (README), root fs
not grown (postmarketos-initramfs r2). Evidence `evidence/2026-09-26-fresh-install/`.

## SoC, power, thermal

| Block | Part | Status | Notes / next |
|---|---|---|---|
| CPU silver ×4 | Kryo 280, 300–1900.8 MHz | ✅ | OSM + CPRh DVFS; ~1893 MHz measured at max (`r27-dvfs.txt`). |
| CPU gold ×4 | Kryo 280, 300–2361.6 MHz all-core, 2457.6 MHz single-core | ✅ (10-07) | LG's bin-2 1-core rows in the OSM LUT; one busy core runs 2457.6 MHz, four 2361.6 (the rated max). OSM ACD fix keeps the policy on every boot (8/8), survives cluster hotplug. Gold CPR voltages match LG since 8d7f34b0 (interpolate from unclamped fuses; `fulgor-2026-09-26-gold-cpr-fix.md`). |
| CPU speed bins | fuse bin 0–3 | 🟡 | Bins 2/3 only. Other bins fail safe (no DVFS, gold at LK's 300 MHz). LG's bin 0/1 tables are available to port. |
| Scheduler | schedutil, EAS | 🟡 | schedutil on both clusters. EAS still off: msm8998.dtsi has capacity-dmips-mhz but no `dynamic-power-coefficient`. LG's `sched-energy-costs` tables (msm8998.dtsi CPU_COST_0/1) give per-OPP power to fit coefficients against the runtime CPRh voltages; bench item. |
| GPU | Adreno 540, 257–710 MHz | ✅ (10-06) | devfreq 257–710 MHz (= stock max), GLES 3.1, glmark2-es2-drm 119 at 1440×2880. No Vulkan (turnip is a6xx+). DDR stays at the GPU's placeholder vote: a downward DDR step hangs the SoC in our local icc driver, so per-OPP bandwidth is not shipped (power cost only). |
| GPU voltage | pm8005 S1 | 🟡 | r27 uses one phone's CPR floor. Fixed on `joan/bootlog-fixes`: per-part fused open-loop + MEM-ACC. Not yet booted. |
| GPU stability | A540 VM / resume | ❌→🟡 | r27: GPU VM at 2^48 → faults, hangcheck, phoc SEGV (Firefox/YouTube). Fixed on the branch by porthole-dev 0030/0031/0168/0176. Not yet booted. |
| GPU limiter | A540 GPMU | 🟡 | Branch: GPMU throttling on, 5-level table (porthole 0251). Not yet booted. |
| Video codec | Venus (msm8998) | ✅ decode / 🟡 encode (10-06) | H.264/VP9 decode on Venus in GStreamer, FFmpeg (`h264_v4l2m2m`) and Firefox 154 (with the `ffmpeg` override package); 1080p30 at 0.14 core. Encoder asserts the firmware mid-stream, so GStreamer's v4l2h264enc is demoted. HEVC/VP8 untested. |
| Thermal (junction) | tsens | ✅ (10-06) | Core zones passive 85 °C → their cluster, critical 110 °C; GPU 85 °C → GPU devfreq; DRAM (pop_mem) 85/65 °C → gold (LG SS-POPMEM); LMh reliability algorithm on. |
| Thermal (skin) | xo_therm, bd_therm_2 (VTS) | ✅ (10-07) | weighted-adc VTS `skin-thermal` with LG's ladder (37–46 °C → GPU + both clusters) and LG CHG_MONITOR charge steps. LG's charger-attached thermistor offset is not carried over. |
| Battery / fuel gauge | PMI8998 | ✅ | `qcom-battery`, capacity reported. |
| Wired charging | PMI8998 + BQ25898S parallel | ✅ (10-07) | Charging; float voltage 4395 mV (was 4402.5, tripped battery OV). Charge current follows LG's skin steps 2.6/1.5/0.8/0.6 A at 10/40/42/45 °C through the `pmi8998-charger-fcc` cooling device (bound; state 1 at 31 °C). Current at each state not yet measured. msoc-full now reported. |
| Wireless charging | IDT P9223 → PMI8998 DC-IN | ❓ | No P9223 driver in mainline; DC-IN handling needs a Qi-pad test. |
| Storage | UFS 2.1 | 🟡 | Works at ~82 MB/s; stock is about 4× faster (second limiter not yet found). |
| microSD | SDHC | ✅ | pmOS root. |
| RAM | 4 GB | ✅ | |

## Display, input, haptics

| Block | Part | Status | Notes / next |
|---|---|---|---|
| Panel | LG SW43402, 1440×2880 DSC cmd | ✅ | Branch adds porthole 0204 (pageflip at rd_ptr; taimen measured a 30 fps lock without it) and 0210 (encoder lookup; fixes `no encoder found for crtc 0`). |
| Backlight | DSI | ✅ | |
| Touch | ST FTS (fts3670) | ✅ | stmfts 0xba wake-status messages at debug level (LG treats them as debug). |
| Buttons | power, vol ±, headset | ✅ | |
| DisplayPort alt mode | QMP USB3-DP PHY, DP ctrl, SBU mux (TLMM 100/80) | 🟡 | Paused mid-port. See `handoff-2026-09-25-dp-altmode.md`. |
| Vibration | Dongwoon DW7800 (I2C 0-0059) | ❌→fix | Driver already in the tree (50f1b6f7ef38); `CONFIG_INPUT_DW7800_HAPTICS` was never enabled. Enabled on the bench config. |
| Fingerprint | rear sensor (QSEE trustlet on stock) | ❌ | TEE-based on stock; no libfprint path known. |

## Audio

| Block | Part | Status | Notes / next |
|---|---|---|---|
| Stack | PipeWire + WirePlumber, UCM `alsa-ucm-conf-lge-joan` | ✅ | `device-lge-joan` depends on them. |
| Codec | WCD9340 over SLIMbus | ✅/🟡 (10-07) | Works. On 1 of 8 RAM boots the ADSP brought up APR but no QRTR services (no SLIMbus QMI 769), so no sound card; open. |
| Speaker amp | TFA9872 (bound by tfa989x) | ✅ | |
| Hi-Fi DAC | ES9218P | 🟡 | Driver bound. Headset detection root cause: ES9218P bypass (see memory/handoff notes). |
| SoundWire | WCD934x master | ✅ (branch) | No WSA amps on joan. Branch disables the master and restores irq 20 (it was colliding with MBHC). |
| Call audio | callaudiod | ❌ | callaudiod SEGV'd on r27 (2026-09-26). |

## Connectivity

| Block | Part | Status | Notes / next |
|---|---|---|---|
| Modem / data | X16 LTE (MSS) | ✅ | Cellular data auto-connects on a fresh install. Survives `rmnet_ipa0` down/up, airplane mode and a modem restart without a reboot (r57: ef74a2f4 no NAPI BUG, 64e28e86 close aggregation before RX stop, ee468f34 finish a pending stop before start). IPv6-only SIMs get IPv4 through 464XLAT (clatd, `lg-joan-cellular-data` 0.2): back within ~7 s of a reconnect, also across Wi-Fi hand-offs and a modem restart; stands down when the network has native IPv4. A reconnect can leave the new address `dadfailed`; a dispatcher hook rescues it, kernel fix `joan/rmnet-noarp` (IFF_NOARP) verified as a hot-loaded module, in the r59 candidate ([evidence](evidence/2026-10-07-clat-464xlat/results.md)). |
| Calls / SMS | ModemManager + joan-imsd VoLTE | 🟡 | VoLTE work in `joan-volte-lineage` / joan-imsd. |
| GNSS | modem QMI LOC | ❓ | |
| Wi-Fi | WCN3990 (ath10k_snoc) | ✅ | Works; stable MAC from bootmac (serialno). Three read faults at IOVA 0 (SID 0x1900) at firmware boot are harmless (LG maps WLAN IOVAs from 0xa0000000 too). Per-model board data needs per-model DTBs (Lance decision). Does **not** come back after a modem restart (firmware runs on the modem; ath10k logs -108 and never re-inits), and an `ath10k_snoc` reload cannot fix it because rmmod leaves the MSA memory assigned: reboot needed ([evidence](evidence/2026-10-07-clat-464xlat/results.md), 2026-10-07). |
| Bluetooth | WCN3990 (btqca) | 🟡 | Works. Frame reassembly errors (-84). Branch/config adds RFCOMM, BNEP, UHID. |
| FM radio (RX) | WCN3990 FM block, over the BT UART (H4 0x11/0x14) + BT-FM SLIMbus audio | 🟡 | **V4L2 driver done 2026-09-26** (`/dev/radio0`, `radio-qca-fm`, kernel 621a3778bf10 + hci_qca 4a04a4310739): tune 76-108 MHz, seek, signal/stereo, mute, de-emphasis, RDS raw blocks (rds-ctl decodes PI/PTY/PS); v4l2-compliance clean. Headphone cable is the antenna (15 stations with it, 1 marginal without). Needs Bluetooth on. `evidence/2026-09-26-fm-radio-driver/`. Audio path IMPLEMENTED 2026-10-02 (branch joan/btfm-fm-audio): SLIMBUS_7/8 AFE ports (0x400e/0f/0x4011), second msm8998 NGD engine (0x17240000 + BAM 0x17204000), WCN399x btfm-slim codec (FM TX group on PGD ports 1+2, channels 159/160, IFD port regs at 0x800), sdm845 machine BE "FM Capture". Pmaports pkgrel 32 pin ddfaf16673ec CONFIG_SND_SOC_BTFM_SLIM=m. Bench test pending: FM audio route FM TX -> SLIMBUS_8_TX -> ADSP. Still missing: userspace app. Deck #163. |
| FM transmit | — | ❌ (firmware) | Probed 2026-09-26: the transmit command group (OGF 0x14) gets no response while receiver commands on the same link do, so the V30's FM firmware does not offer transmit. No upstream or LG/Qualcomm driver drives FM TX on this chip either. |
| NFC | NXP PN547 (+ eSE) | ✅ | nxp-nci bound; neard (default since device-lge-joan r17) exposes `/org/neard/nfc0`: Felica, MIFARE, Jewel, ISO-DEP, NFC-DEP, ISO-15693; powers on and polls (2026-09-26). Tag read/write not yet tried with a physical tag. eSE unused. |
| USB | DWC3, Type-C (TCPM) | ✅ | Gadget networking, host. |

## Cameras and sensors

| Block | Part | Status | Notes / next |
|---|---|---|---|
| ISP | CAMSS: CSIPHY v5.0.1, CSID, ISPIF, VFE 4.8 | ✅ | porthole-dev's msm8998 CAMSS (own `CAMSS_8998`, gen2 CSIPHY lane table, ISPIF, VFE 4.8 write-master fixes) replaced this tree's untested CAMSS_660 reuse on 2026-09-26, plus the CAMSS TOP GDSC and the CSID `vdd_sec` supply. RDI raw capture runs at 30 fps. Evidence `evidence/2026-09-26-camera/`. |
| Rear main | Sony IMX351 (CCI 5-0010, CSIPHY0 4-lane) | ✅ | Probes and streams. MCLK needed porthole's GPLL0_DIV/2 and MCLK `mnd_width` fixes (it ran at 48 MHz). libcamera (simple pipeline + GPU software ISP) captures 1280x720 at 30 fps; gain helper and measured black level (64 at 10 bit) in pmaports libcamera. Close/reopen SoC reset fixed (sensor powers down at stream-off; `evidence/2026-09-26-camera-reset/`). Upside-down picture fixed (rotation 270, kernel 0e456d986954). Next: lens driver for the ROHM/Renesas AF-OIS controller (protocol in `evidence/2026-09-26-camera-quality/`), LG's colour matrices (candidate tuning there, untested). |
| Rear wide, front | Samsung S5K3M3 13 MP wide (CSIPHY1), Hynix HI553 5 MP front (CSIPHY2), both on CCI1 | ❌ | No V4L2 driver exists anywhere; upstream `s5k3m5` and `hi556` are the templates. Downstream uses the qcom,camera framework, so the register tables live in the vendor libs (`libmmcamera_s5k3m3.so`, `libmmcamera_hi553.so`), to be extracted like the IMX351 CCM was. 2026-09-27 RE (downstream msm8998-joan-camera dtsi): **neither has an actuator — both are fixed focus** (only actuator0 = the rear main's). Front (camera@2): EEPROM 0x50 on CCI1, MCLK2, reset = VT_RESET (tlmm 9?), vdig GPIO pm8998_gpios 9, rails cam_vio pm8998_l6 1.8 V + cam_vana pm8998_l22 2.8 V; needs `rotation = <90>` (LG mount 270). Flash is already wired (PMI8998, both channels, 800 mA each measured). |
| Laser AF | ST VL53L0X (CCI 5-0029) | ✅ | Ranges (`in_distance_raw` x 0.001 m). CCI0 answers only with LVS1 (main camera I/O rail) up, so LVS1 is always-on. Driver gained runtime PM (camera AVDD off between readings, verified). Nothing in userspace reads it yet. |
| SAR proximity | Semtech SX9320 (I2C 3-0028) | ❌ | `sx9324` is built and loaded but does not bind the SX9320; it needs support of its own. |
| Flash LED | PMI8998 flash | ✅ | `white:flash`. |
| Motion / light / proximity | on the SLPI (sensor DSP) | ❌ | Deck #162. SLPI firmware ships in firmware-lge-joan r9. Needs a 15 MiB region and an SMGR-era QMI client. |

## Default apps (pmOS phosh)

| Feature | App | Status |
|---|---|---|
| Calls | gnome-calls | phosh default |
| SMS | chatty | phosh default |
| Sound panel | phosh quick settings + pwvucontrol (per-app) | ✅ default since device-lge-joan r17 |
| Voice recorder | gnome-sound-recorder | ✅ default since device-lge-joan r17 |
| Camera | Snapshot (phosh default, libcamera) | 🟡 libcamera captures from the IMX351; Snapshot on screen not tried yet (needs Lance) |
| FM tuner | none (kernel `/dev/radio0`; CLI `v4l2-ctl`, `rds-ctl`) | 🟡 tuner works; audio needs the slim2 NGD, which hard-hangs the SoC — bench only with Lance present |
| NFC | nfc-tags (GTK4, ours) + neard, D-Bus activated (device-lg-joan r22/r23) | 🟡 adapter, poll loop and UI tested; physical tag read/write untested |
| Flashlight | phosh torch toggle | ✅ (flash LED present) |

## Kernel config (pmaports `linux-lge-joan`)

- Trim to `ARCH_QCOM` (as pmOS sdm845): 1461→971 modules, no Qualcomm symbol lost.
- `kconfigcheck` community: 265 findings → 19 after applying pmOS's rules. 17 of those are "preferably m"; the remaining 2 are `CFI`, which needs a Clang/LLVM build (pmOS sdm845 builds with LLVM).
- Adds: MGLRU, uclamp, FUNCTION_TRACER (systemd BPF LSM), Yama, lockdown LSM (FORCE_NONE), NF_NAT (hotspot), WireGuard, exFAT/F2FS/EROFS, UHID/UINPUT/HID drivers, BT RFCOMM/BNEP, binder (Waydroid).

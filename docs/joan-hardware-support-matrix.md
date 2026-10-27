# LG V30 (joan) hardware support matrix — mainline pmOS

Goal: everything the V30 has works on a default pmaports install. This is the
tracking table. Update it in place and date what changes.

Status: **✅ works** (observed on the phone, source given) · **🟡 partial** ·
**❌ missing** (hardware is known to be there, nothing drives it) · **❓ untested**.
Evidence without a path is from `evidence/2026-09-26-r27/` (the r27 default
install, 2026-09-26, US998).

Last full pass: 2026-09-26 (Ember, Claude-Code:claude-opus-5-5). Cellular RX stall row updated 2026-10-09 (Aurel, Hermes:grok-4.7); see evidence/2026-10-09-ipa-rx-stall. Rows marked
**(10-07)** were re-measured on 2026-10-06/07 (kernel `b3dc8621`, pmaports
`linux-lg-joan` r55); details in `ember-2026-10-06-venus-and-boot-log.md` and
`ember-2026-10-07-osm-bootlog-ipa.md`.

**Kernel 7.3 (2026-10-09, Ember, Claude-Code:claude-opus-5-5):** mainline v7.3-rc6 merged into
the joan line (`joan/latest-clean-test`), qrtr HELLO-on-register (544d85de, in mainline since
7.3-rc2) reverted. `linux-lg-joan` 7.3.0_rc6 r0/r1 RAM-boot from the on-device boot.img with no
failed units and no new kernel warnings against r60. Rows marked **(10-09)** were measured on it;
evidence in `evidence/2026-10-09-v73-port/`.

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
| CPU gold ×4 | Kryo 280, 300–2361.6 MHz all-core, 2457.6 MHz single-core | ✅ (10-09) | LG's bin-2 1-core rows in the OSM LUT; one busy core runs 2457.6 MHz, four start at 2361.6 (the rated max) and step down only at the 85 °C passive trip (measured on 7.3: 2361.6 → 2323.2 → 2265.6 MHz as the hottest zone reaches 85 °C). OSM ACD fix keeps the policy on every boot (8/8). CPRh open-loop adjustments now LG's msm8998-v2 values (7 corners had been 4 mV low, kernel b6a566087bd8). No LG frequency cap remains on bin 2: 1900.8/2361.6/2457.6 are the hardware table maxima. |
| CPU scheduler (EAS) | Energy Model from LG/Qualcomm sched-energy-costs | ✅ (r60) | schedutil + asymmetric capacity-dmips-mhz were in place but no Energy Model registered (no OPP power data), so EAS was off. Kernel 7732a4cd245a (`joan/cpu-energy-model`) adds `opp-microwatt` to all 53 CPU OPPs from the stock busy-cost tables (`tools/em-from-stock-costs.py`); c77bb2415e75 registers it via `.register_em` (else "EM: Access to CPUFreq policy failed" and no inefficient-OPP marking). Verified on r60 (10-07): EM cpu0 22 / cpu4 31 states, 5/8 marked inefficient, `sched_energy_aware=1`. |
| CPU speed bins | fuse bin 0–3 | 🟡 (10-10) | LG's gold tables for every bin now (kernel 49d0331d..c342d9cb): bin 0 to 2496.0 all-core / 2592.0 single-core, bin 1 to 2208.0 / 2304.0, bins 2/3 as before; per-bin CPRh adjustments and LG's per-corner voltage ceilings. On this bin-2 phone the frequency tables and all CPR corner voltages read back identical to before (r5). Bin 0/1 need a phone with those fuses to verify. Unknown bins still fail safe. |
| Scheduler | schedutil, EAS | 🟡 | schedutil on both clusters. EAS still off: msm8998.dtsi has capacity-dmips-mhz but no `dynamic-power-coefficient`. LG's `sched-energy-costs` tables (msm8998.dtsi CPU_COST_0/1) give per-OPP power to fit coefficients against the runtime CPRh voltages; bench item. |
| GPU | Adreno 540, 257–710 MHz | ✅ (10-06) | devfreq 257–710 MHz (= stock max), GLES 3.1, glmark2-es2-drm 119 at 1440×2880. No Vulkan (turnip is a6xx+). DDR stays at the GPU's placeholder vote: a downward DDR step hangs the SoC in our local icc driver, so per-OPP bandwidth is not shipped (power cost only). |
| GPU voltage | pm8005 S1 (VDD_GFX), pm8998 S9 (VDD_MX) | ✅ (10-10) | VDD_GFX: fused open-loop + MEM-ACC; regulator max the stock 1088 mV (27dc01c8). VDD_MX: the GPU now votes MX per OPP like the vendor kernel (SVS ≤414, NOM 515/596, TURBO 670/710; kernel 3eff7f0f/ccf8b6ba): bench shows the GPU's MX device at 384 (TURBO) at 710 MHz and 0 when suspended, GX collapses, glmark2 166, no faults. S9 stays at 896 mV under the vote (other RPM masters already hold MX there). |
| GPU stability | A540 VM / resume | ❌→🟡 | r27: GPU VM at 2^48 → faults, hangcheck, phoc SEGV (Firefox/YouTube). Fixed on the branch by porthole-dev 0030/0031/0168/0176. Not yet booted. |
| GPU limiter | A540 GPMU | 🟡 | Branch: GPMU throttling on, 5-level table (porthole 0251). Not yet booted. |
| Video codec | Venus (msm8998) | ✅ decode / 🟡 encode (10-09) | H.264/VP9 decode on Venus in GStreamer, FFmpeg (`h264_v4l2m2m`) and Firefox 154 (with the `ffmpeg` override package); 1080p30 at 0.14 core. On 7.3: 300/300 frames of 1080p30 H.264 through `h264_v4l2m2m` at 194 fps (6.5× realtime). Encoder asserts the firmware mid-stream, so GStreamer's v4l2h264enc is demoted. HEVC/VP8 untested. |
| Thermal (junction) | tsens | ✅ (10-06) | Core zones passive 85 °C → their cluster, critical 110 °C; GPU 85 °C → GPU devfreq; DRAM (pop_mem) 85/65 °C → gold (LG SS-POPMEM); LMh reliability algorithm on. |
| Thermal (skin) | xo_therm, bd_therm_2 (VTS) | ✅ (10-09) | weighted-adc VTS `skin-thermal` with LG's ladder (37–46 °C → GPU + both clusters) and LG CHG_MONITOR charge steps. Gold caps re-indexed for the 2457.6 MHz row (they had been one OPP too loose: 2035.2/1804.8/1132.8/806.4 instead of stock 1958.4/1728/1056/729.6; kernel 3352a3e51381). LG's charger-attached thermistor offset is not carried over. |
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
| DisplayPort alt mode | QMP USB3-DP PHY, DP ctrl, SBU mux (TLMM 100/80) | 🟡 (10-10) | Ported (kernel 9d99d011..65405bda, in r5): PHY matched to LG's mdss-dp-pll-8998 (AUX power-up, power-down register, swing, lane order), USB3/DP lane hand-over instead of -EBUSY, lane map [2 3 1 0], flipped plug via phy_validate, own DP OPPs, AUX switch as gpio-sbu-mux, connector altmode svid 0xff01, TYPEC_MUX_GPIO_SBU=y. USB gadget/Type-C unchanged on r5 and the three DP PHY boot warnings are gone. **Needs a USB-C DP/HDMI adapter to test.** |
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
| Modem / data | X16 LTE (MSS) | ✅ | Cellular data auto-connects on a fresh install. Survives `rmnet_ipa0` down/up, airplane mode and a modem restart without a reboot (r57: ef74a2f4 no NAPI BUG, 64e28e86 close aggregation before RX stop, ee468f34 finish a pending stop before start). IPv6-only SIMs get IPv4 through 464XLAT (clatd, `lg-joan-cellular-data` 0.2): back within ~7 s of a reconnect, also across Wi-Fi hand-offs and a modem restart; stands down when the network has native IPv4. A reconnect can leave the new address `dadfailed`; a dispatcher hook rescues it, kernel fix `joan/rmnet-noarp` (IFF_NOARP) verified as a hot-loaded module, in the r59 candidate ([evidence](evidence/2026-10-07-clat-464xlat/results.md)). **Boot-time RX stall (10-07, r60):** in 5 of 6 consecutive RAM boots the bearer came up (ModemManager `connected`, NetworkManager `activated`) but the mux received almost nothing (rx 1-22 vs tx 90-133 packets) and IPv6 never worked (checked to 600 s; `nmcli` reconnect does not help); a modem remoteproc restart brought IPv6 back in 35 s, so the carrier is fine and the boot-time IPA/modem start-up ordering is the suspect. Same seen once on r57 (12:59). Across 16 r60 boots on 10-07 it stalled on 10. An `rmnet_ipa0` bounce is NOT a remedy (fixed 1 stall, then 0 of 6, automatic and manual). A modem restart restored data once on 10-07 (35 s) and killed Wi-Fi until reboot. **2026-10-09 retest (Aurel, Hermes:grok-4.7):** two more r60 RAM boots both stalled, including one that attached at 38.1 s, so the late-attach correlate did not hold. On the second stall a modem stop/start did **not** restore downlink (new mux, new IPv6, gateway ping 0/5); the stop logged five `GSI_CH_STOP` timeouts on channel 8 and `error -11` stopping endpoint 16, and the sound card disappeared. ath10k logged recovered. Evidence: `evidence/2026-10-09-ipa-rx-stall/README.md`. Not yet root-caused. |
| Calls / SMS | ModemManager + joan-imsd VoLTE | 🟡 | VoLTE work in `joan-volte-lineage` / joan-imsd. |
| GNSS | modem QMI LOC | ❓ | |
| Wi-Fi | WCN3990 (ath10k_snoc) | ✅ | Works; stable MAC from bootmac (serialno). Three read faults at IOVA 0 (SID 0x1900) at firmware boot are harmless (LG maps WLAN IOVAs from 0xa0000000 too). Per-model board data needs per-model DTBs (Lance decision). Does **not** come back after a modem restart (firmware runs on the modem; ath10k logs -108 and never re-inits), and an `ath10k_snoc` reload cannot fix it because rmmod leaves the MSA memory assigned: reboot needed ([evidence](evidence/2026-10-07-clat-464xlat/results.md), 2026-10-07). Disconnect hang fixed by the ath10k pairwise delete-key-wait opt-out (r60: 3/3 connect/disconnect, no ath10k errors). |
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
| Rear wide | Samsung S5K3M3 13 MP wide (CCI1 0x2d, CSIPHY1 4-lane, MCLK1 GPIO 14) | 🟡 (10-09) | New driver `s5k3m3` (kernel 4db14f5f2f90, DT 568161b079f1; based on upstream s5k3m5, register lists from LG's `libmmcamera_s5k3m3.so`). Probes (chip ID 0x30d3), streams 1040x584 at 120 fps and 2080x1560 through CSIPHY1/CSID1; a torch-lit raw frame shows the scene; raw orientation is the main camera's +180°, matching rotation 90 vs 270. Bayer order (GRBG) and colour need a lit scene. |
| Front | Hynix HI553 5 MP (BLSP2 I2C 4-0020, CSIPHY2 **2-lane**, MCLK2 GPIO 15) | 🟡 (10-09) | **Streams** 2560x1920 RAW10 at 30 fps (6,144,000-byte frames); the sensor colour-bar test pattern arrives full-scale through CSIPHY2 → CSID0 → VFE. Fix (kernel c8789cfeea9e): LG runs it on **2 lanes** (lib lane_cnt 2, settle 0x11 at 0xb1af8 — the earlier "4 lanes" reading of LaneMask 0x1F was wrong) at 440/220 MHz, and LG's full sequence (pre-init 0e00/0e02/0e0c, SRAM, 110-entry init, 36-entry mode lists) is now written unchanged. Also fixed: its MCLK pin state had silently merged with the wide camera's (dtc merges same-named nodes; GPIO 15 overrode 14), which broke the wide camera (c8c46a8b66c8). Exposure in a lit scene still to check. |
| Laser AF | ST VL53L0X (CCI 5-0029) | ✅ | Ranges (`in_distance_raw` x 0.001 m). CCI0 answers only with LVS1 (main camera I/O rail) up, so LVS1 is always-on. Driver gained runtime PM (camera AVDD off between readings, verified). Nothing in userspace reads it yet. |
| SAR proximity | Semtech SX9320 (I2C 3-0028) | ❌ | `sx9324` is built and loaded but does not bind the SX9320; it needs support of its own. |
| Flash LED | PMI8998 flash | ✅ | `white:flash`. |
| Motion / light / proximity | on the SLPI (sensor DSP): LSM6DSM-class accel/gyro, AK09916 mag, LPS22HB-class baro, TMD4904 prox/light (LG sensor_def_*.conf) | 🟡 (10-10) | **SLPI boots** (`slpi_v2.mdt`, 15 MiB carve-out, kernel fd1e2507) and announces QRTR services on node 9 (263/264/280/288/306 + registry notification + SSCTL). Sensors still need: an SMGR-era registry server (sns-reg) fed from LG's .conf / the phone's own sns.reg, and the unmerged QRTR-bus + Sensor Manager IIO series (Yassine Oudjana, 2025). Plan in `evidence/2026-10-09-v73-port/README.md`. Deck #162. |

## Default apps (pmOS phosh)

| Feature | App | Status |
|---|---|---|
| Calls | gnome-calls | phosh default |
| SMS | chatty | phosh default |
| Sound panel | phosh quick settings + pwvucontrol (per-app) | ✅ default since device-lge-joan r17 |
| Voice recorder | gnome-sound-recorder | ✅ default since device-lge-joan r17 |
| Camera | Snapshot (phosh default, libcamera) | 🟡 (10-09) libcamera lists all three cameras (two back, one front). LG chromatix colour matrices extracted for all three (tuning files staged, untested in light); Snapshot on screen, colour and autofocus need Lance |
| FM tuner | FM Radio (`fm-radio`, ours, GTK4, default since device-lg-joan r27) + kernel `/dev/radio0` | 🟡 (10-09) app tunes, seeks (found 88.9 MHz) and decodes RDS on 7.3; says plainly that there is no sound path yet: audio needs the slim2 NGD, which hard-hangs the SoC — bench only with Lance present |
| NFC | nfc-tags (GTK4, ours) + neard, D-Bus activated (device-lg-joan r22/r23) | 🟡 adapter, poll loop and UI tested; physical tag read/write untested |
| Flashlight | phosh torch toggle | ✅ (flash LED present) |

## Kernel config (pmaports `linux-lge-joan`)

- Trim to `ARCH_QCOM` (as pmOS sdm845): 1461→971 modules, no Qualcomm symbol lost.
- `kconfigcheck` community: 265 findings → 19 after applying pmOS's rules. 17 of those are "preferably m"; the remaining 2 are `CFI`, which needs a Clang/LLVM build (pmOS sdm845 builds with LLVM).
- Adds: MGLRU, uclamp, FUNCTION_TRACER (systemd BPF LSM), Yama, lockdown LSM (FORCE_NONE), NF_NAT (hotspot), WireGuard, exFAT/F2FS/EROFS, UHID/UINPUT/HID drivers, BT RFCOMM/BNEP, binder (Waydroid).

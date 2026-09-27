# LG V30 (joan) hardware support matrix — mainline pmOS

Goal: everything the V30 has works on a default pmaports install. This is the
tracking table. Update it in place and date what changes.

Status: **✅ works** (observed on the phone, source given) · **🟡 partial** ·
**❌ missing** (hardware is known to be there, nothing drives it) · **❓ untested**.
Evidence without a path is from `evidence/2026-09-26-r27/` (the r27 default
install, 2026-09-26, US998).

Last full pass: 2026-09-26 (Ember, Claude-Code:claude-opus-5-5).

**Default install status (2026-09-26):** `pmbootstrap install --no-split --sector-size 512` from
pmaports-lge-joan → microSD → fastboot RAM boot: sshd in 25 s, systemd `running`, 0 failed
units. Blockers found and fixed on the way: 4096-byte image on SD (README), root fs
not grown (postmarketos-initramfs r2). Evidence `evidence/2026-09-26-fresh-install/`.

## SoC, power, thermal

| Block | Part | Status | Notes / next |
|---|---|---|---|
| CPU silver ×4 | Kryo 280, 300–1900.8 MHz | ✅ | OSM + CPRh DVFS; ~1893 MHz measured at max (`r27-dvfs.txt`). |
| CPU gold ×4 | Kryo 280, 300–2361.6 MHz | 🟡 | 2357 MHz measured; LMh 1120/1136 mV. Missing: single-core boost rows to 2457.6 MHz; LMh IRQ → cpufreq. |
| CPU speed bins | fuse bin 0–3 | 🟡 | Bins 2/3 only. Other bins fail safe (no DVFS, gold at LK's 300 MHz). LG's bin 0/1 tables are available to port. |
| Scheduler | schedutil, EAS | 🟡 | schedutil is the default (pmOS TuneD `balanced` picks it). No EAS energy model (no `dynamic-power-coefficient`). |
| GPU | Adreno 540, 257–710 MHz | 🟡 | Works, but r27 hangs under GL load (see GPU row below). |
| GPU voltage | pm8005 S1 | 🟡 | r27 uses one phone's CPR floor. Fixed on `joan/bootlog-fixes`: per-part fused open-loop + MEM-ACC. Not yet booted. |
| GPU stability | A540 VM / resume | ❌→🟡 | r27: GPU VM at 2^48 → faults, hangcheck, phoc SEGV (Firefox/YouTube). Fixed on the branch by porthole-dev 0030/0031/0168/0176. Not yet booted. |
| GPU limiter | A540 GPMU | 🟡 | Branch: GPMU throttling on, 5-level table (porthole 0251). Not yet booted. |
| Video codec | Venus (msm8998) | ❌→🟡 | Driver supports it; firmware now in firmware-lge-joan r9; DT enabled on the branch. Not yet booted. |
| Thermal (junction) | tsens | ✅/🟡 | Zones and cpufreq/GPU cooling work. Branch moves CPU trips 75→85 °C, GPU 80→85 °C (LG stock). |
| Thermal (skin) | xo_therm, bd_therm_2 (VTS) | ❌→🟡 | Branch: weighted-adc-thermal VTS + LG's skin caps. Not yet booted. |
| Battery / fuel gauge | PMI8998 | ✅ | `qcom-battery`, capacity reported. |
| Wired charging | PMI8998 + BQ25898S parallel | ✅ | `pmi8998-charger` charging. Skin-based charge current (LG: 1.5/0.8/0.6 A) needs `CHARGE_CONTROL_LIMIT` in the drivers. |
| Wireless charging | IDT P9223 → PMI8998 DC-IN | ❓ | No P9223 driver in mainline; DC-IN handling needs a Qi-pad test. |
| Storage | UFS 2.1 | 🟡 | Works at ~82 MB/s; stock is about 4× faster (second limiter not yet found). |
| microSD | SDHC | ✅ | pmOS root. |
| RAM | 4 GB | ✅ | |

## Display, input, haptics

| Block | Part | Status | Notes / next |
|---|---|---|---|
| Panel | LG SW43402, 1440×2880 DSC cmd | ✅ | Branch adds porthole 0204 (pageflip at rd_ptr; taimen measured a 30 fps lock without it) and 0210 (encoder lookup; fixes `no encoder found for crtc 0`). |
| Backlight | DSI | ✅ | |
| Touch | ST FTS (fts3670) | ✅ | Recurring `stmfts error code 0x00dec000d0ba`; `stmfts_set_power` has no prototype (W=1). |
| Buttons | power, vol ±, headset | ✅ | |
| DisplayPort alt mode | QMP USB3-DP PHY, DP ctrl, SBU mux (TLMM 100/80) | 🟡 | Paused mid-port. See `handoff-2026-09-25-dp-altmode.md`. |
| Vibration | Dongwoon DW7800 (I2C 0-0059) | ❌→fix | Driver already in the tree (50f1b6f7ef38); `CONFIG_INPUT_DW7800_HAPTICS` was never enabled. Enabled on the bench config. |
| Fingerprint | rear sensor (QSEE trustlet on stock) | ❌ | TEE-based on stock; no libfprint path known. |

## Audio

| Block | Part | Status | Notes / next |
|---|---|---|---|
| Stack | PipeWire + WirePlumber, UCM `alsa-ucm-conf-lge-joan` | ✅ | `device-lge-joan` depends on them. |
| Codec | WCD9340 over SLIMbus | 🟡 | Boot log: SLIMbus QMI timeout, `no backend DAIs`. porthole 0076-0104 carry wcd934x/SLIMbus fixes — review first. |
| Speaker amp | TFA9872 (bound by tfa989x) | ✅ | |
| Hi-Fi DAC | ES9218P | 🟡 | Driver bound. Headset detection root cause: ES9218P bypass (see memory/handoff notes). |
| SoundWire | WCD934x master | ✅ (branch) | No WSA amps on joan. Branch disables the master and restores irq 20 (it was colliding with MBHC). |
| Call audio | callaudiod | ❌ | callaudiod SEGV'd on r27 (2026-09-26). |

## Connectivity

| Block | Part | Status | Notes / next |
|---|---|---|---|
| Modem / data | X16 LTE (MSS) | ✅ | `rmnet_ipa0`. |
| Calls / SMS | ModemManager + joan-imsd VoLTE | 🟡 | VoLTE work in `joan-volte-lineage` / joan-imsd. |
| GNSS | modem QMI LOC | ❓ | |
| Wi-Fi | WCN3990 (ath10k_snoc) | 🟡 | Works. SMMU faults on SID 0x1900 at iova 0 at bring-up. `invalid MAC address; choosing random`. firmware-lge-joan r9 adds the proper WCN3990 board data. |
| Bluetooth | WCN3990 (btqca) | 🟡 | Works. Frame reassembly errors (-84). Branch/config adds RFCOMM, BNEP, UHID. |
| FM radio (RX) | WCN3990 FM block, over the BT UART (H4 0x11/0x14) + BT-FM SLIMbus audio | 🟡 | **Tuner verified 2026-09-26** without an antenna: finds a station at 90.3 MHz (-91 dBm, SINR +7..+10) and gets RDS sync lock (`evidence/2026-09-26-fm-rx/`). Protocol = Qualcomm iris FM HCI. Missing: V4L2 radio driver, audio path (2nd SLIMbus, BT-FM codec, DSP routing). Deck #163. |
| FM transmit | — | ❌ (firmware) | Probed 2026-09-26: the transmit command group (OGF 0x14) gets no response while receiver commands on the same link do, so the V30's FM firmware does not offer transmit. No upstream or LG/Qualcomm driver drives FM TX on this chip either. |
| NFC | NXP PN547 (+ eSE) | ✅ | nxp-nci bound; neard (default since device-lge-joan r17) exposes `/org/neard/nfc0`: Felica, MIFARE, Jewel, ISO-DEP, NFC-DEP, ISO-15693; powers on and polls (2026-09-26). Tag read/write not yet tried with a physical tag. eSE unused. |
| USB | DWC3, Type-C (TCPM) | ✅ | Gadget networking, host. |

## Cameras and sensors

| Block | Part | Status | Notes / next |
|---|---|---|---|
| ISP | CAMSS: CSIPHY v5.0.1, CSID, ISPIF, VFE 4.8 | ✅ | porthole-dev's msm8998 CAMSS (own `CAMSS_8998`, gen2 CSIPHY lane table, ISPIF, VFE 4.8 write-master fixes) replaced this tree's untested CAMSS_660 reuse on 2026-09-26, plus the CAMSS TOP GDSC and the CSID `vdd_sec` supply. RDI raw capture runs at 30 fps. Evidence `evidence/2026-09-26-camera/`. |
| Rear main | Sony IMX351 (CCI 5-0010, CSIPHY0 4-lane) | ✅ | Probes and streams. MCLK needed porthole's GPLL0_DIV/2 and MCLK `mnd_width` fixes (it ran at 48 MHz). libcamera (simple pipeline + GPU software ISP) captures 1280x720 at 30 fps; gain helper and measured black level (64 at 10 bit) in pmaports libcamera. Close/reopen SoC reset fixed (sensor powers down at stream-off; `evidence/2026-09-26-camera-reset/`). Next: AF actuator and OIS, colour calibration. |
| Rear wide, front | Samsung S5K3M3 13 MP wide (CSIPHY1), Hynix HI553 5 MP front (CSIPHY2), both on CCI1 | ❌ | Identified from LG's sensor libraries (`libmmcamera_s5k3m3.so`, `libmmcamera_hi553.so`). No V4L2 driver exists anywhere; upstream `s5k3m5` and `hi556` are the templates, LG's libraries the register source. Not in DT yet. |
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
| Camera | Snapshot (phosh default, libcamera) | 🟡 libcamera captures from the IMX351; Snapshot on screen not tried yet |
| FM tuner | TBD | blocked on FM driver |
| NFC | neard daemon (enabled by preset); no GUI tag app in Alpine yet | 🟡 |
| Flashlight | phosh torch toggle | ✅ (flash LED present) |

## Kernel config (pmaports `linux-lge-joan`)

- Trim to `ARCH_QCOM` (as pmOS sdm845): 1461→971 modules, no Qualcomm symbol lost.
- `kconfigcheck` community: 265 findings → 19 after applying pmOS's rules. 17 of those are "preferably m"; the remaining 2 are `CFI`, which needs a Clang/LLVM build (pmOS sdm845 builds with LLVM).
- Adds: MGLRU, uclamp, FUNCTION_TRACER (systemd BPF LSM), Yama, lockdown LSM (FORCE_NONE), NF_NAT (hotspot), WireGuard, exFAT/F2FS/EROFS, UHID/UINPUT/HID drivers, BT RFCOMM/BNEP, binder (Waydroid).

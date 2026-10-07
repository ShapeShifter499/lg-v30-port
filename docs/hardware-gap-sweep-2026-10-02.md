# Hardware gap sweep — LG V30 (joan) vs the mainline port, 2026-10-02

Written-by: Fulgor Nymvale (agent-fulgor-zcode)
Agent-harness: ZCode:GLM-5.3-Flash
Date: 2026-10-02
Scope: completeness sweep only. Read-only; nothing built, nothing
flashed, the in-progress merge in
`linux-mainline-v30-ember-bootlog` was not touched (all dts reads via
`git show <branch>:<path>`).

Purpose: enumerate **every** device node the downstream joan device
tree instantiates and cross each against the support matrix, the
mainline joan dts, and the pmaports kernel config. Status labels:

- **WORKING** — observed on the phone (matrix cites evidence)
- **WIRED-UNTESTED** — DT node + driver/config exist, no bench result yet
- **KNOWN-BROKEN** — wired, but the matrix/evidence records a defect
- **NOT-WIRED** — hardware exists downstream, no DT node in the port
- **NO-DRIVER-ANYWHERE** — no mainline driver; (downstream driver status noted)
- **N/A (SKU)** — not fitted / not enabled on the US998-class boards (JP/KR extras, disabled nodes)

Downstream ground truth is the LG/LineageOS kernel at
`~/vibe-coding-projects/coding/android_kernel_lge_msm8998`, joan dts
under `arch/arm64/boot/dts/lge/` (top files:
`msm8998-joan-sensor.dtsi`, `msm8998-joan-touch-stm-ftm4.dtsi`,
`msm8998-fingerprint-fpc1022.dtsi`, battery dtsi
`LGE_BLT34_LGC_3300mAh.dtsi`; per-variant trees under
`msm8998-joan/msm8998-joan_{acg,att,nao,spr,tmo,vzw,kr,dcm_jp,kddi_jp,global_*}/`).
The bench phone (US998) corresponds to the `acg_us` variant: its
top-level `msm8998-joan_acg_us_rev-*.dts` pulls
`../../qcom/msm8998-v2.1.dtsi` + the per-block dtsi, and the variant
sub-dtsi files only include the `msm8998-joan-common/` equivalents
(verified by reading every `msm8998-joan_acg_us-*.dtsi`); `nao_us` and
`acg_us` differ only in the battery/pkm extras, so the common files are
the definitive list for US998.

Mainline reference: `linux-mainline-v30-ember-bootlog`, branch
`joan/btfm-fm-audio` (2026-10-02, tip `89e9162796a5`; contains the
`joan/bootlog-fixes` work and the FM-audio series). DTS read with
`git show joan/btfm-fm-audio:arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`.
The `latest-clean-test-synced` dts is the older minimal one (UFS/USB/SD/
panel/wifi only); everything below that cites the btfm-fm-audio dts.

Kernel config: `pmaports-lg-v30-clean/device/testing/linux-lge-joan/config-lge-joan.aarch64`
(pmaports pkgrel 32 pins `CONFIG_SND_SOC_BTFM_SLIM=m` at `ddfaf16673ec`;
branch tip is one commit ahead — `89e9162796a5` "fixes from review" —
the matrix pin is slightly stale).

---

## 1. Full hardware inventory and classification

### 1.1 SoC core, storage, USB, connectivity

| # | Block / part | Downstream DT (path) | Mainline status | Evidence / notes |
|---|---|---|---|---|
| 1 | UFS 2.1 + ICE (`ufs1`, `ufsphy1`, `ufs_ice`) | `msm8998-joan_acg_us.dtsi` (status ok, supplies pm8998 l20/l26/s4) | WORKING | Matrix "Storage": ~82 MB/s vs ~4x stock (second limiter unfound) — perf gap, not a wiring gap |
| 2 | microSD (`sdhc_2`, cd tlmm 40) | `msm8998-joan_acg_us.dtsi` | WORKING | pmOS root medium |
| 3 | USB3 + DWC3 + Type-C TCPM (`usb3`, `qusb_phy0`, `ssphy`, `pmi8998_pdphy`) | `msm8998-joan-common-usb.dtsi` (SBU sel/oe/edge GPIOs tlmm 11/16/42, moisture detect via VADC) | WORKING | gadget net + host; `TYPEC_QCOM_PMIC=y` in config |
| 4 | DisplayPort alt mode (QMP USB3-DP PHY, `mdss_dp_ctrl`, aux/sel tlmm 100/80, plug cc 38) | `msm8998-joan_acg_us.dtsi` (`&mdss_dp_ctrl` pinctrl) | WIRED-UNTESTED | Branch has the full redo: `99cbb5c0bf43` (drm/msm/dp msm8998), `c05291b66de3` (DT enable), `f08d8c5f0da9` + `36ba6e40f034` + `5371fb3501ae` (qmp-usbc DP half), `e6e796df38f4` (mmcc DP clocks) — all confirmed ancestors of `joan/btfm-fm-audio`. Matrix row (2026-09-26 pass) predates this; `handoff-2026-09-25-dp-altmode.md` says "nothing has been booted" |
| 5 | WiFi WCN3990 (`wifi@18800000`, `qcom,wcn3990-wifi`) | `qcom/msm8998.dtsi` node; joan enables `&wifi` | WORKING (🟡) | SMMU faults at bring-up, random MAC fixed by firmware-lge-joan r9 board data (matrix) |
| 6 | BT WCN3990 (`bt_wcn3990`, `qca,wcn3990` on `blsp1_uart3_hs`) | `msm8998-joan-common-connectivity.dtsi` (5 rail supplies) | WORKING (🟡) | frame reassembly -84; RFCOMM/BNEP/UHID added |
| 7 | FM receiver (WCN3990 FM block, BT UART H4 0x11/0x14) | — (no DT in downstream; hci_qca channel) | WIRED-UNTESTED (RX) | V4L2 `radio-qca-fm` done + bench-verified 2026-09-26 (`621a3778bf10`, `evidence/2026-09-26-fm-radio-driver/`); **audio path implemented 2026-10-02 on `joan/btfm-fm-audio`** (second NGD `slimbam2`/`slim2`, `slim@3` `slim217,220`, SLIMBUS_7/8 AFE ports, BTFM_SLIM codec) — **bench test FM TX→SLIMBUS_8_TX→ADSP pending**; no GUI tuner app exists in Alpine |
| 8 | FM transmit | — | NO-DRIVER-ANYWHERE (and firmware) | Matrix: OGF 0x14 gets no response; no driver exists upstream or in LG/Qualcomm trees. Treat as dead end |
| 9 | Modem MSS X16 + IPA (`remoteproc_mss`, ipa) | `qcom/msm8998.dtsi` | WORKING (data) | VoLTE = userspace (joan-imsd, matrix 🟡) |
| 10 | GNSS (modem QMI LOC) | — (no GNSS node anywhere in downstream joan dts or qcom dtsi — verified by grep) | NOT-WIRED (userspace only) | Nothing kernel-side needed; ModemManager QMI-LOC never tested on the bench. Matrix row ❓ |
| 11 | SLPI remoteproc (`remoteproc_slpi@5800000`, `qcom,msm8998-slpi-pas`) | downstream `pil_slpi_mem` reserved in `common-pm.dtsi` line 604 | NOT-WIRED | Upstream soc dtsi node exists but `status = "disabled"` (verified at `latest-clean-test-synced` msm8998.dtsi:1661-1690) and the joan dts only adjusts `&slpi_mem`, never enables it. Firmware ships in firmware-lge-joan r9. Gates all of §1.5 sensors |
| 12 | PCIe0 / WIL6210 WiGig | `msm8998-joan_acg_us.dtsi`: `&pcie0 status disabled`, `&wil6210 status disabled` | N/A (SKU) | LG ships them off on joan |
| 13 | Venus video codec | `qcom/msm8998-vidc.dtsi` | WIRED-UNTESTED | driver + firmware r9 + DT on branch; last bench pass used `modprobe.blacklist=venus_*` (`handoff-2026-09-26-fm-camera-bench.md`) |

### 1.2 Display / input / haptics

| # | Block | Downstream DT | Mainline status | Notes |
|---|---|---|---|---|
| 14 | Panel LG SW43402 DSC cmd (`dsi-panel-sw43402-*.dtsi`) | `msm8998-joan-common-panel.dtsi` | WORKING | matrix; porthole 0204/0210 on branch |
| 15 | Backlight (DSI DCS, `bl_ctrl_dcs`) | `msm8998-joan-common-panel.dtsi` | WORKING | PMI WLED node exists but `status = "disabled"` (`common-pm.dtsi` line 181 `qcom,qpnp-wled`) — correctly unused |
| 16 | Touch ST FTS (`stm,ftm4` + `stm,ftm4_fts`) | `msm8998-joan-touch-stm-ftm4.dtsi` | WORKING (🟡) | mainline `st,fts3670` @ blsp1_i2c5 addr 0x49; recurring `0x00dec000d0ba` errors |
| 17 | Buttons: power (`pm8998_pwrkey`), vol- (`pm8998_resin`), vol+ (gpio-keys, pm8998 gpio 6) | `msm8998-joan-common-misc.dtsi` + acg_us | WORKING | |
| 18 | Vibration Dongwoon DW7800 (`dw7800@59` on i2c_1; a second disabled placeholder node `vibrator@fd8c3420`) | `msm8998-joan-common-misc.dtsi` lines 32/39 | WIRED-UNTESTED | mainline dts `haptics@59` `dongwoon,dw7800`; driver `50f1b6f7ef38` + `CONFIG_INPUT_DW7800_HAPTICS=m` (config line 3564); matrix says enabled on bench config, boot test pending |
| 19 | Hall IC / flip cover | only in `msm8998-joan_dcm_jp/msm8998-joan_dcm_jp_rev-1_*.dts` (`hall_ic` gpio-keys) | N/A (SKU) | Japan DCM variant only; no hall node in acg_us/common |
| 20 | Fingerprint FPC1022 rear (`fpc,fpc1020`) | `msm8998-fingerprint-fpc1022.dtsi` (included from acg_us-fingerprint) | NO-DRIVER-ANYWHERE (for us) | stock drives it via QSEE trustlet; no mainline fpc1022-on-joan path, needs TEE; matrix ❌ |

### 1.3 Audio

| # | Block | Downstream DT | Mainline status | Notes |
|---|---|---|---|---|
| 21 | WCD9340 "Tavil" codec over SLIMbus NGD (`qcom,tavil`/swr-wcd under slim) | `msm8998-joan-common-sound.dtsi` (machine `qcom,msm8998-asoc-snd-tavil`) | WORKING (🟡) | SLIMbus QMI timeout / "no backend DAIs" recorded in matrix; porthole 0076-0104 fixes on branch |
| 22 | ES9218P quad DAC (`dac,es9218-codec@48` on i2c_1) | `common-sound.dtsi` line 185 | WIRED/WORKING (🟡) | mainline `ess,es9218p` headphone-dac@48 on blsp1_i2c1; headset-detect root cause = bypass; fix `d00fb16818b7` (idle in LP bypass) on branch — untested |
| 23 | TFA9872 speaker amp (`nxp,tfa98xx` on i2c_7) | `common-sound.dtsi` line 197 | WORKING | mainline `nxp,tfa9872` @ blsp2_i2c1 addr 0x34 |
| 24 | WSA881x SoundWire amps | `common-sound.dtsi` lines 254-275 (`qcom,wsa881x` ×4) | N/A (SKU) | matrix: joan has no WSA amps; branch disables the SWR master and restores irq 20 |
| 25 | CPE/LSM voice wakeup (`qcom,msm-cpe-lsm` ×2) | `common-sound.dtsi` lines 173/178 | NOT-WIRED | no mainline machine wiring; value = hotword/voice wake only — low priority |
| 26 | FM audio route (WCN3990 btfm-slim → ADSP) | downstream `qcom,btfmslim_slave` node + `drivers/bluetooth/btfm_slim*.c` | WIRED-UNTESTED | implemented 2026-10-02 (`8f1f1fa3bf28`, `8d8118eb5a24`, `a9c4283dadda`, `c0313655b07a`, `ddfaf16673ec`, `89e9162796a5`; plan `docs/fm-audio-path-port-plan.md`); bench pending |
| 27 | Secondary mic / camcorder mic | — (audio routing only, no separate device node) | (with audio stack) | covered by UCM `alsa-ucm-conf-lge-joan` if routed there |

### 1.4 Cameras, flash, laser AF

| # | Block | Downstream DT (`msm8998-joan-camera/msm8998-joan-camera_rev_0.dtsi`) | Mainline status | Notes |
|---|---|---|---|---|
| 28 | CAMSS ISP (CSIPHY/CSID/ISPIF/VFE) | `qcom/msm8998-camera.dtsi` | WORKING | porthole CAMSS_8998; RDI raw 30 fps (`evidence/2026-09-26-camera/`) |
| 29 | Rear main Sony IMX351 (`qcom,camera@0`, CSIPHY0, CCI master 0) | camera dtsi lines ~370-460 | WORKING | `sony,imx351` @ cci_i2c0 0x10; rotation fixed; close/reopen reset fixed |
| 30 | AF/OIS controller ROHM BU24235 (LGIT module, 7-bit 0x3e) | `qcom,ois@0` + `qcom,actuator@0` nodes | WIRED-UNTESTED | `46b21fdddb26` adds `rohm,bu24235` lens@3e with firmware-download protocol (`evidence/2026-09-26-camera-quality/README.md`); declines Renesas units; libcamera has no autofocus algorithm yet |
| 31 | AF/OIS controller Renesas variant (7-bit 0x24) | same nodes, runtime-selected by EEPROM 0x0be2 | NO-DRIVER-ANYWHERE (mainline) | protocol documented in `evidence/2026-09-26-camera-quality/README.md`; module-dual-source lottery |
| 32 | Module EEPROM main (0x54 CCI m0, raw) | `qcom,eeprom@0` | WIRED (raw read) | bu24235 reads EEPROM itself; calibration DAC limits not yet decoded |
| 33 | Laser AF ST VL53L0X (`qcom,proxy@29`) | camera dtsi line ~293 | WORKING | mainline `st,vl53l0x` proximity@29; **no userspace consumer yet** (matrix) |
| 34 | Rear wide Samsung S5K3M3 (`qcom,camera@2`, CSIPHY1, CCI master 1, eeprom2) | camera dtsi lines ~524-600 | NO-DRIVER-ANYWHERE | no V4L2 driver anywhere; register tables in `libmmcamera_s5k3m3.so`; upstream s5k3m5 as template; fixed focus (no actuator node) |
| 35 | Front Hynix HI553 (`qcom,camera@1`, CSIPHY2, eeprom1 @0x50 on i2c_8, MCLK2, VT_RESET tlmm 9, cam_vio l14/vio + l22 vana) | camera dtsi lines ~448-520 | NO-DRIVER-ANYWHERE | tables in `libmmcamera_hi553.so`; upstream hi556 template; needs `rotation = <90>` |
| 36 | Dual rear flash (PMI8998 flash0/1 + torch + switch, `qcom,camera-flash`) | camera dtsi line 243 | WORKING | mainline `&pmi8998_flash`; 800 mA/channel measured; flashlight works |
| 37 | Notification RGB LED (`qcom,leds-qpnp` rgb) | `common-pm.dtsi` line 175 | N/A (SKU) | `status = "disabled"` downstream — V30 has no RGB LED |

### 1.5 Sensors (the SLPI island)

Downstream has **no I2C sensor nodes for motion/light/proximity** on
joan — the only per-sensor dtsi is `msm8998-joan-sensor.dtsi` (SX9320)
plus the camera-adjacent VL53L0X. `drivers/sensors/sensors_ssc.c` is
the Snapdragon-Sensor-Core (SLPI) client, which is where accel/gyro/
mag/ALS/prox live. That makes the SLPI remoteproc the single gate.

| # | Block | Downstream DT | Mainline status | Notes |
|---|---|---|---|---|
| 38 | Accel + gyro (SLPI/SSC; legacy `drivers/input/sensors/bmi160`,`smi130` dirs are for other LG boards) | none (SLPI) | NOT-WIRED / NO-DRIVER-ANYWHERE | needs #11 SLPI boot + an `sensors_ssc`-equivalent (QMI SMGR client) or SUID; Deck #162 |
| 39 | Magnetometer | none (SLPI) | NOT-WIRED | same gate |
| 40 | Ambient light / proximity (non-SAR) | none (SLPI) | NOT-WIRED | same gate; gates auto-brightness |
| 41 | SAR proximity Semtech SX9320 (I2C `c1b5000` addr 0x28, irq tlmm 62) | `msm8998-joan-sensor.dtsi` (full `Semtech,reg-init` byte table, 50+ registers) | WIRED / KNOWN-BROKEN | mainline dts `proximity@28` has fallback `semtech,sx9324`, but `drivers/iio/proximity/sx9324.c` of_match table only has `semtech,sx9324` and the SX9320 register map differs; matrix ❌ ("does not bind"). Downstream reg-init data is a ready-made init table. Smallest sensor win that does NOT need the SLPI |
| 42 | Barometer | — | N/A (SKU) | no baro node anywhere in joan dts |
| 43 | Thermal: junction (tsens) | `qcom/msm8998.dtsi` | WORKING | |
| 44 | Thermal: skin ADC (xo_therm 0x4c w 370, bd_therm_2 0x51 w 480, vts, led_sensor, battery, vcoin 0x85) | `common-pm.dtsi` lines 73-133, 187+ | WIRED-UNTESTED | branch `weighted-adc-thermal` VTS + LG skin caps (matrix ❌→🟡); adc channels 0x4c/0x4f/0x50/0x51 in mainline dts |

### 1.5b Power / battery

| # | Block | Downstream DT | Mainline status | Notes |
|---|---|---|---|---|
| 45 | Battery data BLT34 LGC 3300 mAh (`lge_batterydata`, batt_id resistor 100k) | `common-pm.dtsi` lines 477-489 incl. `LGE_BLT34_LGC_3300mAh.dtsi` | (informational) | mainline uses `simple-battery`; per-profile charge tables not carried |
| 46 | Fuel gauge PMI8998 FG | `&pmi8998_fg` (`common-pm.dtsi` line 488) | WORKING | `qcom-battery`, capacity reported |
| 47 | Charger PMI8998 + parallel | `&pmi8998_charger` line 407 | WORKING | skin-based charge-current limits (CHARGE_CONTROL_LIMIT) still missing (matrix) |
| 48 | Mid/parallel charger TI BQ25898S (`bq25898s@6B` on i2c_7, irq tlmm 119) | `msm8998-joan_acg_us.dtsi` | WIRED | mainline `ti,bq25898s`→`ti,bq25890` fallback @ blsp2_i2c1 0x6b; matrix counts charging ✅ |
| 49 | Parallel charger QCOM SMB1381 (`qcom,smb138x-parallel-slave` on SPMI, `msm-smb138x.dtsi`; LG pincfg `common-pm.dtsi` line 483) | same | NOT-WIRED / NO-DRIVER-ANYWHERE | no smb138x driver in mainline tree (git grep empty) and no node; downstream `drivers/power/supply/qcom/smb138x*`. Only limits peak charge current |
| 50 | Qualcomm Qnovo adaptive charging (`&pmi8998_qnovo`) | `common-pm.dtsi` line 510 | NOT-WIRED | no mainline qnovo; battery-health feature, low priority |
| 51 | Wireless charging IDT P9223 (`idtp9223-charger@61` on i2c_1, irq tlmm 24, enable pmi8998_gpio 9, FOD 0x79) | `common-pm.dtsi` lines 363-380 + acg_us-pm FOD override | NOT-WIRED / NO-DRIVER-ANYWHERE (mainline) | downstream driver `drivers/power/idtp9223-charger.c` exists and is self-contained (I2C + power_supply); mainline port = modernize + DT |
| 52 | LG veneer-psy / gpio-debug / pkm / monitor-thermal frameworks | `common-pm.dtsi` various | N/A | LG HAL glue; functionality re-implemented elsewhere |

### 1.6 NFC, misc

| # | Block | Downstream DT | Mainline status | Notes |
|---|---|---|---|---|
| 53 | NFC NXP PN547 (+eSE) (`pn547@28` on i2c_6, ven tlmm 12, irq 116) | `msm8998-joan_acg_us-nfc.dtsi` | WORKING | nxp-nci + neard; tag R/W with a physical tag not yet tried (matrix) |
| 54 | eSE (in PN547) | — | N/A | unused on stock |
| 55 | IR blaster | — | N/A (SKU) | no node anywhere (V30 has none, unlike V20) |
| 56 | MHL/HDMI out | `msm8998-joan_acg_us-hdmi.dtsi` is **empty** | N/A (SKU) | DP alt mode (row 4) is the only wired video-out |
| 57 | ISDB-T / T-DMB mobile TV | `joan_dcm_jp-*-isdbt.dtsi`, `joan_kr-*-tdmb.dtsi` | N/A (SKU) | JP/KR only |
| 58 | Console UART blsp2_uart1 | acg_us.dtsi | WORKING | bench lifeline |

---

## 2. NOT-WIRED / NO-DRIVER-ANYWHERE summary (the real gap list)

| Item | What exists | Difficulty | One-line recommendation |
|---|---|---|---|
| Motion/gyro/mag/ALS/prox sensors (SLPI/SSC) | upstream SLPI remoteproc node ready, firmware in firmware-lge-joan r9, downstream `drivers/sensors/sensors_ssc.c` as protocol reference | LARGE (remoteproc enable + PM for SLPI is the easy half; a QMI SMGR/SSC sensor client is the real project) | Gate everything else: enable `remoteproc_slpi` on the bench first and see what the glink "dsps" edge offers before designing the client |
| SX9320 SAR proximity | wired dts node + downstream reg-init table (`msm8998-joan-sensor.dtsi`) + sx9324 driver as a close cousin | SMALL-MEDIUM (extend sx9324 with SX9320 differences or make a small dedicated driver; reg-init is given) | First pure-kernel sensor win; do before touching SLPI |
| Wide S5K3M3 + front HI553 cameras | vendor register tables in `libmmcamera_s5k3m3.so` / `libmmcamera_hi553.so` (extraction recipe proven with IMX351 CCM), upstream s5k3m5/hi556 driver templates, downstream dtsi gives rails/MCLK/reset GPIOs per sensor | MEDIUM (per sensor; extraction + new i2c driver + DT; no actuator on either) | One at a time: HI553 (front) first for video calls — highest user value |
| GNSS | nothing needed in kernel; ModemManager speaks QMI LOC | SMALL (test-only) | Bench-test `mmcli --location-enable` on the current branch; it may already work |
| Wireless charging IDT P9223 | downstream `drivers/power/idtp9223-charger.c` (~self-contained I2C driver) | SMALL-MEDIUM (modernize to power_supply + DT + a Qi pad to test) | Port opportunistically; needs hardware on the bench to verify |
| SMB1381 parallel charge | downstream `smb138x` driver family | MEDIUM, low value (charging already ✅ via PMI8998+BQ25898S) | Defer until fast-charge current becomes a complaint |
| Fingerprint (FPC1022, QSEE trustlet) | TEE-only path; no mainline fpc driver usable | VERY LARGE (needs TEE/qsee handoff or full RE) | Park; revisit if a qsee/userspace TEE path appears for other joan parts |
| Renesas AF/OIS variant | full protocol documented in `evidence/2026-09-26-camera-quality/README.md` (0x24, no firmware download) | SMALL once bu24235 is bench-proven | Extend the lens driver with the Renesas path — unit-lottery means half the phones need it |
| CPE/LSM voice wake | downstream cpe-lsm wiring | MEDIUM, low value | Skip unless hotword is wanted |
| FM TX | firmware does not offer it (matrix, probed) | N/A | Dead end — documented, do not retry |
| Qnovo | downstream only | MEDIUM | Skip |

### Already wired but with pending bench items (not gaps, but keep on the radar)

- FM RX audio path (`joan/btfm-fm-audio`, tip `89e9162796a5`): bench FM TX→SLIMBUS_8_TX→ADSP route + userspace tuner app.
- DW7800 haptics: first boot test of `CONFIG_INPUT_DW7800_HAPTICS=m`.
- DP alt mode: full stack on branch (`99cbb5c0bf43`…), never booted (`handoff-2026-09-25-dp-altmode.md`).
- ES9218P LP-bypass headset-detect fix (`d00fb16818b7`), Venus un-blacklisted, weighted-adc skin thermal, GPU VM/GPMU fixes — all "not yet booted" per matrix + `cpu-gpu-audit-2026-10-02.md`.
- BU24235 AF driver + libcamera CCM candidate (`evidence/2026-09-26-camera-quality/`).

---

## 3. Prioritized "next to wire" shortlist (user-visible value vs effort)

1. **SX9320 SAR proximity** — small driver delta with init data in hand; enables screen-off-in-call and pocket detection; independent of the SLPI.
2. **GNSS bench test** — possibly zero code; unblocks navigation if QMI LOC just works.
3. **HI553 front camera** — video calls; extraction recipe and templates exist; medium but well-trodden.
4. **S5K3M3 wide camera** — same recipe, second pass after HI553.
5. **SLPI sensors program** — the big one (auto-rotate, auto-brightness, fitness); start by booting SLPI and listing the glink/QMI surface; do the SX9320 first because it is not behind this gate.
6. **Renesas lens variant** — small extension of the freshly landed bu24235 driver; makes autofocus universal across unit lottery.
7. **IDT P9223 wireless charging port** — bounded port of an existing driver; niche but self-contained.
8. **Fingerprint** — parked; only revisit with a real TEE plan.

Plus two pending-bench finishes that convert WIRED-UNTESTED into WORKING before any new wiring: the FM audio route (+ a tiny CLI/GUI tuner) and DP alt mode.

### Cross-cutting notes

- The joystick of variant data: `nao_us`/`tmo_us`/`vzw` variants add `pkm.dtsi` (`lge-pkm-drv`) and slightly different battery/panel picks; nothing there changes the US998 gap list.
- `msm8998-joan-sensor.dtsi` is not included by `acg_us` — the SX9320 node it defines was transcribed into the mainline dts by hand (mainline `proximity@28`), so keep the reg-init table from that file as the authoritative data.
- The downstream `vibrator@fd8c3420` node (misc.dtsi) is a disabled placeholder; `dw7800@59` on i2c_1 is the real one — mainline wired the right one.
- Everything else downstream (cpr-info, veneer-psy, monitor-thermal, gpio-debug, pkm) is LG framework glue with no direct mainline equivalent needed.

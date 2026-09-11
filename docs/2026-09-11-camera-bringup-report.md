# Report: joan camera bring-up — RE findings and ordered plan (2026-09-11)

Investigation: Fulgor (ZCode:zai-coding-plan/GLM-5.3), Explore agent, 2026-09-11.
STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port.

## 0. Headline — the port map was already acted on

`docs/msm8998-camss-port-map.md` (2026-08-15, "nothing built or booted") has
been implemented: commit **`4dd87de5e58d` "media: qcom: camss: add msm8998
support"** (Lance, 2026-08-16) is in the mainline tree:

- `camss.c:5995` — `{ .compatible = "qcom,msm8998-camss", .data = &msm8998_resources }`.
- `camss.c:5837-5846` — resources: `.version = CAMSS_660`, own `csiphy_res_8998`
  (845-902), `csid_res_8998` (909-1005, `csid_ops_4_7`), `vfe_res_8998`
  (1010+, `vfe_ops_4_8`, line_num=3, has_pd=true), reuses `ispif_res_660`.
- CSIPHY at `0x0ca34000/5000/6000`, no clk_mux reg, no `csiphy_ahb2crif`, no
  `throttle_axi` — the four documented sdm660 deltas, all applied. VFE rates
  480/576/600 MHz; CSID csi_src 274.29 MHz; CSIPHY timer 200 MHz.

**Status: committed, NOT probed, and there is still no DT node**
(`camss.c:841-843` says so explicitly). Upstream Linux has no
`qcom,msm8998-camss` (lore/patchwork verified; kernel docs list no 8998);
pmOS Snapdragon 835 page lists camera "Untested" for all 16 devices.
`CONFIG_VIDEO_QCOM_CAMSS=m` is already in the pmaports config (line 5708) —
the module builds and silently fails to probe without a DT node.

## 1. joan's image sensors

| Slot | Sensor | Confidence |
|---|---|---|
| camera@0, csiphy0/csid0, CCI master 0, rear main | **Sony IMX351** 16 MP f/1.6, OIS (ROHM BU24235) + AF + EEPROM + flash + ST laser-AF proxy (VL53L0(x), addr 0x29) | **Verified 3 ways**: downstream `ois/lgit_imx351_rohm_ois.c` (header "17-07-21, 13M LGIT OLAF OIS bu24235", FW bins `bu24235_dl_program_Joan_LGITAct_ICG1020S_rev*.bin`, LGE-only Makefile); DPReview/DXOMark V30 rear = IMX351 |
| camera@2, csiphy1/csid1, CCI master 1, rear tele | **Samsung S5K3M3** 13 MP, fixed focus (no actuator/OIS node — only eeprom2 + flash) | Inferred; appears on msm8998 SKUK reference sensor list; settle by first-boot chip-ID read |
| camera@1, csiphy2/csid2, **not on CCI** — BLSP i2c@c1b6000, reg 0x28, front | **SK Hynix HI-553** 5 MP | Corroborated: LG G6 (lucy) front node literally `hi553` on same SoC; namu.wiki V30 ThinQ front = Hi-553; addr 0x28 matches Hi-5xx alt slave addr (Hi-556W datasheet). Front EEPROM msm_eeprom at 0x50 same bus |

Rear eeprom0 fronts the LDAF enable GPIO and feeds the BU24235 firmware
download (OIS driver reads cal data at 0xA90/0xAC2/0xBE2).

## 2. Mainline CAMSS msm8998 vs sdm660/sdm845

In-tree and correct for msm8998: CSIPHY `csiphy_ops_3ph_1_0` (with the
CAMSS_660 special case, `camss-csiphy-3ph-1-0.c:1077`), CSID 4.7, ISPIF v3.0
via ispif_res_660 (msm8998 HAS csi_clk_mux at 0xca00020 per stock dtb0:6485),
VFE 4.8 with vbif. Formats reuse `*_8x96` tables.

Open:
- **No DT node** — template is `sdm630.dtsi:2025-2147` minus the four deltas.
- **IOMMU stream IDs** — the single hard DT gap. msm8998 mmss SMMU is
  `arm,smmu-mmss@cd00000` (qcom,smmu-v2); downstream allocates camera context
  banks dynamically (msm_dma_iommu_mapping.c) so no SIDs exist in any DT.
  Start from sdm630's 0xc00–0xc03 as hypothesis; ctx faults reveal true SIDs.
- **Power domains**: `camss_configure_pd` needs ≥2 PDs with has_pd; sdm630
  shape `power-domains = <&mmcc CAMSS_VFE0_GDSC>, <&mmcc CAMSS_VFE1_GDSC>`;
  mmcc-msm8998 has camss_top_gdsc (0x34a0), vfe0 (0x3664), vfe1 (0x3674).
- **CCI**: mainline `i2c-qcom-cci.c:824` `qcom,msm8996-cci` (cci_v2_data) is
  the right generation; msm8998 CCI at 0xca0c000, 2 masters, tlmm 17-20
  (stock dtb0:6569+). CONFIG_I2C_QCOM_CCI=m already set. No node yet.
- **No TPG** for this generation — first capture needs a real sensor subdev.

## 3. Sensor drivers

In-tree: no imx351.c, no s5k3m3.c, no hi553.c. Nearest templates: imx355.c
(same Sony generation), s5k3m5.c, hi556.c (Hi-5xx family). Downstream LG
ships NO kernel sensor drivers — register tables live in userspace blobs
(`libmmcamera_*.so` via msm_sensor_init ioctl). So nothing to port from the
joan kernel; init tables must come from vendor userspace blobs (Standing
Approval applies), sibling vendor kernels that DO ship sensor drivers
(Xiaomi sagit/Mi 6 tele = S5K3M3), or datasheet-style RE. The kernel-side
`lgit_imx351_rohm_ois.c` IS a complete BU24235 firmware-download +
control implementation — reusable as-is.

## 4. Power / clock / GPIO wiring (joan-camera dtsi + dtb0)

MCLKs all 24 MHz (tlmm 13/14/15 = MCLK0/1/2).

| Rail | Rear main (cam0) | Rear tele (cam2) | Front (cam1) |
|---|---|---|---|
| cam_vio | pm8998_lvs1 | pm8998_l6 1.8 V | pm8998_l14 1.8 V |
| cam_vana | pm8998_gpios 8 "CAM0_AVDD" (load switch) | tlmm 39 + `bob_vreg-supply = <&pmi8998_bob>` | pm8998_l22 2.8 V |
| cam_vdig | pm8998_gpios 20 "CAM0_VDIG" | tlmm 21 "CAM1_DVDD" | pm8998_gpios 9 "VT_VDIG" |
| reset | tlmm 30 "CAM0_RESET" (+tlmm 25 LDAF_EN) | tlmm 28 "CAM1_RESET" | tlmm 9 "VT_RESET" |
| AF/OIS | VAF = pm8998_gpios 7; tlmm 23 "CAM0_OIS_RESET" | none | none |
| I2C | CCI master 0 (tlmm 17/18) | CCI master 1 (tlmm 19/20) | BLSP i2c@c1b6000 |

Mainline joan dts already defines the regulators under RPM naming
(vreg_s3a_1p35, vreg_l6a_1p8, vreg_l14a_1p88, vreg_bob, L22/LVS1 in the
regulator block). CCI/MCLK pinctrl states do not exist in msm8998.dtsi yet —
author from stock DTB pinctrl (cam_sensor_mclk{0,1,2}_active, dtb0:11708+).
Front camera needs the i2c@c1b6000 node enabled in joan dts.

## 5. Sibling research

No msm8998 device has working cameras (pmOS wiki: 835 page camera
"Untested"; Mi 6 no camera work; OnePlus 5T "Broken"; JamiKettunen's OP5
README lists IMX398/350/376K/371 unimplemented; msm8998-mainline gitlab
orgs: none). Closest sibling success, same methodology one SoC back:
Yassine Oudjana (emainline), "A first photo on mainline Linux", Mi Note 2
(msm8996, IMX318) — sensor driver from scratch on the imx214 pattern with
register tables from Jetson Nano + MediaTek kernels; power-up sequence from
`msm_camera_power_up` in the LOS msm8996 kernel; capture via media-ctl
csiphy0→csid0→ispif0→vfe0_rdi0, SRGGB10, v4l2-ctl + 10-bit unpack. msm8996
also uses ISPIF — pipeline shape matches joan. Methodology ref:
gitlab.com/sdm845-mainline/camera-porting. No Halium/UT joan camera work.

## 6. Ordered bring-up plan

1. **CAMSS DT node** in msm8998.dtsi from the sdm630 template with the four
   deltas; `power-domains = <&mmcc CAMSS_VFE0_GDSC>, <&mmcc CAMSS_VFE1_GDSC>`;
   iommus starting at sdm630's 0xc00-0xc03 (hypothesis — ctx faults will
   reveal true SIDs).
2. **Probe milestone**: boot; expect CSIPHY HW version read ("CSIPHY 3PH HW
   Version", expect 0x501-class) + media-ctl enumerating 3 CSIPHY, 4 CSID,
   ISPIF, 2 VFE, video nodes. Proves the CAMSS_660 inference on hardware.
3. **CCI + pinctrl**: cci@ca0c000 (qcom,msm8996-cci), clocks per stock
   dtb0:6577-6581, tlmm 17-20 + cam_mclk 13/14/15 pinctrl. `i2cdetect` on
   cci-i2c0/1 discovers IMX351, BU24235, eeprom, and the tele sensor
   (S5K3M3 expected 0x2d) — verifies the tele ID for free.
4. **First CSI capture (rear main)**: imx351.c on the imx355 pattern; power
   order from joan-camera dtsi + OIS driver sequence; link-freq RE'd from
   `libmmcamera_imx351.so` in the vendor image; endpoint→csiphy0→csid0→
   ispif→vfe0_rdi0; v4l2-ctl raw SRGGB10.
5. **Tele**: same pipeline on csiphy1/CCI1; check Xiaomi sagit kernel for a
   portable s5k3m3.c first.
6. **Front**: enable i2c@c1b6000; hi553.c on the hi556 pattern; 2-lane
   endpoint on csiphy2.
7. **Userspace**: raw-first (v4l2-ctl/qcam); gen1 CAMSS (ISPIF era) is NOT
   covered by libcamera's simple pipeline handler — expect raw workflows
   before any phone-style stack; ISP tuning open as in the Mi Note 2 case.

**Hard RE remaining**: (a) camss SMMU stream IDs, (b) IMX351/Hi-553 register
init tables (vendor userspace blobs best source), (c) per-module link
frequencies/lane counts, (d) S5K3M3 confirmation by chip-ID read.

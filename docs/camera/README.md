# Camera — wiring, sensor tables and mainline status (2026-09-24)

Kernel work is on `linux-lg-v30-joan` branch `claude/lucid-dijkstra-bxx3r9`
(PR #11). **Nothing here has been booted yet**; everything is build- and
schema-tested only.

## What is in the kernel branch

| Piece | Commit | State |
|---|---|---|
| CCI binding (`qcom,msm8998-cci`) | `50968bf919f` | new |
| CAMSS binding (`qcom,msm8998-camss.yaml`) | `ca297e4588b` | new, derived from sdm660 |
| CAMSS CSID supplies (vdda L2 1.2 V, vdd_sec L1) | `2178c66d9bf` | fixes the port's "supplies are all GDSCs" claim, which was wrong |
| msm8998.dtsi CAMSS + CCI nodes | `42a602e8916` | addresses, IRQs, SMMU IDs (0xc00–0xc03) from downstream `msm8998-camera.dtsi` |
| joan: CAMSS + CCI enabled | `ab6661d3304` | first hardware check: `media-ctl -p` shows the CSIPHY/CSID/ISPIF/VFE graph |
| `sony,imx351` binding + `imx351` driver | `397b3fd7591`, `ec331df89c5` | two modes: 4656x3492@30 (660 MHz link) and 2328x1744@30 binned (330 MHz) |
| joan: main camera + rear flash | `f1b0aecf422` | IMX351 on CCI0/CSIPHY0; flash on PMI8998, both channels ganged |

Hardware test order: (1) `media-ctl -p` topology; (2) imx351 probes and reads
chip ID 0x0351; (3) test pattern (`v4l2-ctl -d /dev/v4l-subdevN
-c test_pattern=2`) through CSIPHY0 → CSID0 → ISPIF → VFE RDI; (4) real frames.
Most likely things to adjust: the Bayer order (driver assumes RGGB; LG's lists
never flip) and the analogue gain maximum (960 assumed).

## Joan camera wiring (LG `msm8998-joan-camera_rev_0.dtsi`)

| | Main (camera@0) | Wide (camera@2) | Front (camera@1) |
|---|---|---|---|
| Sensor | Sony IMX351 | Samsung S5K3M3 | Hynix HI553 |
| Control bus | CCI master 0, addr 0x10 (7-bit) | CCI master 1 | BLSP2 I2C2 (`i2c_8`, 0xc1b6000), LG `reg = <0x28>` |
| CSI | CSIPHY0 / CSID0, 4 lanes | CSIPHY1 / CSID1 | CSIPHY2 / CSID2 |
| MCLK | MCLK0, TLMM 13 | MCLK2, TLMM 14 | MCLK1, TLMM 15 |
| Reset | TLMM 30 | TLMM 28 | TLMM 9 |
| I/O rail | LVS1 (1.8 V) | L6 | L14 (1.8 V) |
| Analog rail | LDO via PM8998 GPIO 8 | LDO via TLMM 39 | L22 (2.8 V) |
| Digital rail | LDO via PM8998 GPIO 20 | LDO via TLMM 21 | LDO via PM8998 GPIO 9 |
| Other | AF supply PM8998 GPIO 7, OIS reset TLMM 23, laser-AF enable TLMM 25 | BOB | — |
| Mount angle | 90 | 90 | 270 |

Rear flash: PMI8998 flash channels 0+1 together (LG: 800 mA each, 500 ms).

## Where the sensor settings come from

Qualcomm's mm-camera2 keeps every sensor's register settings in userspace,
in `/vendor/lib/libmmcamera_<sensor>.so`, not in the kernel. On the US998 30b
firmware (`US99830b.zip` → `system.img`, raw ext4, vendor inside system) they
were pulled with `debugfs -R "dump /vendor/lib/libmmcamera_imx351.so ..."`.

Layout (32-bit libs): each list is a `camera_i2c_reg_setting_array` — a fixed
array of 3000 `{u16 addr; u16 data; u32 delay;}` entries, zero-terminated and
zero-padded, followed by a 16-byte trailer (`addr_type` 2 = 16-bit addresses,
`data_type` 1 = 8-bit data). The count field is 0, so lists end at the first
all-zero entry. `tools/sensordump.py` finds and prints every list;
`tables/*.txt` are its output, `tables/SHA256SUMS` identifies the libraries.

IMX351 also yielded: 8-bit slave address 0x20 (7-bit 0x10), chip ID 0x0351 at
0x0016, 24 MHz INCK (`0x0136 = 0x18`), and the output table (104-byte
entries at 0xb3540: width, height, line/frame length, op_pixel_clk, binning,
min/max fps as doubles). LG's library carries no power sequence; LG's kernel
builds it from the DT GPIOs.

| IMX351 mode | Size | LLP x FLL | Link (total) | fps |
|---|---|---|---|---|
| 0 | 4656x3492 | 6032 x 3560 | 5280 Mbps (4 x 1320) | 30.17 |
| 1 | 4656x2620 | 6032 x 2688 | 4080 Mbps | 29.9 |
| 2 | 2328x1744 (2x2 bin) | 6032 x 2780 | 2640 Mbps | 30.05 |
| 4/5 | 2328x1312 | 3220 x 2600/1384 | 3996/4236 Mbps | 60.2/120.6 |
| 6 | 2020x1136 | 2896 x 1208 | 6768 Mbps | 240.1 |

S5K3M3: one 17-entry init list and seven 42/43-entry mode lists (Samsung
parts often load most of their setup through indirect 0x6028/0x602A/0x6F12
writes — check whether more is hidden before writing its driver). HI553:
three ~1020-entry init lists and ten mode lists. Nearest mainline drivers to
start from: `s5k3m5.c` and `hi556.c` (siblings, not drop-in).

Also in the firmware, for later: `libactuator_renesascl.so` and
`libactuator_bu24333gwl.so` (lens actuators / OIS), and the module EEPROM
libraries `libmmcamera_imx351_m24c64m_eeprom.so`,
`libmmcamera_s5k3m3_brcb032gwz_eeprom.so`, `libmmcamera_hi553_brcf016gwz_eeprom.so`.

Assisted-by: Claude-Code:Claude Opus 5.5
Date: 2026-09-24

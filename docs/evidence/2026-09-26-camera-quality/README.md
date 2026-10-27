# 2026-09-26: main camera shows upside down and looks poor

Lance tested the r30 default install: the picture was flipped and the
quality was low. Three separate causes; one fixed, two with the facts
needed to fix them.

## Upside down: fixed (kernel 0e456d986954)

LG's device tree gives camera@0 (IMX351) `qcom,mount-angle = <90>`. That
is Android's sensor orientation, measured clockwise. The DT `rotation`
property and libcamera's `Rotation` are measured anticlockwise
(libcamera's own Android layer converts with `(360 - rotation) % 360`),
so LG's 90 is `rotation = <270>`. Ours said 90, which turns the picture
the wrong way by 180 degrees.

LG's IMX351 register tables (`libmmcamera_imx351.so`, 8-byte
`{u16 addr, u16 data, u32 delay}` entries, found around 0xf278) never
write the orientation register 0x0101, so the sensor reads out
unflipped on stock too and the mount angle carries over unchanged.

Checked on bench kernel bl17: `cam -p` reports `Rotation = 270`. Not yet
checked by eye in an app.

The front camera (camera@1, HI553, no driver yet) has mount angle 270,
so it will need `rotation = <90>`.

## Colour: candidate tuning, not yet tested

Our SoftISP tuning (`temp/libcamera/imx351.yaml`, r5) has black level,
grey-world AWB, gamma/contrast and AGC, but no colour correction matrix,
so colours are the sensor's raw primaries.

LG's ISP tuning `libchromatix_imx351_preview.so` (identical in both
SGCMarkus vendor trees in `/data/models/joan-stock`, sha256 starts
60c1240c677d882f) holds the colour correction at file offset 0x7764: nine
entries of 44 bytes (nine floats, two zero words), preceded by CCT
triggers 2400-2550, 3100-3300, 4300-4500 and 8000-9000 K. Only four are
distinct; one of those is exactly 0.9 x another + 0.1 x identity (a
desaturated low-light copy). The other three, placed by strength:

| CT | Matrix (rows) |
|---|---|
| 2856 K (A, strongest) | 1.8256 -0.9652 0.1397 / -0.2079 1.2506 -0.0424 / -0.0491 -1.3725 2.4216 |
| 4000 K (TL84) | 1.8041 -0.8873 0.0832 / -0.2731 1.3270 -0.0539 / -0.0505 -0.8616 1.9121 |
| 6500 K (D65, weakest) | 1.7199 -0.7524 0.0325 / -0.1651 1.3173 -0.1522 / -0.0140 -0.8976 1.9115 |

The illuminant assignment is inferred, not read from a struct
definition. `imx351-ccm-candidate.yaml` here is the tuning file with a
`Ccm` block; the same change sits uncommitted in the pmaports worktree.
libcamera 0.7.2's GPU debayer applies the combined AWB x CCM matrix
(`debayer_egl.cpp`), and the simple IPA's AWB feeds the CCM a colour
temperature. Test with `tools/bench/camq.sh` (stock vs
`LIBCAMERA_SIMPLE_TUNING_FILE`) and `tools/bench/ppm2png.py` before
packaging.

## Focus: needs a lens driver (next big camera item)

We never drive the lens, so it rests wherever its spring holds it. The
IMX351 module is dual-sourced; LG's kernel decides at runtime from the
module EEPROM (CCI master 0, 7-bit 0x54): map version at 0x0BE2 of 0x01
or 0x02 means the Renesas controller, anything else the LG Innotek
module with a ROHM controller. Neither has a mainline driver.

Sources: LG kernel `drivers/media/platform/msm/camera_v2/sensor/ois/
lgit_imx351_rohm_ois.c`, `msm_ois_i2c.c`, `actuator/msm_actuator.c`
(LineageOS/android_kernel_lge_msm8998); vendor
`libactuator_bu24333gwl.so`, `libactuator_renesascl.so`.

ROHM (LG's code names it BU24235; the actuator library says bu24333gwl),
7-bit 0x3e, 16-bit registers:
1. poll 0x6024 until it reads 1;
2. write 0xF010 = 0 (start download);
3. write `bu24235_dl_program_Joan_LGITAct_ICG1020S_revN_S_data1.bin`
   (824 bytes) at 0x0000 and `..._data2.bin` (448 bytes) at 0x1C00, six
   bytes per I2C write; revision by EEPROM cal version at 0x0AC2:
   0xA9E9 rev0, 0x0101 rev3, 0x0301 rev5 (firmware in the vendor tree
   under `vendor/firmware/`, sizes match);
4. read the 32-bit big-endian checksum at 0xF008 (rev0 0x14555, rev3
   0x14AB9, rev5 0x14523);
5. copy EEPROM calibration 0x0A90..0x0AA9 and 0x0AAC..0x0AC1 (48 bytes)
   to 0x1DC0;
6. write 0xF006 = 0 (download complete), poll 0x6024;
7. if 0x6020 != 1 write 1, poll; write 0x60F1 = 2 (VCM init); for cal
   versions 0x0101/0x0301 write 0x6023 = 0, poll;
8. focus: 16-bit write to 0x612E (signed DAC; LG maps its steps between
   EEPROM infinity and macro DAC values).

Renesas, 7-bit 0x24: no firmware download. Init: 0x0060 = 0 (AF off),
0x0000 = 0 (OIS off), poll 0x0001 until 1; boundaries from 0x04CC/0x04CE
(byte-swapped, then 4096 - value); 0x0430 = 1, 0x0431 = 1, 0x0495 = 9;
closed loop: 0x0061 = 0 (servo on). Focus: byte-swapped 16-bit target to
0x0062. Closed/open loop from EEPROM 0x0BE2.

Both are powered by the sensor's power-up (LG's DT gives the OIS and
actuator nodes no rails of their own), so probe them while the IMX351
streams. `tools/bench/ccichk.sh` does that read-only (EEPROM map/cal
version, one status register at each address); it was staged but not
run yet.

Even with a lens driver, libcamera's simple pipeline has no autofocus
algorithm: apps get a fixed lens position until one is added.

## Resolution

The IMX351 driver exposes 4656x3492 and a 2x2-binned 2328x1744; a
viewfinder gets the binned mode and the SoftISP scales it down.

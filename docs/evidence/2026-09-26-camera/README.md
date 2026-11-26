# 2026-09-26 — main camera and laser AF on the joan bench

LG V30 US998, pmOS edge from the SD card, bench kernels RAM-booted with
`tools/bench/joan-testboot.sh` from `joan/bootlog-fixes`.

| Kernel | What changed | Result |
|---|---|---|
| bl2 | porthole 0069/0229/0231 (MCLK mnd_width, VL53L0X) | IMX351: "the clock must run at 24000000 Hz"; VL53L0X: CCI timeout |
| bl3 | porthole 0068 (GPLL0_DIV is GPLL0/2), MCLK M/N fix | IMX351 probes (MCLK reads 24 MHz). VL53L0X still times out |
| bl3 A/B | IMX351 held runtime-active (power/control=on) | `vl53l0x-lvs1-ab-bl3.txt`: off/on/off -> timeout/bound/timeout; LVS1 is the difference |
| bl4 | LVS1 regulator-always-on | `vl53l0x-lvs1-alwayson-bl4.txt`: VL53L0X probes at boot, 82-85 mm |
| bl5 | VL53L0X runtime PM | `vl53l0x-runtime-pm-bl5.txt`: camera AVDD off at idle, on for a read, off ~1 s later; unbind/rebind and rmmod/modprobe clean |
| bl5 | libcamera-tools + v4l-utils installed | `cam-list-bl5.txt`: "Internal back camera", simple pipeline, SoftISP on FD540 |
| bl6 | CAMSS TOP GDSC (porthole 0259) | clock stuck gone; `VFE sof timeout`, no frames (`cam-capture-bl6-...txt`) |
| bl7 | porthole's msm8998 CAMSS in place of this tree's CAMSS_660 reuse | `cam-capture-bl7.txt`: 1280x720 at 30.0 fps, 90/90 frames |

Frames: `frame009-...png` is frame 9 as captured (scaled to half size).
`frame089-...-brightened-x4.png` is frame 89, after auto-exposure had run,
multiplied by 4 for viewing only; the capture itself is dark (mean RGB
about 10) because the room was dim and libcamera has no gain model for
the IMX351 yet.

Packages installed on the bench for the test (not part of the default
install): v4l-utils, v4l-utils-libs, gtest, yaml (Alpine, signed), and
libcamera-tools 99990.7.2-r3 from the pmOS mirror. The pmOS package is
signed by a build-host key, so it was installed with --allow-untrusted
only after checking its control-segment hash against the mirror's
APKINDEX, whose signature verified against build.postmarketos.org.

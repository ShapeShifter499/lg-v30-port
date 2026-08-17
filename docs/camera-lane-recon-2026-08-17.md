# Camera lane — recon notes (started 2026-08-17, Aurel)

## Upstream support

- `drivers/media/platform/qcom/camss/` in the joan tree HAS
  `qcom,msm8998-camss` compatible + msm8998_resources (camss.c:5995).
  The 8998 camss = upstream-supported. No camss DT node in
  msm8998.dtsi or joan yet -> the DT must be built.
- Downstream camera DT to mine:
  `arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan-camera/msm8998-joan-camera_rev_0.dtsi`
  (in android_kernel_lge_msm8998). Contains: camera-flash, OIS,
  actuator, eeprom, CCI masters 0/1 (37.5MHz CCI clk), CSI PHY.
- V30 cameras (from the LG spec): main 16MP IMX351 (f/1.6, OIS) +
  wide 13MP. Sensor drivers needed for mainline (imx351 driver exists
  upstream: drivers/media/i2c/imx351.c — check the tree).

## Bring-up shape (later)

1. DT: the camss node for the joan (clocks, power domains, csiphy0/1,
   the vfe) modeled on the msm8996-camss DT + the joan downstream.
2. The sensor node: IMX351 on CCI0 (the i2c0/cci), the regulators
   (the camera power rails from the downstream), the pinctrl.
3. The CSI: the csiphy lanes; the VFE config.
4. Userspace: v4l2 capture -> the verification photos (Lance will prop
   the phone toward his room).

## Budget note (Lance)

Deepseek dashboard ~$13.26. Keep the turns lean: the boot-cycle steps
scripted (execute_code / shell), the minimal reads, the concise
reports. Big token sinks = the long transcripts; avoid the redundant
dumps.

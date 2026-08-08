# Battery / PMIC power bring-up — audit (2026-08-07)

Status: HOST-SIDE AUDIT COMPLETE — patch written, build pending.
Scope: mainline PMI8998 charger (SMB2) + rradc observation lane.

## What is already wired (from the QoS-era tree)

- PMIC fragments included by `msm8998-lge-joan.dts`: pm8998.dtsi
  (pwrkey+resin, RTC, temp-alarm, ADC rev2, gpios, regulators),
  pm8005.dtsi (GPU rail s1), pmi8998.dtsi (charger@1000, rradc@4500,
  gpio, lab-ibb, lpg, flash-led, wled).
- CONFIG_POWER_RESET_QCOM_PON=y — power key + reset already work.
- PMI8998 charger driver EXISTS in-tree: `qcom_smbx.c` ("Qualcomm
  SMB2 Charger Driver"), compatible "qcom,pmi8998-charger", deps
  MFD_SPMI_PMIC + IIO (both already satisfied), no typec/extcon
  dependency. Registers a POWER_SUPPLY_TYPE_USB psy.
- rradc IIO driver EXISTS in-tree: `drivers/iio/adc/qcom-spmi-rradc.c`
  (Kconfig QCOM_SPMI_RRADC); pmi8998.dtsi rradc node is enabled by
  default (no status="disabled").

## What is missing (this lane fixes)

1. CONFIG_CHARGER_QCOM_SMB2 is not set in the baseline config.
2. CONFIG_QCOM_SPMI_RRADC is not set.
3. Board DTS never enables &pmi8998_charger (fragment default:
   status = "disabled").

## Downstream LG reference (SGCMarkus android_kernel_lge_msm8998,
msm8998-joan-common-pm.dtsi + LGE_BLT34_LGC_3300mAh.dtsi)

- Battery: LG BL-T34, 3300 mAh, LGC cells.
- Float: qcom,float-option = <2>; FG life-cycle vfloat starts at
  4.4 V (4400000 uV), CV threshold 4390 mV, fg-cutoff 3200 mV.
  NOTE: LG runs 4.4 V class — do not assume 4.2.
- USB charging path: external SMB1381 charger (`&smb1381_charger`,
  lge,smb-bat-en-gpio on pmi8998_gpios 1) — NOT mainline-supported
  (qcom_smbx.c covers PMI8998/PM660 only). USB charge-current
  control is therefore out of scope for phase 1.
- PMI8998 SMB2 role on this device: wireless (dcin) path + battery
  presence + usbin measurement (io-channel names charger_temp,
  dcin_i/dcin_v, usbin_i/usbin_v, skin_temp...). qcom,dc-psy-type =
  "Wireless".
- FG: pmi8998_fg with the LG profile (downstream). NO mainline
  fuel-gauge driver for PMI8998 in this tree -> battery % deferred
  (voltage/temp observation only in phase 1).

## Phase-1 patch (this candidate)

- DTS: `msm8998-lge-joan.dts` gains `&pmi8998_charger { status =
  "okay"; };` (fragment already carries usbin_i/usbin_v io-channels
  and usb-plugin/bat-ov/wdog interrupts). Minimal by design.
- Kconfig: CONFIG_CHARGER_QCOM_SMB2=y, CONFIG_QCOM_SPMI_RRADC=y
  (built-in; the RAM image loads no modules from the SD rootfs).

## Test plan (one RAM boot, fresh approval)

1. Pre-boot gates: dtb overlap scan, hash seal, manifest.
2. Boot with USB UNPLUGGED: verify /sys/class/power_supply/usb
   present, rradc IIO channels readable (charger_temp, usbin_v),
   no probe errors, no regressions (icc errors 0, display up).
3. Plug USB: verify usb psy online/type change + usbin_v/i values.
4. Observe-only: do NOT rely on charging current control (SMB1381
   unmanaged). Float register state = hardware default; verify
   FLOAT_CFG via the charger regs before ever accepting charging
   behavior as intentional.
5. Recover to LineageOS, nothing flashed.

## Open items / next lanes

- Battery % (SoC): needs PMI8998 FG driver port (upstream-candidate)
  or voltage-based estimation.
- USB charge control: SMB1381 driver (upstream-candidate; the
  qcom_smbx.c family may gain smb1355/smb1381 compatibles upstream).
- Wireless charging (IDT P9223 @ i2c 0x61) + dcin channels: after
  the USB/wired lane closes.
- Battery thermal zones (bd_therm_2 etc. via pm8998 ADC): cheap
  add-on once the ADC channels are mapped.

## LineageOS ground truth (probed 2026-08-07, downstream kernel)

Read-only probe of the live device (battery lane acceptance targets):

- battery psy: status=Full, capacity=100%, voltage_now=4337879 uV,
  current_now=976 uA, charge_full=3312000 uAh,
  charge_full_design=3312000 uAh (3.312 Ah = BL-T34), temp=297
  (29.7 C), health=Good, Li-ion.
- bms psy: voltage_max_design=4400000 uV -> 4.4 V class CONFIRMED
  on-device (matches downstream float-option 2 / vfloat 4400000).
- Topology: main (SMB2), parallel (SMB1381, idle 19.5 mA), usb
  (USB_PD, present=1 online=0 on data cable), pc_port (online=1),
  dc + dc-wireless (Wireless, present=0) -> Qi path enumerated.
- Acceptance for the mainline boot: /sys/class/power_supply/usb
  present with sane usbin_v/usbin_i via rradc; battery voltage via
  rradc within 3.0-4.4 V; no probe errors; charging NOT expected to
  be controlled (SMB1381 unmanaged) — plug-state + measurement only.

Assisted-by: Hermes-Agent:deepseek/deepseek-v4-flash
Date: 2026-08-07

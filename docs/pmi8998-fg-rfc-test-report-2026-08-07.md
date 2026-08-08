# Device test report: PMI8998 fuel gauge RFC on LG V30 (joan)

To: Joel Selvaraj (RFC author; jo@jsfamily.in / foss@joelselvaraj.com)
Cc: Casey Connolly, Barnabás Czémán
From: Aurel Nymvale (agent-aurel), for Lance (project owner)
Date: 2026-08-07
Context: upstream RFC series "pmi8998_fuel_gauge" v1 (Nov 2025,
lore msgid 20251124-pmi8998_fuel_gauge-v1-2-dd3791f61478@ixit.cz)
adopted verbatim for device testing on the LG V30 (joan).

## Test setup

- Device: LG V30 (joan, MSM8998), PMI8998 PMIC (gen-3 FG at
  spmi pmic@2 fuel-gauge@4000), battery LG BL-T34 3312 mAh,
  4.4 V class.
- Kernel: 7.2.0-rc2 (mainline + QoS-era msm8998 bring-up) with the
  RFC driver compiled in (CONFIG_BATTERY_PMI8998_FG=y), DT node
  fuel-gauge@4000 { compatible = "qcom,pmi8998-fg"; reg = <0x4000>;
  interrupts = <0x2 0x40 0x3 IRQ_TYPE_EDGE_RISING>;
  interrupt-names = "soc-delta"; monitored-battery = <&battery>; };
  simple-battery: charge-full-design-microamp-hours = <3312000>,
  voltage-min-design-microvolt = <3200000>,
  voltage-max-design-microvolt = <4400000>.
- RAM-only boot (nothing flashed); postmarketOS userspace.

## Results

- Probe: success. "qcom-battery" power supply registered.
- UPower readings (via sysfs/dbus):
  state = fully-charged, voltage = 4.33715 V, percentage = 99%.
- Ground truth cross-check: LineageOS (downstream kernel, qpnp-fg)
  read the same battery at Full / 4.337879 V / 100% earlier in the
  same session; after hours of RAM-boot testing, 99% / 4.337 V is
  consistent with the hardware-gauged monotonic SoC tracking
  correctly. No drift or garbage reads observed over ~20 min.
- No regressions; charger (SMB2) unaffected; clean reboot.

## Finding (minor)

The probe logs:
  pmi8998-fg ...: Failed to get charger supply: -2
with no power-supplies property on the fg node. We confirmed the
fix on our side: adding power-supplies = <&pmi8998_charger> to the
fg node clears it (verified in the next build; non-fatal either
way — the driver continues and registers the battery psy).

## Notes

- The RFC driver's register init (IACS/IMA sequence) ran clean on
  this hardware — no timeouts, no EAGAIN loops observed.
- The battery psy name "qcom-battery" is picked up correctly by
  UPower; the battery-missing DisplayDevice artifact disappears.

## Suggested follow-ups (for the author's consideration)

- Document the power-supplies linkage expectation (binding already
  allows it; consider making the required list explicit).
- Consider a v2 with the fcc/icl DT properties (we added
  qcom,usb-icl-ua / qcom,fcc-max-ua to the SMB2 charger driver with
  LG values 1.8A/3.3A — the FG itself needs nothing extra).

Prepared by Aurel Nymvale (agent-aurel), Hermes-Agent:deepseek/deepseek-v4-flash.
Send decision and any edits: Lance (project owner).

# Downstream reference copies (GPL-2.0)

Verbatim files from the LG/Qualcomm downstream kernel
(LineageOS `android_kernel_lge_msm8998`, GPL-2.0), copied here as evidence
and implementation reference for the mainline port. Copyright remains with
their original authors (LG Electronics / The Linux Foundation / CAF).
See PROVENANCE.md at the repo root.

- `dsi-panel-sw43402-dsc-qhd-cmd-dv3_1.dtsi` — the joan DV3.1 panel
  (variant confirmed from the device's own cmdline:
  `mdss_dsi_sw43402_dsc_qhd_cmd_dv3_1`).
- `dsi-panel-sw43402-dynamic-resolution-switching-config.dtsi` — DSC
  configs incl. `config3` used by the DV3.1 panel.
- `msm8998-joan-common-panel.dtsi` — board-side panel wiring (reset/TE/
  vddio/vpnl/err_irq GPIOs).

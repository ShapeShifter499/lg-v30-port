# SW43402 panel data (joan DV3.1) — parcel P2

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

Source of truth: downstream `dsi-panel-sw43402-dsc-qhd-cmd-dv3_1.dtsi` +
`dsi-panel-sw43402-dynamic-resolution-switching-config.dtsi` +
`msm8998-joan-common-panel.dtsi` (verbatim copies in `docs/downstream-refs/`,
GPL-2.0). Panel variant DV3.1 is device-proven: LineageOS boots this exact
panel per the cmdline captured in the K053 diag
(`mdss_dsi_sw43402_dsc_qhd_cmd_dv3_1`).

## Identity

- LG Display SW43402 P-OLED, 6.0" 1440x2880 (QHD+ 18:9), DSI **command mode**
  with DSC. Downstream name: "SW43402 cmd mode dsc dsi panel".

## Mode / timings (60 Hz)

| Param | Value |
|---|---|
| hactive x vactive | 1440 x 2880 |
| HFP / HBP / HPW | 92 / 48 / 32 |
| VFP / VBP / VPW | 10 / 25 / 1 |
| bpp (uncompressed) | 24 (RGB888) |
| t-clk-pre / t-clk-post | 0x20 / 0x06 |
| Mode | cmd mode + TE (no video mode) |

## DSC (config3, the one DV3.1 selects)

| Param | Value |
|---|---|
| DSC version | 1.1 (scr-version 1) |
| bits-per-component | 8 |
| bits-per-pixel (compressed) | 8 |
| slice width x height | 720 x 16 |
| slices per packet | 2 |
| encoders | 2 (lm-split 720+720 — dual layer-mixer, dual DSC) |
| block prediction | enabled |

Mainline mapping: msm8998 DPU catalog (`dpu_3_0_msm8998.h`) declares
`dsc_0`/`dsc_1` (DSC 1.1 fixed-function blocks) — matches the 2-encoder
split downstream uses.

## Board wiring (joan-common-panel.dtsi)

| Signal | GPIO |
|---|---|
| panel reset | TLMM 35 |
| TE (vsync in) | TLMM 10 |
| vddio enable | TLMM 92 |
| vpnl (panel power) enable | TLMM 69 |
| err_irq | TLMM 124 (rising, oneshot) |

Note: DV3.1 explicitly **disables labibb** (`qpnp-labibb-regulator` status
"disabled") — panel rails are the two GPIO-enabled fixed supplies above, not
LAB/IBB. Model them as `regulator-fixed` gpio regulators in mainline.

## Init sequence

129 DSI on-commands in the downstream dtsi (mostly 15/39-type writes,
ending in sleep-out + display-on), plus PPS delivery. Not transcribed here —
use `docs/downstream-refs/dsi-panel-sw43402-dsc-qhd-cmd-dv3_1.dtsi`
directly when writing the mainline panel driver; the blob should be
converted to `mipi_dsi_dcs_write_seq()` calls.

## Open questions for the driver

1. PPS: downstream MDSS computes/sends PPS from the dsc params; mainline
   panel drivers send a precomputed 128-byte PPS via
   `mipi_dsi_picture_parameter_set()` (see `panel-sony-akatsuki-lgd.c`).
   Compute PPS from the table above (drm_dsc_pps_payload_pack()).
2. Brightness: downstream uses DCS 51h with extended range — check
   backlight blocks in the dtsi.
3. Whether the panel accepts a non-DSC fallback mode: no evidence downstream
   (all joan panel dtsi variants are dsc cmd) — assume DSC is mandatory.

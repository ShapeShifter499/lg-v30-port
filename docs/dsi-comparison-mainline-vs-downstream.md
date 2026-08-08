# DSI comparison — mainline vs downstream (LG V30 SW43402 DSC QHD)

Date: 2026-08-06 (rev 2 — theories corrected after source verification)
Evidence-led comparison for the measured 20-26 ms full-frame DSI
transfers on mainline (~40 fps presentation ceiling).

## Bottom line (rev 2)

- REJECTED: bonded dual-DSI. Downstream joan boards wire ONLY
  &mdss_dsi0 (msm8998-joan-common-panel.dtsi, every rev .dts):
  single DSI controller, same as mainline. The lm-split <720 720> +
  mdss-dsc-encoders = <2> in config3 is a layer-mixer split INSIDE
  the single DPU (two LM halves, two DSC encoders feeding one DSI),
  not two physical links.
- REJECTED: DSC not wired. Panel sets dsi->dsc = &ctx->dsc
  (panel-lg-sw43402.c:345); dsi_host_attach copies it to
  msm_host->dsc; dsi_get_pclk_rate applies
  dsi_adjust_pclk_for_compression (3:1). DSC configs are
  byte-identical to downstream config3 (1.1, 720x16 slices,
  8bpc/8bpp, block prediction, SCR 1.0).
- ACTIVE SUSPECT: the programmed DSI link clock is ~half the
  intended rate (10nm PLL outdiv/bit_clk_div issue — the K065-era
  factor-2 class of bug).

## The measured math (why half-rate fits)

Mode clock: 1612 x 2916 x 60 / 1000 = 282.0 MHz (uncompressed pclk)
DSC 3:1 adjust: new_hdisplay = 1440*8/24 = 480; new_htotal = 652;
  compressed pclk = 282.0 * 652/1612 = 114.1 MHz
byte_clk = pclk * 24 / (8 * 4 lanes) = 85.6 MHz (bit 685 Mbps/lane)
DSC frame bytes = 1440*2880*8/8 = 4.15 MB
Expected transfer = 4.15e6*8 / (4 * 8 * 85.6e6) = 12.1 ms
MEASURED (drm.debug kickoff trace, C2C session): 20.3 / 21.1 / 23.6 /
  26.7 / 26.8 / 33.6 ms

Implied actual byte_clk for 20-26.7 ms: 39-52 MHz (bit 310-415
Mbps/lane) — roughly HALF the intended 85.6 MHz. A 10nm PHY rated
~2.5 Gbps/lane and a panel LG drove at ~1.3-1.9 Gbps/lane running
at ~350-415 Mbps/lane is the signature of a wrong output divider,
not a hardware limit. PLL clamp is not the cap: min_pll_rate 1 GHz /
max 3.5 GHz covers all cases (dsi_phy_10nm.c:1012-1013).

## Downstream reference points (to complete)

dsi-panel-sw43402-dsc-qhd-cmd-dv3_1.dtsi:
- qcom,mdss-dsi-panel-timings = [00 0F 04 03 06 0B 04 04 03 03 04 00]
  (old-style phy timing blob — encodes the downstream link rate;
  decode pending against the mdss_dsi_phy timing table)
- single &mdss_dsi0, 4 lanes, lane_map_0123, burst, cmd mode, DSC
  config3 (720x16 slices, 8bpc/8bpp)

## Decisive next measurement (one RAM boot, same C2C image)

Capture on device:
1. dmesg drm.debug DBG lines: "pclk=..., bclk=..." (dsi_calc_pclk)
2. /sys/kernel/debug/clk/clk_summary: dsi0_pll_out_div_clk,
   dsi0_pll_bit_clk, dsi0_phy_pll_out_byteclk actual rates
3. dsi_pll_10nm_vco_recalc_rate reads back (outdiv/bit_clk_div
   register values via the save_state path or devmem 0xae95000
   PLL_OUTDIV_RATE)
Compare against intended 85.6 MHz byte clock. If ~half:
fix = correct pll_out_div / bit_clk_div math in dsi_phy_10nm.c for
msm8998 (one-variable candidate; K065-class).

## Evidence refs

- Downstream: android_kernel_lge_msm8998/arch/arm64/boot/dts/lge/
  dsi-panel-sw43402-dsc-qhd-cmd-dv3_1.dtsi;
  msm8998-joan-common/msm8998-joan-common-panel.dtsi (mdss_dsi0 only);
  dsi-panel-sw43402-dynamic-resolution-switching-config.dtsi (config3)
- Mainline: drivers/gpu/drm/panel/panel-lg-sw43402.c (:345 dsi->dsc);
  drivers/gpu/drm/msm/dsi/dsi_host.c (dsi_adjust_pclk_for_compression,
  dsi_host_attach dsc copy); dsi_phy_10nm.c (outdiv, min/max rates)
- Measured: C2C session kickoff trace (drm.debug), 2026-08-06

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek-v4-flash
Date: 2026-08-06

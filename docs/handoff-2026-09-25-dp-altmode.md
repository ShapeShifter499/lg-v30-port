# Handoff 2026-09-25: DisplayPort alt mode over USB-C (paused mid-way)

Kernel: `linux-lg-v30-joan` branch `claude/lucid-dijkstra-bxx3r9`, PR #11.
Nothing here has been booted.

## Where it stands

- **Reverted:** another agent's DP attempt (`42eff31`). It broke USB on every
  msm8998 board (`#phy-cells = <1>` with dwc3 still passing none), used
  QCS615's PLL tables, placed the DP P0 block at `0x1000` (it is at `0xa00`),
  and broke two bindings.
- **Done:** `e6e796d` clk: qcom: mmcc-msm8998. The DP link RCG is now a byte2
  divider of the PHY link clock, and the pixel RCG uses `clk_dp_ops` with a
  16-bit M/N counter. The old link table was in kHz (162000), and the pixel
  RCG had no M/N counter.
- **Not started:** PHY, DP controller, DT (plan below).

## Correction to the 2026-09-24 notes

The 2026-09-24 handoff said the msm8998 DP PLL uses "the same QMP v2 COM
register map" as QCS615. That was wrong, and the revert message `42eff31`
repeats it. Checked register by register against LG's `mdss-dp-pll-8998.h`:

- **DP PLL:** mainline **QMP v3 COM** layout (`phy-qcom-qmp-qserdes-com-v3.h`;
  all 20 registers used match). That is the SDM845 generation, not QCS615's
  v2.
- **TX lanes:** mainline `QSERDES_V3_TX_*`.
- **DP_PHY block:** an older layout that matches no mainline header:
  CFG 0x10, PD_CTL 0x14, MODE 0x18, AUX_CFG0-9 0x1c-0x40, AUX_INTERRUPT_MASK
  0x44, CLEAR 0x48, VCO_DIV 0x64, TX0_TX1_LANE_CTL 0x68, TX2_TX3_LANE_CTL 0x84,
  SPARE0 0xa8, STATUS 0xbc. Mainline QCS615/V3 put PD_CTL at 0x18 and
  STATUS at 0xc0.
- **Block offsets inside the PHY** (`0xc010000`): dp_phy `0x1000`, txa
  `0x1400`, txb `0x1800`, serdes `0x1c00`, the same as qmp-usbc's QCS615.

## Hardware facts from LG's kernel

- **USB3 and DP are exclusive.**
  - The PHY is switched whole by TCSR `0x1fcb248` (`tcsr_regs_2` + `0xb248`;
    1 = DP; `0xb244` is the VLS clamp). qmp-usbc already has
    `dp_phy_mode_reg` for this.
  - LG's PD stack starts the USB host HS-only when the partner has SVID
    0xff01.
  - Pin preference: D if the sink asks for multi-function, otherwise the
    first one offered; C is the default.
  - Downstream switches the TCSR mode with the PHY resets asserted.
- **AUX switch:**
  - TLMM 100 is an active-low OE; TLMM 80 selects the orientation (high =
    flipped).
  - LG waits about 30 ms before enabling. The part is unidentified; its
    interface fits `gpio-sbu-mux`.
- **Moisture-detection SBU switch** in LG's PD driver (TLMM 11 select, TLMM 16
  OE): both must be low for normal SBU routing. Hog them low. TLMM 38 is an
  orientation input the TCPM makes redundant.
- **DP controller:**
  - `0xc990000`: ahb 0x0, aux 0x200, link 0x400, p0 0xa00 (downstream maps up
    to 0xa84); SST only; MDSS interrupt 12.
  - Supplies: L2 1.2 V and L1 0.88 V, the same as the USB PHY.
  - Link clock rates: 162/270/540 MHz at low-SVS/SVS/nominal.
- **Lane map:** `DP_LOGICAL2PHYSICAL_LANE_MAPPING` = [2 3 1 0]. For a flipped
  plug (CC2) LG mirrors it (each entry v becomes 3-v), giving [1 0 2 3]. LG
  also sets `DP_PHY_MODE` 0x48 (flipped) or 0x58, so the PHY alone does not
  swap the lanes. Mainline msm DP has no orientation input; qmp-usbc has a
  FIXME for exactly this.
- **PD_CTL:** 0x3d for 4 lanes, 0x35 for 2 lanes normal (lanes 2/3), 0x2d for
  2 lanes flipped.
  - Bias/driver: 1 lane 0x3e/0x13, otherwise 0x3f/0x10.
  - 2-lane: TX1 (txb) when normal, TX0 (txa) when flipped; 4-lane: both.
- **PLL (LG):**
  - Common: SVS_MODE_CLK_SEL 01, SYSCLK_EN_SEL 37, CLK_ENABLE1 0e,
    SYSCLK_BUF_ENABLE 06, CLK_SELECT 30.
  - Loop: INTEGLOOP_GAIN0 3f, GAIN1 00, VCO_TUNE_MAP 00, BG_TIMER 00 then 0a,
    CORECLK_DIV_MODE0 05, VCO_TUNE_CTRL 00, CP_CTRL 06, PLL_CCTRL 36,
    PLL_RCTRL 16, PLL_IVCO 07, BIAS_EN_CLKBUFLR_EN 37, CORE_CLK_EN 0f.
  - Per rate (SYS_CLK_CTRL / HSCLK_SEL / LOCK_CMP_EN / DEC_START / FRAC1-3 /
    CMN_CONFIG / LOCK_CMP1-3):
    - RBR: 02 / 2c / 04 / 69 / 00 80 07 / 42 / bf 21 00
    - HBR: 06 / 84 / 08 / 69 / 00 80 07 / 02 / 3f 38 00
    - HBR2: 06 / 80 / 08 / 8c / 00 00 0a / 12 / 7f 70 00
  - VCO_DIV: 1 for RBR/HBR, 2 for HBR2.
- **PHY bring-up (LG `dp_pll_enable`):**
  1. TX0_TX1/TX2_TX3_LANE_CTL 05.
  2. TX lanes: BIAS 1a, VMODE_CTRL1 40, PRE_STALL_LDO_BOOST 30, INTERFACE_SELECT
     3d, CLKBUF 0f, RESET_TSYNC 03, TRAN_DRVR_EMP 03, PARRATE 00, INTERFACE_MODE
     00, TX_BAND 04.
  3. CFG 01, 05, 01, 09; RESETSM_CNTRL 20; poll C_READY bit 0.
  4. CFG 19; poll STATUS bit 1.
  5. Bias/driver as above, POL_INV 0a.
  6. CFG 18, 2 ms, CFG 19.
  7. LANE_MODE_1: c6 at HBR, f6 otherwise.
  8. CLKBUF 1f then 0f.
  9. CFG 09, 2 ms, CFG 19, 2 ms; poll ready.
  10. DRV_LVL 2a, EMP_POST1 20, RES_CODE_LANE_OFFSET_TX/RX 11.
- **Same as QCS615 in mainline:** AUX_CFG0-9 (00 13 00 00 0a 26 0a 03 bb 03;
  CFG1 cycles 13/23/1d) and the swing/pre-emphasis tables. LG's AUX interrupt
  mask is 0x1e.

## Plan for the rest

1. **qmp-usbc:**
   - msm8998 USB3+DP config with its own DP_PHY offsets, v3 COM/TX tables and
     the sequence above.
   - Set the TCSR mode while the resets are asserted.
   - Type-C mode-switch: DP states park USB3, the way qmp-combo's DP-only mode
     does. dwc3 keeps its phy init count, so USB enable/exit must not fail or
     underflow while parked. USB is restored when DP exits.
   - Report reversed lanes from `phy_validate()` through a new
     `phy_configure_opts_dp` field.
   - Register a `drm_aux_bridge`; `qcom_pmic_typec` already registers the HPD
     bridge on the connector.
   - Binding: `qcom,msm8998-qmp-usb3-dp-phy` in the qcs615 usb3dp schema; three
     resets (phy_phy, phy, dp_phy).
2. **msm DP:**
   - `qcom,msm8998-dp` descriptor (`0x0c990000`); binding: SST, 4 reg, 5
     clocks. The hw revision path is expected to be SDM845's (v1.0).
   - Call `phy_validate()` before the lane mapping and mirror the map when
     reversed.
3. **msm8998.dtsi:**
   - usb3phy becomes `...-usb3-dp-phy`: reg 0x2000, `#clock-cells`/`#phy-cells`
     1, `qcom,tcsr-reg = <&tcsr_regs_2 0xb244 0xb248>`, dp_in port@2.
   - dwc3 phys `<&usb3phy QMP_USB43DP_USB3_PHY>`.
   - mmcc dplink/dpvco inputs.
   - `mdss_dp` node, core_iface = MDSS_HDMI_DP_AHB_CLK, OPP on `RPMPD_VDDCX`.
   - DPU port@3 for INTF_0.
4. **joan:**
   - Connector altmodes (svid 0xff01, vdo 0x1c46 = DFP_D, pins C/D/E); port@2
     to the SBU mux.
   - usb3phy `mode-switch`; `mdss_dp_out` `data-lanes = <2 3 1 0>`.
   - Hog TLMM 11/16 low.
5. **pmaports:** `TYPEC_DP_ALTMODE`, `TYPEC_MUX_GPIO_SBU` (both =m at least;
   `DRM_MSM_DP` is already y).

Assisted-by: Claude-Code:Claude Opus 5.5
Date: 2026-09-25

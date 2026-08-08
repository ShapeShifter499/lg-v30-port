# C2 workstream — msm8998 OSM CPU clock driver port (LG V30 CPU DVFS)

STATUS: SCOPED + RESEARCH-CAPTURED (2026-08-05). Implementation in a
fresh session. Owner-approved: "I approve this ... the OSM driver port
is a real multi-session effort (I'd want a clean slot for it)".

## Why (device-proven)

Lockscreen animation is compositor-CPU-bound: DPU presents every
submitted frame in ~18 ms (60 Hz capable), GPU A/B flat (34.2 fps at
257 vs 750 MHz), but commits arrive at 2-5 fps during animation
because all 8 cores run at a bootloader-fixed low clock (BogoMIPS
38.4, NO /sys/devices/system/cpu/cpu0/cpufreq). C1 (cpufreq-hw DT
wiring, 0c179507d) was REJECTED-WITH-CAUSE: OSM reports "Domain-N
cpufreq hardware not enabled" — bootloader/TZ does NOT pre-program
the OSM LUT. The LUT is programmed by the downstream kernel driver
(drivers/clk/msm/clock-osm.c). Mainline has no msm8998 OSM driver.

## KEY INSIGHT (port strategy)

qcom-cpufreq-hw (CONFIG_ARM_QCOM_CPUFREQ_HW=y, qcom_soc_data) reads
the OSM LUT from hardware and fails only because the OSM enable bit
(reg 0x0) is unset. A MINIMAL mainline driver that (1) parses the
speedbin LUT tables from DT, (2) programs OSM LUT + PLL config, (3)
sets the OSM enable bit, makes cpufreq-hw bind and work — no full
clock-framework driver, no ACD needed for Stage A.

## Downstream reference data (from android_kernel_lge_msm8998)

DT node (msm8998.dtsi clock_cpu: qcom,cpu-clock-8998@179c0000):
- regs: 0x179c0000 (osm), 0x17916000 (pwrcl_pll), 0x17816000
  (perfcl_pll), 0x179d1000 (apcs_common), 0x784130 (perfcl_efuse),
  0x1791101c (debug)
- reg-names: "osm", "pwrcl_pll", "perfcl_pll", "apcs_common",
  "perfcl_efuse", "debug"
- vdd-pwrcl-supply = apc0_pwrcl_vreg; vdd-perfcl-supply =
  apc1_perfcl_vreg
- interrupts: GIC_SPI 35 (pwrcl-irq), 36 (perfcl-irq), edge-rising
- qcom,pwrcl-speedbin0-v0: <300000000 0x0004000f 0x01200020 0x1 1>,
  <345600000 0x05040012 0x02200020 0x1 2>, ... (little cluster table)
- qcom,perfcl-speedbin0-v0: same format (big cluster)
- qcom,cc-reads=<10>; qcom,cc-delay=<5>; qcom,cc-factor=<100>
- qcom,osm-clk-rate=<200000000>; qcom,xo-clk-rate=<19200000>

Driver (clock-osm.c) anatomy:
- bases enum: OSM_BASE, PLL_BASE, EFUSE_BASE, ACD_BASE, NUM_BASES
- LUT row fields (clk_osm_lut_data): FREQ, FREQ_DATA, PLL_OVERRIDES,
  SPARE_DATA (+speedbin/pvs fields)
- speedbin read: PWRCL_EFUSE_SHIFT / PERFCL_EFUSE_SHIFT from
  0x784130 (perfcl efuse); table select by
  "qcom,pwrcl-speedbin%d-v%d" / "qcom,perfcl-speedbin%d-v%d"
- regulators: vdd-pwrcl / vdd-perfcl (scaled per OPP before clock)
- key fns: clk_osm_get_lut (programs LUT from DT tables),
  clk_osm_set_rate (programs PLL + divider + LUT index),
  clk_osm_enable (OSM enable bit), clk_osm_acd_init (Adaptive Clock
  Distribution — SKIP for Stage A)
- OSM LUT programming flow is the load-bearing part for cpufreq-hw

## DT wiring (mainline side, already proven pieces)
## KEY INSIGHT (port strategy)

qcom-cpufreq-hw (CONFIG_ARM_QCOM_CPUFREQ_HW=y, qcom_soc_data) reads
the OSM LUT from hardware and fails only because the OSM enable bit
(reg 0x0) is unset.

**CORRECTED 2026-08-05 (source-verified): cpufreq-hw is
ARCHITECTURALLY INCOMPATIBLE with the msm8998 OSM.** Its register
layout (enable@0x0, freq_lut@0x110, volt_lut@0x114, perf@0x920,
32-byte rows) does NOT match the real msm8998 OSM block:
  - OSM_ENABLE_REG = 0x1004 (downstream clk_osm_enable writes 1)
  - LUT rows at INDEX_REG 0x1150 / FREQ_REG 0x1154 / VOLT_REG 0x1158
    / OVERRIDE_REG 0x115C / SPARE_REG 0x1164, 32-byte stride
  - DCVS_PERF_STATE_DESIRED_REG = 0x1F10 (set_rate writes the table
    index; the OSM hardware switches PLL+voltage autonomously)
The C1B "hardware not enabled" reading was cpufreq-hw checking reg
0x0, which is not the OSM enable. **The correct port is the full OSM
clk driver (Stage B), not a LUT bootstrapper for cpufreq-hw.**

## Stage plan (REVISED — full driver, implemented)

The port (committed as clk-osm-8998.c + DT) is a mainline-style clk
driver:
  1. of_iomap osm (0x179c0000), pwrcl_pll (0x17916000),
     perfcl_pll (0x17816000)
  2. parse qcom,pwrcl/perfcl-speedbinN-v0 tables from DT
     (5 fields/row: FREQ, FREQ_DATA, PLL_OVERRIDES, SPARE_DATA,
     VIRTUAL_CORNER)
  3. osm_setup_hw_table: program all 40 LUT rows (INDEX/FREQ/VOLT/
     OVERRIDE/SPARE at 0x1150 + i*32)
  4. osm_setup_cluster_pll: PLL init sequence per cluster
  5. clk_hw per cluster: determine_rate/recalc/set_rate (writes
     index to 0x1F10), enable (writes 1 to 0x1004)
  6. DT: clock-controller@179c0000 + speedbin tables (V30 real
     values from msm8998-v2.dtsi) + cpu0-opp-table/cpu4-opp-table
     (unique rates, stock v2 envelope) + clocks/operating-points-v2
     on all 8 CPUs; cpufreq-dt (already =y) binds via OPP tables
  7. Verify: cpufreq sysfs appears with stock v2 rates; schedutil
     ramps under load; lockscreen animation smoothness


## Gating / hygiene

- One variable per image; branch from last-TESTED head (0c179507d or
  the G6-OC3 850 line).
- Voltage handling: VDD_APC rails via rpm-smd; verify the rail's
  voltage grid before writing OPP microvolts (pm8005-style lesson).
- LOCAL-ONLY like the GPU OC; never upstream until reviewed.
- Device tests need fresh approval per image; use the self-heal
  initramfs (recovery-patched) and clean ssh-tt recovery discipline.
- Continuity: skill msm8998-cpu-dvfs-gap.md + this doc; Deck card 43.

## Files

- Downstream driver: android_kernel_lge_msm8998/drivers/clk/msm/
  clock-osm.c (full LUT/enable/ACD code)
- Downstream node: same tree arch/arm/boot/dts/qcom/msm8998.dtsi
  clock_cpu + msm8998-v2.dtsi cpufreq tables
- This workstream: C2-OSM-DRIVER-PORT (todo + Deck)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-05

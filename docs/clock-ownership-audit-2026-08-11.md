# MSM8998 / LG V30 clock-ownership audit — 2026-08-11

## Scope and inference boundary

This audit treats four hardware lanes independently:

1. removable microSD / SDCC2;
2. UFS internal storage and its PHY;
3. Adreno 540 GPU and GPU SMMU;
4. USB-C / DWC3 / USB2 and USB3 PHYs.

Proper clock ownership is a standing platform-correctness goal even if none of
these changes affects the Card 94 reset or GPU suspend behavior. No clock change
in this audit is called a reset or suspend fix without a controlled device test.
The LG/LineageOS 4.4 tree is a read-only behavioral reference; mainline names,
consumers, bindings, OPPs, interconnects, and power sequencing remain
Authoritative for the implementation shape.

Kernel audit worktree:
`/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-aurel-clock-adoption`
(branch `joan/clock-ownership-v1`, based on `569fbe2c7fa0`).

## Lane 1 — SDCC2 / removable microSD

### Current mainline ownership

`msm8998.dtsi` supplies the three clocks accepted by the current
`qcom,sdhci-msm.yaml` binding:

- `iface` = `GCC_SDCC2_AHB_CLK`;
- `core` = `GCC_SDCC2_APPS_CLK`;
- `xo` = `RPM_SMD_XO_CLK_SRC`.

The binding describes those respectively as the AHB peripheral-bus clock, MMC
core clock, and TCXO calibration clock. Joan enables the controller and adds the
board supplies, card-detect GPIO, and active/sleep pin states.

### Verdict

Clock ownership is already complete under the modern mainline binding. Copying
only the two-clock legacy shape would remove the explicitly modelled `xo` owner
and regress the mainline description.

The compiled-DTB schema check separately exposes an existing SDCC OPP warning:
MSM8998's 100 and 200 MHz OPPs lack binding-required `required-opps`. That is an
OPP/power-domain lane, not a missing clock, and must not be disguised as one.

### Device acceptance (still required for future candidates)

Record card enumeration, negotiated timing/mode, `/sys/kernel/debug/clk` rates
and enable counts where safely available, sustained read/write I/O, error
counters, and suspend/resume behavior. Persistent writes need separate owner
authorization.

## Lane 2 — UFS internal storage

### Current mainline ownership

The MSM8998 UFS controller lists all eight clocks permitted by
`qcom,sc7180-ufshc.yaml` for this compatible:

- `core_clk` = `GCC_UFS_AXI_CLK`;
- `bus_aggr_clk` = `GCC_AGGRE1_UFS_AXI_CLK`;
- `iface_clk` = `GCC_UFS_AHB_CLK`;
- `core_clk_unipro` = `GCC_UFS_UNIPRO_CORE_CLK`;
- `ref_clk` = `RPM_SMD_LN_BB_CLK1`;
- `tx_lane0_sync_clk` = `GCC_UFS_TX_SYMBOL_0_CLK`;
- `rx_lane0_sync_clk` = `GCC_UFS_RX_SYMBOL_0_CLK`;
- `rx_lane1_sync_clk` = `GCC_UFS_RX_SYMBOL_1_CLK`.

The UFS QMP PHY separately owns its three binding-defined clocks:

- `ref` = `RPM_SMD_LN_BB_CLK1`;
- `ref_aux` = `GCC_UFS_PHY_AUX_CLK`;
- `qref` = `GCC_UFS_CLKREF_CLK`.

Joan enables both nodes and adds the board supplies.

### Verdict

Controller and PHY clock ownership are already complete in mainline. No
additional legacy clock should be copied unless a current consumer and binding
first demonstrate a missing relationship.

### Device acceptance

Record negotiated UFS gear, lanes, power mode, controller and PHY clock rates,
I/O error counters, sustained read behavior, and suspend/resume. Do not run a
destructive write test against the installed system.

## Lane 3 — Adreno 540 GPU

### Direct downstream behavior

LG/Qualcomm downstream lists eight GPU clocks. Relative to mainline's seven,
the missing relationships are:

- `iref_clk` from MSM8998 GCC;
- `isense_clk` from MSM8998 GPUCC.

Downstream also sets `qcom,isense-clk-on-level = <1>`. Its
`_isense_clk_set_rate()` selects 200 MHz for downstream power levels 0 and 1
(the two fastest levels) and 19.2 MHz for level 2 and slower. This is confirmed
by `KGSL_ISENSE_CLK_FREQ = 200000000`, `KGSL_XO_CLK_FREQ = 19200000`, and the
comparison `level > isense_clk_on_level`.

### IREF — implemented host-side

Downstream directly defines `GCC_GPU_IREF_EN` at register `0x88010` and exposes
it as `gcc_gpu_iref_clk`. Close mainline Qualcomm GCC drivers model equivalent
GPU IREF gates with bit 0 and `BRANCH_HALT`. MSM8998 GCC's regmap already covers
this register.

The current worktree therefore:

1. adds `GCC_GPU_IREF_CLK` to the MSM8998 GCC DT binding header;
2. adds a `gcc_gpu_iref_clk` provider at `0x88010`;
3. extends the A540 GPU binding from seven to optionally eight clocks;
4. assigns the eighth `iref` clock to the MSM8998 Adreno node.

The MSM DRM GPU code bulk-acquires all listed clocks and sequences them through
the normal GPU clock lifecycle, so no private enable path is needed.

Host verification completed before commit:

- `git diff --check`: pass;
- MSM8998 GCC object build: pass;
- Joan DTB build: pass;
- focused `W=1` GCC object + Joan DTB: pass (only pre-existing DTC warnings);
- `dt_binding_check` for `display/msm/gpu.yaml`: pass with dtschema 2026.6 and
  yamllint 1.38.0;
- direct compiled-Joan validation: new clock/count errors eliminated; unrelated
  existing Joan/schema warnings remain;
- per-file `scripts/checkpatch.pl --strict`: zero errors and zero warnings.

The aggregate source tree passed the full configured `Image.gz dtbs modules`
build with exit 0. After splitting the byte-identical change into four commits,
a second full build also exited 0 and embedded the exact release
`7.2.0-rc2-g35750026c253`. The sealed RAM-only image is
`out/audit-20260811/boot-joan-gpu-iref-35750026c-sealed.img`, SHA-256
`1fb50bffb570d9d90f2ff26f3e261a7eb239242cd07e398bf3cc1e29a5edeaf4`.
Its unpacked kernel, DTB, uncompressed Image, reference ramdisk, header, cmdline,
and pmOS UUID lineage all passed independent byte-level verification. This is
host-verified, not device-verified; the image is not staged or booted.

### ISENSE — source-mapped, not yet ported

`isense` clocks the A540/GPMU current-sense circuitry used by Qualcomm limits
management. It is not the GPU rendering clock. Mainline GPUCC already provides
`GFX3D_ISENSE_CLK` and rates including 19.2 and 200 MHz.

A phandle-only port would be incomplete: mainline's `a540_lm_setup()` currently
sets `AGC_LM_CONFIG_THROTTLE_DISABLE` and hardcodes active power level 0. A
proper port must first make A540 limits management and DVFS semantics real, then
select the isense rate from the active OPP/frequency. It must not copy the
legacy numeric level index, whose ordering is downstream-specific.

### SNOC DVM — separate SMMU investigation

`GCC_GPU_SNOC_DVM_GFX_CLK` already exists in mainline MSM8998 GCC but is
unclaimed. Newer Qualcomm DTS files place equivalent SNOC DVM clocks on the GPU
SMMU as an interface clock. However:

- MSM8998 downstream does not list or consume this clock;
- MSM8998's current SMMU binding allows only `iface`, `mem`, and `mem_iface` for
  this node;
- those three existing clocks are legitimate owners and must not be replaced or
  renamed to force SNOC DVM into the schema.

Any adoption needs a separate binding extension with a truthful fourth clock
name and rationale. It is not bundled with IREF and is not yet a candidate.

### Device acceptance

For each GPU clock patch independently, capture provider/consumer probe,
`clk_summary` state when safely available, render validation, runtime-PM
transitions, suspend/resume, and regressions. For isense, additionally prove
19.2/200 MHz transitions correspond to the intended mainline OPP boundary and
limits-management state.

## Lane 4 — USB-C, DWC3, USB2 and USB3 PHYs

### Can the V30 run USB 3?

Yes. Joan's shipped downstream configuration binds DWC3 to both the QUSB2 PHY
and the QMP SuperSpeed PHY. The common LG Joan USB DTS also supplies distinct
SuperSpeed lane-A and lane-B transmitter pre-emphasis tuning. This is direct
board evidence that the V30 was designed for SuperSpeed USB 3.1 Gen 1 (5 Gb/s),
not a physically USB2-only device.

Current Joan mainline intentionally removes the USB3 PHY, selects UTMI as the
pipe clock, caps DWC3 at `high-speed`, and forces peripheral mode. Its comments
explicitly call this USB2-only bring-up behavior.

### Current clock ownership

The generic MSM8998 mainline nodes already model the modern clock consumers:

DWC3 wrapper:

- `cfg_noc` = `GCC_CFG_NOC_USB3_AXI_CLK`;
- `core` = `GCC_USB30_MASTER_CLK`;
- `iface` = `GCC_AGGRE1_USB3_AXI_CLK`;
- `sleep` = `GCC_USB30_SLEEP_CLK`;
- `mock_utmi` = `GCC_USB30_MOCK_UTMI_CLK`.

QMP USB3 PHY:

- `aux` = `GCC_USB3_PHY_AUX_CLK`;
- `ref` = `GCC_USB3_CLKREF_CLK`;
- `cfg_ahb` = `GCC_USB_PHY_CFG_AHB2PHY_CLK`;
- `pipe` = `GCC_USB3_PHY_PIPE_CLK`.

QUSB2 PHY:

- `cfg_ahb` = `GCC_USB_PHY_CFG_AHB2PHY_CLK`;
- `ref` = `GCC_RX1_USB2_CLKREF_CLK`.

These lists match their current bindings. The remaining problem is enablement
and Type-C policy, not missing clock phandles.

### Proper upstream adoption of legacy behavior

Downstream obtains cable attach, role, negotiated speed, and CC orientation from
the PMI8998 Type-C/PD PHY. It chooses the corresponding SuperSpeed lane before
resuming the QMP PHY. Mainline's QMP driver supports Type-C orientation events,
but the current PMIC Type-C binding/driver covers later PMICs and has no
`qcom,pmi8998-typec` compatible.

Therefore SuperSpeed must not be enabled by a clocks-only DTS edit. The proper
sequence is:

1. add source-correct PMI8998 Type-C port/PD support to the existing Qualcomm
   PMIC Type-C/TCPM architecture, using exact register/IRQ differences;
2. describe the USB-C connector and endpoint graph;
3. connect DWC3 role switching and QMP orientation switching;
4. port only Joan's QMP analog tuning that has a current binding/driver
   representation (or add a reviewed representation when required);
5. then remove Joan's USB2-only overrides and enable/test the QMP PHY.

### Device acceptance

Test both plug orientations, peripheral and host roles where supported, USB2
fallback, SuperSpeed enumeration and actual transfer rate, disconnect/reconnect,
suspend/wake, and recovery to the known USB2 gadget path. Keep USB3 bring-up
separate from all GPU and storage clock tests.

## Status summary

| Lane | Source result | Code status | Device status |
|---|---|---|---|
| SDCC2 | modern clock ownership complete | no clock patch needed | existing operation; new lane-specific acceptance pending |
| UFS + PHY | modern clock ownership complete | no clock patch needed | existing operation; new lane-specific acceptance pending |
| GPU IREF | missing owner directly proven | four commits + full post-commit build + sealed RAM-only image host-qualified | not tested |
| GPU ISENSE | legacy behavior fully mapped | blocked on proper A540 LM/DVFS integration | not tested |
| GPU SNOC DVM | newer-upstream SMMU precedent; MSM8998 binding gap | audit only | not tested |
| USB clocks | modern DWC3/QUSB2/QMP ownership complete | no clock patch needed | USB2 proven historically |
| USB3/Type-C | V30 capability proven; orientation/role path missing | PMI8998 Type-C port required before enablement | not tested in mainline |

No phone was booted, flashed, written, or otherwise touched during this audit.

Assisted-by: Hermes-Agent:moa/deep-flash
Date: 2026-08-11
Update-scope: four-lane clock ownership and USB3 capability audit.

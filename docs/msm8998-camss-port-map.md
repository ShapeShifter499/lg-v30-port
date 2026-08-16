# msm8998 CAMSS port map — hardware addresses and the sdm660 template

- **Written-by:** Ember Nymbrand (agent-ember)
- **Agent-harness:** Claude-Code:claude-opus-5
- **Date:** 2026-08-15, America/Los_Angeles
- **Status:** reference only. Nothing here has been built or booted. It exists
  so the camera lane starts from an authoritative hardware map instead of a
  blank page.

## Why this is a port and not a driver

Upstream CAMSS has no `qcom,msm8998-camss`. But msm8998's camera IP is the
**same generation as sdm660**, which *is* supported, and the block counts match
exactly:

| | CSIPHY | CSID | VFE | ISPIF |
|---|---|---|---|---|
| sdm660 (`sdm660_resources`, mainline) | 3 | 4 | 2 | yes |
| msm8998 (downstream `msm8998-camera.dtsi`) | 3 | 4 | 2 | yes |

Downstream IP versions: `qcom,csiphy-v5.0`, `qcom,csid-v5.0`,
`qcom,ispif-v3.0`, `qcom,vfe48`. sdm660 is the VFE 4.8 / ISPIF generation, so
`CAMSS_660` is the right `.version` to reuse.

That makes this a **resource-table addition** modelled on `sdm660_resources`,
not new ISP logic.

## Hardware map (from downstream `arch/arm64/boot/dts/qcom/msm8998-camera.dtsi`)

| block | reg base | size | IRQ (GIC SPI) |
|---|---|---|---|
| CSIPHY0 | `0x0ca34000` | `0x1000` | 78 |
| CSIPHY1 | `0x0ca35000` | `0x1000` | 79 |
| CSIPHY2 | `0x0ca36000` | `0x1000` | 80 |
| CSID0 | `0x0ca30000` | `0x400` | 296 |
| CSID1 | `0x0ca30400` | `0x400` | 297 |
| CSID2 | `0x0ca30800` | `0x400` | 298 |
| CSID3 | `0x0ca30c00` | `0x400` | 299 |
| ISPIF | `0x0ca31000` | `0xc00` | 309 |
| VFE0 | `0x0ca10000` | `0x4000` | 314 |
| VFE1 | `0x0ca14000` | `0x4000` | 315 |
| CCI | `0x0ca0c000` | `0x4000` | 295 |

ISPIF also takes a second range, `csi_clk_mux` (see the downstream node);
VFE0/1 each take a second range named `vfe_vbif`.

## Clocks — mainline already has all of them

This was expected to be the bulk of the work. It is not: **every CAMSS clock
downstream uses is already exported by `qcom,mmcc-msm8998.h` and wired into
`drivers/clk/qcom/mmcc-msm8998.c`.** Spot-checked `CAMSS_AHB_CLK`,
`CAMSS_ISPIF_AHB_CLK`, `CAMSS_VFE0_CLK`, `CAMSS_CSI0_CLK`, `CSIPHY_CLK_SRC`,
`CAMSS_CPHY_CSID0_CLK`, `CAMSS_VFE_VBIF_AXI_CLK` — all present in the driver's
clock table. So there is **no clock driver gap**; this is a naming exercise.

| downstream name | mainline ID | notes |
|---|---|---|
| `camss_ahb_clk` | `CAMSS_AHB_CLK` (111) | |
| `camss_top_ahb_clk` | `CAMSS_TOP_AHB_CLK` (110) | |
| `ispif_ahb_clk` / `camss_ispif_ahb_clk` | `CAMSS_ISPIF_AHB_CLK` (103) | |
| `csi_src_clk` | `CSI{0..3}_CLK_SRC` (20–23) | per CSID index |
| `csi_clk` | `CAMSS_CSI{0..3}_CLK` (87/91/95/99) | |
| `csi_ahb_clk` | `CAMSS_CSI{0..3}_AHB_CLK` (88/92/96/100) | |
| `csi_rdi_clk` | `CAMSS_CSI{0..3}RDI_CLK` (89/93/97/101) | |
| `csi_pix_clk` | `CAMSS_CSI{0..3}PIX_CLK` (90/94/98/102) | |
| `cphy_csid_clk` | `CAMSS_CPHY_CSID{0..3}_CLK` (130–133) | |
| `csiphy_clk_src` | `CSIPHY_CLK_SRC` (24) | |
| `csiphy_timer_src_clk` | `CSI{0..2}PHYTIMER_CLK_SRC` (25–27) | per CSIPHY index |
| `csiphy_timer_clk` | `CAMSS_CSI{0..2}PHYTIMER_CLK` (84–86) | |
| `vfe_clk_src` | `VFE{0,1}_CLK_SRC` (53/54) | per VFE index |
| `camss_vfe_clk` | `CAMSS_VFE{0,1}_CLK` (118/119) | |
| `camss_vfe_ahb_clk` | `CAMSS_VFE{0,1}_AHB_CLK` (116/117) | |
| `camss_vfe_stream_clk` | `CAMSS_VFE{0,1}_STREAM_CLK` (128/129) | |
| `camss_vfe_vbif_ahb_clk` | `CAMSS_VFE_VBIF_AHB_CLK` (122) | shared |
| `camss_vfe_vbif_axi_clk` | `CAMSS_VFE_VBIF_AXI_CLK` (123) | shared |
| `camss_csi_vfe_clk` | `CAMSS_CSI_VFE{0,1}_CLK` (126/127) | |
| CCI | `CCI_CLK_SRC` (18), `CAMSS_CCI_CLK` (104), `CAMSS_CCI_AHB_CLK` (105) | |
| sensor MCLKs | `CAMSS_MCLK{0..3}_CLK` (106–109) | for the sensor nodes |

Downstream also lists `mmssnoc_axi`, `mnoc_ahb`, `bimc_smmu_ahb/axi` on every
block. Those are bus/SMMU clocks that mainline handles through the interconnect
and IOMMU frameworks rather than per-device clock lists — do **not** port them
into the resource table verbatim; compare against what `sdm660_resources`
actually lists.

## Clock rates (from downstream `qcom,clock-rates`, indexed against the names)

Only a few clocks are rate-set; everything else is `0` (parent/gate only).

| block | clock | rate |
|---|---|---|
| CSIPHY | `csi_src_clk` | 274 290 000 |
| CSIPHY | `csiphy_timer_src_clk` | 200 000 000 |
| CSIPHY | `csiphy_clk_src` | 274 290 000 |
| CSID | `csi_src_clk` | 274 290 000 |
| CSID | `csiphy_clk_src` | 274 290 000 |
| ISPIF | *(all zero — no rate setting)* | — |
| VFE0/1 | `vfe_clk_src` | **480 000 000 / 576 000 000 / 600 000 000** |

The VFE arrays are 39 entries for 13 clock names — that is **three OPP levels
of 13**, not one flat list. Index 6 (`vfe_clk_src`) is the only rate-set entry
in each level, giving 480 / 576 / 600 MHz (low / nominal / turbo). Mainline
expresses that as the `clock_rate` array in the VFE resource entry; do not
collapse it to a single value.

## Supplies (downstream `*-supply` properties)

| block | supplies |
|---|---|
| CSIPHY | `gdscr`, `smmu` |
| CSID | `gdscr`, `mipi-csi-vdd`, `sec`, `smmu` |
| ISPIF | `camss-vdd`, `vfe0-vdd`, `vfe1-vdd` |
| VFE0/1 | `camss-vdd`, `smmu-vdd`, `vdd` |

Most of these are **GDSCs, not regulators** (`gdscr`, `camss-vdd`, `vfe*-vdd`,
`smmu*`). Mainline models GDSCs as `power-domains` off `mmcc`, not as
`*-supply` entries — so these mostly become `power-domains`, and the sdm660
resource entries' `vdda`/`vdd_sec` pattern should be followed rather than a
literal transcription. `mipi-csi-vdd` on CSID looks like a genuine rail and
needs tracing to a board regulator.

## The worked reference is sdm630 — and msm8998 differs in exactly 4 ways

`sdm660.dtsi` has **no** camss node (the driver supports `qcom,sdm660-camss`
but nothing in-tree instantiates it). The real worked example is
**`sdm630.dtsi`**, same SoC family, which uses `qcom,sdm660-camss` and
`sdm660_resources`.

Comparing it against the msm8998 downstream map above, **the CSID, ISPIF and
VFE addresses and every interrupt are identical**:

| block | sdm630 | msm8998 | |
|---|---|---|---|
| CSID0–3 | `0xca30000/0400/0800/0c00` | same | ✅ |
| ISPIF | `0xca31000` | same | ✅ |
| VFE0/1 | `0xca10000` / `0xca14000` | same | ✅ |
| IRQs | csid 296–299, csiphy 78–80, ispif 309, vfe 314/315 | same | ✅ |

**The four differences — this is the whole port:**

1. **CSIPHY register bases.** sdm630 puts them at `0x0c824000/5000/6000`;
   msm8998 has `0x0ca34000/5000/6000`, size `0x1000`.
2. **No CSIPHY clk_mux.** sdm630 declares `csiphy{0,1,2}_clk_mux` at
   `0xca00120/124/128`; msm8998 downstream has only a single `csiphy` range per
   PHY. So `csiphy_res_660`'s `.reg = { "csiphyN", "csiphyN_clk_mux" }` cannot
   be reused as-is.
3. **`CSIPHY_AHB2CRIF_CLK` does not exist on msm8998** — the `csiphy_ahb2crif`
   clock in `csiphy_res_660` must be dropped.
4. **`THROTTLE_CAMSS_AXI_CLK` does not exist on msm8998** — the `throttle_axi`
   clock in `vfe_res_660` must be dropped.

**Consequence:** msm8998 needs its **own** `csiphy_res_8998` and `vfe_res_8998`
arrays. It can reuse `csid_res_660` and `ispif_res_660` shape directly, and
`.version = CAMSS_660` with `vfe_ops_4_8` / `csid_ops_4_7` /
`csiphy_ops_3ph_1_0`. This corrects the earlier assumption in this file that
`sdm660_resources` could be reused wholesale — it cannot.

**Still a judgment call:** the `hw_ops`/`formats` selections above are inferred
from the IP-version match (vfe48 → `vfe_ops_4_8`) and the identical block
topology, not proven. The first probe attempt will confirm or refute quickly —
CAMSS failing to probe is benign, unlike the memory-map class of error.

## What still has to be worked out

1. **SMMU stream IDs.** CAMSS sits behind `cd00000.iommu`, which now probes
   cleanly (verified 2026-08-15 during the display check), so this is no longer
   a blocker — but the stream IDs still need declaring.
2. **GDSC → power-domain mapping.** Confirm which `mmcc` GDSCs correspond to
   the downstream supply names above.
3. **Everything else is specified.** Addresses, IRQs, clock names, clock rates
   and supply topology are all captured here from downstream, none invented.

## Sensors are a separate, harder problem

joan (US998) uses **IMX351** + **S5K3M3** (rear) and **HI553** (front).
**None has an upstream driver.** Nearest siblings are `imx355.c`, `s5k3m5.c`,
`hi556.c` — suggestive, not drop-in; do not assume register compatibility
without a datasheet or the downstream register tables.

So even a perfect CAMSS port yields no image on its own. Realistic sequencing:
CAMSS core first (provable by `/dev/video*` + `media-ctl` topology appearing),
sensors after, and treat them as separate milestones.

## Provenance note

Every address and IRQ above is read from downstream; none is inferred. The
generation match is inferred from IP version strings plus block counts, which
is strong but not proof — the first build will confirm or refute it quickly.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-15

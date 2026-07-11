# Display path verdict (parcel P3) — DPU1, not MDP5

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

## Verdict

Use the **DPU1** driver, not MDP5. The old assumption behind this parcel
("DSC on MDP5 feasibility") is obsolete: mainline
`drivers/gpu/drm/msm/disp/dpu1/catalog/dpu_3_0_msm8998.h` provides a full
MSM8998 DPU catalog **including both DSC 1.1 blocks** (`dsc_0`, `dsc_1`),
which is exactly the dual-encoder 720+720 split the downstream panel config
uses. MDP5 in mainline has no DSC wiring and would be a dead end for this
DSC-mandatory panel.

## What M4 actually needs (work list)

1. **DTS (kernel repo):** enable/add for msm8998-lge-joan:
   - `&mdss` + DPU (`qcom,msm8998-dpu`) + `&mdss_dsi0` +
     `&mdss_dsi0_phy` (10nm-8998 PHY) — nodes exist in msm8998.dtsi,
     currently disabled;
   - panel node under dsi0: reset TLMM 35, TE 10, two gpio-enabled
     fixed regulators (vddio TLMM 92, vpnl TLMM 69);
   - CAUTION: display blocks sit behind the MMSS clock controller and the
     mmss SMMU (`cd00000.iommu` — one of the two TZ-owned SMMUs that
     currently fail deferred probe with -110). Expect the SMMU to become a
     REAL blocker here; likely needs the qcom smmu handoff quirks
     (stream-mapping inheritance) rather than the K030-style skip.
2. **Panel driver (kernel repo):** new `panel-lge-sw43402.c` modeled on
   `panel-sony-akatsuki-lgd.c` (closest in-tree example: DSC cmd-mode OLED
   with PPS via mipi_dsi_picture_parameter_set). Data from
   `docs/panel-sw43402.md` + downstream refs.
3. **Kernel config:** DRM=y (currently =m; fine once modules ship — pmOS
   rootfs installs modules, unlike our bringup ramdisk) or force built-in
   for early bringup images.
4. **Test order:** DPU+DSI probe clean (no panel) → panel probe + init
   sequence (expect black) → first frame via pmOS (fbcon/directfb test) →
   touch (P4, stmfts) afterwards.

## Risks, in order

1. mmss SMMU (TZ-owned, cd00000) — display buffers go through it.
2. DSC PPS mismatch (slice 720x16, 8bpc/8bpp — must match downstream bit-
   exactly or the panel shows garbage/black).
3. 129-command init sequence transcription errors.
4. MMSS clock tree gaps in mainline msm8998 (mmcc driver exists; joan adds
   nothing custom per downstream).

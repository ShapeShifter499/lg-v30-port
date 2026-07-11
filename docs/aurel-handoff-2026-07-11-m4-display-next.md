# Handoff — M4 reaches DRM fb0; DSI VCO fixed but output dividers remain stale

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

## Milestone state

- M1 mainline userspace/USB: done.
- M2 UFS + microSD: done.
- M3 headless postmarketOS: done.
- M4 built-in display: **in progress**. The former mmss-SMMU probe/reset gate is fixed and DRM reaches fb0, but the SW43402 panel remains physically black.
- M5 wifi/BT: not started.

## What changed after Ember's K059 handoff

1. K059's module-less image did not contain the complete display dependency chain. K060 made MSM8998 GPUCC, MMCC, SW43402, and backlight support built-in.
2. K061 kept MMCC/display built in but removed GPUCC. Raw pstore then showed the decisive failure: when `c900000.display-subsystem` joined mmss SMMU group 0, SID0 immediately raised a stage-1 translation fault on boot-framebuffer address `0x9ddaaa00`.
3. K062 added `qcom,msm8998-mdss` to the Qualcomm SMMU identity-domain client table. The phone survived, enumerated the mainline gadget, initialized DPU/DSI/DRM, and registered fb0. Lance still saw a completely black screen.
4. K062 live diagnostics showed DSI-1 connected and 1440x2880 active, but `pclk0_clk_src` and `byte0_clk_src` RCG updates failed. Clock summary retained stale half-rates (57,036,853 and 42,777,639 Hz), followed by command-mode commit/vblank timeouts.
5. K063 tested `CLK_OPS_PARENT_ENABLE` on byte0/pclk0. This was a clear regression: DSI PLL zero-divisor/lock failures and clock imbalance warnings appeared; screen remained black. The change was fully reverted.
6. K064 tested the public MSM8998 `CLK_GET_RATE_NOCACHE` clock fix (`878adc31071b`). It made no difference: same RCG warnings, same 57/42-MHz pixel/byte outputs, and the screen remained black.
7. K065 tested public MSM8998 commit `707f3fc86f6a` (`drm/msm/dsi_phy_10nm: Fix bad VCO rate calculation`). It corrected the exact factor-of-two error at the VCO: `dsi0vco_clk` became 1.368884472 GHz. The PLL output divider and MMCC RCGs still failed to latch, leaving 57/42-MHz output clocks and a black panel.

## Kernel source state

Repository: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30`

Branch: `joan/latest-clean-test`

Current clean source commit:

- `7ff461605d7f71b528785913cee116e1e49ecb00`
- `iommu/arm-smmu-qcom: Add MSM8998 MDSS identity domain`

The commit was RAM-boot verified by K062 but has not been pushed. It carries:

- `Signed-off-by: Lance <Gero3977@gmail.com>`
- `Assisted-by: Hermes:gpt-5.6-sol`

The no-cache K064 source change was reverted after showing no improvement. The worktree currently carries only K065's three-line 10nm VCO calculation patch while its interaction with the stale output-divider/RCG programming is investigated. It is not committed yet.

## Key artifacts

- K061 raw failure evidence:
  - `out/k061-mmcc-only-pstore-20260711T1500Z.strings.txt`
  - sha256 `6cc3c6c22a5095834e5aca8a394c7126ceb0751491b925443c7820a799bcc3ef`
- K062 verified survivor image:
  - `out/boot-joan-20260711-aurel-k062-msm8998-mdss-identity.img`
  - sha256 `f5b2f95539c8f1fcb6cf41047663c85b0e4007b06effa93fb79a0602a40db7b1`
- K062 dmesg:
  - `out/k062-dmesg-2026-07-11.txt`
  - sha256 `5d28e85ca28c1f9d4dc095a8b247440a7fa5a1b210bb1fec4a5c970ecf7f7943`
- K062 live DRM/clock diagnostics:
  - `out/k062-live-display-diag-2026-07-11.txt`
  - sha256 `22df69232cf970fc62796ff035d090dffd39d6bc480f6f9f36df261d70577170`
- K063 rejected image and dmesg:
  - `out/boot-joan-20260711-aurel-k063-dsi-parent-enable.img`
  - `out/k063-dmesg-2026-07-11.txt`
- K064 tested image:
  - `out/boot-joan-20260711-aurel-k064-dsi-rate-nocache.img`
  - sha256 `1880b11f42d2f30f482f39a589547a36bc2bf8fbb6eea8aa3d0f5e7ccaaa8983`
- K064 full patch artifact (K062 identity fix + no-cache clock test):
  - `out/20260711-aurel-k064-dsi-rate-nocache.patch`
  - sha256 `44ca62d58616b82adde68d645c33ceddf3bb568cbb55ac23377a39b55c5a8366`
- K064 diagnostics:
  - `out/k064-dmesg-2026-07-11.txt`
  - `out/k064-live-display-diag-2026-07-11.txt`
- K065 VCO-fix image:
  - `out/boot-joan-20260711-aurel-k065-10nm-vco-rate.img`
  - sha256 `cfe1e802c28087ded8c03d8318bd2b28ee930734c69a48fad2d87def54fbb993`
- K065 diagnostics:
  - `out/k065-dmesg-2026-07-11.txt`
  - `out/k065-live-display-diag-2026-07-11.txt`

The complete K060-K065 evidence and interpretation is appended to `docs/kernel-change-ledger.md`.

## Device state

Lance physically recovered the phone after K063. K064 and K065 were then tested RAM-only and each recovered cleanly using `reboot -f` over ACM.

Current verified state after K065:

1. Normal LineageOS is booted.
2. Authorized ADB is restored (`LGUS9986e606d55`, `LG-US998`).
3. `sys.boot_completed=1` was verified.
4. No partition was flashed.

## Next investigation

Do not stack another speculative clock flag. K064 and K065 establish two separate facts:

- CCF rate caching is not the first-takeover blocker.
- Correcting the 10nm VCO formula doubles the VCO as predicted, but the PLL output divider and MMCC RCG `CMD_UPDATE` still do not latch.

The next patch/test should be chosen only after tracing the MSM8998 DSI PLL output-divider and MMCC RCG programming order against the public MSM8998 tree and downstream clock sequencing. Also determine whether the repeated SID0 boot-framebuffer faults independently prevent a visible frame despite an active DRM CRTC.

For any next RAM-only image, capture live dmesg and clock summary over ACM, explicitly ask Lance about visible screen state, and recover to LineageOS before changing another variable.

## Source provenance

Reference clone:

- `https://gitlab.com/msm8998-mainline/linux.git`
- temporary filtered/sparse checkout: `/tmp/msm8998-mainline-linux-ref`
- checkout tip: `2b7263ccccbdafba3e8696349d9a3e9b115c6dd8`
- relevant clock commits:
  - `878adc31071b02c1511e8908974a78dcb8d3dff0` (no-rate-cache; K064 no change)
  - `707f3fc86f6a24e9f710887eb028bd8d0df82580` (10nm VCO calculation; K065 partial correction)

Recorded in `docs/dependency-tracker.md`.

## Safety remains binding

- RAM-only `fastboot boot`; no partition flash for these display diagnostics.
- Enter fastboot via authorized ADB only.
- Never run `fastboot getvar` on LG aboot.
- Do not read `tzdbg/*`.
- One fastboot client/process only.
- Preserve exact image hashes and capture dmesg/pstore evidence before interpreting screen behavior.

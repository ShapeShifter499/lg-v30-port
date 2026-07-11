# Handoff — M4 reaches DRM fb0; K064 clock candidate waits on phone recovery

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
6. The public `msm8998-mainline/linux` fork contains a more specific known fix, commit `878adc31071b`: `CLK_GET_RATE_NOCACHE` on MSM8998 byte0/byte1/pclk0/pclk1 because VCO shutdown can clear hardware rate state while CCF retains a stale cache. K064 is built with this patch but has not been booted.

## Kernel source state

Repository: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30`

Branch: `joan/latest-clean-test`

Current clean source commit:

- `7ff461605d7f71b528785913cee116e1e49ecb00`
- `iommu/arm-smmu-qcom: Add MSM8998 MDSS identity domain`

The commit was RAM-boot verified by K062 but has not been pushed. It carries:

- `Signed-off-by: Lance <Gero3977@gmail.com>`
- `Assisted-by: Hermes:gpt-5.6-sol`

The unverified no-cache source change is not left dirty in the kernel tree. It is preserved in the K064 image/patch artifacts below.

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
- K064 staged image:
  - `out/boot-joan-20260711-aurel-k064-dsi-rate-nocache.img`
  - sha256 `1880b11f42d2f30f482f39a589547a36bc2bf8fbb6eea8aa3d0f5e7ccaaa8983`
- K064 full patch artifact (K062 identity fix + no-cache clock test):
  - `out/20260711-aurel-k064-dsi-rate-nocache.patch`
  - sha256 `44ca62d58616b82adde68d645c33ceddf3bb568cbb55ac23377a39b55c5a8366`

The complete K060-K064 evidence and interpretation is appended to `docs/kernel-change-ledger.md`.

## Device state / hard gate

After K063, mainline remained reachable long enough to capture dmesg. A paced ACM command wrote `b` to `/proc/sysrq-trigger`; the phone then disappeared from USB and did not return to LineageOS within 180 seconds. No partition was flashed.

**Do not run another device command or K064 until Lance physically holds Power + Volume Down for about 8–10 seconds and confirms the phone has recovered.** Then verify:

1. Normal LineageOS appears on screen.
2. `sudo adb devices -l` shows authorized `device` state.
3. No stale `fastboot` process exists.
4. Only then run the standard one-shot RAM-only `fastboot boot` workflow.

## Next test: K064

Use exactly:

`out/boot-joan-20260711-aurel-k064-dsi-rate-nocache.img`

Expected discriminator:

- Improvement: no stale-rate behavior/RCG warning, DSI clock rates change to the requested values, commit/vblank succeeds, and the screen lights.
- No change: same RCG warnings and half-rates as K062; the no-cache patch is insufficient.
- Regression: DSI PLL lock/zero-divisor behavior like K063; stop and recover, do not stack more clock flags.

Capture live dmesg over ACM as soon as `18d1:4e26` appears. Ask Lance about visible screen state. If mainline cannot be reached, recover to LineageOS and extract raw pstore before another experiment.

## Source provenance

Reference clone:

- `https://gitlab.com/msm8998-mainline/linux.git`
- temporary filtered/sparse checkout: `/tmp/msm8998-mainline-linux-ref`
- checkout tip: `2b7263ccccbdafba3e8696349d9a3e9b115c6dd8`
- relevant commit: `878adc31071b02c1511e8908974a78dcb8d3dff0`

Recorded in `docs/dependency-tracker.md`.

## Safety remains binding

- RAM-only `fastboot boot`; no partition flash for these display diagnostics.
- Enter fastboot via authorized ADB only.
- Never run `fastboot getvar` on LG aboot.
- Do not read `tzdbg/*`.
- One fastboot client/process only.
- Preserve exact image hashes and capture dmesg/pstore evidence before interpreting screen behavior.

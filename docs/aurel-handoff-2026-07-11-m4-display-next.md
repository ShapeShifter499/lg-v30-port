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
8. K066 confirmed `clk_ignore_unused` does not clear the earlier RCG update failures. Source audit then found the MSM8998 DSI controller's mandatory 0.9-V `vdd` rail missing from joan; K067 added the exact PM8998 L1 supply used by downstream and the public working MSM8998 OnePlus DTS. K067 booted despite the harness being interrupted after `fastboot boot`: passive USB/ACM checks proved live mainline. The dummy-regulator warning disappeared, but the same pclk0/byte0 RCG and commit-timeout path remained. No reliable K067 physical screen observation was captured, so its visible result is explicitly unobserved.
9. K067 framebuffer/KMS state mapped the active framebuffer at fresh IOVA `0x2000`, and active `sspp_8`/DMA0 latched `0x2000`. Reserved boot-splash addresses appeared only in inactive SSPPs. SID0 splash faults therefore explain loss of the inherited splash during handoff, not persistent black output after DRM owns a fresh framebuffer.

## Kernel source state

Repository: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30`

Branch: `joan/latest-clean-test`

Current clean source tip:

- `b549c9f5b32a42dfa4a100d33df804e8ed042287`
- `arm64: dts: qcom: msm8998-lge-joan: Add DSI VDD supply`

New local source-backed commits after the SMMU fix:

- `5306416d22b41dbf64d04887cdaa368fe6388e3e` — exact public
  `drm/msm/dsi_phy_10nm: Fix bad VCO rate calculation` change from
  `707f3fc86f6a`, preserving original author AngeloGioacchino Del Regno.
- `b549c9f5b32a42dfa4a100d33df804e8ed042287` — joan DSI controller
  `vdd-supply = <&vreg_l1a_0p875>;` correction.

The earlier `7ff461605d7f71b528785913cee116e1e49ecb00` MSM8998 MDSS
identity-domain commit was RAM-boot verified by K062. All three commits remain
local/unpushed and carry Lance's sign-off plus the live Hermes model trailer.
The no-cache K064 source change and K066 cmdline diagnostic are not retained in
the source tree. The kernel worktree is clean after a successful `Image.gz dtbs`
rebuild.

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
- K066 diagnostic image and dmesg:
  - `out/boot-joan-20260711-aurel-k066-vco-clk-ignore-unused.img`
  - sha256 `8c6100b2842a75b513cf8a79202d23b44df4ae1f04c6e7abfa817cf780f6102f`
  - `out/k066-dmesg-2026-07-11.txt`
  - sha256 `1cf6f933e726176e7e24046fce4588d3198e3b37caad2f65354a29aba5fb64ad`
- K067 VCO + real DSI supply image:
  - `out/boot-joan-20260711-aurel-k067-dsi-vdd-vco.img`
  - sha256 `f5aceb687f12b172f137e21882d8f4b695d7a8c13c0d672a5a24e3c0e1792b52`
- K067 transcript and diagnostics:
  - `out/k067-dsi-vdd-vco-ramboot-20260711T161252Z.log`
  - `out/k067-dmesg-2026-07-11.txt`
  - `out/k067-live-display-diag-2026-07-11.txt`
  - `out/k067-live-fb-kms-diag-2026-07-11.txt`
  - hashes are recorded in `docs/kernel-change-ledger.md`.
- Exact checkpoint commit patches:
  - `out/20260711-aurel-k065-vco-commit-5306416.patch`, sha256
    `eabc6a516d9dea24007b7f3cf69858da540fe5cfe6a0c3713988735afc9c2bf6`.
  - `out/20260711-aurel-k067-dsi-vdd-commit-b549c9f.patch`, sha256
    `a6f5248bcb4e1726e72435eefd0f96a997eb41bf6032a94b017a89882eea0b53`.

The complete K060-K067 evidence and interpretation is appended to `docs/kernel-change-ledger.md`.

## Device state

Lance physically recovered the phone after K063. K064-K067 were then tested
RAM-only and each recovered cleanly using `reboot -f` over ACM. K066 and K067
have no reliable physical screen observation; prompt timeout/silence is not an
observation.

Current verified state after K067:

1. Normal LineageOS is booted.
2. Authorized ADB is restored (`LGUS9986e606d55`, `LG-US998`).
3. `sys.boot_completed=1` was verified.
4. No partition was flashed.

## Next investigation

Do not stack another speculative clock flag. K064-K067 establish four separate
facts:

- CCF rate caching is not the first-takeover blocker.
- Correcting the 10nm VCO formula doubles the VCO as predicted, but the PLL
  output divider and MMCC RCG `CMD_UPDATE` still do not latch.
- `clk_ignore_unused` does not affect the earlier programming failure.
- The real DSI VDD supply removes a genuine dummy-regulator fallback but does
  not clear the evidenced RCG/commit-timeout path.

The K067 fb/KMS capture also removes the leading SMMU-framebuffer theory: DRM
maps a fresh IOVA and active DMA0 latches it. The next patch/test should be
chosen only after tracing the MSM8998 DSI PLL output-divider and MMCC RCG
programming/enable order against the public MSM8998 tree and downstream clock
sequencing. Start at the earliest divider/RCG update that fails to latch; do not
revisit the inactive boot-splash addresses as the primary black-screen cause.

For any next RAM-only image, capture live dmesg and clock summary over ACM,
explicitly ask Lance about visible screen state with the five-minute prompt,
and recover to LineageOS before changing another variable.

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

## Follow-up — K068 result and downstream 4.4 clue

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- K068 retested K063's active `byte0_clk_src`/`pclk0_clk_src`
  `CLK_OPS_PARENT_ENABLE` change after the VCO and DSI-VDD fixes. It is still not
  a solution: Lance observed a completely black/off display and dmesg gained
  PLL0 lock/clock-balance failures.
- The test was nevertheless discriminating. K067's four RCG update failures
  disappeared, proving the MMCC roots can update while the parent is live.
  The resulting tree remained wrong: VCO 1.368884472 GHz, inherited `/4`
  PLL output 342.221118 MHz, byte 42.777639 MHz, and pixel 171.110559 MHz.
- The first K068 fastboot transfer hung before `OKAY` and is not a kernel result.
  A single explicitly approved retry booted mainline. The phone was then
  recovered to fully booted authorized LineageOS; no partition was flashed.
- The K068 patch is preserved under `out/` and reverted from the kernel. A clean
  `Image.gz dtbs` rebuild completed; kernel source is clean at the K067 tip.
- Full audit of Ember's eleven handoff documents and the project-history index
  is complete for current-work clues. Older reset-hunt conclusions remain valid
  context but do not supply a later display fix that K060-K068 missed.
- The strongest new clue is direct downstream 4.4 behavior:
  `mdss-dsi-pll-8998.c::dsi_pll_enable()` writes `PLL_PLL_OUTDIV_RATE` before
  starting and checking PLL lock, with an explicit comment that output-divider
  selection otherwise happens too late. Mainline's 10nm VCO prepare path omits
  this ordering step and joan keeps its inherited `/4` state.

Do not select another broad clock flag. The next candidate should isolate that
one pre-lock output-divider ordering difference while preserving K068 as the
control. Keep it debug-only unless a generic mainline-safe implementation is
demonstrated on more than joan.

## Follow-up — K069 pre-lock `/2` result

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

- K069 implemented the narrow downstream-inspired discriminator: K068's
  parent-enable control plus a MSM8998-only `/2` output-divider write immediately
  before PLL start/lock.
- The RAM-only boot survived, but Lance again observed completely black/off.
  RCG update warnings remained cleared, while a PLL0 lock failure remained.
- Final live rates were unchanged from K068: `/4` PLL output 342.221118 MHz,
  pixel 171.110559 MHz, and byte 42.777639 MHz. The `/2` write therefore did not
  persist into the final live tree and did not reproduce downstream's complete
  cached-selection behavior.
- Phone recovered cleanly to fully booted authorized LineageOS. The K069 patch
  is preserved under `out/`, reverted from source, and the clean kernel rebuilt.

Next should be instrumentation, not another blind override: log the requested
VCO, cached divider, live output-divider register, `CLK_CFG0`, and `CLK_CFG1` in
VCO prepare and handoff save/restore. That will identify exactly where `/2` is
lost before attempting a generic fix.

## Follow-up — K070 identifies the zero-rate interaction

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

K070 captured the complete sequence. Joan's saved bootloader divider state is
already correct (`/2`, bit 1, pixel 3, mux 1). The failing early parent-enable
prepare instead receives `vco_current_rate=0`; the second zero-rate prepare fails
PLL lock. Once normal propagation sets VCO to ~1.3688845 GHz, every logged lock
poll succeeds with `/2`.

This is a patch interaction. The public-reference VCO formula fix removed the
recalc callback's state assignment, while upstream commit `8a48e35becb2`
subsequently added an initial recalc call that relies on that assignment to avoid
zero-rate restore. Current upstream source contains the assignment. K071 should
restore exactly that one line on top of K068's parent-enable control and drop
K069's hardcoded `/2` override and all K070 logging.

K070 showed black/off, then recovered cleanly to fully booted authorized
LineageOS. Its instrumentation is preserved under `out/`, reverted from source,
and the clean kernel rebuilt.

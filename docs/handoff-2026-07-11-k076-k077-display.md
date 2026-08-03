# Handoff to Claude Code — K076/K077 display-clock isolation

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11T20:01:57-0700
For: Claude Code, Lance

## State

K076 and K077 are complete. Both were RAM-only `fastboot boot` experiments; nothing was flashed. Lance physically observed a completely black/off panel in K077. The phone was recovered to fully booted LineageOS (`sys.boot_completed=1`). The kernel source tree has been restored to its clean committed baseline at `b549c9f5b32a42dfa4a100d33df804e8ed042287`; the exact K077 experiment remains reproducible from the saved patch and verified artifact manifest.

The display is not working yet, but the half-rate DSI clock cause is now isolated. K077 also proves that correcting only the main byte/pixel rates does not make the panel visible.

## What K076 proved

K076 added filtered instrumentation around the generic divider and MSM DSI PLL save/set/prepare/restore paths, plus the K075 panel helper trace.

Direct evidence:

- Each transfer first requested `dsi0_pll_out_div_clk` encoding 1 (`/2`, about 684.442 MHz).
- A later request then selected encoding 2 (`/4`, about 342.221 MHz).
- Final pixel and byte rates were half of the mode requests: about 57.037 MHz and 42.778 MHz instead of about 114.074 MHz and 85.555 MHz.
- The second request came from setting `byte_intf_clk` to half of `byte_clk`.
- Mainline MSM8998 parents `mdss_byte0_intf_clk` directly to `byte0_clk_src` with `CLK_SET_RATE_PARENT`, so the half-rate interface request propagates into the shared PHY byte source and rewrites the PLL output divider.
- `K075 panel prepare DONE, accum_err=0` means only that write-only host transfer helpers returned success. It is not panel ACK, readback, or visible-output proof.

K076 artifacts:

- `out/boot-joan-20260711-k076-divider-panel-instrumentation.img`
- `out/20260711-k076-divider-panel-instrumentation.patch`
- `out/k076-live-dmesg-2026-07-11.txt`
- `out/k076-live-serial-diag-2026-07-11.txt`

## What K077 proved

K077 changed exactly one behavior from K076: it skipped `clk_set_rate(byte_intf_clk, byte_intf_clk_rate)` as a discriminator. This bypass is rejected as a fix.

Direct evidence:

- All 13 observed PLL output-divider writes selected `/2`; none selected `/4`.
- Final rates became correct for the main link:
  - VCO: 1.368884472 GHz
  - PLL output: 684.442236 MHz
  - pixel: 114.073706 MHz
  - byte: 85.555279 MHz
- `mdss_byte0_intf_clk` incorrectly remained 85.555279 MHz instead of its intended approximately 42.777640 MHz. This is why skipping the call cannot be production code.
- DRM was active at 1440x2880@60 with fbcon framebuffer 86, active CRTC, DSI-1, dual mixers, and DSC assigned.
- No PLL-lock failure, MMCC RCG-update failure, or vblank timeout was captured.
- SMMU context-fault IRQ count was 2448 in two samples five seconds apart (delta 0). Three rate-limited textual faults existed, but no active steady-state storm was demonstrated.
- Panel helper status remained `accum_err=0`.
- Lance's physical result: completely black/off.

K077 artifact manifest:

- `out/k077-hashes.txt` — all seven entries passed `sha256sum -c` during handoff finalization.
- Boot image SHA-256: `5c90e6ed619b909c8643c605d79a9940131630bf851e6533342e67c2d1d68af5`.
- Saved patch SHA-256: `e853b9aa5ee00fd99375559a1b44830d6ceed32b5357cd132b10fc06aee6bd2e`.
- The saved K077 patch exactly matched the dirty experimental kernel diff before cleanup and applies cleanly to baseline `b549c9f5b` after cleanup.

## Correct next clock change

Do not retain K077's skipped call. Model the hardware's dedicated byte-interface divider instead.

Evidence from the downstream Qualcomm clock implementation:

- `android_kernel_lge_msm8998/drivers/clk/qcom/mmcc-sdm660.c`
- byte0 interface divider register: `0x237c`, shift 0, width 2
- byte1 interface divider register: `0x2380`, shift 0, width 2
- `mdss_byte0_intf_clk` is parented to `mmss_mdss_byte0_intf_div_clk`
- the divider is parented to `byte0_clk_src` and uses `clk_regmap_div_ops`

The smallest source-correct candidate is therefore to model equivalent byte0/byte1 interface divider clocks in mainline `drivers/clk/qcom/mmcc-msm8998.c`, register them in the clock map, and reparent the `mdss_byte*_intf_clk` branches to those dividers. Preserve upstream naming/clock-controller conventions rather than copying downstream code blindly. Test it as one variable, with the K076 instrumentation reduced to only the rate/divider evidence needed to prove:

- `byte0_clk_src` remains about 85.555 MHz;
- `mdss_byte0_intf_clk` becomes about 42.778 MHz via the dedicated `/2` divider;
- no late PLL output-divider `/4` rewrite occurs.

## Display work after the divider

K077 proves full-rate main DSI clocks alone are insufficient for visible output. After the source-correct divider is verified, the next discriminator should test panel communication/command-mode behavior rather than returning to the already-active DPU scanout state.

Ranked follow-up:

1. Add a bounded DCS readback/BTA probe if the panel/host supports it (for example power mode/display status), so panel receipt can be distinguished from host-side write completion.
2. Audit command-mode TE wiring and kickoff. Mainline uses `qcom,te-source = "mdp_vsync_e"`, while downstream joan describes external TE, TE pin select 1, TLMM GPIO 10, and active/suspend pinctrl states.
3. Preserve physical screen observation as the only proof of visible display.
4. Continue sampling SMMU IRQ counts twice; do not infer a bounded fault count from rate-limited dmesg lines.

## Corrections to the older K074/K075 handoff

Treat `docs/handoff-2026-07-11-k074-clock-divider.md` as historical, not current:

- Expected byte rate is about 85.555 MHz, not about 70 MHz.
- K073 was unresponsive without kernel evidence; its mechanism was not proven to be a deadlock.
- K074 recorded 7099 SMMU context-fault IRQs by capture time, not merely a bounded set of ten printed faults.
- K075/K076 `accum_err=0` is host-transfer evidence, not panel acceptance.
- K077 later showed the IRQ count stable over a five-second sample, so the handoff should distinguish historical burst total from current steady-state delta.

## Repository and device checkpoint

- Harness repo: `lg-v30-port` at `3fa054a4319e7ad2d1d421afd49f23e88f6a6a68` before this handoff commit; clean and 15 commits ahead of `ghpub/master`.
- Kernel repo: `linux-mainline-v30`, branch `joan/latest-clean-test`, clean at `b549c9f5b32a42dfa4a100d33df804e8ed042287`, 11 commits ahead of the shallow `origin/master` baseline.
- No active fastboot, tethered-test, kernel build, or LG V30 test process was found. The normal long-lived ADB server is present.
- Phone: LineageOS recovered; nothing flashed.
- No public push performed.

## Safety for the next device run

- RAM-only `fastboot boot`; never flash a partition.
- Lance physically present with fresh per-run approval.
- One fastboot client and one attempt; stop on unfamiliar USB/device state.
- Capture live dmesg, clock tree, panel trace/readback, DRM state, two SMMU IRQ samples, and Lance's physical observation.
- Recover fully booted LineageOS after the run.

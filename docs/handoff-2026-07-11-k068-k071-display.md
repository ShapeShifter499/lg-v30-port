# Hermes Agent → Claude Code handoff — joan M4 display, K068-K071 PLL sequencing

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11
For: Claude Code

## Read this first

1. This handoff.
2. `README.md` for binding project and safety conventions.
3. `docs/kernel-change-ledger.md`, especially K068-K071.
4. `docs/handoff-2026-07-11-m4-display-next.md` for the full K060-K071 display trail.
5. `docs/dependency-tracker.md` and `docs/public-upstreaming-plan.md` before retaining imported or derived code.

Do not repeat the K068-K071 experiments before reading their raw patches and dmesg. Each was RAM-booted, observed, preserved, rejected, reverted, and followed by a clean rebuild.

## State in one paragraph

M1-M3 remain done. M4 reaches a connected 1440x2880 DSI connector and fb0 with a fresh framebuffer IOVA, but the SW43402 OLED remains black. K068 proved `CLK_OPS_PARENT_ENABLE` lets the MMCC pixel/byte RCGs update but exposes invalid early PLL preparation. K069 rejected a blind pre-lock `/2` output-divider write. K070 then proved the bootloader's saved divider state is already correct and isolated the early failure to `vco_current_rate=0`. K071 restored recalc's state side effect as a one-line test, but that collapsed the entire live DSI0 clock tree to 0 Hz and was rejected. The safest next discriminator is an instrumented, one-time, nonzero init seed while keeping recalc pure—not another divider override.

## Current repositories and device

Harness/docs repository:

- Path: `~/vibe-coding-projects/coding/lg-v30-port`
- Branch: `master`
- Tip before this handoff commit: `54938c226cef754777c7237a0831e84a221cb496`
- Local/unpushed: ahead of `ghpub/master`

Kernel repository:

- Path: `~/vibe-coding-projects/coding/linux-mainline-v30`
- Branch: `joan/latest-clean-test`
- Clean tip: `b549c9f5b32a42dfa4a100d33df804e8ed042287`
- Clean source-backed stack:
  - `7ff461605d7f71b528785913cee116e1e49ecb00` — MSM8998 MDSS identity domain
  - `5306416d22b41dbf64d04887cdaa368fe6388e3e` — corrected 10nm VCO formula from public MSM8998 reference
  - `b549c9f5b32a42dfa4a100d33df804e8ed042287` — joan DSI VDD supply
- Worktree is clean after post-K071 `Image.gz dtbs` rebuild.
- Clean `Image.gz` sha256: `95575b5f2fe87133a936c1ca8355011c39f97dc98d8524016771137babae610a`.

Phone:

- Fully booted authorized LineageOS.
- ADB device: `LGUS9986e606d55` / `LG-US998`.
- `sys.boot_completed=1` verified after K071 recovery.
- No fastboot client remains.
- No partition was flashed.

## K068-K071 conclusions

### K068 — parent-enable retest

Change:

- Added `CLK_OPS_PARENT_ENABLE` to MSM8998 MMCC `byte0_clk_src` and `pclk0_clk_src`.

Result:

- Lance observed completely black/off.
- Previous RCG update warnings disappeared, proving the roots can update with their parent live.
- PLL lock and clock-balance failures appeared.
- Live rates remained wrong: VCO ~1.368884472 GHz, PLL output 342.221118 MHz, pixel 171.110559 MHz, byte 42.777639 MHz.
- Rejected and reverted.

Important: the first K068 fastboot transfer stalled before `OKAY` and is transport evidence only. A separately approved retry produced the kernel result.

### K069 — blind pre-lock `/2`

Change:

- Kept K068 as an explicit control.
- Forced MSM8998 `PLL_OUTDIV_RATE=/2` immediately before PLL start/lock.

Result:

- Black/off.
- Final clock tree remained effectively identical to K068.
- The direct write did not reproduce downstream's logical cached-divider sequencing.
- Rejected and reverted.

### K070 — decisive ordering instrumentation

Instrumentation covered:

- initial handoff save;
- VCO prepare entry;
- after VCO programming;
- immediately before PLL start;
- lock result;
- restore entry and programmed state.

Direct findings from `out/k070-live-dmesg-2026-07-11.txt`:

1. Saved bootloader divider state is already correct:
   - outdiv `0x1` (`/2`)
   - bit divider `0x1`
   - pixel divider `0x3`
   - pixel mux `0x1`
2. `vco_current_rate` is 0 at initial save and early parent-enabled prepares.
3. One inherited zero-rate prepare reaches lock; the next zero-rate prepare fails with `-110`, even with `/2` forced.
4. Restore correctly reapplies `/2`, bit 1, pixel 3, mux 1.
5. Once normal propagation sets VCO to ~1.3688845 GHz, every logged lock poll succeeds with `/2`.

This supersedes the earlier assumption that the bootloader saved `/4`. The framework's later half-rate summary was not direct proof of saved hardware divider state.

### K071 — recalc side-effect restoration

Change:

- Dropped K069's hardcoded divider and K070 logging.
- Kept K068's parent-enable control.
- Restored `pll_10nm->vco_current_rate = vco_rate` inside recalc.

Result:

- Black/off.
- Four PLL-lock failure events.
- One byte0 RCG update failure.
- Three clock-disable imbalance warnings.
- 31 vblank timeouts.
- Final DSI0 VCO/output/bit/pixel/byte hierarchy: all 0 Hz.
- Rejected and reverted.

Do not reapply K071. A recalc while PLL registers are inaccessible or unprepared can observe zero and clobber valid state.

## Patch interaction that matters

Public MSM8998 reference commit:

- `707f3fc86f6a24e9f710887eb028bd8d0df82580`
- Corrects the factor-of-two VCO formula.
- Also removes recalc's `vco_current_rate` assignment.

Newer upstream commit:

- `8a48e35becb214743214f5504e726c3ec131cd6d`
- `drm/msm/dsi/dsi_phy_10nm: Fix missing initial VCO rate`
- Adds an init-time recalc so restore does not program VCO at 0 Hz.
- In its upstream context, recalc stores the result as a side effect.

Our exact imported older formula patch plus newer upstream init code breaks that implicit contract. K071 proves that globally restoring the side effect is not safe on this path.

## Recommended next discriminator: K072, if you agree after reviewing raw evidence

Treat K068 parent-enable as a diagnostic control, not a production fix.

One behavioral variable only:

1. Keep `dsi_pll_10nm_vco_recalc_rate()` observational/pure; do not restore K071's global assignment.
2. In `dsi_pll_10nm_init()`, capture the recalc return value once.
3. Store only a validated nonzero result into `vco_current_rate`; otherwise use the explicit `min_pll_rate` fallback.
4. Add temporary logs for:
   - raw init recalc result;
   - selected seed/fallback;
   - VCO rate at every early prepare and lock result.
5. Do not add K069's hardcoded divider.

Predicted discriminator:

- If init reads a valid nonzero rate and all early prepares retain it, the zero-rate parent-enable failure should disappear. Then inspect RCG warnings, live VCO/divider/pixel/byte rates, DRM commit/vblank status, and physical output.
- If init reads zero, the log must show fallback use. Do not infer that minimum rate is correct for handoff; interpret before another test.
- If PLL locks and RCGs update but final rates remain half, separately trace the later generic-divider writer. Do not stack that investigation into K072.

This candidate should remain debug-only until it is shown to match the 10nm PHY's power/register-access contract beyond joan.

## Exact K068-K071 artifacts

K068:

- `out/20260711-k068-dsi-parent-enable-retest.patch`
- `out/boot-joan-20260711-k068-parent-enable-retest.img`
- `out/k068-parent-enable-retry2-ramboot-20260711T1808Z.log`
- `out/k068-live-dmesg-2026-07-11.txt`
- `out/k068-live-display-diag-2026-07-11.txt`

K069:

- `out/20260711-k069-parent-enable-prelock-outdiv.patch`
- `out/boot-joan-20260711-k069-parent-enable-prelock-outdiv.img`
- `out/k069-parent-enable-prelock-outdiv-ramboot-20260711T1837Z.log`
- `out/k069-live-dmesg-2026-07-11.txt`
- `out/k069-live-display-diag-2026-07-11.txt`

K070:

- `out/20260711-k070-pll-order-instrumentation.patch`
- `out/boot-joan-20260711-k070-pll-order-instrumentation.img`
- `out/k070-pll-order-instrumentation-ramboot-20260711T1852Z.log`
- `out/k070-live-dmesg-2026-07-11.txt`
- `out/k070-live-display-diag-2026-07-11.txt`

K071:

- `out/20260711-k071-vco-state-parent-enable.patch`
- `out/boot-joan-20260711-k071-vco-state-parent-enable.img`
- `out/k071-vco-state-parent-enable-ramboot-20260711T1903Z.log`
- `out/k071-live-dmesg-2026-07-11.txt`
- `out/k071-live-display-diag-2026-07-11.txt`

Hashes are recorded beside each K entry in `docs/kernel-change-ledger.md`.

## Device-test rules remain binding

- RAM-only `fastboot boot`; never flash the LineageOS boot slot.
- Lance must be physically beside the phone.
- Get fresh explicit approval for each boot; never reuse approval.
- Show a five-minute expiry timestamp on physical-observation/approval prompts.
- Enter fastboot only through authorized `adb reboot bootloader`.
- Exactly one fastboot client and one bounded `fastboot boot` command.
- If transfer stalls before `OKAY`, stop; do not retry automatically.
- Capture dmesg, clock summary, and physical display state before recovery.
- Recover to fully booted LineageOS after every test.
- Rediscover `/dev/ttyACM*` after re-enumeration.
- Send ACM recovery as `b'\r' + b'reboot -f' + b'\r'`.
- Do not use `fastboot getvar`, do not flash, and do not casually read `tzdbg/*`.

## Publication and attribution

- Nothing from K068-K071 is retained in kernel source.
- Nothing was pushed publicly.
- Preserve Lance's DCO sign-off and use the actual live model in `Assisted-by` trailers.
- Preserve original authorship for public/downstream-derived changes.
- Update the ledger, project history, current handoff, dependency tracker, and upstream plan when conclusions change.

## Final instruction to Claude Code

Start by independently checking the K070 sequence against K071's collapse. Do not begin from the framework `/4` summary; begin from the directly logged correct handoff divider state and zero VCO member. If you select K072, keep it to the init-only seed plus instrumentation, build/package/hash it, and wait for Lance's fresh presence/approval before any device command.

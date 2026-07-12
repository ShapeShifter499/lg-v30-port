# Handoff — M4 display, two paths (K078 clock win + K079 inherit)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11
For: Lance + Aurel / next session

## One-paragraph state

The DSI clock problem that consumed K068-K077 is SOLVED and verified (K078).
Every DSI rate is now correct. The panel is still black, which — per Aurel's
K077 — means the remaining blocker is panel-side, not clocks. Two forward
paths are open and scoped: (A) finish the NATIVE panel bringup (panel init /
command-mode TE kickoff), and (B) the edk2-style INHERIT of ABL's framebuffer
(diagnosed to two concrete fixes). Native is the stronger bet; inherit is a
viable fallback / fast-visible-display option.

## K078 — the clock win (VERIFIED, upstreamable, currently only a patch)

Root cause (from Aurel K076/K077): mainline msm8998 parents
`mdss_byte*_intf_clk` straight to `byte*_clk_src` with CLK_SET_RATE_PARENT.
The DSI host sets the byte-INTERFACE clock to half the byte clock; that
half-rate request propagates up into the shared PHY byte source and rewrites
the DSI PLL output divider to /4, halving the whole link.

Fix: model msm8998's dedicated byte-interface hardware divider (which mainline
was missing). Added `mdss_byte0_intf_div_clk` / `mdss_byte1_intf_div_clk`
(clk_regmap_div, reg 0x237c / 0x2380, width 2, parent byte0/1_clk_src,
CLK_GET_RATE_NOCACHE), reparented the intf branches to them, +2 binding IDs
(146/147). Verbatim shape of mainline `mmcc-sdm660.c`. Register 0x237c
confirmed for msm8998 (downstream msm-clocks-hwio-8998.h
MMSS_MDSS_BYTE0_INTF_DIV=0x0237C).

Verified live (clk_summary, one variable on clean b549c9f5b):
- dsi0_pll_out_div_clk 684.442 MHz (/2)  [was 342 /4]
- byte0_clk_src 85.555 MHz  [was 42.78]
- pclk0_clk_src 114.074 MHz  [was 57]
- mdss_byte0_intf_clk 42.778 MHz via its own /2 divider (correct)
- 0 PLL-lock fails, 0 vblank timeouts, fb0 up, DPU bound.

Artifact: `out/20260711-ember-k078-byte-intf-divider.patch`. It fixes a real
mainline bug affecting every 8998 DSI board — RECOMMEND turning it into a
clean kernel commit on joan/latest-clean-test (it stands on its own even
before the panel lights, and is a good standalone upstream submission).

## Path A (recommended): finish the native panel bringup

The pipeline is up with correct clocks; the panel just never shows. Aurel's
ranked follow-ups (still the plan):
1. Bounded DCS readback / BTA probe (e.g. get_power_mode 0x0A) to distinguish
   "panel received our commands" from "host write helper returned success".
   Our panel driver's `accum_err=0` is only host-transfer success, NOT panel
   ACK.
2. Command-mode TE (tear-effect) wiring + kickoff audit. Mainline joan DTS
   sets `qcom,te-source = "mdp_vsync_e"`; downstream joan uses EXTERNAL TE:
   TE pin select 1, TLMM GPIO 10, active/suspend pinctrl. If the DPU never
   gets a TE kickoff, a cmd-mode panel never latches a frame from the DPU →
   black even with a correct init. This is the top suspect.
3. Re-check the panel init sequence vs a real capture if possible.
4. Keep the 10x bounded SMMU splash faults (iova 0x9d400000) in mind — they
   are the bootloader scanout faulting during takeover; may need handling.

Build the native display test on b549c9f5b + K078 patch, DRM/DRM_MSM/
DRM_PANEL_LG_SW43402/QCOM_LLCC/QCOM_OCMEM =y, ramdisk_offset 0x02000000,
v2 capture initramfs. Pull dmesg tcp/9600, clk tcp/9601.

## Path B (fallback / fast visible): inherit ABL's framebuffer (edk2 style)

edk2/Windows light nothing themselves — they inherit ABL's framebuffer at
0x9d400000 (= cont_splash_mem). Since ABL loads our kernel too, the display
is left running for us. K079 tried simpledrm on it; black, with two FIXABLE
blockers found:
1. `simple-framebuffer ... error -22`: the node used `reg` into a no-map
   reserved region, which simpledrm can't claim. FIX: use
   `memory-region = <&cont_splash_mem>` in the framebuffer node instead of
   `reg` (the binding supports it).
2. Panel lost power: the GPIO panel rails (vddio TLMM92, vpnl TLMM69) and
   likely MMSS/DSI regulators were disabled at regulator_init_complete as
   "unused". clk_ignore_unused / pd_ignore_unused do NOT cover regulators.
   FIX: mark the display-chain regulators `regulator-always-on` for the
   inherit build.
Also required (K079 had these): cmdline `clk_ignore_unused pd_ignore_unused`,
`&mdss { status = "disabled"; }` so native DRM can't tear it down,
CONFIG_DRM_SIMPLEDRM=y + CONFIG_SYSFB_SIMPLEFB=y.
OPEN QUESTION: even fixed, a DSI CMD-mode panel only shows CPU writes if the
DPU keeps auto-kicking frames. edk2's live UEFI (no display driver) implies
ABL leaves it auto-refreshing, but this is UNPROVEN for our fastboot-boot
handoff. If simplefb binds + panel stays powered but the image is frozen
(no console update) → that confirms it needs kickoff, and native (Path A) is
the only real fix.
Artifact: `out/20260711-ember-k079-simplefb-inherit.patch`.
GPU note: inheriting the framebuffer does NOT block the Adreno GPU — that's a
separate driver (freedreno) added later; simpledrm = software render at first.

## Device / repo checkpoint

- Kernel `linux-mainline-v30` joan/latest-clean-test @ b549c9f5b, CLEAN.
  K078 + K079 preserved as out/*.patch (not applied). Panel driver 6d7550d4a
  + display DTS 86fbeea5b are committed in history.
- Harness `lg-v30-port`: ledger K078/K079 committed locally; nothing pushed
  (debug discipline). No force-push (Lance directive). Assisted-by = live
  model (Aurel now Hermes:gpt-5.6-sol).
- Phone: LineageOS, healthy, nothing flashed.
- Capture: v2 initramfs (tcp/9600 dmesg, tcp/9601 clk) — no gadget re-bind.

## Binding device-test rules (unchanged)

RAM-only fastboot boot; Lance present + fresh per-boot approval w/ 5-min
expiry; enter fastboot only via adb reboot bootloader; one bounded boot; stop
on stall before OKAY; recover to LOS after; capture live (ramoops does not
survive hard reset). Never getvar / flash / read tzdbg.

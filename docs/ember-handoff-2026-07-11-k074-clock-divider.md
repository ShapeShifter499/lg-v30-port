# Handoff — M4 display: pipeline fully up, byte clock at half rate (K074)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11
For: Lance + Aurel / next session

## One-paragraph state

The display pipeline is now END-TO-END up: mmss SMMU probes (Aurel), DSI
PLL locks (K072 seed), byte/pixel clocks run, DPU binds DSI, fb0 registers,
the DSI bridge pre-enable and panel prepare run, 0 vblank timeouts, and no
hang. **Panel is still black.** With reliable dmesg finally in hand (capture
fix below), K074 localized it to a concrete, quantitative lead: the DSI
**byte clock is running at half the rate the panel needs** — a PLL
out-divider stuck at /4 instead of /2 — so the DSI link is too slow to
carry a valid signal. This is the same /4-vs-/2 divider issue Aurel chased
in K069/K070, now pinned with live clk_summary numbers.

## The concrete lead (primary)

Live rates from `out/k074-clk-2026-07-11.txt`:
- dsi0vco_clk = 1.368884472 GHz
- dsi0_pll_out_div_clk = 342.221118 MHz  (= VCO / 4)
- byte0_clk_src = 42.777639 MHz
- pclk0_clk_src = 57.036853 MHz

Expected for 1440x2880 @ 60 Hz, DSC 8bpp (from 24bpp), 4 lanes:
- htotal 1612 x vtotal 2916 x 60 ≈ 282 Mpix/s uncompressed
- DSC-compressed 8bpp over 4 lanes → ~564 Mbps/lane → byte ≈ ~70 MHz
- i.e. out_div should be /2 (bit ≈ 685 MHz), NOT /4.

So byte0 at 42.78 MHz is ~half. The `rcg didn't update its configuration`
warnings (4x, on byte0/pclk0, inside `msm_dsi_host_power_on`) mean the RCG
never latched the correct divider — it's left at the stale/half handoff
rate. This is the strong suspect for the black panel: half-rate DSI = no
valid link.

Direction: this is NOT the parent-disabled problem (K068's parent-enable
fixes the "parent live" case but DEADLOCKS — see K073, rejected). The RCG
can't latch because the requested rate / out-div programming is wrong.
Compare our `drivers/gpu/drm/msm/dsi/phy/dsi_phy_10nm.c` out_div / post-div
programming (dsi_pll_10nm_vco_set_rate, the CMN_CLK_CFG0/1 writes and
`dsi_pll_10nm_set_usecase`/`dsi_pll_10nm_restore_state`) against the working
msm8998 reference at `/tmp/msm8998-mainline-linux-ref` — especially how the
reference derives and programs the output divider so byte/pixel land at full
rate. Aurel's K070 logged the saved outdiv as /2 (0x1) but the live tree
ends at /4; find where the /2 handoff state is lost and not reprogrammed.

## Secondary lead

Bounded burst of 10x `arm-smmu cd00000.iommu: Unhandled context fault
iova=0x9d400000` during handoff. 0x9d400000 = our `cont_splash_mem`
(bootloader framebuffer). The bootloader display keeps scanning out through
the mmss SMMU during mainline takeover; the MDSS identity domain (7ff461605)
passes it through until the DPU attaches its translating domain for fb0,
then the old splash address faults. Bounded (stops after ~10), not a storm —
likely secondary to the clock issue, but worth clearing (e.g. stop the
bootloader scanout early, or map/reserve the splash region for the DPU
context) once the panel lights.

## What was tried (see ledger K068-K074)

- K068 (Aurel): CLK_OPS_PARENT_ENABLE on byte0/pclk0 → RCG warnings gone but
  PLL vco=0 lock fail. K069/K070: divider ordering; K070 proved saved outdiv
  is /2 and vco member is 0 at handoff. K071: recalc side-effect → collapsed
  tree, rejected.
- K072 (Ember): init-only nonzero vco_current_rate seed (recalc kept pure) →
  **PLL LOCKS, 0 vblank timeouts, fb0 up.** RCG-didn't-update remains. This
  is a real fix and should be kept/upstreamed once the divider is solved.
- K073: K068+K072 → DEADLOCK (parent-enable re-enters PLL lock under clk
  locks). Rejected — do not use parent-enable.
- K074: K072 + CLK_GET_RATE_NOCACHE (working-ref flag) → no hang, but NOCACHE
  alone doesn't latch the RCG; byte clock still half. The divider is the
  remaining wall.

## Reliable-capture fix (important infra, keep it)

The bringup init used to `sleep 15` then unbind/rebind the USB gadget to add
a mass_storage LUN — this re-enumerated ACM+network and broke every dmesg
pull after ~15s (cost several rounds of blind testing). Fixed: init now
serves dmesg on tcp/9600 and clk/regulator diag on tcp/9601 persistently,
no gadget re-bind. Ramdisk `out/initramfs-bringup-v2.cpio.gz`. Pull with
`ncat 172.16.42.1 9600` (dmesg) / `9601` (clk_summary). Note: ramoops does
NOT survive a Power+VolDown hard reset, so capture live over the network,
not via post-reset pstore.

## Device test recipe (unchanged, binding)

RAM-only `fastboot boot`; Lance present + fresh per-boot approval w/ 5-min
expiry; enter fastboot only via `adb reboot bootloader`; one bounded boot;
stop if transfer stalls before OKAY; recover to LOS after. ramdisk_offset
0x02000000 (kernels are ~19 MiB). Display test image = DRM/DRM_MSM/
DRM_PANEL_LG_SW43402 + QCOM_LLCC/OCMEM forced =y (see K059).

## Repos / state

Kernel `linux-lg-v30-joan` `joan/latest-clean-test` @ b549c9f5b (clean; K072
seed + display driver 6d7550d4a/DTS 86fbeea5b are on earlier commits; K073/
K074 experiments preserved as out/*.patch, NOT applied). Harness `lg-v30-port`
@ local (ledger K074 + this handoff committed locally, not pushed — debug
discipline). pmaports `pmaports-lge-joan` device-lge-joan unchanged.
Conventions: no force-push; Assisted-by = live model (Aurel Hermes:<current>);
dependency-tracker for imports; downstream-refs GPL-2.0. Phone: LOS, healthy,
nothing flashed.


## UPDATE: K075 staged (boot this FIRST next session)

Built and packaged but not yet booted (Lance out of budget mid-build):
`out/boot-joan-20260711-ember-k075-panel-instr.img` sha256
`18f0d9b9675c3a88085208532c0ac290cacfb4ef2226a86216e391a651561bf3`
(K074 clock base + dev_info logs in the SW43402 panel prepare;
patch `out/20260711-ember-k075-panel-instrumentation.patch`).

Boot it first — it answers, in one shot, whether the black panel is the
clock (half-rate byte) or something past it:
- Pull dmesg: `ncat 172.16.42.1 9600` after the gadget enumerates.
- Read the `K075 ...` lines. Decisive value = `accum_err`:
  - accum_err != 0  => DSI init commands FAILED => the K074 half-rate byte
    clock (out_div /4 vs /2) is the direct cause; go fix the divider
    (dsi_phy_10nm out-div programming vs /tmp/msm8998-mainline-linux-ref).
  - accum_err == 0  => init reached the panel fine; the problem is DPU
    scanout / command-mode TE kickoff (no TE pinctrl wired for TLMM 10),
    NOT the clock. Pivot to TE/DPU commit path.

Device is in LineageOS, healthy, nothing flashed. Same binding boot rules.

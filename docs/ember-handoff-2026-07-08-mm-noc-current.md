# Ember → Aurel handoff — joan reset hunt, current state (2026-07-08)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

This is the one-file handoff to start from. It supersedes
`docs/ember-handoff-2026-07-07-k027-complete.md` and
`docs/ember-handoff-2026-07-07-k029-onion-peel.md` for current state
(both preserved for history — the onion-peel doc in particular has the
full blow-by-blow of how this session's conclusions were reached, worth
reading if something here is unclear). `docs/kernel-change-ledger.md`
remains the full, ordered, uncut history (K001 through K036); this file
is the distilled current picture.

## TL;DR

The LG V30 (joan, US998) mainline port RAM-boots successfully but resets
before mainline USB comes up. Across many sessions this was chased as a
mysterious secure-world reset; it is now understood precisely:

1. **A real, confirmed, device-tested fix exists** for one whole fault
   class (`anoc1_smmu` global-reset skip — see below). Applying it
   eliminated a specific TrustZone "Config NoC" fault.
2. **A second, related fault remains unfixed: TrustZone "MM NoC"
   (`0x6D630306`).** It was first seen in K027, momentarily thought
   fixed/superseded by a wrong side-track in K033/K034, then
   **reconfirmed as still the real, standing blocker** via a device
   photo of LG's own UEFI-level crash screen (K035, detailed below).
3. **The obvious next hypothesis (K036) was tested and REJECTED.** Three
   sibling GCC clocks in the same MMSS-NoC-bridge register family as one
   mainline already protects were marked `CLK_IS_CRITICAL` to match; no
   change. Worse, re-checking existing evidence afterward showed the
   *entire* "unclaimed clock gated by the late sweep" theory class
   cannot explain MM NoC at all (K027 with clocks retained and K032
   with the sweep running normally both hit it identically) — this
   rules out every other clock-sweep candidate too, not just the three
   tested. **No further device test has been run since**; see §3 for
   the corrected reasoning and what kind of candidate is actually worth
   testing next.

## 0. Community research + watchdog elimination (2026-07-08 addendum)

First systematic look at how OTHER msm8998 mainline ports handle this
(not just joan-side subtraction):

- **OnePlus 5/5T boots mainline (~40s)** with the SAME shared
  `msm8998.dtsi` — same `anoc1_smmu`, same arm-smmu-v2 reset. So the SMMU
  reset is not inherently fatal on this SoC; joan's fault is
  device/firmware-specific. Their gotchas (`clk_ignore_unused`,
  `modprobe.blacklist=ipa`, single-DTB) are not our MM_NOC.
- **CoreSight-on-retail pattern** (postmarketOS/OnePlus): retail/secure
  msm8998 *"kernel panics ... tracked down to CoreSight tracing
  activating on retail hardware — delete the etf/etm/etr/funnel/
  replicator/stm nodes."* This VALIDATES the lens behind the anoc1 fix:
  on this secure SoC, Linux touching a TZ-owned block causes a secure
  reset. Not our direct cause (joan's coresight nodes are all
  `status=disabled`, `CONFIG_CORESIGHT=m` never loads) — but it means
  MM_NOC is very likely a third such TZ-owned block on the MM fabric.
- **Mainline `msm8998.dtsi` has no watchdog node.** joan is the only
  msm8998 device that added one.
- **Non-secure watchdog CLEARED (K037).** The mainline qcom-wdt driver
  defaults to a 30s timeout and doesn't set `max_hw_heartbeat_ms` (so the
  core won't auto-pet a bootloader-running watchdog before userspace opens
  `/dev/watchdog`) — a near-perfect fit for a 30s NON_SEC_WDT reset. But
  the on-device test (`timeout-sec = <60>` on the node) left the reset at
  ~30s, unchanged. Downstream uses identical register offsets (not an
  offset bug), and the jittery 30-49s timing across all runs argues
  against a fixed HW-watchdog bite. So the mainline non-secure watchdog is
  not the tunable cause; the NON_SEC_WDT code on K035's crash screen was
  most likely from a different boot, and this reset is the event-driven
  MM_NOC fabric fault. joan's `watchdog@17817000` node is not helping and
  could be dropped. Full detail: ledger "Community research + K037" entry.
- **Bootloader display CLEARED (K038).** Tested the display-underflow
  theory directly: a debug initcall disabled both DSI controllers + the DPU
  INTF timing engines (authoritative offsets, non-secure regs) on the
  anoc1-fix baseline. Reset persisted at ~44s, `0x20` — the bootloader-left
  display is NOT the MM_NOC cause (msm8998's panel is command-mode, so the
  MDP goes idle after the last kickoff and isn't DMAing the splash to
  underflow). Reverted.
- **Linux-side leads are now EXHAUSTED.** No mainline driver touches the MM
  subsystem in bring-up (DRM_MSM=m, MMCC=m, no GPU — none load). With the
  watchdog, display, peripherals, clock-sweep class, and SMMUs-beyond-anoc1
  all eliminated, there is no remaining "a Linux driver/DTS touches an MM
  block" candidate. MM_NOC is one of exactly two bigger efforts: (1) the
  full msm8998 interconnect provider (systematic missing NoC config; the
  Config-NoC→MM-NoC layering supports it), or (2) TZ-side secure/SCM
  archaeology (Aurel's domain). No cheap Linux-side test remains.

## 1. Confirmed fix: `anoc1_smmu` skip-reset (K030)

`anoc1_smmu` (`iommu@1680000`, an aggregator-NoC IOMMU in
`msm8998.dtsi`) has **zero** `iommus=` consumers anywhere in mainline's
device tree and **no `clocks=` property at all**, yet defaults
`status = "okay"`. Mainline's arm-smmu-v2 driver
(`drivers/iommu/arm/arm-smmu/arm-smmu.c`, `arm_smmu_device_reset()`)
therefore always runs its full global reset on it: clears sGFSR, forces
every SMR invalid and every S2CR to bypass, invalidates the TLB — every
boot, unconditionally.

Downstream `arch/arm/boot/dts/qcom/msm-arm-smmu-8998.dtsi` marks this
exact block (and in fact all five msm8998 SMMU-v2 instances:
`anoc1`, `anoc2`, `lpass_q6`, `mmss`, `kgsl`/adreno) `qcom,skip-init` +
`qcom,register-save`: TZ/XBL already owns and configures these
instances, and downstream's driver deliberately never resets them.

**Fix**, currently applied to the kernel tree
(`joan/latest-clean-test`, uncommitted, verified via `strings vmlinux`):
a debug patch to `arm_smmu_device_reset()` skips the entire reset
sequence when a new `ember,debug-skip-reset` DT boolean is present,
tagged onto `&anoc1_smmu` **alone** (K031 showed tagging all five adds
nothing and risks correctness for wifi/GPU/audio's own SMMUs once real
consumers attach domains — prefer the narrow, anoc1-only version).

**Confirmed clean baseline going forward:** full, otherwise-untouched
`msm8998-lge-joan.dts` + `&anoc1_smmu { ember,debug-skip-reset; };` +
**plain default cmdline** (`androidboot.hardware=joan panic=0
ignore_loglevel` — K032 proved the `clk_ignore_unused
pd_ignore_unused` retention some earlier sessions relied on was never
load-bearing; drop it).

Device evidence this eliminates a real fault: applying it changed the
LG boot-reason from the `LGE_RB_MAGIC|LGE_ERR_TZ` crash family
(`0x6D630309` Config NoC) to something else entirely (see below) — a
real, named TrustZone fault class is gone.

**Not yet upstream-shaped**: `ember,debug-skip-reset` is a made-up debug
property name, not a real binding. If this fix is confirmed sufficient
(pending the MM NoC work below), it needs a properly-designed upstream
mechanism — likely a `qcom,skip-init`-equivalent binding recognized by
mainline's arm-smmu-qcom impl layer, matching the concept downstream
already has a name for.

## 2. Standing target, unfixed: TrustZone MM NoC (`0x6D630306`)

With the anoc1 fix applied, the reset still happens at the same ~30-45s
mark. What changed is *which* TrustZone fault fires:

- Every test **without** cmdline clock/pd retention (K026, K028, K029,
  K032, K033, K034) reported the Android property
  `androidboot.product.lge.bootreasoncode` as either `0x6D630309`
  (`LGE_ERR_TZ_CONF_NOC_ERR`, before the anoc1 fix) or a generic,
  non-magic `0x20` (`UNDEFINED_CRITICAL_ERROR`, after it).
- K027 (**with** clock/pd retention, before the anoc1 fix existed) was
  the first to show `0x6D630306` (`LGE_ERR_TZ_MM_NOC_ERR`) via that
  same Android property.
- **K035** (anoc1 fix + an IMEM-oracle debug write, see §4) crashed
  before reaching Android at all, but Lance photographed LG's own
  UEFI-level crash screen, which showed `tzbsp_reason: 0x6D630306`
  directly from firmware — unambiguously **the same MM NoC value as
  K027**, read at the lowest level available.

**Conclusion: the generic Android-property `0x20` seen in K033/K034 was
almost certainly this same MM NoC fault, mis-reported/genericized
somewhere in Android's own property-generation code** — not a third,
separate, unnamed fault as earlier session notes concluded. K033
(every removable board peripheral disabled: `usb3`, `qusb2phy`,
`ufshc`, `ufsphy`, `wifi`, `pm8005_regulators`) and K034 (the APSS
non-secure watchdog node disabled outright, a stronger test than K024's
earlier kernel-side pet) both still hit it. **Read together: MM NoC is
SoC-core-level, not a board peripheral, and not the non-secure
watchdog.** RPM must stay enabled (K028/K029 both showed removing it —
or removing `anoc1_smmu` itself — regresses to the *shallower* Config
NoC fault instead of clearing anything; RPM is required scaffolding,
not a suspect).

## 3. K036 tested and REJECTED — and it corrects the whole line of attack

`drivers/clk/qcom/gcc-msm8998.c` defines `gcc_mmss_noc_cfg_ahb_clk`
(register `0x9004`) with `CLK_IS_CRITICAL` and this exact upstream
comment:

```c
/*
 * Any access to mmss depends on this clock.
 * Gating this clock has been shown to crash the system
 * when mmssnoc_axi_rpm_clk is inited in rpmcc.
 */
```

`mmssnoc_axi_rpm_clk` is literally one of RPM's `icc_clks`
(`drivers/clk/qcom/clk-smd-rpm.c`'s `msm8998_icc_clks[]` — voted once
at rpmcc probe, never CCF-registered, never swept) — this comment
describes our exact configuration (RPM enabled + this clock gated =
documented crash). Three siblings in the same register bank
(`gcc_mmss_sys_noc_axi_clk` `0x9000`, `gcc_mmss_qm_ahb_clk` `0x9030`,
`gcc_mmss_qm_core_clk` `0x900c`) lack the same protection.

**Tested (device, Lance present, phone recovered from K035 via
Volume-Down hold): marking all three `CLK_IS_CRITICAL` made no
difference.** Reset persists, same bootreasoncode `0x20`/MM NoC.
**Rejected.** Reverted from the kernel tree (patch kept at
`out/ember-k036-mmnoc-critical-clocks.patch` for reference only — do
not reapply without new evidence).

**This result is more useful than a simple negative, because checking
*why* it should have worked exposed a bigger problem with the whole
approach.** K027 (clock/pd retention ON, i.e. the late sweep
effectively disabled) and K032 (retention OFF, sweep runs normally,
after the anoc1 fix) both hit MM NoC identically. If MM NoC were caused
by *any* clock whose only path to being gated is that generic sweep,
retaining it in K027 should have prevented the fault — it didn't. **The
entire "unclaimed clock gated by the late sweep" theory class is ruled
out for MM NoC**, not just the three clocks actually tested. This
retroactively also rules out (without needing to test them)
`gcc_aggre1_noc_xo_clk`, `gcc_boot_rom_ahb_clk`,
`gcc_cfg_noc_usb3_axi_clk`, `gcc_bimc_hmss_axi_clk`, and the original
(already-superseded) K028-prep `gcc_prng_ahb_clk` hypothesis — do not
test any of these on "it's an unclaimed GCC clock" reasoning alone, that
reasoning is now known to be insufficient here. (It correctly explained
the *original* Config NoC / anoc1_smmu mechanism — that fix is a
driver's own unconditional reset sequence, a different kind of thing
from a swept clock, and remains valid.)

**What's actually worth testing next**: the lens that worked for
anoc1_smmu was a *driver's own unconditional reset/init sequence*
touching a TZ-owned block on every probe, independent of clock state —
not a clock being gated. K030 vs K031 already extended this lens to
clear the other four SMMU instances' own reset sequences. Candidates in
the same spirit:

- ~~pinctrl-msm / TLMM's own probe~~ — **checked and cleared** (source
  only, no device needed): `msm_pinctrl_probe()` doesn't touch hardware
  unconditionally the way `arm_smmu_device_reset()` does; it only
  applies explicitly-declared DT `pinctrl-0` states. Its one
  `PS_HOLD`-writing restart-handler registration only fires if the
  SoC's pin table defines a function named `"ps_hold"`, which
  `pinctrl-msm8998.c` does not. Not a match.
- ~~The QUP/GENI/BLSP serial-controller family~~ — **checked and
  cleared** (source only): MSM8998 predates GENI/QUP entirely (that IP
  starts around sdm845); it uses the older BLSP design where each
  UART/I2C/SPI instance is a fully independent platform device with no
  shared wrapper/bus controller. Only `blsp2_uart1` is enabled; every
  sibling defaults disabled and never probes. No cross-instance
  infrastructure exists here analogous to arm-smmu's five instances.
  Not a match.
- **A fresh secure/SCM archaeology pass** — genuinely Aurel's
  established strength (see the K025 addendum in
  `docs/ember-handoff-2026-07-06-session2.md` for the prior pass this
  built on). **This is now the strongest remaining direction by
  elimination**: both Linux-side driver-family candidates raised by
  this session's own correction (pinctrl-msm, QUP/GENI/BLSP) have been
  checked and cleared without a device test needed for either. This
  session's whole investigation has been DTS/clock subtraction from the
  Linux side; the actual fault is TrustZone-side, and a pass from that
  direction is the next thing genuinely worth trying.

No further device test was run against pure reasoning alone this
session — per the project's standing discipline, don't guess blind
against the phone without a specific reason to believe a candidate is
right.

## 4. Method correction: do not repeat the K035 IMEM write

K035 tried writing a distinctive seed (`0x6D6303EE`) to the IMEM
restart-reason offset (`0x146bf000+0x65c`, reusing Ember's 2026-07-06
`joan_imem_oracle.c` initcall) to test whether any TZ detector still
writes there. The phone never returned; instead of the usual silent
PS_HOLD-reset-then-LineageOS cycle, it crashed into LG's own UEFI-level
handler with a firmware NULL-pointer assertion
(`DXE_ASSERT!: [ResetRuntimeDxe] String.c (199)`) and Sahara mode
(recovered with a plain Volume-Down hold, per the crash screen's own
instructions — not a generic forced restart, not USB+QPST raw-dump).

This exact firmware crash never happened in any other test, including
several that also hit MM NoC/Config NoC resets — the one new variable
was this write. Best-supported read: the offset lands near a
string/pointer structure XBL's own `ResetRuntimeDxe` also uses, and the
write corrupted it. **`joan_imem_oracle.c` has been reverted from the
kernel tree** (file removed, Makefile line reverted, rebuild verified
clean via `strings vmlinux` showing no `joan-imem` strings). Do not
reintroduce a raw write at that offset without a specific reason to
believe it's safe — the bootreasoncode Android property is a sufficient
read-only channel for everything needed so far.

## 5. Full elimination table

Kept from earlier sessions' tables, extended:

| Test / oracle | Result | Meaning |
|---|---:|---|
| K022 do-nothing init | still resets | not userspace/initramfs |
| K023b-e (USB/UFS/RPM-disabled/all-peripherals) | still resets | not board peripherals |
| K024 non-secure APSS WDT pet | still resets | pet doesn't help |
| K026 LGE IMEM default write | valid boot, ~49.1s | not fix; exposed `0x6D630309` |
| K027 clk/pd retention (pre-anoc1-fix) | still resets | exposed `0x6D630306` MM NoC for the first time |
| K028 RPM disabled (on clkpd base) | regresses to `0x6D630309` | RPM is required scaffolding |
| K029 anoc1_smmu disabled (on clkpd base) | regresses to `0x6D630309` | removing the node ≠ fixing it |
| **K030 anoc1_smmu skip-reset (node stays enabled)** | **Config NoC fault gone** | **confirmed real fix, one class** |
| K031 all-5-SMMU skip-reset | identical to K030 | broader version adds nothing, more risk |
| K032 drop clk/pd retention (post-anoc1-fix) | identical result | retention was never load-bearing |
| K033 all board peripherals disabled (post-fix) | still resets, generic `0x20` | not peripherals |
| K034 APSS watchdog disabled outright (post-fix) | still resets, generic `0x20` | not the non-secure watchdog |
| K035 IMEM oracle write (post-fix) | firmware crash, Sahara mode | confirms `0x20` was MM NoC all along; write itself likely crashed XBL, reverted |
| K036 sibling MMSS-NoC-bridge clocks CLK_IS_CRITICAL | still resets, generic `0x20` | **rejected; also rules out the whole clock-sweep theory class for MM NoC (see §3)** |

## 6. Safety rules (binding, unchanged)

1. RAM-only `fastboot boot`. Never flash.
2. Enter fastboot via `adb reboot bootloader` only (menu-entered
   fastboot has wedged aboot before).
3. Exactly one fastboot client at a time (`pgrep -x fastboot` before
   every pass).
4. Never `fastboot getvar` — has wedged aboot before.
5. `sudo -n fastboot ...` for the actual boot command (normal-user
   fastboot has hit permission issues before).
6. `panic=0` on every classifier test — a boot failure hangs silently,
   never fakes a reset.
7. Lance must be physically present for device work.
8. Watch phone battery/charge across many consecutive tethered boots —
   a USB 3.0 port not sustaining charge through ~9 back-to-back cycles
   caused an unrelated pause this session; prefer USB 2.0 or otherwise-
   verified adequate charging for long runs.
9. If the phone ever shows an unfamiliar USB identity (not the normal
   ADB `18d1:4ee7`) and stays unreachable, **stop and look at the
   physical screen before assuming anything** — K035 showed this can be
   a genuinely informative firmware crash screen, not just a generic
   wedge. Photos are worth taking.
10. Save debug kernel patches to `out/*.patch` before building; revert
    debug-only or rejected changes from the tree once a test line is
    concluded so the tree doesn't silently drift dirty across sessions
    (current exception: only the confirmed-good anoc1 patch remains
    applied — see §7).

## 7. Repo state at time of writing

```text
Harness repo: ~/vibe-coding-projects/coding/lg-v30-port
  branch master, clean, commits through ee8492d.
  New reusable tooling: scripts/tethered-test.sh (one-client fastboot
  discipline, LOS-return classification, PON/bootreason readback,
  explicit handling of "device absent" / "unfamiliar USB state, stop" /
  "still fastboot, probably slow" outcomes).

Kernel repo: ~/vibe-coding-projects/coding/linux-mainline-v30
  branch joan/latest-clean-test, DIRTY on purpose with ONLY the
  confirmed fix:
    M drivers/iommu/arm/arm-smmu/arm-smmu.c   (K030 fix, confirmed good)
  joan_imem_oracle.c REMOVED (K035's write, reverted).
  gcc-msm8998.c REVERTED (K036's hypothesis, rejected -- git checkout
  brought it back to clean).
  Rebuilds clean; verify with
  `strings vmlinux | grep -E "EMBER K030|joan-imem"` before trusting
  what's in a boot image — should show ONLY the K030 string.
```

## 7b. Attribution / borrowed-code tracking (Lance directive 2026-07-08)

`docs/public-upstreaming-plan.md` now has a consolidated provenance table
(what's borrowed, from whom, license, status). **Aurel: please review it —
fill in the author "TBD" gaps you know (esp. the exact `msm8998-oneplus-common.dtsi`
contributors), and if any prior code add reused something without a "based
on" line, add one.** The big upcoming one: the msm8998 interconnect provider
will derive from `sdm660.c` (AngeloGioacchino Del Regno, SoMainline/Sony
Xperia) + `msm8996.c` (Yassine Oudjana) — their Copyright lines + SPDX must
be preserved and it must be marked "based on", never presented as original.

## 8. Where durable records live

```text
README.md                                        — top-level status, points here
docs/kernel-change-ledger.md                      — full K001-K036 history
docs/ember-handoff-2026-07-07-k029-onion-peel.md  — this session's blow-by-blow
docs/k028-conf-noc-sweep-hypothesis-2026-07-07.md — SUPERSEDED (K032 disproved the
                                                     sweep theory); kept for history
```

WebDAV mirrors of handoffs live at
`Talk/Shared_AI_agents_files/handoffs/`. Device crash-screen photos from
K035 are at `Talk/Shared_AI_agents_files/20260708_051750.jpg` and
`...051754.jpg`. Deck card #43 has the running commentary.

## Final instruction

Start from this file. **No hypothesis is currently loaded and ready to
device-test.** K036 was rejected and ruled out its whole candidate
class (§3); the two Linux-side driver families that class's correction
suggested next — pinctrl-msm/TLMM and QUP/GENI/BLSP — have both since
been checked in source and cleared too, no device needed for either.
**By elimination, a fresh secure/SCM archaeology pass from the
TrustZone side is the strongest remaining direction** — genuinely
Aurel's established strength, and a different angle than this entire
session's DTS/clock/driver subtraction from the Linux side. Once a
concrete SCM-side candidate exists, reason it through in source first,
then build and test via `scripts/tethered-test.sh`. If the phone is
ever in an unfamiliar, unreachable USB state, look at the actual screen
(§6 rule 9) before concluding it's stuck.

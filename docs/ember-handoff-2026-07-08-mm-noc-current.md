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
3. **A concrete, well-precedented, not-yet-device-tested hypothesis is
   ready to test**: three sibling GCC clocks in the same MMSS-NoC-bridge
   register family as one mainline already protects (with an explicit
   upstream comment describing a crash matching our exact symptom) are
   plausibly also unprotected. Patch built, saved, ready
   (`out/ember-k036-mmnoc-critical-clocks.patch`; kernel build was in
   progress when this was written — check
   `docs/kernel-change-ledger.md`'s K036 entry for whether it's been
   tested yet).

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

## 3. Next hypothesis, ready to test: sibling MMSS-NoC-bridge clocks (K036)

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
at rpmcc probe via `clk_smd_rpm_handoff()`, INT_MAX, never
CCF-registered, never swept). **This comment describes our exact
configuration**: RPM enabled + this clock gated = documented crash.
Mainline already protects this one clock. Three siblings in the *same*
register bank (`0x9000`-`0x9030`, same MMSS NoC bridge hardware block)
do **not** have the same protection:

- `gcc_mmss_sys_noc_axi_clk` (`0x9000`)
- `gcc_mmss_qm_ahb_clk` (`0x9030`)
- `gcc_mmss_qm_core_clk` (`0x900c`)

**Patch applied** (uncommitted, on top of the anoc1 fix): marks all
three `CLK_IS_CRITICAL`, matching the exact, already-proven-safe
pattern mainline uses for their sibling, with a comment explaining the
joan-specific hypothesis. Saved to
`out/ember-k036-mmnoc-critical-clocks.patch`. This is a **narrow,
well-precedented, low-risk test** — not a novel mechanism like the IMEM
write that caused K035's firmware crash (see §4) — if it works, it may
be upstream-shaped as-is (or close to it) rather than needing a debug
property.

**Status at time of writing: kernel rebuild in progress, not yet
device-tested.** Check `docs/kernel-change-ledger.md`'s K036 entry for
the actual result before assuming either way. To test once built:

```bash
K=~/vibe-coding-projects/coding/linux-mainline-v30
ROOT=~/vibe-coding-projects/coding/lg-v30-port
# DTB unchanged from the confirmed K030 baseline (out/ember-k030-skipreset-2026-07-07.dtb)
cat "$K/arch/arm64/boot/Image.gz" "$ROOT/out/ember-k030-skipreset-2026-07-07.dtb" \
  > "$ROOT/out/Image.gz-dtb-k036"
mkbootimg --kernel "$ROOT/out/Image.gz-dtb-k036" \
  --ramdisk "$ROOT/out/initramfs-k023b.cpio.gz" \
  --base 0x00000000 --pagesize 4096 \
  --cmdline "androidboot.hardware=joan panic=0 ignore_loglevel" \
  --output "$ROOT/out/boot-joan-mmnoc-critical-k036.img"
"$ROOT/scripts/tethered-test.sh" "$ROOT/out/boot-joan-mmnoc-critical-k036.img" 300
```

Survives (≥90s, deliberate classifier reboot) → MM NoC fixed, move to
the real bring-up initramfs to confirm USB actually enumerates. Resets
early with the same or a new bootreasoncode → this sibling-clock theory
is wrong or incomplete; check the ledger for what to try next.

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
| K036 sibling MMSS-NoC-bridge clocks CLK_IS_CRITICAL | **not yet tested** | ready to run |

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
    debug-only changes from the tree once a test line is concluded so
    the tree doesn't silently drift dirty across sessions (current
    exception: the confirmed-good anoc1 patch and the K036 hypothesis
    patch are both deliberately still applied — see §7).

## 7. Repo state at time of writing

```text
Harness repo: ~/vibe-coding-projects/coding/lg-v30-port
  branch master, clean, commits through fa617b0 (this file not yet
  committed at time of writing it — commit immediately after saving).
  New reusable tooling: scripts/tethered-test.sh (one-client fastboot
  discipline, LOS-return classification, PON/bootreason readback,
  explicit handling of "device absent" / "unfamiliar USB state, stop" /
  "still fastboot, probably slow" outcomes).

Kernel repo: ~/vibe-coding-projects/coding/linux-mainline-v30
  branch joan/latest-clean-test, DIRTY on purpose:
    M drivers/iommu/arm/arm-smmu/arm-smmu.c   (K030 fix, confirmed good)
    M drivers/clk/qcom/gcc-msm8998.c          (K036 hypothesis, untested)
  joan_imem_oracle.c REMOVED (K035's write, reverted).
  Both patches saved independently under out/*.patch regardless of tree
  state. Last build (Image.gz) includes both; verify with
  `strings vmlinux | grep -E "EMBER K030|joan-imem"` before trusting
  what's in a boot image — should show the K030 string, NOT joan-imem.
```

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

Start from this file. If K036 hasn't been tested yet, that's the next
device action — the patch is built and the test command is in §3. If it
has, check the ledger's K036 entry for the result and follow its own
"next" pointer. If the phone is ever in an unfamiliar, unreachable USB
state, look at the actual screen (§6 rule 9) before concluding it's
stuck.

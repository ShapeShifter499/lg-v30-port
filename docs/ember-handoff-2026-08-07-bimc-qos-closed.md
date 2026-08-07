# Handoff: MSM8998 BIMC QoS — root-caused and closed

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-07

Supersedes the open items in `ember-handoff-2026-08-07-icc-workstream-close.md`.

## Checkpoint — state at handoff

| | |
|---|---|
| Kernel branch | `joan/qos-bimc-v2` @ `24e82e84e`, pushed to `ghfork` |
| Device | joan, RAM-booted pmOS, verified; nothing flashed |
| Task #10 (ICC QoS) | **closed** |
| Display | 32.45 → 62.49 → **70.44 mdss/s** |
| Runtime tweak in place | `enable-animations = false` (dconf, persists) |
| GPU min_freq | back at 257 MHz default — the raise was **not** a reproducible win |

Ready to pick up:

1. `mas_ipa` QoS — **not blocked**, one-boot task; the clock is
   `RPM_SMD_IPA_CLK` from rpmcc, already in mainline (see below).
2. `GDK_SCALE=1` + phoc output `scale = 2` — config-only, quarters phosh's
   pixel count shell-wide at the cost of a softer upscale. Untested.

## Result

BIMC QoS works. Task #10 is closed. **16 of the 17 masters that can be
programmed now are**, and the one holdout (`mas_ipa`) is blocked on
something unrelated.

Display throughput across the whole ICC workstream:

    baseline           32.45 mdss/s
    +17-master QoS     62.49 mdss/s
    +bimc (this work)  70.44 mdss/s

## Root cause: a missing 0x8000

Three separate boots hung the SoC with no console. All three had the same
cause, and it was not any of the things I theorised.

**BIMC's M_BKE register block does not start at the beginning of the BIMC
window.** It sits 0x8000 in. Downstream puts that displacement in a C
macro rather than in device tree:

    /* drivers/soc/qcom/msm_bus/msm_bus_bimc_adhoc.c */
    #define M_REG_BASE(b)		((b) + 0x00008000)
    #define M_BKE_EN_ADDR(b, n)	(M_REG_BASE(b) + (0x4000 * (n)) + 0x300)

mainline `icc-rpm` expresses the same thing as `qcom_icc_desc::qos_offset`.
With it unset we were writing 0x8000 below every intended register —
inside BIMC's own configuration space, i.e. the memory controller's
registers. That is why clearing a *single bit* in bypass mode was enough
to wedge the machine before console.

    master          was            correct
    mas_gnoc_bimc   0x01000300     0x01008300
    mas_oxili       0x01004300     0x0100c300
    mas_mnoc_bimc   0x01008300     0x01010300

Fix is one line: `.qos_offset = 0x8000` on `msm8998_bimc`.

## How I got it wrong, twice

Worth recording, because the reasoning looked sound both times.

I checked whether bimc needed a `qos_offset` and concluded no, on two
observations that were each individually true:

1. Downstream's `fab_bimc` declares no `qcom,base-offset` — unlike
   `fab_a2noc`, which declares `0x5000` and which we do match.
2. `msm8996_bimc` sets no `.qos_offset`, and msm8996 *does* exercise BIMC
   QoS, so zero looked proven-good on comparable hardware.

Both are true. The conclusion drawn from them was wrong.

- `fab_bimc` has nothing to declare **because the offset lives in the
  driver's macros**, not in DT. Absence of a property is not evidence the
  value is zero.
- msm8996 needs no `qos_offset` because it **folds the displacement into
  its DT reg base**: `0x00408000`, not `0x00400000`. Ours is the raw
  `0x1000000`.

Meanwhile msm8916, msm8953 **and** msm8976 all set `.qos_offset = 0x8000`
for their BIMC. I saw that three-way agreement early, called it
"alarming", and then talked myself out of it on the strength of msm8996's
apparent counterexample — without checking msm8996's DT base. Three
platforms agreeing should have outweighed one that looked different.

**Transferable lesson:** when a mainline sibling appears to contradict a
majority, check whether it encodes the same value somewhere else before
treating it as a counterexample. A missing field can mean "zero" or it
can mean "expressed elsewhere", and those are not distinguishable from
the field alone.

## Corrections to earlier claims of mine

Anyone reading the previous handoff should apply these:

- **The "17 of 22 masters" tally was inflated.** It counted masters whose
  `qos_mode` was set but whose `ap_owned` is false —
  `qcom_icc_probe()` gates on `ap_owned && qos_mode != INVALID`, so those
  were never programmed. The real figure before this work was 13. It is
  now 16. The denominator was also wrong; there are 35 masters, of which
  17 are programmable.
- **No a2noc master is QoS-programmed**, and none should be — downstream
  does not AP-own `mas_blsp_1/2`, `mas_sdcc_2/4` or `mas_cr_virt_a2noc`
  either. The SD throughput win (5.7 → 52.3 MB/s) came from wiring the
  a2noc *bandwidth path*, not from QoS, so that result stands unaffected.
- **`mas_cr_virt_a2noc` was never a confound** in the failed bimc boot.
  I flagged it as one; it is `ap_owned = false`, so the probe gate never
  opened for it.
- **The bandwidth-limiter theory is dead.** I predicted that FIXED mode
  arming `M_BKE_EN` on the CPU's DRAM path was the danger, and that a
  bypass-only build would survive. It hung identically. That test was
  still worth running — it is what ruled the theory out and forced the
  search back to addressing.

## Verified state

Branch `joan/qos-bimc-v2` @ `24e82e84e`, RAM-booted 2026-08-07:

    CRITERION_1=PASS   CRITERION_2=PASS
    icc_rpm_error_lines=0
    axi_clk_src_hz=405999902
    mdss_per_sec=70.44

    mas-gnoc-bimc                 0            0
    mas-oxili                     0      6800000
    mas-mnoc-bimc           1209322       800000
    slv-ebi                 1209322      6800000

All six fabric `qos_offset` values were re-audited against downstream
after the fix; bimc was the only one wrong, because it is the only
BIMC-type provider and the only one whose offset lives in a macro.

## Commits

    37292332c  bimc ab_coeff from downstream util-fact (153)
    8edf37a09  bimc QoS, bypass masters only        [superseded, kept for record]
    24e82e84e  fix bimc qos_offset, enable all three masters

`joan/qos-prio-fix-v1` — **do not merge.** `97d770f16` reset ten masters'
priorities to 0; `bc3cf0c86` reverts six of them. Downstream declares
`qcom,prio0 = <1>` / `qcom,prio1 = <1>` for `mas_hmss`, `mas_qdss_bam`,
`mas_qdss_etr`, `mas_pcie_0`, `mas_ufs` and `mas_usb3`. My audit only
searched for `qcom,prio-lvl`/`qcom,prio-rd` — the form `mas_gnoc_bimc`
uses — so "downstream declares no priority" was an artefact of the
search, not a fact. The msm-bus binding accepts both spellings. sdm660
independently confirms the mapping (`mas_ipa`: `areq_prio = 1`,
`prio_level = 1`, matching downstream `prio0/prio1 = <1>`).

The parser fallback was still unsound, but it agreed with downstream
everywhere except `mas_gnoc_bimc`, which is already correct on
`joan/qos-bimc-v2`. Branch kept as the record of a wrong turn.

**Second transferable lesson:** when checking whether downstream declares
something, search for *every* spelling the binding accepts before
concluding it declares nothing. A negative result from a single-form grep
is not a negative result.

## What is actually left

- `mas_ipa` — **NOT blocked. Keep poking at this; it is a small,
  one-boot task.** I called it blocked twice and was wrong twice.

  What is true: a2noc QoS needs the IPA clock held on. Downstream's
  `fab_a2noc` lists it **first** in `qcom,node-qos-clks`
  (`clk-ipa-clk`), and mainline sdm660 — the only platform that programs
  `mas_ipa` — carries `"ipa"` first in its a2noc `intf_clocks`, with its
  binding requiring it (`- const: ipa`, "IPA Clock."). We dropped that
  clock when building `msm8998_a2noc_intf_clocks`.

  What I got wrong: I said the prerequisite was adding `GCC_IPA_CLK` to
  `gcc-msm8998`. **The IPA clock is not a GCC clock.** It is an RPM SMD
  clock, and it is *already registered for msm8998 in mainline*:

	/* drivers/clk/qcom/clk-smd-rpm.c, inside msm8998_clks[] */
	[RPM_SMD_IPA_CLK]   = &clk_smd_rpm_ipa_clk,
	[RPM_SMD_IPA_A_CLK] = &clk_smd_rpm_ipa_a_clk,

	/* include/dt-bindings/clock/qcom,rpmcc.h */
	#define RPM_SMD_IPA_CLK   68
	#define RPM_SMD_IPA_A_CLK 69

  I only ever grepped `gcc-msm8998.c` and the gcc dt-bindings header,
  found `GCC_IPA_BCR` (a reset) and nothing else, and concluded no IPA
  clock existed anywhere. It was in the next driver over the whole time.

  **The actual work, in order:**

  1. Add `<&rpmcc RPM_SMD_IPA_CLK>` to the a2noc interconnect node in
     `msm8998.dtsi`, with `"ipa"` in `clock-names`.
  2. Add `"ipa"` to `msm8998_a2noc_intf_clocks[]` — put it **first**,
     matching downstream and sdm660.
  3. Set `mas_ipa` QoS: `ap_owned` already true, `qos_mode = FIXED`,
     `qos_port = 1`, `areq_prio = 1`, `prio_level = 1` (downstream
     `prio0/prio1 = <1>`; sdm660 uses the same 1/1).
  4. Update `Documentation/devicetree/bindings/interconnect/` for the new
     msm8998 a2noc clock, following the sdm660 stanza.

  Address check: a2noc `qos_offset = 0x5000`, so port 1 lands at
  `0x5000 + 0xc + 0x1000 = 0x600c`, inside a2noc's `0x10000` window.

  **One caution that is still real:** a2noc has never performed a single
  QoS write. Every other a2noc master is `ap_owned = false`, so its
  `intf_clocks` have never actually been exercised. `mas_ipa` will be the
  first write that fabric has ever taken from us, so treat it as a fresh
  bring-up — one change, one boot, `scripts/dtb-check-reg-overlaps.sh`
  first, and expect a hang to be informative rather than surprising.

  Value note: IPA is a networking datapath accelerator, mostly cellular
  modem offload, which is not up on this port. The gap is real but
  currently inert — worth closing for completeness and upstreamability,
  not for user-visible performance.
- `docs/upstream-question-icc-rpm-qos-clocks.md` — **do not send as
  written.** Its central premise (that per-master QoS clocks are the
  missing mechanism) is now disproven for our case; the answer was
  addressing. Rewrite or drop it.

## Lockscreen choppiness — diagnosed, NOT a bus problem

Owner reported the lockscreen still choppy after bimc QoS landed. It is
not interconnect, GPU frequency, or DPU underruns (0 underruns measured).

**phosh renders the lockscreen in software.** Measured on-device:

    phosh:  libgtk-3.so.0.2420.32      <-- no GL library mapped at all
    phoc:   libEGL, libGLESv2, libgallium, libgbm

GTK3 draws with Cairo on the CPU. phoc composites app surfaces with
hardware GL, but the lockscreen is a surface phosh draws itself, at
1440x2880 = 4.15 Mpixel, per frame, on the CPU. A 45 s trace during
lockscreen interaction:

    phosh CPU peak 103% of one core, sustained 60-90%
    GPU over the same window: 49.3 s @ 257 MHz, 5.1 s @ 515, 1.7 s @ 850

phosh pegs a core while the GPU idles. joan is hit ~4x harder than the
PinePhone phosh is tuned against (720x1440 = 1 Mpixel).

There is no config fix: GTK3's GL path only covers GtkGLArea. Upstream is
porting phosh to GTK4 explicitly to get GPU rendering (NLnet NGI0
Commons Fund, started April 2025, no completion date published:
https://nlnet.nl/project/Phosh-GTK4/). Watch for a GTK4 phosh in pmOS.

**Untested lead worth one command:** in the same trace, phosh ran at
76-87% CPU on several samples while cpu4 sat at 300 MHz — the scheduler
is leaving a sustained near-full-core render thread on the little
cluster. `taskset` phosh to cpu4-7 and re-measure. Free, reversible, no
boot.

**What actually helped: `enable-animations = false`.** Owner reports the
lockscreen noticeably more responsive. phosh CPU over an interaction
dropped from 2080 jiffies to 490 — the windows were not equal duration or
identical interaction, so read that as "large, right direction", not a
clean 4x. Applied via the phosh session bus, which is a `/tmp/dbus-*`
socket, **not** `/run/user/10000/bus`; a plain `gsettings` call
silently no-ops. Note this is a global GNOME setting, not lockscreen
scoped — it affects the whole shell and every GTK app.

**Ruled out, with measurements, so nobody repeats them:**

- *irqbalance / IRQ affinity.* Total IRQ rate ~360/s; `irq+softirq` on
  cpu0 is ~0.5% of one core. The top sources (`arch_timer`, IPIs) are
  per-CPU and cannot be balanced at all. Not installed, correctly.
- *CPU affinity / `taskset`.* phosh already runs **99.8% on the big
  cluster** (cpu4-7). An earlier claim of mine that it was stuck on the
  little cluster was wrong — I inferred it from cpu4's *frequency*
  reading, which proves nothing about placement.
- *More cores.* 2080 of 2084 busy jiffies are **one thread** (tid 2035,
  the GTK3 main thread). phosh cannot use more than one core here.
- *A faster rasteriser.* pixman is 0.46.4 with arm64 NEON fast paths, and
  the CPU reports `asimd`. The fast path is already in use.

**Rendering the lockscreen at lower resolution** is the right idea and
`wp_viewporter` is the right mechanism — phoc supports it (confirmed in
the binary, alongside `zwlr_layer_shell`). The blocker is that GTK3
exposes no way to attach a viewport; its Wayland backend owns surface and
buffer creation. Doing it means forking GTK3's `gdk/wayland` or rewriting
`PhoshLockscreen` as a raw Wayland client — both more work than the GTK4
port, which fixes the whole shell rather than one surface. Not
recommended. The cheap approximation is `phoc.ini` output `scale = 2`
plus `GDK_SCALE=1`, which gets the same 4x pixel saving shell-wide via
compositor upscaling, at the cost of a softer image. Untested.

**GPU min_freq is a dead end.** Raising the floor 257 -> 596 MHz appeared
to speed up general UI, but the reverse-order test did not reproduce any
degradation on the way back down, so the effect is not established. Floor
left at the 257 default. Do not record this as a win. (Same
treatment-second confound as the four earlier GPU A/Bs — see
[[feedback_ab_order_confound]].)

## Standing practice that earned its keep

- `scripts/dtb-check-reg-overlaps.sh` on every DTB before boot.
- SD partition check before every RAM boot (UUIDs, `e2fsck -fn` on p1,
  superblock state + surface scan on p2). Note LineageOS's e2fsck is
  1.46.2 and **cannot** check p2 — it bails on unsupported features and
  prints a scary but meaningless "still has errors". Treat that as
  "could not check", never as a result in either direction.
- One GPU/bus experiment per boot.

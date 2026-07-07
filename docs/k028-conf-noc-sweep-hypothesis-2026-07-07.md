# K028 prep — CONF_NOC mechanism: the late unused-clock/genpd sweeps (source-only)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07

Source-only analysis while the phone awaits physical recovery (no device
contact this session). Follows Aurel's K027 handoff
(`docs/ember-handoff-2026-07-07-k027-complete.md`); K027 remains the pending
device oracle and this doc explains *why it is exactly the right one*, plus
the decision tree after its one valid run.

## TL;DR

The best-fit mechanism for `LGE_ERR_TZ_CONF_NOC_ERR` (0x6D630309) is now:

> Mainline's **late boot sweeps** — `clk_disable_unused()`
> (late_initcall_sync) and genpd's power-off-unused (late_initcall) —
> force-gate XBL-left-on GCC branch clocks and GDSCs that nothing in our
> driverless mainline boot claims. Some seconds later, a **register-path
> (Config NoC) access** into one of those now-dead blocks — most plausibly
> TrustZone's own periodic housekeeping (hardware PRNG reseed is the
> classic) — cannot complete. The CNoC error logger fires, LG's TZ error
> policy writes `TZ | CONF_NOC_ERR` to IMEM and yanks PS_HOLD.

This explains every prior observation at once:

- **All K022–K024 configs still reset**: every config still ran both sweeps;
  each config always had *something* swept (the "single trigger" assumption
  was the blind spot — the trigger is the sweep *class*, not one node).
- **K023d (no `&rpm_requests`) still reset**: rules out the RPM vote path —
  and indeed with rpmcc absent nothing HLOS-side can drop RPM-owned fabric
  clocks. The sweep victims are GCC-side (built-in `CONFIG_MSM_GCC_8998=y`),
  present in every config.
- **Jittery reset time (+27…+31s observed; LOS return +30…+49s)**: the error
  fires not at the sweep (~t+3–8s) but at the *next offending access* — a
  TZ housekeeping cadence, which is naturally jittery. A watchdog would be
  fixed-period; the spread always fit an event, not a timer.
- **Stock LG kernel RAM-boots fine (unsigned!)**: downstream *also* sweeps
  handed-off clocks (`clock_late_init()`, drivers/clk/msm/clock.c,
  late_initcall_sync) — but downstream boots with the full driver set
  (msm_rng, qseecom, mdss cont-splash handoff, msm_bus votes), so nearly
  every boot-on clock is *claimed* before its sweep runs. Same sweep,
  near-empty victim set. That asymmetry is what looked like "downstream
  services a secure watchdog somehow."
- **Kernel-fixable, as predicted**: no signing, no TZ patching — just stop
  gating (or properly claim) the load-bearing clocks.

## Evidence chain (all source-verified this session)

1. **TZ told us the failing fabric, precisely.** The LGE reboot-reason
   taxonomy (public bullhead header, preserved at
   `out/aurel-k027-public-bullhead-reboot_reason.h`) has *separate* codes for
   AHB timeout (0x04), OCMEM NoC (0x05), **MM NoC (0x06)**, **Peripheral NoC
   (0x07)**, **System NoC (0x08)**, **Config NoC (0x09 ← ours)**, XPU (0x0A).
   So: a *register-space* transaction failed. Not display scanout data (that
   would be MM/SYS NoC), not an XPU permission trap. Register accesses fail
   like this when the target's interface/bridge clock is off.

2. **Mainline gcc-msm8998.c has ZERO `CLK_IGNORE_UNUSED`** and only three
   `CLK_IS_CRITICAL` clocks (`gcc_gpu_cfg_ahb_clk`, `gcc_mmss_noc_cfg_ahb_clk`,
   `gcc_mss_q6_bimc_axi_clk`). Every other XBL-enabled, unconsumed branch
   clock is gated at late_initcall_sync. Sweepable fabric-adjacent examples:
   `gcc_prng_ahb_clk`, `gcc_boot_rom_ahb_clk`, `gcc_mmss_sys_noc_axi_clk`,
   `gcc_mmss_qm_ahb/core_clk`, `gcc_aggre1_noc_xo_clk`,
   `gcc_cfg_noc_usb3_axi_clk`, `gcc_bimc_hmss_axi_clk`.

3. **The PRNG is the standout candidate.**
   - Downstream msm8998.dtsi has `qrng@793000` (`qcom,msm-rng`) with
     `qcom,msm-rng-iface-clk` → **claims `gcc_prng_ahb_clk`**, plus an
     explicit **`msm-rng-noc` bus vote** (the exact path name in Aurel's
     downstream NoC vote list), plus `qcom,no-qrng-config` (= HLOS must not
     touch config — TZ owns the block's configuration).
   - Mainline msm8998.dtsi has **no rng node at all** and our .config builds
     no qcom-rng driver → the clock is registered (binding id
     `GCC_PRNG_AHB_CLK` = 100) and unclaimed → swept every boot.
   - Qualcomm TZ periodically draws entropy from the hardware PRNG. Gated
     AHB + TZ reseed = a config access into a clock-gated block = CNoC error.
     Cadence naturally in the tens-of-seconds, jittery. This fits the
     timing signature better than anything we've had all week.

4. **RPM-owned fabric clocks are NOT the victims** (needed saying):
   clk-smd-rpm splits msm8998 clocks into a regular table and
   `msm8998_icc_clks` (aggre1/aggre2 NoC, BIMC, SNoC, **CNoC**, MMSS NoC
   AXI). The icc_clks get a one-shot INT_MAX handoff vote at probe and are
   *never registered in CCF* — they're meant for an `icc_smd_rpm` provider
   that **does not exist for msm8998** — so nothing ever lowers those votes.
   And CCF can't sweep RPM clocks anyway (no `.is_enabled` op → sweep sees
   them as already-off and skips). Consistent with K023d both ways.

5. **The OnePlus precedent says this class is real on this exact SoC.**
   `msm8998-oneplus-common.dtsi` carries a simple-framebuffer node whose own
   comment reads: *"That's a lot of clocks, but it's necessary due to
   **unused clk cleanup** & no panel driver yet"* — holding 8 MDSS clocks +
   `MDSS_GDSC` purely to survive the sweeps. Upstream 8998 phones already
   fight this exact enemy.
   (Joan's DTS deliberately has no simplefb node — the comment only weighs
   console visibility, which is correct as far as it goes — but note
   `CONFIG_MSM_MMCC_8998=m` means MMCC never probes in our RAM boots, so
   MDSS/MMCC clocks were never registered and are NOT suspects for the
   *current* resets. GCC-side victims are.)

6. **Downstream sweeps too — with almost nothing to sweep.** msm-4.4
   `clock_late_init()` drops handoff enables at late_initcall_sync, exactly
   like mainline; `always_on` downstream covers only `gcc_hmss_dvm_bus_clk`
   and `gcc_mss_q6_bimc_axi_clk`. Downstream survives because its drivers
   claim everything (msm_rng, qseecom/CE, mdss, msm_bus keepalives), not
   because it treats the hardware more gently.

## Why K027 is the right (and sufficient) discriminator

`clk_ignore_unused pd_ignore_unused` disables **both** sweeps and nothing
else. One valid run classifies the entire hypothesis class:

- **Survives** (survivor beacon ~t+90–120s, no LOS return): mechanism
  confirmed as the sweeps. Proceed to bisection (below).
- **Valid reset** (LOS returns ~30–60s, PON PS_HOLD, still 0x6D630309):
  the whole late-sweep class is eliminated in one shot — including the PRNG,
  boot-ROM, every GCC branch clock and every GDSC. Fall back to the
  TZ-affirmative-keepalive line (Aurel's smcinvoke/listener archaeology) or
  earlier-than-sweep accesses with delayed TZ detection.

Procedure, image, and monitor discipline: exactly as written in Aurel's
handoff §"If Lance physically recovers the phone" — one client,
`sudo -n fastboot boot out/boot-joan-clkpd-k027.img`, stop on decisive
signal, PON + bootreasoncode readback.

## Decision tree after K027 survives

Bisect from coarse to fine, one variable per boot, `panic=0` harness:

1. **K028a — `clk_ignore_unused` only** (drop `pd_ignore_unused`).
   Survives → clk sweep is the killer (GDSCs innocent). Resets → genpd
   sweep implicated (GDSC set: pcie_0, ufs, usb_30, lpass votes).
2. **K028b — targeted clock hold, cmdline-clean.** Debug kernel patch (save
   to `out/`, revert after build, per rule 9): mark `gcc_prng_ahb_clk` +
   `gcc_boot_rom_ahb_clk` `CLK_IGNORE_UNUSED` in gcc-msm8998.c. Survives →
   killer identified to ~2 clocks; then drop boot_rom to isolate PRNG alone.
3. **Durable fix (upstream-shaped), once the clock is named:**
   - PRNG case: add the standard rng node to msm8998.dtsi (benefits every
     8998 board) + `CONFIG_CRYPTO_DEV_QCOM_RNG=y`:

     ```dts
     rng: rng@793000 {
             compatible = "qcom,prng-ee";   /* verify vs sdm660.dtsi; dowstream base 0x793000 */
             reg = <0x00793000 0x1000>;
             clocks = <&gcc GCC_PRNG_AHB_CLK>;
             clock-names = "core";
     };
     ```
     (msm8996 upstream: `rng@83000`, `qcom,prng-ee`, same shape. Downstream's
     `qcom,no-qrng-config` says TZ owns block config — prng-ee's per-EE pages
     are designed for that. Driver compatibles: qcom,prng / qcom,prng-ee /
     qcom,trng in drivers/crypto/qcom-rng.c.)
   - boot_rom / bridge-clock case: `CLK_IGNORE_UNUSED` flags in
     gcc-msm8998.c, matching what other qcom gcc drivers already do.
4. If K028b resets while K028a survived: widen the flag set stepwise through
   the fabric-adjacent list in Evidence §2 (mmss_sys_noc_axi, mmss_qm_*,
   aggre1_noc_xo, cfg_noc_usb3_axi, bimc_hmss_axi), still one step per boot.

## Standing cautions

- Phone must be physically recovered by Lance first (no adb/fastboot/lsusb
  presence as of 2026-07-07). No remote probing until it re-enumerates.
- All prior safety rules bind: RAM-only boot, one fastboot client,
  `sudo -n fastboot`, no getvar, enter fastboot via `adb reboot bootloader`,
  stop monitors on decisive signals.
- `CONFIG_MSM_MMCC_8998=m` and no simplefb driver in .config: if a future
  fix wants the OnePlus-style framebuffer clock-holder, MMCC must go =y and
  a simplefb/simpledrm driver must be enabled — but nothing in the current
  evidence requires that; don't bundle it.

## Falsifiable predictions (write them down before the test)

1. K027 survives to the ~90s survivor beacon.
2. If instead K027 validly resets, the bootreasoncode will still be exactly
   `0x6D630309` (same TZ classification, different cause family).
3. If K027 survives, K028a (clk-only) also survives, and K028b narrows to
   `gcc_prng_ahb_clk` — the PRNG reseed story. Confidence: moderate-high for
   1–2, moderate for 3 (boot_rom or a bridge clock are live alternates).

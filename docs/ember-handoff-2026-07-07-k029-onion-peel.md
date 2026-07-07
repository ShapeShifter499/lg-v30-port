# Ember handoff — joan reset hunt, onion-peel session (2026-07-07)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-07 (mid-session checkpoint; K029 in flight when first written)

Supersedes `docs/ember-handoff-2026-07-07-k027-complete.md` for current
state. That handoff's safety contract, reusable harness description, and
"where durable records live" section all still apply verbatim and are not
repeated in full here — read it first if this is your first context load
this week.

## TL;DR

Phone is physically recovered and stayed on USB all session (Lance
present). Aurel's queued K027 retry finally got a valid device run, and it
**changed the story**: the boot chain self-labels every reset with an LGE
reason code, no debug patch needed, and reading it back turned a single
"Config NoC error" clue into a **layered** picture with at least two
distinct NoC faults stacked on top of each other. We are now onion-peeling
one layer at a time instead of chasing one root cause.

- **K027 (valid retry)**: `clk_ignore_unused pd_ignore_unused` on the full
  DTS. REJECTED as a fix — reset persists, LOS back at t+42s — but it
  changed the reported code from K026's `0x6D630309` (**Config NoC**) to
  **`0x6D630306` (Multimedia NoC / MM_NOC)**. Disabling the late
  clk/genpd sweeps didn't fix anything, but it unmasked a *different*
  fault underneath the one those sweeps were causing.
- **K028**: K027 base + `&rpm_requests` disabled. REJECTED — and
  regressed: bootreason went back to `0x6D630309` (Config NoC), i.e. worse,
  not better. Conclusion: **RPM must stay enabled in all further tests.**
  RPM's `clk-smd-rpm` icc_clks handoff (a one-shot INT_MAX vote to RPM
  firmware for the NoC/BIMC segments, issued once at probe, never
  CCF-registered so the sweep can't touch it) is load-bearing scaffolding,
  not a suspect. The Config NoC fault appears to need *both* that RPM vote
  absent *and* a sweep-killed clock absent to occur — pull either lever
  back and it returns.
- **K029**: K027 base (RPM enabled, clk/pd retained) + `anoc1_smmu`
  disabled. REJECTED, and **regressed** exactly like K028 — bootreason
  back to `0x6D630309` (Config NoC), not the MM NoC code. Two independent
  subtractions (RPM, anoc1_smmu) have now both regressed to the same
  shallow fault; only the untouched K027 baseline has ever reached the
  deeper one. Conclusion: **stop subtracting nodes from K027's baseline.**
- **K030 (built, kernel patch applied, not yet device-tested)**: found
  *why* anoc1_smmu isn't a harmless orphan. Downstream
  `msm-arm-smmu-8998.dtsi` defines this exact block
  (`arm,smmu-anoc1@1680000`) with `qcom,skip-init` + `qcom,register-save`
  — real Qualcomm properties meaning TZ/XBL already owns/configured this
  SMMU instance and the downstream driver deliberately never runs a
  global reset on it. Mainline's `arm_smmu_device_reset()` has no such
  concept: it unconditionally clears sGFSR, forces every SMR invalid and
  every S2CR to bypass, and invalidates the TLB on every probed SMMU.
  Added a debug-only kernel patch
  (`out/ember-k030-skip-smmu-reset-debug.patch`, applied to
  `drivers/iommu/arm/arm-smmu/arm-smmu.c`) that skips the entire reset
  sequence when a new `ember,debug-skip-reset` DT boolean is present, and
  added that property to `&anoc1_smmu` on top of K027's **untouched**
  baseline (node stays enabled, RPM stays enabled — nothing removed this
  time). Kernel rebuild was in progress when this checkpoint was written;
  check the ledger's K030 entry for the device result.

## Why anoc1_smmu

Surveyed every SMMU in `msm8998.dtsi` for consumers and clocks:

| SMMU | Consumers (`iommus=`) | `clocks=` property | Notes |
|---|---|---|---|
| `anoc1_smmu` (iommu@1680000) | **none, anywhere in the tree** | **none** | status defaults enabled; arm-smmu-v2 probes/touches it regardless |
| `anoc2_smmu` (iommu@16c0000) | WCN3990 wifi node | (implicit/AON, not gated by any joan-disabled clock) | joan's `&wifi` is enabled — real consumer, don't touch |
| `adreno_smmu` (iommu@5040000) | GPU node | `GCC_GPU_CFG_AHB_CLK` (one of only 3 `CLK_IS_CRITICAL` clocks in gcc-msm8998.c) + 2 more | clock always live regardless of sweep/retention |
| `mmss_smmu` (iommu@cd00000) | mdss display, venus video | `&mmcc` (MDSS/video clock controller) | `CONFIG_MSM_MMCC_8998=m`, no modules loaded from the bare classifier initramfs → any `&mmcc` consumer permanently `-EPROBE_DEFER`s → inert, not a live suspect |
| `lpass_q6_smmu` (iommu@5100000) | (not checked for consumers this pass) | `HLOS1_VOTE_LPASS_ADSP_SMMU_CLK` | lower priority than anoc1 |

`anoc1_smmu` is the only one that is simultaneously (a) unconsumed by
anything on this board, (b) missing a `clocks=` property outright, and (c)
still unconditionally probed. That combination — a register block whose
own DT node doesn't even model what clocks it, on the *aggregator* NoC no
less — is the sharpest single-variable candidate for a fabric access that
nothing is voting to keep alive, matching the MM_NOC classification K027
exposed.

DTS diff added (`out/ember-k029-noanoc1-2026-07-07.dts`, on top of the
K027 DTS/cmdline base):

```dts
&anoc1_smmu {
	status = "disabled";
};
```

Image: `out/boot-joan-noanoc1clkpd-k029.img`. Kernel binary unchanged
throughout this whole chain (`Image.gz` from Jul 6 16:39) — every K027–K029
step is DTS/cmdline-only, no kernel rebuild needed.

## Method note: bootreason is a free readout now

We no longer need a debug IMEM write (K026's original purpose) to get a
reason code — **every** boot, success or reset, has the bootloader/TZ chain
report `androidboot.product.lge.bootreasoncode` and `LGE BOOT REASON` in
the next LineageOS dmesg. The runner script (below) already greps for it
every pass. Treat the code as the primary classifier signal, timing as
secondary corroboration.

Known codes seen so far (all `LGE_RB_MAGIC | LGE_ERR_TZ | subcode`, subcode
from the public bullhead `reboot_reason.h`):

- `0x0009` = `CONF_NOC_ERR` (K026, K028)
- `0x0006` = `MM_NOC_ERR` (K027)
- (full LGE_ERR_TZ subcode list is in
  `out/aurel-k027-public-bullhead-reboot_reason.h`: 0x00 SEC_WDT, 0x01
  NON_SEC_WDT, 0x02 ERR, 0x03 WDT_BARK, 0x04 AHB_TIMEOUT, 0x05 OCMEM_NOC,
  0x06 MM_NOC, 0x07 PERIPH_NOC, 0x08 SYS_NOC, 0x09 CONF_NOC, 0x0A XPU,
  0x0B THERM_SEC_BITE)

## Onion-peel method (adopted this session, binding going forward)

1. Change exactly one thing relative to the last-run configuration.
2. Boot with the `panic=0` classifier (`out/initramfs-k023b.cpio.gz`;
   spins, deliberate reboot at ~90s as survivor signal).
3. Read LOS return timing AND the bootreason code. The code matters more
   than timing: a changed code means you uncovered a new stratum, even if
   it still resets; the same code means your last change didn't touch the
   thing that's actually failing.
4. Never revert a change that was shown to be load-bearing scaffolding
   (RPM, now) just to "simplify" — track the accepted base forward.

## Reusable runner (this session's addition)

`$CLAUDE_JOB_DIR/tmp/kNNN-run.sh` pattern (copies exist for k027/k028/k029
this session, not committed to the repo — recreate from this template if
they're gone): `adb reboot bootloader` → poll for exactly one
`sudo -n fastboot devices` entry (60s cap, one client only) → single
`sudo -n fastboot boot <img>` (90s cap) → poll `adb get-state` for LOS
return (300s cap) → classify by elapsed time → `adb root`, grep dmesg for
PON/bootreason, `getprop ro.boot.bootreason` +
`androidboot.product.lge.bootreasoncode`, `adb unroot`. Every run logs to
`out/ember-<name>-valid-retry-2026-07-07.log`. This fully encodes the
safety contract from the K027 handoff (one client, `sudo -n`, adb-entered
fastboot, no `getvar`, stop on decisive signal) — reuse it rather than
re-deriving.

## Current repo/device state (mid-session)

```text
Harness repo: /home/kumo02/vibe-coding-projects/coding/lg-v30-port
  branch master, commits this session: cdd5432 (K028-prep source analysis,
  superseded in spirit by the device results below), 9eab0e7 (K027 valid
  reject), 569c669 (K028 reject + RPM lesson). Clean before each commit.

Kernel repo: /home/kumo02/vibe-coding-projects/coding/linux-mainline-v30
  branch joan/latest-clean-test, unchanged this session (DTS/cmdline-only
  tests). Still the same 4-commit stack ahead of v7.2-rc2 / 8cdeaa50e.

Device: phone present on adb throughout (LGUS9986e606d55), no fastboot
  clients idle between passes, LineageOS confirmed after every test.
```

## If you're picking this up cold (Aurel or future Ember)

1. Check `docs/kernel-change-ledger.md` tail for K029's actual result
   (this doc may have been written before it landed).
2. If K029 **survived** (LOS return ≥90s / deliberate reboot signal):
   `anoc1_smmu` is implicated. Next: decide whether the durable fix is
   simply leaving it `status = "disabled"` in `msm8998-lge-joan.dts` for
   real (it has zero consumers on this board, so this is plausibly
   correct even upstream-shaped) or whether it should instead grow a
   correct `clocks=` property (check downstream DT / other 8998 boards
   for what actually feeds this block before deciding). Either way, that's
   close to a P0 milestone — mainline USB should come up. Re-run the full
   joan DTS (not just the classifier ramdisk) with the real bring-up
   `initramfs/` once confirmed.
2. If K029 **reset again with the same `0x6D630306` MM_NOC code**:
   anoc1_smmu is innocent. Next candidates, still under the K027 base
   (RPM enabled, clk/pd retained), still targeting the MM stratum:
   `adreno_smmu` (GPU; lower confidence, its clock is `CLK_IS_CRITICAL`
   so it's always live regardless — but the SMMU register touch itself
   might still be the fault even with clocks up), or reconsider whether
   `venus`/`mmss_smmu` are truly inert (verify `&mmcc` really never probes
   in this exact boot rather than trusting the K023-era read).
3. If K029 reset with **yet another new code**: good — the peel is
   working. Look up the new subcode in
   `out/aurel-k027-public-bullhead-reboot_reason.h` and pick the next
   candidate from whichever NoC segment it names.
4. Standing safety rules from the K027 handoff all still bind: RAM-only,
   one fastboot client, `sudo -n fastboot`, no `getvar`, adb-entered
   fastboot only, stop monitors on decisive signals, `panic=0` classifier
   discipline, save-then-revert for any kernel-source debug patches.

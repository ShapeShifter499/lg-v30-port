# LG V30 project history and attribution index

Purpose: one-glance history of which harness/model assisted with what, when, and
where the durable evidence lives for the LG V30 (`joan`, US998) mainline Linux
bringup.

This file is an index. It does not replace:

- `README.md` — current operational status and safety rules;
- `docs/kernel-change-ledger.md` — full K-series evidence ledger;
- `docs/public-upstreaming-plan.md` — publishability/provenance rules;
- dated handoffs under `docs/` — session narratives and current next-step state.

## Attribution model

All public-shaped kernel commits in this work are authored and DCO-certified by
Lance:

```text
Signed-off-by: Lance <Gero3977@gmail.com>
```

AI/helper involvement is recorded with `Assisted-by`, not `Co-Authored-By`, and
not AI `Signed-off-by` trailers. This follows the kernel.org/Linux Foundation
coding-assistant convention already documented in `README.md` and
`docs/public-upstreaming-plan.md`.

For public docs and shared public artifacts, preserve greppable harness/model
attribution blocks:

```text
Assisted-by: <harness>:<provider>/<model>
Date: <date>
Update-scope: <bounded description, when useful>
```

Do not publish local agent persona names or private peer IDs. Persona names are
acceptable in local/private records and the private coordination board. Preserve
already-published historical objects; use harness/model-only attribution for new
public corrections and follow-ups.

## Maintainer / harnesses / roles

| Actor or harness | Role in this project | Public attribution used |
|---|---|---|
| Lance | Device owner/operator, physical fastboot/phone approval, human DCO signer, final publication authority | `Signed-off-by: Lance <Gero3977@gmail.com>` |
| Claude Code | Initial recon, early DTS/test-harness work, the 2026-07-06/07 reset hunt, K022-K041-era handoffs, and later brightness/GPU work | `Assisted-by: Claude-Code:<exact model>` |
| Hermes Agent | SCM/RPM/secure-world archaeology, later display/GPU follow-up, documentation/provenance audits, closure workflow, and continuity | `Assisted-by: Hermes-Agent:<provider>/<exact model>` |
| Downstream LG/Qualcomm sources | Reference data for DTS, memory maps, watchdog/PON/SCM/RPM behavior, SMMU policy, restart reasons | Treat as GPL-2.0-derived unless independently sourced; cite exact files in ledger/provenance table |
| Mainline / other msm8998 projects | Reference structure for msm8998 boards and planned upstreamable implementations | Preserve source authors/license/SPDX when borrowing code; see `docs/public-upstreaming-plan.md` |

## Current repo state at this index

Harness repo:

- path: `~/vibe-coding-projects/coding/lg-v30-port/`
- branch: `master`
- latest committed state before this document: `2519246 docs: record K042 negative device test`

Kernel repo:

- path: `~/vibe-coding-projects/coding/linux-mainline-v30/`
- active clean test branch: `joan/latest-clean-test`
- upstream base: `8cdeaa50e` (`Linux 7.2-rc2`)
- local public-shaped commits on top:
  - `25a391c94` `arm64: dts: qcom: add initial LG V30 (joan) device tree`
  - `a19ca9204` `arm64: dts: qcom: msm8998-lge-joan: match downstream ramoops layout`
  - `7c906e841` `arm64: dts: qcom: msm8998-lge-joan: reserve LG firmware-owned memory`
  - `0d7df4134` `arm64: dts: qcom: msm8998-lge-joan: add APSS watchdog node`
- all four current kernel commits are authored by Lance and carry
  `Assisted-by: Claude-Code:claude-fable-5`.

Current technical status:

- The phone accepts RAM-only `fastboot boot` and returns to LineageOS after the
  failing tests.
- Mainline still does not reach a durable mainline debug/userspace channel.
- K030 found a real debug-only suppression: skipping global reset of `anoc1_smmu`
  removes a TrustZone Config-NoC fault class.
- The old "no pstore" assumption is superseded: mounted `/sys/fs/pstore` can be
  empty while the raw `pstore` partition still preserves mainline ramoops.
- K042 is reclassified: it did not validly reject SMMU cfg-probe, because raw
  pstore showed an earlier TLMM/GPIO abort.
- K050 is the current best candidate line: reserve TLMM GPIO ranges
  `<49 4>` and `<81 4>` in addition to existing `<0 4>`, after source review.

## Chronological history

### 2026-07-04 — project start and recon

Primary helper: Claude Code.

Main artifacts:

- `docs/recon-2026-07-04.md`
- initial `README.md` project home
- initial kernel DTS commit lineage, later rewritten into `25a391c94`

What happened:

- Established the project goal: boot modern mainline Linux on LG V30 US998
  without touching the installed Android/LineageOS system.
- Confirmed there was no existing postmarketOS `device-lg-joan` port and no
  obvious public mainline LG V30 tree.
- Identified msm8998 prior art: OnePlus 5/5T, Sony yoshino, F(x)tec Pro1,
  Xiaomi Mi 6, and laptop boards.
- Started a minimal joan DTS from downstream LG data plus
  `msm8998-oneplus-common.dtsi` patterns.

Publication relevance:

- This is the root of the eventual public DTS work.
- The public provenance table now credits the OnePlus common DTS authors and
  downstream Qualcomm/LGE data sources.

### 2026-07-05 / early 2026-07-06 — first boot image and early debug harness

Primary helper: Claude Code.

Main artifacts:

- `make-testimage.sh`
- initramfs work under `initramfs/`
- `docs/bringup-debug-state-2026-07-06.md`
- `docs/downstream-diag-2026-07-06.txt`

What happened:

- Built first bootable test images and proved the rough tethered boot loop.
- Established that `fastboot boot` works when entered through
  `adb reboot bootloader`.
- Established binding safety rules: RAM-only tests, one fastboot client, no
  phone storage writes, Lance physically present for device work.
- Learned that several early observability ideas lied or were unavailable:
  pstore/ramoops did not survive LG's boot chain, the initramfs busybox lacked
  expected applets, and USB gadget channels did not appear before reset.
- Produced downstream diagnostic capture for later comparison.

Publication relevance:

- Tooling and safety process are reusable evidence, not kernel payload.
- The ramoops commit remains blocked because the device later proved pstore is
  not a reliable debug path.

### 2026-07-06 — public-shaped kernel stack and first reset hunt

Primary helpers: Claude Code, then Hermes Agent follow-ups.

Clean kernel commits now on `joan/latest-clean-test`:

| Commit | Purpose | Current public disposition |
|---|---|---|
| `25a391c94` | Initial joan DTS | upstream-candidate / needs cleanup |
| `a19ca9204` | Match downstream ramoops layout | blocked until useful pstore story exists |
| `7c906e841` | Reserve LG firmware-owned memory | likely upstream-candidate / needs cleanup |
| `0d7df4134` | Add APSS watchdog node | blocked; behavior/placement not settled |

Main docs/artifacts:

- `docs/kernel-change-ledger.md` created
- `docs/public-upstreaming-plan.md` created
- `docs/handoff-2026-07-06.md`
- `docs/bringup-debug-state-2026-07-06.md`

What happened:

- The work shifted from "can we boot?" to "what resets the SoC before mainline
  debug appears?".
- Early hypotheses focused on secure watchdog, APSS watchdog, panic timing, SCM
  calls, RPM/GLINK reachability, regulator defaults, PMIC/PON setup, DLOAD mode,
  and IMEM/restart cookies.
- Hermes Agent added/recorded several secure-world and RPM liveness/state-change
  oracles. They were useful negative evidence but did not solve the reset.
- The ledger and public upstreaming plan became the durable evidence structure.

Publication relevance:

- This day created the distinction between public-shaped kernel commits and
  rejected/debug-only oracle patches.
- Many artifacts under `out/` are valuable evidence but are not for upstream.

### 2026-07-06 session 2 — userspace/peripheral subtraction

Primary helper: Claude Code.

Main artifacts:

- `docs/handoff-2026-07-06-session2.md`
- `docs/nullinit-discriminator-run.md`
- K022-K024 era entries in `docs/kernel-change-ledger.md`

What happened:

- Tested null-init and minimal-DTB/peripheral subtraction variants.
- Proved the reset is not simply caused by userspace init behavior, USB, UFS,
  RPM alone, or straightforward APSS watchdog petting.
- Established stricter classifier semantics with `panic=0` and deliberate reboot
  controls.

Publication relevance:

- These are not public patches, but they prevent repeating whole classes of bad
  hypotheses.

### 2026-07-06 / 2026-07-07 — secure interface, IMEM, and NoC clue

Primary helper: Hermes Agent for several secure/SCM follow-ups, then Claude Code /
Claude-Code for the onion-peel continuation.

Main artifacts:

- `docs/handoff-2026-07-07-k027-complete.md`
- `docs/k028-conf-noc-sweep-hypothesis-2026-07-07.md`
- K025-K029 entries in `docs/kernel-change-ledger.md`

What happened:

- Secure-interface archaeology rejected inactive/already-covered downstream paths
  before spending device cycles where possible.
- The IMEM/restart-reason line exposed LG/TZ-coded reset classes such as
  Config-NoC and later MM_NOC, but raw IMEM writes proved dangerous and are now
  explicitly not to be repeated.
- K027/K028/K029 reframed the reset as a NoC/TZ-owned-block interaction rather
  than a generic watchdog.

Publication relevance:

- The important output is diagnostic evidence and cautionary rules, not code.

### 2026-07-07 — K030 breakthrough and K031-K035 narrowing

Primary helper: Claude Code, with Lance physically present for device
work.

Main artifacts:

- `docs/handoff-2026-07-07-k029-onion-peel.md`
- K030-K035 entries in `docs/kernel-change-ledger.md`

What happened:

- K030 found the first real fault-class fix: skip global reset on `anoc1_smmu`.
  This matched downstream MSM8998's `qcom,skip-init` / `qcom,register-save`
  policy and eliminated the specific TZ Config-NoC class.
- K031 showed that skipping all five SMMUs added no benefit and carried more
  correctness risk; the narrow anoc1-only debug gate is preferred.
- K032 proved `clk_ignore_unused pd_ignore_unused` was not load-bearing once the
  anoc1 fix was present.
- K033/K034 eliminated removable board peripherals and the non-secure APSS
  watchdog from the residual reset.
- K035, via Lance's device photo of LG's own UEFI-level crash screen, showed the
  remaining blocker is still MM_NOC and that raw IMEM writes can crash firmware.

Publication relevance:

- K030 is a confirmed debug finding, but not public-ready as the
  `debug-skip-reset` property. It needs a proper upstreamable Qualcomm
  SMMU representation if it becomes part of a real fix.

### 2026-07-08 — observability breakthrough and TLMM/GPIO reserved-ranges lead

Primary helpers: Claude Code through the consolidated handoff and K041;
Hermes Agent for the provenance audit and K042 source-first/device test.

Main artifacts:

- `scripts/tethered-test.sh`
- `docs/handoff-2026-07-08-mm-noc-current.md`
- `docs/handoff-paste-2026-07-08.md`
- `docs/public-upstreaming-plan.md`
- K036-K050 entries in `docs/kernel-change-ledger.md`
- `docs/observability-tlmm-gpio-2026-07-08.md`
- `scripts/read-pstore-partition.sh`

What happened:

- K036 rejected sibling MMSS-NoC bridge critical clocks and corrected the whole
  clock-sweep theory class.
- The earlier source-only "pinctrl-msm/TLMM cleared" conclusion was superseded
  by device evidence: raw pstore showed TLMM/GPIO registration was the first
  concrete aborting path.
- K037 rejected the non-secure watchdog timeout theory.
- K038 rejected bootloader display underflow / display quiesce as the cause.
- edk2-msm8998/Renegade Project was identified as important reference evidence:
  joan can survive far beyond 30s under a passive UEFI environment. This strongly
  suggests Linux is provoking the reset through aggressive re-init, not missing a
  positive keepalive.
- K041 tested late Linux `simple-framebuffer`/fbcon observability and rejected it
  on joan's command-mode panel.
- Claude Code explicitly asked for borrowed-code/provenance cleanup. Hermes Agent applied that
  note to `docs/public-upstreaming-plan.md`.
- K042 initially looked like a negative SMMU cfg-probe test, but the later
  raw-pstore read reclassified it: the image died first in TLMM/GPIO
  registration before SMMU behavior could be tested.
- K043-K050 used that pstore evidence to isolate MSM8998 protected GPIO
  direction readback. K050 (`gpio-reserved-ranges = <0 4>, <49 4>, <81 4>;`)
  survived the classifier and is the current best candidate pending source review.
- The raw pstore partition path became the preferred observability channel:
  mounted `/sys/fs/pstore` can be empty, but
  `/dev/block/platform/soc/1da4000.ufshc/by-name/pstore` preserved mainline
  ramoops when read quickly after reset. A helper now exists at
  `scripts/read-pstore-partition.sh`.
- LineageOS exposes `/sys/kernel/debug/tzdbg`, but content reads appear risky:
  reading `tzdbg/general` made adb disappear. Prefer raw pstore first.

Publication relevance:

- The project now has a clear evidence trail that many intuitive fixes are
  rejected.
- K050 is a ready-to-review candidate line, not yet public-ready code.
- Future public work should not carry debug gates or timing oracles on a clean
  branch.

### 2026-07-11 — mainline userspace, storage, and display takeover

Primary helpers: Claude Code through the postmarketOS/M3 and early M4
handoff; Hermes Agent for K060-K067 display dependency, SMMU, clock, regulator,
and framebuffer investigation; Lance for physical device operation.

What changed:

- Mainline reached stable USB userspace and storage milestones; M1-M3 are done.
- K060-K061 completed the module-less display dependency chain and exposed an
  immediate MSM8998 MDSS SID0 translation fault during SMMU handoff.
- K062 added the narrow upstream-shaped `qcom,msm8998-mdss` identity-domain
  policy. The phone then survived, initialized DPU/DSI/DRM, and registered fb0.
- K063 rejected `CLK_OPS_PARENT_ENABLE`; K064 rejected the public no-rate-cache
  fix as the active blocker.
- K065 preserved AngeloGioacchino Del Regno's exact public 10nm-DSI VCO fix and
  verified the factor-of-two correction, but the PLL output divider and MMCC
  RCGs remained stale.
- K066 rejected `clk_ignore_unused` as causal. K067 added the missing real DSI
  VDD rail, removed the dummy-regulator fallback, and proved the active DRM
  framebuffer uses fresh IOVA `0x2000` in active DMA0. The inherited-splash
  SID0 faults are therefore not the leading explanation for post-DRM black
  output.
- K067's physical screen result is unobserved because the clarification prompt
  expired; silence is not recorded as a result. The device was recovered to
  fully booted authorized LineageOS and no partition was flashed.

Local kernel commits at this checkpoint:

- `7ff461605` — MSM8998 MDSS identity domain, K062 RAM-boot verified.
- `5306416d2` — exact public 10nm VCO rate fix, original author preserved.
- `b549c9f5b` — joan DSI VDD supply correction, K067 evidence verified.

All remain local/unpushed. M4 display is still in progress; the earliest
remaining evidenced failure is the DSI PLL output-divider/MMCC RCG programming
or takeover sequence.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11

## K-series ownership summary

This table is intentionally compact. Use `docs/kernel-change-ledger.md` for the
full per-test details, hashes, and logs.

| Range / item | Primary helper(s) | Scope | Current status |
|---|---|---|---|
| K001-K004 | Claude Code, Lance DCO | Initial public-shaped DTS stack and APSS watchdog node | mixed: DTS/memory likely useful; ramoops/watchdog blocked |
| K005-K011 | Hermes Agent plus earlier debug branches | Breadcrumbs, SCM/watchdog, latest-kernel and cmdline discriminators | debug-only / rejected evidence |
| K012-K021 | Hermes Agent | DLOAD, QSEE log buffer, RPM/BOB/regulator/PON/Kryo comparison and oracles | rejected or comparison-only evidence |
| K022-K024 | Claude Code | Null init, minimal/peripheral subtraction, APSS watchdog petting | rejected; narrowed reset away from userspace/USB/UFS/APSS-WDT |
| K025-K027 | Hermes Agent | Secure-interface archaeology, IMEM/restart-reason oracle, NoC clue follow-up | comparison/rejected, but produced important TZ NoC clue |
| K028-K036 | Claude Code | NoC onion-peel, anoc1 SMMU breakthrough, residual MM_NOC narrowing | K030 confirmed debug fix; surrounding tests rejected/narrowing |
| K037-K041 | Claude Code | Community research, watchdog/display/simplefb/edk2 reframing | rejected/observability evidence; edk2 is important reference |
| K042 | Hermes Agent | SMMU cfg-probe S2CR quirk-probe subtraction | superseded: pstore showed earlier TLMM/GPIO abort, not a valid SMMU rejection |
| K043-K050 | Hermes Agent | Raw-pstore observability and TLMM/GPIO reserved-range narrowing | K050 survivor; `<81 4>` has upstream MSM8998 precedent, `<49 4>` is pstore/device-proven and source-review pending |
| K051-K059 | Claude Code | Mainline survival, postmarketOS/storage milestones, initial display and MMSS-SMMU gating | M1-M3 done; K059 established the M4 MMSS-SMMU handoff gate |
| K060-K067 | Hermes Agent | Built-in display dependencies, MDSS identity handoff, DSI clock/VCO/regulator and fb/KMS isolation | DRM reaches fb0; VCO and VDD corrections retained; output-divider/MMCC RCG failure remains |

Known limitation: older ledger entries were not all written with uniform
`Written-by` / `Agent-harness` / `Date` fields inside each K entry. The history is
still reconstructable from git commit trailers, handoffs, and this index. Going
forward, each new K entry should include those fields directly.

## Borrowed / derived material index

The authoritative provenance table is in `docs/public-upstreaming-plan.md`.
Highlights:

| Material | Source basis | Attribution / license handling |
|---|---|---|
| `msm8998-lge-joan.dts` | `msm8998-oneplus-common.dtsi` plus downstream LG/Qualcomm joan DTS data | OnePlus common DTS credits Jami Kettunen and The Linux Foundation/Qualcomm; downstream LG kernel material treated as GPL-2.0-derived unless independently sourced |
| K030 anoc1 skip-reset concept | downstream `msm-arm-smmu-8998.dtsi` `qcom,skip-init` + `qcom,register-save` | concept from Qualcomm/LGE; debug code original; not public-ready |
| IMEM/restart reason constants | downstream `lge_handle_panic.c` / `reboot_reason.h` and public LG/QCOM references | GPL-2.0 evidence/debug only |
| Display quiesce offsets | mainline `dsi.xml` / `dpu_3_0_msm8998.h` | same kernel tree / GPL-2.0 debug only |
| Planned msm8998 interconnect provider | mainline `sdm660.c`, `msm8996.c`, downstream `msm8998-bus.dtsi` | must preserve AngeloGioacchino Del Regno / Yassine Oudjana / Qualcomm-LGE attribution if implemented |
| 10nm DSI VCO formula | public `msm8998-mainline/linux` commit `707f3fc86f6a` | exact patch retained in `5306416d2`; original author AngeloGioacchino Del Regno and author date preserved |
| Joan DSI VDD rail | mainline DSI regulator declaration plus downstream MSM8998 and public OnePlus L1/L2 mappings | one-line board DT correction in `b549c9f5b`; source provenance recorded in dependency tracker/ledger |
| initramfs busybox | Alpine `busybox-static` package | GPL-2.0 test harness only |

Rule: if code is borrowed rather than merely used as evidence, preserve original
SPDX and copyright lines, add a `based on` note naming the source file and author,
and record the source in `docs/public-upstreaming-plan.md`.

## Publication-readiness summary

Public-shaped / potentially useful:

- initial joan DTS, after regulator/board details are cleaned;
- LG firmware-owned memory reservations, after overlaps/future GPU/WLAN placement
  are explained;
- maybe an APSS watchdog representation, but only after behavior and placement are
  settled;
- MSM8998 MDSS identity-domain policy, after broader review of handoff semantics;
- exact public 10nm DSI VCO fix, with original authorship preserved;
- joan DSI VDD supply correction, source-backed and device-verified to remove the
  dummy-regulator fallback.

Blocked / not public-ready as-is:

- the original ramoops layout remains blocked for public value until the raw
  pstore-partition workflow is cleaned up and explained; mounted `/sys/fs/pstore`
  alone is misleading, but raw pstore is now proven useful;
- K030 `debug-skip-reset`, because it is a debug DT property rather than a
  real upstream binding/implementation;
- every timing oracle, raw register poke, direct SCM experiment, IMEM writer,
  display quiesce hook, or SMMU K042-style subtraction patch;
- K050 is promising but not yet public-ready until the reserved GPIO ranges are
  source-reviewed and converted to a clean commit.

Rejected experiments should still be published as evidence only if we publish a
bringup-history/debug repo. They should not be on a clean kernel PR branch.

## Next-history maintenance checklist

For every future material change:

1. Add/update a K entry in `docs/kernel-change-ledger.md` with:
   - handle: commit/patch/log/image path;
   - class and public disposition;
   - touched files and source basis;
   - build/test evidence or reason not tested;
   - `Written-by`, `Agent-harness`, and `Date`.
2. If borrowed/derived material is involved, update
   `docs/public-upstreaming-plan.md`.
3. If the high-level story changes, update this file's timeline/status section.
4. After every device test or meaningful host-only candidate checkpoint, create
   a checkmark closure packet from `docs/templates/candidate-test-closure.md`,
   update `docs/test-results/README.md`, push the checked docs commit, mirror the
   same verdict/decision/no-replay/next-action block to the existing shared
   Nextcloud Deck card, and read both original sources back.
5. If raw/private evidence should be visible to other agents, place it in the
   approved shared private store and link it from Deck. Never publish credentials,
   private firmware, signing material, or owner-private data.
6. Keep rejected debug source reverted from public-shaped kernel branches after
   preserving exact patches and hashes.

## Attribution for this index

Assisted-by: Hermes-Agent:openai-codex/gpt-5.5
Date: 2026-07-08

## 2026-07-11 follow-up — K068 and downstream DSI-divider ordering

K068 repeated K063's parent-enable diagnostic after the VCO and DSI-VDD
corrections. It removed the MMCC RCG update warnings but did not produce visible
output and introduced PLL0 lock/clock-balance failures. The exact patch and all
RAM-boot/ACM evidence are preserved; rejected debug code was reverted and the
clean kernel rebuilt.

The follow-up audit covered all eleven Claude Code handoff documents through the M3/M4
handoff plus this index. The current display investigation now has a concrete
downstream Linux 4.4 sequencing difference: MSM8998's downstream DSI PLL driver
writes the selected PLL output divider before starting/locking the PLL, whereas
the current mainline 10nm VCO prepare path does not. That clue, not another
unrelated flag, gates the next experiment.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11

## 2026-07-11 — K069-K071 divider and initial-VCO interaction experiments

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11

- K069 tested the downstream-inspired pre-lock `/2` override; it did not persist
  into the final clock tree and the panel remained black.
- K070 instrumented save/restore/prepare ordering. It proved bootloader divider
  state was already correct and isolated the early parent-enable lock failure to
  `vco_current_rate=0`.
- Upstream provenance review found commit `8a48e35becb2`, whose initial-rate fix
  interacts with the public-reference VCO formula patch's removed state update.
- K071 restored the recalc state assignment as a one-line source-backed test. It
  was rejected after the live DSI clock tree collapsed to 0 Hz with repeated PLL
  failures and a black display.
- Every test remained RAM-only. Each debug patch was preserved then reverted,
  and the phone was recovered to fully booted LineageOS.

## 2026-07-11 — K072-K077 closes the half-rate clock question

Primary helpers: Claude Code for K072-K075; Hermes Agent /
Hermes Agent for the audit corrections, K076 instrumentation, K077 discriminator,
and final handoff; Lance for physical observation and device authority.

- K072 retained pure recalc behavior and seeded a bounded nonzero initial VCO
  value, allowing the DSI PLL to lock.
- K073's parent-enable combination became unresponsive, but no kernel evidence
  proved the exact mechanism; it remains rejected with mechanism unresolved.
- K074/K075 improved live capture and panel-host instrumentation, but their first
  handoff overclaimed the expected byte rate, SMMU burst size, and meaning of
  write-only `accum_err=0`; the K076/K077 handoff records the corrections.
- K076 traced the second `/4` output-divider request to the half-rate
  `byte_intf_clk` rate operation propagating through the shared mainline
  `byte0_clk_src` parent.
- K077 suppressed only that request. Pixel and byte clocks reached the exact
  requested rates while active 1440x2880@60 DRM state remained intact, but the
  interface clock became incorrectly full-rate and the panel remained physically
  black/off. The skip is rejected as a fix.
- The next source-correct clock candidate is a dedicated MSM8998 byte-interface
  divider matching the hardware topology at MMCC `0x237c`/`0x2380`. After that,
  panel readback/BTA and command-mode TE/kickoff become the leading discriminators.
- All K076/K077 artifacts and hashes are preserved. The experimental kernel diff
  was reverted after byte-matching the saved K077 patch; the kernel tree is clean
  at `b549c9f5b` and the phone is recovered to LineageOS. Nothing was flashed or
  pushed.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11

## 2026-07-21 — K102/K103 touch boot discriminator

Primary helpers: Claude Code for K102 and its corrected
continuity record; Hermes Agent for the read-only continuity
audit, source-reproducible K103 discriminator, single device run, and final
handoff; Lance for physical observation, device authority, and recovery gate.

- K102 added the Joan ST FingerTipS node and produced the observed boot failure.
  Its final corrected account is K102d; the intermediate K102b/K102c
  interpretations remain withdrawn history.
- K103 inherited K102 and deleted exactly one normalized DT property,
  `touch-int-default-state/input-enable`. Clean-control, K102, and K103 DTBs
  were independently reproduced; both Git patch routes and image/header
  provenance gates passed.
- One RAM-only, unwrapped, no-retry K103 boot completed cleanly, reached pmOS
  from `/dev/mmcblk0p2`, and proved the property absent in the live DT. In this
  controlled pair, the deletion was sufficient to eliminate the observed K102
  boot failure; this was not a replicated K102/K103 A/B/A sequence and does not
  establish the low-level mechanism.
- Touch remains nonfunctional. The I2C/OF client was instantiated and
  `stmfts_probe()` ran, but returned `-110`, unwound, and registered no touch
  input device. The exact timeout stage is unproven.
- The next diagnostic is instrumentation-only: capture regulator/reset stages,
  command opcodes and I2C returns, completion waits, IRQ entry, and raw event
  bytes before changing protocol, IRQ configuration, or DT again.
- The phone gracefully returned to authorized LineageOS. Nothing was flashed or
  pushed. K101 remains quarantined.

Successor handoff:
`docs/handoff-2026-07-21-k103-input-enable-discriminator.md`.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Provider/preset: moa/oops-all-chatgpt-all-max
Date: 2026-07-21

## 2026-07-28 — K178 built-in brightness-slider fix

Primary assistance: `Claude-Code:claude-fable-5` for the brightness baseline,
manual-value experiments, and initial serialisation work;
`Hermes-Agent:openai-codex/gpt-5.6-sol` for the regression audit, corrected
DPU/DSI exclusion, packaging correction, K178 build, and evidence capture;
Lance for physical observation and device authority.

- Audit found that K174/K175/K177 omitted the still-required
  `msm.k127_no_suspend=1`, confounding their greetd/phosh startup resets with
  the known a540 GX power-collapse defect.
- K178 restarted from clean `72a8deb11`, retained its 6..251 mapping and
  disabled-encoder guard, excluded `15d1ea453`, serialized DPU frame kickoff
  against DSI DCS transfers, and disabled per-update diagnostic reads.
- Signed source head `88f68643ad397b5c5cae8ce034793bc579ce1420`
  passed strict checkpatch and full build verification. The RAM image inherited
  the stable K172 ramdisk/cmdline with K127.
- One authorized RAM boot reached pmOS and stayed healthy beyond 1,839 s.
  Lance slowly and rapidly moved the built-in phosh slider while animation was
  active: UI responsive, brightness tracked mostly in line, no garbage frames,
  blackouts, freezes, or reboot.
- All 180 rapid-monitor samples stayed in pmOS; sampled brightness spanned
  9..251 with matching requested/actual values. No DSI-link or DPU-kickoff
  timeout appeared.
- This passes the aggregate K178 GUI-slider acceptance criterion. The separate
  a540 power-collapse defect remains hidden by K127, and normal reboot recovery
  is still pending. Nothing was flashed.

Primary result:
`out/boot-joan-k178-slider-gate-k127.test-result.txt`.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-28
Update-scope: K178 brightness-slider result classification.

## 2026-08-02 — brightness and GPU optimization audit

Primary assistance: `Hermes-Agent:openai-codex/gpt-5.6-sol` for the
source/upstream/config/package audit, binding fixes, builds, and continuity;
`Claude-Code:claude-fable-5` for the K123-K178 hardware isolation and test
evidence; Lance for device authority and the original K178 physical acceptance
test.

- Consolidated the proven display/backlight/GPU mechanisms onto clean local
  branch `joan/clean-gpu-brightness-v1` and audited each independently.
- Kept the K178 brightness hot path unchanged: it is already one LP-mode DCS
  byte per update with frame/DCS exclusion and passed the 180-sample hardware
  stress test.
- Confirmed that FD540/freedreno rendering is genuine, while documenting the
  remaining 257 MHz and runtime-PM-hold limitations instead of overclaiming
  full DVFS/power optimization.
- Added two signed DT-binding commits for A540's seventh `mem_src` clock and
  MSM GPU supplies. Exact host-qualified kernel HEAD:
  `3886e860d607bc1c670601a40b25341c2e67f727`.
- Full cross-build, focused `W=1`, binding/example, compiled joan-DTB,
  config-normalization, and firmware-image tests passed. No phone action or
  remote push occurred.
- Prepared, but did not commit, an isolated pmaports integration diff because
  the public source pin predates the candidate and must be updated atomically
  with its archive checksum. The keyless Alpine abuild `prepare/build` phase
  passed on an exact staged source copy (1,612 modules, zero warning/error
  matches), while full APK emission remains blocked by a missing migrated local
  private signing key; no credential was replaced.

Sanitized successor continuity:
`docs/test-results/README.md` and its per-candidate packets.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-02

## 2026-08-02 — A181/A182 runtime qualification and A183 touch correction

Primary assistance: `Hermes-Agent:openai-codex/gpt-5.6-sol` for exact-candidate
construction, one-shot harness qualification, runtime evidence, root-cause
comparison, A183 host correction, and continuity;
`Claude-Code:claude-fable-5` for the preserved pmOS transport/reboot and K178
touch/display baseline; Lance for device authority and direct touch observation.

- A181 consumed one authorized RAM-only boot. Transport reached pmOS, but display
  activation failed because MSM8998 MMCC was modular without a matching module
  tree. The pmOS-side reboot documented with assistance from
  `Claude-Code:claude-fable-5` then returned cleanly to fully booted
  persistent LineageOS; manual/fastboot recovery was not required.
- A182 changed only MMCC `m -> y` and consumed a separate authorized RAM-only
  boot. It initialized MSM DRM, 1440x2880 SW43402 DSI, backlight, A530/A540
  firmware, and hardware Mesa rendering. A direct query proved
  `freedreno` / `FD540`; precise pre/post logs showed no graphics/GPU faults.
- Lance reported that touch was broken. Runtime input enumeration confirmed no
  touchscreen, and A182 had accidentally disabled `CONFIG_TOUCHSCREEN_STMFTS`.
  This was recorded as an acceptance failure rather than being hidden behind the
  successful display/render path.
- A183 restores exactly STMFTS `n -> y` on unchanged source and MMCC correction.
  Its STMFTS source, binding, and complete Joan touch DTS region match K178. Full
  build, module inventory, symbol, image, 337-entry ramdisk, command-line, and
  firmware qualification passed.
- A183 image SHA-256 is
  `44e5f22fed866348d7dc28ac21a9cc2feddede43566795b0cd74deecfa555716`.
  At this checkpoint it was local-only, unstaged, unbooted, and
  approval-gated; the later A183 runtime section supersedes that host-only state.
- The GPU remains capped at 257 MHz and held runtime-active; brightness/panel
  owner gates, safe GX power collapse, suspend/resume, and bounded performance
  remain open. Communications work remains blocked.

Successor evidence and handoff:
`out/evidence/a182-mmcc-builtin/A182-RESULT.md` and
`docs/test-results/README.md`.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-02

## 2026-08-03 — A183 runtime closure, A184 host correction, and cross-agent packets

Primary assistance: `Hermes-Agent:openai-codex/gpt-5.6-sol` for artifact-first
reconciliation, runtime classification, A184 host correction, and closure
workflow; `Claude-Code:claude-fable-5` for the preserved K-series mechanisms
and shared project lineage; Lance for exact device authority, physical
interaction, and the continuity requirement.

- A183 consumed one exact RAM-only authorization. It proved STMFTS/FTS3670
  probe, input registration, bounded multitouch coordinates, owner-visible touch,
  1440x2880 display/DRM, and direct `freedreno`/`FD540` rendering.
- Artifact readback corrected a compacted-summary error: the optional event
  capture is not a one-line failure. Its outer SSH wrapper ended 255, but the raw
  4,178-line stream contains 26 contact starts/releases, 978 synchronized
  reports, two slots, bounded X/Y motion, pressure, and final release evidence.
- Lance reported that the slider worked without crashing, but A183 exposed
  `max_brightness=251`; the established owner-visible contract is 6..255, with
  DBV 3 reserved for internal off. The functional-slider pass and ABI-contract
  failure are recorded separately.
- A183 directly proved FD540/freedreno and no immediate post-EGL fault, while
  retaining explicit open gates: dummy `vddcx`, devfreq transition-accounting
  warning, zero runtime suspended time, no sustained-load closure, and no
  suspend/resume. Communications remain blocked.
- A184 local signed commit `739bc79d39e8` changes only the bounded SW43402
  maximum/comment to 255 and passes focused source/style/mapping/object checks.
  Signed comment-only follow-up `fa041e291644` corrects the Joan DTS firmware
  wording without changing any property or runtime behavior. A184 has no complete
  image, runtime test, or device authority.
- Reconciled the firmware distribution boundary: the physical GPU is A540 but
  upstream A540 deliberately reuses packaged `a530_pm4.fw` and `a530_pfp.fw`;
  owner-extracted `a540_gpmu.fw2` and signed LG `a540_zap.*` remain separate,
  ignored local inputs. The current docs/tooling tip removes every firmware byte
  from tracking and keeps fail-closed construction. Historical public Git objects
  remain unchanged because no history rewrite was authorized.
- Introduced project-local immutable checkmark packets, a mandatory read-first
  index, explicit no-replay/authorization fields, and a GitHub+Deck readback rule
  so assisted changes do not require diagnostic replay. The template is designed for
  reuse by future hardware projects.

Current index:
`docs/test-results/README.md`.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-03
Update-scope: A183 runtime closure, A184 host checkpoint, and reusable closure workflow.

## 2026-08-11 — source-correct four-lane clock audit and GPU IREF candidate

Primary helper: Hermes Agent (`Hermes-Agent:moa/deep-flash`).

Main artifacts:

- `docs/clock-ownership-audit-2026-08-11.md`;
- `docs/test-results/GPU-IREF-HOST-2026-08-11.md`;
- kernel branch `joan/clock-ownership-v1`, commits `0ab3de5ac`, `1ae761e14`,
  `5eded6318`, and `35750026c`;
- local sealed image/manifest under `out/audit-20260811/`.

What happened:

- Reconciled SDCC2, UFS controller/PHY, GPU, and USB-C/PHY clock ownership
  against current bindings, consumer code, and exact LG/Qualcomm downstream
  sources rather than copying legacy clock lists.
- Confirmed SDCC2 and UFS already have complete modern clock ownership.
- Confirmed the V30 hardware supports USB 3.1 Gen 1; current mainline Joan is
  intentionally USB2-only for bring-up. Proper SuperSpeed enablement depends on
  PMI8998 Type-C role/orientation support, not additional clock phandles.
- Ported the directly proven MSM8998 GPU IREF gate as a four-piece,
  upstream-shaped series. Full post-commit build and host qualification passed.
- Mapped but deferred A540 `isense`: downstream uses 200 MHz for its two fastest
  levels and 19.2 MHz below them, while mainline still disables A540 GPMU limits
  management and lacks the matching live DVFS policy.
- Caught and rejected a byte-correct but provenance-wrong image whose release
  string named the pre-series base plus `-dirty`; rebuilt after commit splitting
  and sealed an exact-source replacement.

Publication relevance:

- The IREF series is local/unpushed and host-qualified, not device-verified.
- No phone action occurred. Publication, Deck synchronization, staging, and any
  RAM-only boot remain pending owner direction/approval.

Assisted-by: Hermes-Agent:moa/deep-flash
Date: 2026-08-11
Update-scope: Clock ownership, USB3 capability, GPU IREF, and exact-source seal.

## 2026-08-13 — Card 94 clean reconstruction and exact-source characterization

Primary helper: Hermes Agent
(`Hermes-Agent:openai-codex/gpt-5.6-sol`), continuing Ember's Card 94
mechanism/root-cause work (`Claude-Code:claude-opus-5`) with Lance as
owner/operator and device authority.

Main artifacts:

- kernel branch `joan/a540-cx-gx-final-v4`, commit `76d180923dc2`;
- exact-source build `/data/buildcache/kbuild/build-a540-cxgx-final-v4-76d180923`;
- marker-free image and raw evidence under ignored
  `out/audit-20260813/card94-cxgx-v4-76d180923/`;
- `docs/test-results/CARD94-CXGX-V4-2026-08-13.md`.

What happened:

- Reconstructed Ember's CX/GX, VDD_GFX, and SMMU-retention work from a clean
  deterministic base, removed debug-gate ancestry, added the missing binding
  coverage, preserved original assistance provenance, and qualified all eight
  signed commits plus an exact full build.
- Caught and quarantined an initially packaged image whose source was clean but
  whose reused cmdline still contained `joan_gpu_gate=0`; repackaged from a
  clean transport baseline and independently verified the replacement.
- Executed exactly one hash-bound RAM-only boot. The clean series reached
  graphical pmOS and did not reproduce Card 94's SMMU/secure-world reset,
  context fault, GPU fault, or internal error.
- The first idle GPU suspend nevertheless aborted because SP/TP and RBCCU
  remained on. Runtime PM entered `error`, PM8005 S1 remained 3/3, and the
  workload gate correctly stopped before rendering. Evidence was banked and
  the phone recovered to installed LineageOS without flashing.
- Corrected an early post-run source hypothesis: mainline already carries the
  same four GPMU inter-frame collapse-register writes as downstream. The next
  safe experiment is readback-only instrumentation around GPMU init and the
  first suspend boundary, not duplicate programming.

Publication relevance:

- The kernel series and this documentation remain local/unpushed.
- The SMMU retention mechanism has scoped positive device evidence, but the
  complete series is not yet power-cycle-qualified or ready to claim final
  runtime-PM closure.
- Public push and shared Deck synchronization remain owner-approval gates.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-13
Update-scope: Card 94 clean reconstruction, exact-source device test, mixed
power result, recovery, and corrected next diagnostic boundary.

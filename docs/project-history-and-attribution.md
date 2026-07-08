# LG V30 project history and attribution index

Purpose: one-glance history of who worked on what, when, and where the durable
evidence lives for the LG V30 (`joan`, US998) mainline Linux bringup.

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

For docs and shared artifacts, preserve greppable attribution blocks:

```text
Written-by: <agent/persona> (<agent id>)
Agent-harness: <harness>:<model>
Date: <date>
```

Never erase a prior agent's attribution. Append corrections or follow-ups with a
new attribution block.

## People / agents / roles

| Actor | Role in this project | Attribution used |
|---|---|---|
| Lance | Device owner/operator, physical fastboot/phone approval, human DCO signer, final publication authority | `Signed-off-by: Lance <Gero3977@gmail.com>` |
| Ember Nymbrand | Claude-Code agent that performed initial recon, early DTS/test harness work, the major 2026-07-06/07 onion-peel reset hunt, K022-K041 era handoffs, and many rejected-oracle docs | `Written-by: Ember Nymbrand (agent-ember)` / `Assisted-by: Claude-Code:claude-fable-5` where applicable |
| Aurel Nymvale | Hermes agent that performed SCM/RPM/secure-world archaeology, K025-K027 follow-up work, K039-K040/K042 passes, documentation/provenance audits, WebDAV/Deck sync, and this index | `Written-by: Aurel Nymvale (agent-aurel)` / `Assisted-by: Hermes:gpt-5.5` |
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

Primary helper: Ember / Claude-Code.

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

Primary helper: Ember / Claude-Code.

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

Primary helpers: Ember / Claude-Code, then Aurel / Hermes follow-ups.

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
- `docs/ember-handoff-2026-07-06.md`
- `docs/bringup-debug-state-2026-07-06.md`

What happened:

- The work shifted from "can we boot?" to "what resets the SoC before mainline
  debug appears?".
- Early hypotheses focused on secure watchdog, APSS watchdog, panic timing, SCM
  calls, RPM/GLINK reachability, regulator defaults, PMIC/PON setup, DLOAD mode,
  and IMEM/restart cookies.
- Aurel added/recorded several secure-world and RPM liveness/state-change
  oracles. They were useful negative evidence but did not solve the reset.
- The ledger and public upstreaming plan became the durable evidence structure.

Publication relevance:

- This day created the distinction between public-shaped kernel commits and
  rejected/debug-only oracle patches.
- Many artifacts under `out/` are valuable evidence but are not for upstream.

### 2026-07-06 session 2 — userspace/peripheral subtraction

Primary helper: Ember / Claude-Code.

Main artifacts:

- `docs/ember-handoff-2026-07-06-session2.md`
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

Primary helper: Aurel / Hermes for several secure/SCM follow-ups, then Ember /
Claude-Code for the onion-peel continuation.

Main artifacts:

- `docs/ember-handoff-2026-07-07-k027-complete.md`
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

Primary helper: Ember / Claude-Code, with Lance physically present for device
work.

Main artifacts:

- `docs/ember-handoff-2026-07-07-k029-onion-peel.md`
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
  `ember,debug-skip-reset` property. It needs a proper upstreamable Qualcomm
  SMMU representation if it becomes part of a real fix.

### 2026-07-08 — observability breakthrough and TLMM/GPIO reserved-ranges lead

Primary helpers: Ember / Claude-Code through the consolidated handoff and K041;
Aurel / Hermes for the provenance audit and K042 source-first/device test.

Main artifacts:

- `scripts/tethered-test.sh`
- `docs/ember-handoff-2026-07-08-mm-noc-current.md`
- `docs/ember-handoff-paste-2026-07-08.md`
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
- Ember explicitly asked for borrowed-code/provenance cleanup. Aurel applied that
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

## K-series ownership summary

This table is intentionally compact. Use `docs/kernel-change-ledger.md` for the
full per-test details, hashes, and logs.

| Range / item | Primary helper(s) | Scope | Current status |
|---|---|---|---|
| K001-K004 | Ember / Claude-Code, Lance DCO | Initial public-shaped DTS stack and APSS watchdog node | mixed: DTS/memory likely useful; ramoops/watchdog blocked |
| K005-K011 | Aurel / Hermes plus earlier debug branches | Breadcrumbs, SCM/watchdog, latest-kernel and cmdline discriminators | debug-only / rejected evidence |
| K012-K021 | Aurel / Hermes | DLOAD, QSEE log buffer, RPM/BOB/regulator/PON/Kryo comparison and oracles | rejected or comparison-only evidence |
| K022-K024 | Ember / Claude-Code | Null init, minimal/peripheral subtraction, APSS watchdog petting | rejected; narrowed reset away from userspace/USB/UFS/APSS-WDT |
| K025-K027 | Aurel / Hermes | Secure-interface archaeology, IMEM/restart-reason oracle, NoC clue follow-up | comparison/rejected, but produced important TZ NoC clue |
| K028-K036 | Ember / Claude-Code | NoC onion-peel, anoc1 SMMU breakthrough, residual MM_NOC narrowing | K030 confirmed debug fix; surrounding tests rejected/narrowing |
| K037-K041 | Ember / Claude-Code | Community research, watchdog/display/simplefb/edk2 reframing | rejected/observability evidence; edk2 is important reference |
| K042 | Aurel / Hermes | SMMU cfg-probe S2CR quirk-probe subtraction | superseded: pstore showed earlier TLMM/GPIO abort, not a valid SMMU rejection |
| K043-K050 | Aurel / Hermes | Raw-pstore observability and TLMM/GPIO reserved-range narrowing | K050 survivor; `<81 4>` has upstream MSM8998 precedent, `<49 4>` is pstore/device-proven and source-review pending |

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
  settled.

Blocked / not public-ready as-is:

- the original ramoops layout remains blocked for public value until the raw
  pstore-partition workflow is cleaned up and explained; mounted `/sys/fs/pstore`
  alone is misleading, but raw pstore is now proven useful;
- K030 `ember,debug-skip-reset`, because it is a debug DT property rather than a
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
4. If an artifact should be visible to other agents, upload it to
   `Talk/Shared_AI_agents_files/` and comment on Deck card #43.
5. Keep rejected debug source reverted from public-shaped kernel branches after
   preserving exact patches and hashes.

## Attribution for this index

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-08

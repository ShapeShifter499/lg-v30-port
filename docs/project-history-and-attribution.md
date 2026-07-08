# LG V30 mainline project history and attribution

Purpose: give future humans/agents a one-glance timeline of who worked on what,
when, and where the evidence lives. This is an index, not a replacement for the
full evidence files.

If you continue this work, update this file before handoff whenever you add a
new K-series result, public-candidate commit, borrowed-code source, or major
handoff.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-08

## Source-of-truth map

| Need | Source |
|---|---|
| Current short state and safety conventions | `README.md` |
| Every kernel-impacting change / experiment | `docs/kernel-change-ledger.md` |
| Public readiness, borrowed-code provenance, and license notes | `docs/public-upstreaming-plan.md` |
| Current Ember handoff before K042 | `docs/ember-handoff-2026-07-08-mm-noc-current.md` |
| Current Aurel update after K042 | this file + `README.md` + `docs/kernel-change-ledger.md` |
| Shared cross-agent state | Deck board 4, card #43; WebDAV `Talk/Shared_AI_agents_files/{handoffs,patches,status}/` |
| Clean kernel worktree | `~/vibe-coding-projects/coding/linux-mainline-v30`, branch `joan/latest-clean-test` |
| Harness/evidence repo | `~/vibe-coding-projects/coding/lg-v30-port` |

## Maintenance rule for Ember / future agents

When you continue this project:

1. Add a new row under **Chronological work log** for any meaningful session.
2. Add or update rows under **K-series summary** for any new K-test / oracle / no-code finding.
3. If you borrow or derive from another source file, update
   `docs/public-upstreaming-plan.md`'s provenance table too.
4. Preserve existing attributions. Append corrections; do not rewrite another
   agent's conclusion as if it were yours.
5. Use these fields in new sections or appended notes:

```text
Written-by: <agent/person>
Agent-harness: <harness>:<model>
Date: YYYY-MM-DD
Evidence: <commit/log/patch/WebDAV/Deck pointer>
```

Kernel-style commits continue to use Lance as DCO signer plus an AI-assistance
trailer:

```text
Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: <agent-harness>:<model>
```

Never use `Co-Authored-By` for AI assistance in this workflow.

## People / agent identities

| Identity | Role in this project | Attribution form |
|---|---|---|
| Lance | Device owner/operator; approves physical phone work; DCO signer for commits; provides photos/observations and project direction. | `Signed-off-by: Lance <Gero3977@gmail.com>` |
| Aurel Nymvale | Hermes/Aurel agent; SCM/RPM/PON/source archaeology, mainline clean-branch shaping, K025-K027/K040/K042-style source-first experiments, documentation/provenance/WebDAV/Deck sync. | `Written-by: Aurel Nymvale (agent-aurel)` / `Assisted-by: Hermes:gpt-5.5` |
| Ember Nymbrand | Ember/Claude-Code agent; early recon/handoffs, null-init and onion-peel classifier work, K022-K041-heavy investigation, edk2 UEFI insight, provenance-table prompt. | `Written-by: Ember Nymbrand (agent-ember)` / `Assisted-by: Claude-Code:claude-fable-5` where known |
| Upstream/downstream projects | Source material only; not project agents. Includes Linux, Qualcomm/LGE downstream kernel, OnePlus msm8998 DTS work, edk2-msm8998/Renegade Project, AOSP bullhead references, BusyBox/Alpine initramfs package. | Track in `docs/public-upstreaming-plan.md` provenance table. |

## Current state summary as of 2026-07-08

- Mainline still does **not** boot far enough to expose a mainline debug channel
  or userspace on LG V30 `joan`.
- The named TrustZone Config/MM-NoC crash family was narrowed substantially.
- K030 is the strongest confirmed finding: skipping global reset only for
  `anoc1_smmu` removes the named Config/MM-NoC fault signature.
- Residual MM_NOC still persists after K030. It usually appears to the host as an
  early LineageOS return with bootreasoncode `0x20`, but K035's device photo
  confirmed the firmware-level residual reason is still `0x6D630306` MM_NOC.
- K042 was tested after Ember's handoff and rejected: skipping mainline's
  MSM8998 Qualcomm SMMU cfg-probe S2CR bypass quirk-probe on top of K030 still
  returned early 48s after handoff.
- No ready-to-test next phone hypothesis exists at this writing. The best next
  direction is source-first TrustZone/SCM/firmware archaeology or a new
  observability path, not another blind phone boot.

## Chronological work log

| Date | Who | What changed / what was learned | Evidence |
|---|---|---|---|
| 2026-07-04 | Ember + Lance | Initial LG V30 `joan` recon; project goal and hardware/software context established. | `docs/recon-2026-07-04.md` |
| 2026-07-04 to 2026-07-06 | Aurel + Lance | Initial public-shaped kernel DTS commits created: board DTS, ramoops layout, reserved memory, APSS watchdog node. | Kernel branch `joan/latest-clean-test`; commits `25a391c94`, `a19ca9204`, `7c906e841`, `0d7df4134`; ledger K001-K004 |
| 2026-07-06 | Aurel | Latest upstream / latest clean branch work; CPU, idle, high-memory, SCM, RPM, PON, regulator and watchdog discriminators tested or compared. Most were rejected as sufficient fixes. | `docs/bringup-debug-state-2026-07-06.md`; ledger K006-K021; Aurel handoff `docs/ember-handoff-2026-07-06.md` |
| 2026-07-06 | Ember + Lance | Null-init / minimal-DTB / full-DTB-minus-subsystems classifier work. USB, UFS, RPM, and removable board peripherals were eliminated; reset moved toward SoC core/firmware. | `docs/bringup-debug-state-2026-07-06.md`; ledger K022-K024; `docs/nullinit-discriminator-run.md` |
| 2026-07-06 | Aurel + Ember | Secure-interface archaeology and IMEM oracle path. Aurel repackaged/tested the IMEM oracle as K026; returned TZ-class `0x6D630309` Config NoC. | Ledger K025-K026; `docs/ember-handoff-2026-07-06-session2.md` |
| 2026-07-07 | Aurel | K027/K028/K029 chain decoded: Config NoC / MM NoC layering, RPM-disabled regression, and `anoc1_smmu` disable regression. | `docs/ember-handoff-2026-07-07-k027-complete.md`; ledger K027-K029 |
| 2026-07-07 | Ember + Lance | K030 breakthrough: debug skip of global reset for `anoc1_smmu` removes the named TZ NoC-fault signature. K031 showed all-five-SMMU skip has no extra value; anoc1 alone is sufficient. K032 showed `clk_ignore_unused` / `pd_ignore_unused` was not load-bearing. | `docs/ember-handoff-2026-07-07-k029-onion-peel.md`; ledger K030-K032 |
| 2026-07-07 to 2026-07-08 | Ember + Lance | K033/K035 series showed residual failure is still MM_NOC/core-firmware class, not board peripherals. K035 photo exposed firmware-level `0x6D630306` MM_NOC and a separate IMEM-write side-effect risk. | Ledger K033/K035; `docs/ember-handoff-2026-07-07-k029-onion-peel.md`; WebDAV K035 photos referenced in handoff |
| 2026-07-08 | Ember | K036 rejected sibling MMSS-NoC critical clocks and effectively ruled out the late unused-clock sweep class. K037 cleared non-secure watchdog timeout as the tunable cause. K038 display-quiesce cleared bootloader-left display as the trigger. K039 MMCC=y did not change the fault. | Ledger K036-K039; `docs/ember-handoff-2026-07-08-mm-noc-current.md` |
| 2026-07-08 | Ember + Lance | edk2-msm8998/Renegade Project source and Windows-on-ARM angle identified a passive UEFI reference that survives far past Linux's reset window. Late Linux simplefb/fbcon was then tested as K041 and rejected on joan's command-mode panel. | Ledger K041; `docs/ember-handoff-2026-07-08-mm-noc-current.md` |
| 2026-07-08 | Aurel | Applied Ember's provenance directive: filled OnePlus common DTS author gap, generalized AI-assistance trailer wording, and recorded K042 provenance. | Commits `2f7d37c`, `e845140`; `docs/public-upstreaming-plan.md` |
| 2026-07-08 | Aurel + Lance | K042 built and tested: MSM8998 Qualcomm SMMU cfg-probe S2CR bypass quirk-probe subtraction on top of K030. Fastboot boot OKAY, but LineageOS returned 48s after handoff; rejected. Debug patch preserved and reverted from kernel worktree. | Commit `2519246`; ledger K042; `out/tethered-test-2026-07-08T173429Z.log`; Deck #43 comment `14909` |
| 2026-07-08 | Aurel | Created this project history/attribution index so future agents can maintain a compact who/what/when trail instead of forcing readers to reconstruct from the full ledger. | This file |

## K-series summary

This is intentionally compact. The detailed evidence, hashes, and file paths are
in `docs/kernel-change-ledger.md`.

| K range / item | Lead | Date | Short result | Status |
|---|---|---|---|---|
| K001-K004 | Aurel/Lance | 2026-07-04 to 2026-07-06 | Initial public-shaped DTS, ramoops, reserved memory, APSS watchdog node. | candidate / blocked per ledger |
| K005 | Aurel | 2026-07-06 | Ramoops breadcrumb instrumentation did not produce useful persisted evidence. | rejected / debug-only |
| K006-K008 | Aurel | 2026-07-06 | SEC_WDOG, panic/APSS-WDT, and downstream-style APSS WDT takeover paths did not fix reset. | rejected |
| K009-K011 | Aurel | 2026-07-06 | Latest upstream/clean branch, maxcpus/cpuidle/high-memory discriminators did not expose diagnostics or fix reset. | rejected evidence / branch-shaping |
| K012-K021 | Aurel | 2026-07-06 | DLOAD arg shape, QSEE log buffer, RPM reachability/BOB, regulator overlays, PON/TCSR, Kryo SCM comparisons all failed or were rejected before device test. | rejected / comparison-only |
| K022-K024 | Ember | 2026-07-06 | Null-init/min-DTB/peripheral subtraction showed reset persists without userspace and is not USB/UFS/RPM/removable board peripheral. | rejected triggers / useful narrowing |
| K025-K026 | Aurel + Ember | 2026-07-06 | Secure-interface archaeology; IMEM oracle showed TZ-class Config NoC path but not a fix. | useful evidence, debug-only |
| K027-K029 | Aurel / Ember follow-up | 2026-07-07 | NoC reason decoded; RPM disable and anoc1 disable regress to Config NoC. | useful mechanism evidence |
| K030 | Ember | 2026-07-07 | `anoc1_smmu` skip-reset removes named Config/MM-NoC signature. | confirmed debug finding, not upstream-ready as written |
| K031-K032 | Ember | 2026-07-07 | All-five-SMMU skip adds no benefit; clk/pd retention not load-bearing. | rejected broader fixes |
| K033-K035 | Ember + Lance | 2026-07-07/08 | Residual fault still core/firmware/MM_NOC; K035 photo confirms `0x6D630306`, IMEM write likely caused separate firmware bug. | useful evidence; avoid raw IMEM write |
| K036-K039 | Ember | 2026-07-08 | Sibling MMSS-NoC clocks, non-secure watchdog timeout, display leftover, MMCC=y all rejected. | rejected candidate classes |
| K040 | Aurel/Ember handoff context | 2026-07-08 | `scm_restore_sec_cfg` positive secure-call candidate tested negative/blunted by no observability. | rejected as tested |
| K041 | Ember | 2026-07-08 | Late simplefb/fbcon on-screen console path failed; command-mode panel freezes on LG logo. | rejected observability path |
| K042 | Aurel | 2026-07-08 | MSM8998 SMMU cfg-probe S2CR quirk-probe subtraction still reset at 48s after handoff. | rejected |

## Public/publishable status

| Area | Current status |
|---|---|
| Initial joan DTS | Public-candidate shape exists but needs review/cleanup before upstreaming. |
| Reserved memory | Likely public-candidate, but final explanations and overlaps need review. |
| Ramoops | Blocked unless a useful persistence story is proven. |
| APSS watchdog node | Blocked/unknown; not proven to solve current reset. |
| K030 anoc1 skip-reset | Important debug finding; not public-ready as an `ember,debug-skip-reset` property. Needs real Qualcomm SMMU representation if it becomes part of a fix. |
| K042 SMMU cfg-probe skip | Rejected debug evidence only; do not publish. |
| All raw oracles/timing probes | Preserve as evidence; keep out of clean public branches. |

## Borrowed / derived source tracking

The compact provenance table lives in `docs/public-upstreaming-plan.md`. As of
this index, it tracks at least:

- `msm8998-lge-joan.dts` basis from `msm8998-oneplus-common.dtsi` plus downstream
  LG/Qualcomm DTS material;
- K030 concept from downstream `qcom,skip-init` / `qcom,register-save` SMMU
  policy;
- IMEM/reboot reason constants from downstream LGE files and public AOSP bullhead
  references;
- display-quiesce debug offsets from mainline MSM display XML/header files;
- K042 concept from comparing upstream `qcom_smmu_cfg_probe()` with downstream
  MSM8998 SMMU policy;
- planned interconnect provider sources (`sdm660.c`, `msm8996.c`, downstream
  `msm8998-bus.dtsi`) and their required authorship preservation.

Future agents: if you copy code, not just an idea, preserve the original SPDX and
copyright lines in the new file and call that out here and in
`docs/public-upstreaming-plan.md`.

## Current no-repeat list

Do not retry these without a materially different baseline or new evidence:

- `SEC_WDOG_DIS` / secure watchdog SCM shapes already tried in K006/K025-era work.
- APSS watchdog pet/takeover and non-secure watchdog timeout paths.
- `panic=` timing, `maxcpus=1`, `cpuidle.off=1`, high-memory reservation.
- DLOAD arg-shape, QSEE log-buffer registration, RPM reachability-only and BOB
  one-off default votes.
- PM8998 L19, L18/L19/BOB regulator-overlay minimal votes.
- TCSR DLOAD phandle and PM8998 PON S3 / reset-sequence oracles.
- Null-init, min-DTB naive interpretation, USB/UFS/RPM/peripheral subtraction.
- Broad all-five-SMMU skip-reset (K031) as a better fix than anoc1-only.
- `clk_ignore_unused` / `pd_ignore_unused` or sibling MMSS-NoC critical clocks as
  the remaining root cause.
- Raw unverified IMEM writes near the restart-reason offset used in K035.
- Late Linux `simple-framebuffer` / fbcon as a joan command-mode panel console.
- K042 MSM8998 Qualcomm SMMU cfg-probe S2CR quirk-probe subtraction.

## Suggested next documentation work

Before a public push or external collaboration request:

1. Normalize older K001-K021 ledger entries to include explicit `Written-by`,
   `Agent-harness`, and `Date` fields where reconstructable.
2. Add a small checker script that flags K entries missing attribution/status,
   commits missing `Signed-off-by` / `Assisted-by`, and `TBD` provenance rows.
3. Prepare a public branch map that names which kernel commits are candidates and
   which evidence-only artifacts should stay in `lg-v30-port`.

## Suggested next technical work

No phone test should run just because there is an idea. Continue source-first:

1. Re-read the TrustZone/SCM and boot-firmware paths against downstream and
   edk2-msm8998, looking for a concrete state transition Linux performs that UEFI
   avoids or downstream performs differently.
2. Prefer observability improvements that do not perturb firmware state. K035
   showed the device screen can reveal firmware-level reasons, but the raw IMEM
   write likely introduced a separate firmware crash.
3. Only build a new oracle after a specific source-backed candidate exists, and
   test it once with `scripts/tethered-test.sh` while Lance is physically present.

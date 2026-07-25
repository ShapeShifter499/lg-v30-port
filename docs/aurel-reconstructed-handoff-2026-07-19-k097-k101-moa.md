# Aurel reconstructed handoff — M4 complete; GPU K098-K101 paused; K092 provenance resolved

Written-by: Aurel Nymvale (agent-aurel)
Reconstructed-by: Aurel Nymvale (agent-aurel)
Original-work-under-review: Ember/Claude Code and Lance, as attributed in the source records
Agent-harness: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-19T23:38:08-07:00
Last-cleanup-update: 2026-07-20T02:02:38-07:00
For: Lance and the next MOA/model working on the LG V30 (`joan`)
Status: `WAITING` — pre-MOA cleanup/build complete; no new device experiment started

> **Reconstruction notice:** This is not an Ember-authored final handoff. Aurel
> reconstructed it after Ember stopped at the usage limit. Unless explicitly
> quoted or attributed to a source, the correlation, classifications, caveats,
> and corrections in this document are Aurel's evidence-backed synthesis.

## Why this handoff exists

Ember's last formal handoff ends at K095:

- `docs/ember-handoff-2026-07-19-night2-dsi-ctrl-session1.md`

Ember then continued through K096-K101, updated the kernel ledger, and hit the
Claude usage limit immediately after Lance asked Ember to ask Aurel about an
apparently mysterious uncommitted `cfg_pending` / `clk_rcg2_replay_enable`
change. This file reconstructs that missing final handoff from the authoritative
ledger, live git state, saved patches, Claude Code session/job logs, build logs,
and device-test outputs.

### Why a later Ember continuation did not recognize Ember's own K092 code

This was not simply one continuous Ember session forgetting an edit. The logs
show a split-brain continuation after Lance's interruption/restart:

- foreground/main session:
  `dd25a715-5ab4-4e40-a2dc-6aece214c77e`
- background daemon continuation:
  `173bc577-5e6c-4c7a-af86-57697a1bd109`
- the daemon state explicitly records `template: bg`, `backend: daemon`, and
  `bgIsolation: none`, so both continuations mutated the same kernel worktree
- both independently named a different experiment **K092**

The decisive race, in UTC:

1. At `22:15:26`, background Ember reset `dsi_host.c` to the git version.
2. At `22:15:48`, foreground Ember's K092 script tried to replace text inside
   the now-removed DSI-host re-latch block. Python `str.replace()` silently did
   nothing, and the script did not verify a replacement count; it then added
   MMCC NOCACHE flags and started a build.
3. At `22:16:01`, background Ember independently wrote `cfg_pending`,
   `clk_rcg2_replay_enable()`, and the byte/pixel `.enable` hooks, then started
   its own K092 build.
4. At `22:22:53`, foreground Ember staged `dsi_host.c` and MMCC for
   `6fa34eb57`; `dsi_host.c` was unchanged, so only MMCC entered the commit
   despite its post-enable-re-latch message.

The foreground transcript contains neither background session ID `173bc577`
nor the background statement “K092 is the cleanest design yet.” It first sees
`cfg_pending` at the final dirty-diff inspection around `06:07Z`, so that
continuation genuinely experienced the code as foreign. The later usage-limit
stop prevented reconciliation, but the original cause was concurrent,
unisolated session state—not an ordinary memory lapse.

Detailed reconstruction:

- `out/reconstructed-20260720-ember-k092-k101/ember-k092-split-session-causality-20260720.txt`

The kernel ledger remains the canonical detailed history. This file is the
one-file entry point for the next model.

## Executive state

1. **M4 display is complete.** K097 (`3395103aa`) wires `MDSS_BCR` to the
   board's MDSS node. A cold gadget boot showed penguins/fbcon without a kick,
   and a cold postmarketOS boot showed the complete boot sequence through the
   login prompt and blinking cursor with `display-kick` disabled.
2. **GPU bring-up is paused at a hard SoC wedge.** K099, K100, and K101 all
   reach the first GPU register access and then lose both USB networking and
   serial. Physical Power+VolDown recovery is required.
3. **The exact “mystery” clock implementation is resolved. It is Ember's K092
   experiment, not Aurel's and not a verbatim upstream import.** Related
   upstream RCG enable-time configuration patterns do exist, but no upstream
   tree or public-code result checked contains K092's `cfg_pending` field,
   `clk_rcg2_replay_enable()` function, or byte/pixel-op hook. Ember authored
   and device-tested this local implementation in a Claude background
   continuation job, then accidentally left its two generic `clk-rcg` hunks
   dirty. A commit audit found a second issue: pushed commit
   `6fa34eb57` is titled/described as a post-enable re-latch, but it contains
   only MMCC flag changes and no DSI-host re-latch call.
4. **Do not boot the current generic gadget image.**
   `out/boot-joan-mainline.img` was packaged for K101 before Ember reverted the
   K101 `ALWAYS_ON` GDSC source hack. The source is reverted; the binary is not.
5. **The dirty state is preserved, and the clean line is now the shared regular
   + MOA main branch.** The original four-file K092/K093/K099-K100 diff is
   archived exactly. Local `joan/latest-clean-test` at the standard kernel path
   now points to clean K097 commit `16e3950bf`, excludes `6fa34eb57`, has GPU
   disabled, and is used by both regular agents and MOA with one writer at a
   time. The old line is retained under an archive branch.

## Critical safety / artifact warning

### DO NOT BOOT `out/boot-joan-mainline.img`

Current image identity:

- path: `out/boot-joan-mainline.img`
- packaged: `2026-07-19 23:02:28 -0700`
- sha256: `494a7cfaf2e5fc2e9439718f7845f90a4956bed4cac68b114dc2cbeb0470a34c`

The K101 source build completed at about 23:02, with both `gpu_cx` and `gpu_gx`
GDSCs forced `ALWAYS_ON`. Ember tested that image, observed the same hard wedge,
and reverted `drivers/clk/qcom/gpucc-msm8998.c` at about 23:06. No rebuild
followed before the usage limit. Therefore the generic image is a stale K101
test artifact even though `git diff` no longer shows the GDSC hack.

A warning sidecar now exists at:

- `out/boot-joan-mainline.img.DO-NOT-BOOT-K101-TAINTED.txt`

Before any later RAM boot, rebuild the kernel/DTB and package a fresh image from
an explicitly reviewed source state. Do not infer image cleanliness from source
cleanliness.

### Device state at reconstruction stop

Passive host inspection at 2026-07-19 23:38 PDT found the phone healthy in
LineageOS and authorized over USB (`18d1:4ee7`). No real `fastboot` process or
fastboot device was active. Aurel sent no commands to the phone and performed no
boot, flash, mount, or write during this reconstruction.

All future device tests remain RAM-only `fastboot boot` unless Lance explicitly
approves otherwise. Keep one-client fastboot discipline; never use
`fastboot getvar`; require Lance's physical presence for a wedge-risk test.

## Repository snapshot

### Harness / evidence repo

Path:

- `~/vibe-coding-projects/coding/lg-v30-port`

Audit-start state:

- branch: `master`
- HEAD: `441e741680b75e46f9a3ea7b077b7778d14bdc62`
- matched `ghpub/master`
- tracked tree was clean
- untracked GPU firmware trees existed at `firmware/` and
  `initramfs/root/lib/`

This reconstructed handoff is intentionally local/uncommitted for Lance to hand
to the next model. The copied raw logs live under ignored `out/`.

### Shared active kernel repo (regular + MOA)

Path:

- `~/vibe-coding-projects/coding/linux-mainline-v30`

Current state:

- branch: `joan/latest-clean-test`
- HEAD: `16e3950bf9135070bd042ffc84e50e6ca7ebf468`
- tree: `e5f9c1f81d09f62fb6045ae2d53fee4b9077a0b2`
- tracked worktree clean
- `6fa34eb57` is not an ancestor; K092/K093/K099-K101 source is absent
- pre-GPU config restored with `CONFIG_MSM_GPUCC_8998=n`
- corrected cross-configured `dtbs` build exited 0; Joan DTB sha256:
  `3d4c0d338f42ecefa0a77650cd43d7d407b2d1af42a175205d0032a7f40b0b42`
- regular agents and MOA both use this path/branch, but only one writer may
  mutate it at a time

Rollback/remote state:

- local archive branch
  `archive/joan-latest-clean-test-pre-cleanup-20260720` preserves old
  `3395103aa8b60ad3738727b53ec4696b86c51af5`
- remote `ghfork/joan/latest-clean-test` still points to that old commit and
  still contains `6fa34eb57`; do not pull/merge it into the local clean line

Pre-cleanup dirty files were:

  - `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`
  - `drivers/clk/qcom/clk-rcg.h`
  - `drivers/clk/qcom/clk-rcg2.c`
  - `drivers/gpu/drm/panel/panel-lg-sw43402.c`

Exact pre-cleanup diff preserved at:

- `out/reconstructed-20260720-ember-k092-k101/current-kernel-worktree-full.patch`
- sha256: `0afa5565ca4ee3f97ff54ff538953d2f94c32880acec8a6a1cc31a75d05db16b`

Historical dirty-file ownership/disposition:

| File(s) | Origin | Current meaning |
|---|---|---|
| `clk-rcg.h`, `clk-rcg2.c` | Ember K092 | Generic pending-config replay experiment; built/tested, not committed; accidentally left dirty |
| `panel-lg-sw43402.c` | Ember K093 | DCS/BTA readback probes; intentional debug instrumentation; saved patch exists |
| `msm8998-lge-joan.dts` | Ember K099/K100 | GPU reserved-memory relocation, GPU enable/zap node, PM8005 floor and `vdd-supply`; enables the wedging path; do not commit as-is |

K101's GDSC `ALWAYS_ON` edit was reverted and is not in the archived diff.

### Former detached full-build evidence (removed for space)

- former path:
  `~/vibe-coding-projects/coding/linux-mainline-v30-clean-build-evidence-20260720`
- detached HEAD: `16e3950bf9135070bd042ffc84e50e6ca7ebf468`
- full and repeat `Image.gz dtbs` builds exited 0
- kernel release: `7.2.0-rc2-g16e3950bf913`
- `Image.gz` sha256:
  `a752d4f07610691fb46d215e79d0455f1824e305893749077dbd1dbc8b1f1b72`
- Joan DTB sha256:
  `3d4c0d338f42ecefa0a77650cd43d7d407b2d1af42a175205d0032a7f40b0b42`

The temporary `joan/moa-clean-baseline` branch was deleted after the same clean
commit was promoted to the shared main branch. Lance then directed removal of
this redundant detached worktree. Preflight found no open references; removal
reclaimed `3857702912` bytes (`3.593 GiB`). The compiled files no longer exist
there, but their hashes/build record remain and the clean source/config are
reproducible. See `pre-moa-cleanup-20260720.txt`,
`shared-main-promotion-20260720.txt`, and
`build-evidence-worktree-removal-20260720.txt`. Nothing was packaged or booted.

### pmaports

Path:

- `~/.local/var/pmbootstrap/cache_git/pmaports`
- branch: `device-lge-joan`
- HEAD: `25f24b1d26`
- clean at reconstruction time

## Resolved provenance: the K092 `cfg_pending` code

The final Ember session incorrectly concluded that the clock code might be
Aurel's. The logs resolve it conclusively:

- authoring session/job:
  `~/.claude/projects/-home-kumo02/173bc577-5e6c-4c7a-af86-57697a1bd109.jsonl`
- state record: `~/.claude/jobs/173bc577/state.json`
- model/harness in the authoring record: `Claude-Code:claude-fable-5`
- exact edit: JSONL line 1290 at `2026-07-19T22:16:01.426Z`
- Ember's own description immediately afterward:
  “K092 config-replay-at-enable” / “the cleanest design yet”
- saved full experiment patch:
  `out/20260719-ember-k092-full-worktree.patch`
- patch sha256:
  `ee3374e1554562b16c50320621592a33db3b7d3f7a85d7ce7e84009926a4b444`

The saved K092 patch contains the exact current `cfg_pending` and
`clk_rcg2_replay_enable` hunks, plus then-current MMCC flags and panel changes.
It was not an Aurel edit and was not unsaved.

### Upstream provenance audit — exact code is local; mechanism has precedent

Checked-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:openai-codex/gpt-5.6-sol
Checked: 2026-07-20T00:05:05-07:00

The exact K092 implementation was not found in upstream or public code:

- Torvalds `master` at `1590cf0329716306e948a8fc29f1d3ee87d3989f`
  (`Linux 7.2-rc4`; <https://github.com/torvalds/linux/commit/1590cf0329716306e948a8fc29f1d3ee87d3989f>)
  contains none of `cfg_pending` under the Qualcomm RCG driver,
  `clk_rcg2_replay_enable`, or the K092 log string.
- Current `linux-next`, the clock maintainer's `clk-next`, and Qualcomm's
  `for-next` trees likewise contain none of those identifiers in
  `clk-rcg.h`/`clk-rcg2.c`.
- Exact GitHub global code, commit, and issue searches returned zero matches
  for the function and log string. Exact local `git log --all -S/-G` searches
  found no committed version in any local branch or remote-tracking ref.
- Ember's authoring log contains no upstream/shared-op lookup. Immediately
  before writing K092, Ember inspected `clk_byte2_ops` and `clk_pixel_ops`,
  said, “Neither has an `.enable` — so I'll give them one that replays a
  pending config,” and then wrote the current implementation directly.

The broader mechanism is not unprecedented, however:

- Current upstream `clk_rcg2_shared_enable()` writes a cached `parked_cfg` and
  calls `update_config()` when a shared RCG is enabled.
- A 2023 LKML proposal by Taniya Das, **“clk: qcom: rcg: Update rcg
  configuration before enabling it,”** proposed checking hardware
  `CMD_DIRTY_CFG` and calling `update_config()` before enabling a shared RCG.
  That exact proposal is absent from current Torvalds/next/clk-next source:
  <https://lkml.iu.edu/hypermail/linux/kernel/2305.0/00277.html>

Neither precedent is K092's code: neither adds K092's software boolean,
function name, failure-path state tracking, or `.enable` hook to the generic
byte/pixel ops. The evidence therefore supports **Ember as author of the exact
local K092 implementation**, while not claiming that the underlying
“configuration written while unavailable, commit it at enable” idea was novel
to Ember.

### Background-daemon K092 test evidence

The K092 device run showed:

- `byte0_clk_src: replaying rcg config at enable`
- `pclk0_clk_src: replaying rcg config at enable`
- two expected pre-enable RCG WARNs
- zero PLL failures
- zero overflow
- panel readbacks `0x98`, `0x9c`, diagnostic `0x40`, DBV `0xff`
- first-session framebuffer content still black
- one blank/unblank still made fbcon visible

So K092 was a verified partial discriminator, not the final display fix.

Ember then saved the full K092 diff and split out/committed the brightness
settle as `bff40d20b`. The K092 generic `clk-rcg` hunks were never reset, which
is why they remained in all later builds.

### Additional commit audit: `6fa34eb57` does not contain its claimed re-latch

This reconstruction also checked the pushed commit itself rather than relying
on its subject or ledger summary:

- `git show --name-status 6fa34eb57` lists only
  `drivers/clk/qcom/mmcc-msm8998.c`.
- Its diff adds `CLK_GET_RATE_NOCACHE` to byte0/1 and pclk0/1 and removes that
  flag from the byte-interface branches.
- It contains **no change at all** to
  `drivers/gpu/drm/msm/dsi/dsi_host.c`.
- The live DSI host still sets the link-clock rate and then enables the clocks;
  there is no second post-enable `link_clk_set_rate()` call.
- The background-continuation log shows why: at JSONL line 1279 Ember ran
  `git checkout -- drivers/gpu/drm/msm/dsi/dsi_host.c`. Twenty-two seconds
  later, foreground Ember's K092 `str.replace()` looked for the now-absent
  re-latch block and silently made no DSI-host edit. The later commit command
  tried to stage `dsi_host.c`, but the file was unchanged, so only the MMCC
  flags entered `6fa34eb57`.
- Earlier K064/K074 evidence already showed that `CLK_GET_RATE_NOCACHE` without
  an actual later update/replay was insufficient to fix the latch failure.

Therefore the generic dirty K092 replay hook—not `6fa34eb57`—provided the
actual post-enable RCG replay in the background K092 test and later K093-K096
images. The simultaneously built foreground K092 artifact is race-tainted and
should not be treated as a clean provenance reference. The pushed commit's
title, body, and ledger descriptions overstate what its tree contains.
Do not present `6fa34eb57` upstream as a verified re-latch fix. It needs an
explicit correction/revert/replacement decision after a clean K097 regression
test.

### Consequence for K097's display claim

K097 was tested with the uncommitted K092 replay code and K093 panel probes
compiled in. That contamination must be disclosed.

However, the complete preserved K097 dmesg contains neither:

- `replaying rcg config at enable`, nor
- `rcg didn't update its configuration`

The MDSS BCR reset made the first RCG update latch normally, leaving K092's
replay hook dormant in that run. This strongly supports the BCR reset as the
actual cold-boot display fix rather than K092. Still, a clean committed-tree
rebuild/test without K092/K093 is required before a publication-grade claim
that the pushed stack alone was independently verified.

Do not commit the generic K092 clock change as-is merely because it worked as a
discriminator. It affects all users of `clk_byte2_ops` and `clk_pixel_ops` and
needs a proper concurrency/lifecycle/upstream-design review first.

## Display closeout: K096-K097

### K096 — DSI host/PHY-only cycle

A first-enable DSI host+PHY cycle ran successfully, panel probes were green,
and the display remained black. This ruled out a single-block DSI/PHY cycle as
sufficient. The experimental behavior was reverted.

### K097 — MDSS BCR reset: M4 complete

Commit:

- `3395103aa` — `arm64: dts: qcom: msm8998-lge-joan: reset MDSS at probe to shed splash state`

Change:

- `resets = <&mmcc MDSS_BCR>;` on `&mdss`

Result:

- existing `msm_mdss_reset()` asserted the whole MDSS reset for 20 ms at probe
- cold gadget boot rendered penguins and fbcon with no blank/unblank kick
- no RCG-update warnings appeared
- only remaining visible WARN was the unrelated
  `gcc_rx1_usb2_clkref_clk status stuck at 'on'`
- pmOS image with the fixed DTB and `display-kick.start` renamed to
  `.disabled` showed penguins, the full OpenRC boot sequence, login prompt,
  blinking cursor, and no crash; Lance observed it directly

Pre-GPU pmOS image:

- `out/boot-joan-pmos-display.img`
- packaged: `2026-07-19 22:29:32 -0700`
- sha256: `5a4eb091e307f56da46247b163821746a216fd5d8edef1c11f821866a5361db4`

This image predates K098's GPUCC config change and K099-K101 GPU enablement. It
was the display-validation image, not the current generic K101 image.

## GPU arc: K098-K101

### K098 — enable MSM8998 GPUCC

Change:

- effective config changed from unset to `CONFIG_MSM_GPUCC_8998=y`
- snapshot: `out/config-20260720-ember-k098-gpucc`
- sha256: `793948a2c5f2aed7a7c417cb35bedd23eafa81c6873b480530e7f21ef7eaa566`

Result:

- both previously deferred GPU-related SMMUs probed cleanly
- no deferred-probe timeout remained for those blocks
- display still booted visibly

This config is still active in the current kernel `.config`.

### GPU firmware state

Untracked firmware now exists in the harness/initramfs:

- LG/LineageOS-derived (the zap payload is TZ-signed/address-bound):
  - `a540_zap.mdt`
  - `a540_zap.b00`
  - `a540_zap.b01`
  - `a540_zap.b02`
  - `a540_zap.elf`
  - `a540_gpmu.fw2`
- from host package `linux-firmware-qcom 20260622-1`:
  - `a530_pm4.fw`
  - `a530_pfp.fw`

The zap and GPMU files came from the same phone's LineageOS/stock firmware
paths. The zap files must be under `qcom/` in the initramfs; a bare firmware
root path failed with `-2`. Complete checksums are preserved at:

- `out/reconstructed-20260720-ember-k092-k101/FIRMWARE_SHA256SUMS`

Do not add these binaries to git until licensing, redistribution, and provenance
are reviewed explicitly. `docs/dependency-tracker.md` is currently missing the
2026-07-19 `linux-firmware-qcom` install and these firmware extraction rows.

### K099 — memory map + GPU enable + zap

Saved patch:

- `out/20260720-ember-k099-k100-gpu-enable-UNCOMMITTED.patch`
- sha256: `7786a38b8d00b6b02081a73ab693424457cde7c9232f3502065a4f86a38dbf0a`

Changes in the current DTS:

- move `gpu_mem` from `0x95600000` to LG's `pil_ipa_gpu` address
  `0x95c00000`
- extend `reserved@95215000` from `0x3eb000` to `0x4eb000`
- shrink `reserved@95800000` from `0x500000` to `0x400000`
- enable `&adreno_gpu`
- add the zap-shader memory-region hookup

Result:

- Adreno probed and bound
- PM4/PFP/GPMU/zap firmware loaded after path corrections
- zap loading proceeded without an SCM authentication error; Ember recorded
  this as TZ acceptance/authentication of the LG payload
- the first real GPU register read via debugfs hard-wedged the entire SoC

### K100 — VDD_GFX supply/floor

Changes:

- PM8005 S1 minimum raised from 524 mV to 988 mV
- `vdd-supply = <&pm8005_s1>` added to the GPU node

Result:

- the missing `vdd` warning disappeared
- `vddcx` remained a dummy regulator
- the same first register read still hard-wedged the SoC

Therefore 524 mV was not proven to be the wedge cause. The saved K099/K100 patch
currently contains a comment saying the GPU wedges “with the rail that low.”
That wording overclaims the evidence and must be corrected before any commit.

### K101 — force GPU GDSCs always-on

Experiment:

- add `ALWAYS_ON` to both `gpu_cx_gdsc` and `gpu_gx_gdsc`
- rebuild and run the same first-register-read discriminator

Result:

- start sentinel reached serial
- end sentinel never returned
- USB network and serial both died
- `WEDGED`
- physical Power+VolDown recovery required

Disposition:

- K101 source hack reverted
- K101 image left stale in `out/boot-joan-mainline.img`
- GDSC sequencing alone is not sufficient

### Scope the interconnect conclusion carefully

Ember's ledger says “interconnect ruled out.” The evidence is narrower:

- working MSM8996 has a normal interconnect property/provider
- mainline MSM8998 has no interconnect provider node/driver to reference
- the MSM8998 GPU node already has `mem` and `mem_iface` BIMC clocks

This rules out simply adding the usual mainline `interconnects = ...` property
with the current tree. It does **not** prove that BIMC/NoC path state, firmware
ownership, or an equivalent non-ICC setup cannot contribute to the bus wedge.
Treat “no actionable mainline ICC provider” as proven; treat “the bus path is
innocent” as unproven.

## GPU stopping point and next useful discriminator

Do not spend another physical recovery on a blind one-flag boot. The remaining
credible classes require evidence captured immediately before the first GPU
register access:

1. `gpupll0` / GFX3D RCG did not actually latch or turn on despite framework
   state.
2. VDDCX/CPR/GX voltage sequencing is incomplete under load; mainline lacks the
   MSM8998 CPR path Ember expected.
3. Mainline's GMU-less A540 initialization is missing an MSM8998/A540-specific
   sequence present downstream (ISENSE/LM/limits or related ordering).
4. BIMC/NoC path state is incomplete through a mechanism other than mainline
   ICC.

A proper GPU continuation should instrument and emit, over raw serial, at the
last safe point before the first `gpu_read()`/register touch:

- GPUCC PLL/RCG registers and live root/parent selection
- CX/GX GDSCR and clamp/reset state
- relevant GCC BIMC GPU clock state
- regulator/OPP votes and observed rates
- exact A5xx init call boundary reached

Capture the dump before the dangerous register read so the evidence survives
the hang. One-variable tests only; no flash; one physical recovery maximum per
well-defined discriminator.

A lower-risk parallel path is touch (`stmfts` vs LG's downstream FTM4 wiring)
and/or Phosh on llvmpipe. Touch is GPU-independent and aligns with Lance's
“proper display and GUI before laf flash” priority.

## Preserved logs and evidence

Thirty raw build/boot/dmesg/task-result files were copied byte-for-byte from
Claude Code's ephemeral directories to:

- `out/reconstructed-20260720-ember-k092-k101/`

Read first:

- `README.txt`
- `SOURCE_PATHS.tsv`
- `SHA256SUMS`
- `build-evidence-worktree-removal-20260720.txt`
- `kernel-source-state.txt`
- `current-kernel-worktree-full.patch`
- `6fa34eb57-commit-audit.txt`
- `ember-k092-split-session-causality-20260720.txt`
- `pre-moa-cleanup-20260720.txt`
- `shared-main-promotion-20260720.txt`
- `upstream-provenance-audit-20260720.txt`
- `job-173bc577-k092-dmesg.log`
- `k097-dmesg.log`
- `k098-dmesg.log`
- `k099c-dmesg.log`
- `k100-first-register-read-wedge.output`
- `k101-gdsc-always-on-first-register-read-wedge.output`

`SHA256SUMS` covers the preserved archive. `FIRMWARE_SHA256SUMS` covers the
untracked firmware trees in place.

## Documentation debt discovered during reconstruction

Do not mistake these stale docs for live state:

1. `README.md` still says M4 is black/in progress and points to the K078/K079
   handoff; its short current-status section predates K097.
2. `docs/project-history-and-attribution.md` does not yet carry the K097/K101
   closeout.
3. `docs/dependency-tracker.md` lacks the July 19 GPU firmware/package pulls.
4. Pushed commit `6fa34eb57` and its ledger text claim a DSI post-enable
   re-latch that is absent from the commit; this needs an append-only
   correction and a source-level disposition.
5. The K099/K100 patch's low-voltage comment overclaims K100's negative result.
6. The K101 ledger's “interconnect ruled out” wording should be narrowed as
   described above.
7. The clean committed-stack source now builds successfully, but a clean device
   display regression remains needed because K092 and K093 were present in the
   earlier successful K097/pmOS boots.

Do not rewrite Ember's historical entries. Append corrections with current
attribution.

## MOA/model entry instructions

Use the normal shared kernel worktree and start read-only:

- `~/vibe-coding-projects/coding/linux-mainline-v30`
- branch: `joan/latest-clean-test`

1. Read this file.
2. Read `README.md` for binding safety/contribution conventions, but take the
   ledger and this reconstruction over its stale status paragraph.
3. Read `docs/kernel-change-ledger.md` lines covering K089-K101.
4. Inspect the archived pre-cleanup dirty diff and the two saved Ember patches;
   do not reapply them wholesale.
5. Read the preserved K092, K097, K100, and K101 evidence listed above.

Before implementation or a device test, produce a plan that explicitly states:

- which track is being pursued: clean display verification, touch/llvmpipe, or
  instrumented GPU work;
- which dirty hunks are retained, exported, or removed;
- the exact rebuilt image provenance and hash;
- the one variable under test;
- what evidence will discriminate the outcome;
- the bounded recovery/stop condition.

Do not boot the current generic image. Do not commit K099/K100 or the generic
K092 clock experiment as-is. Do not push publicly or flash anything without
Lance's explicit authorization.

### Shared-main and later publication workflow

Regular agents and MOA use the same path and local `joan/latest-clean-test`
branch; changing harness/model does not require a Git merge. Writers must be
serialized: the active writer leaves a committed accepted change or an
exported-and-reverted experiment, records status, and stops before the next
writer begins. Within MOA, workers stay read-only unless one designated
aggregator owns writes.

If true concurrent implementation is needed, create temporary topic
branches/worktrees from local `joan/latest-clean-test`, then cherry-pick only
reviewed commits back. This is an exception, not the normal workflow.

Before publication, rebase the clean series onto the then-current upstream
base and rerun build/check/device gates. Push a reviewed branch to `ghfork` and
open review/PR as appropriate.

Remote `ghfork/joan/latest-clean-test` still points to the old K097 line that
includes `6fa34eb57`. Do not pull or merge it into local main. Prefer first
publishing the clean line under a new remote branch. Replacing the old remote
name requires explicit approval and a reviewed `--force-with-lease`; never use
a plain force push. Historical K092/K093/GPU patches remain evidence and should
be selectively reimplemented only if later validation justifies them.

## Clean pause

Aurel has not started a successor device experiment. The phone is recovered,
the missing authorship question is answered, the stale K101 image is visibly
quarantined by a sidecar warning, the dirty source is preserved and removed
from the live tracked tree, and clean K097 is now the standard shared regular +
MOA branch. The redundant detached full-build worktree was removed for space;
its hashes and build record remain. The still-open Ember CLI was suspended with
`SIGSTOP`, not killed, to prevent another shared-worktree mutation.

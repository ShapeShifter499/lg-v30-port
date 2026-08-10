# Handoff to Ember — 2026-08-10: integration landed, master merged, branches aligned

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-flash
Date: 2026-08-10

This closes the loop on your handoff
(handoff-2026-08-10-ember-to-aurel-touch-bt-gpu.md). Everything you
handed me is verified and landed. Your touch/BT/GPU work was all
correct as described; the only stale line in your handoff was "PRs
#5 and #7 parked, untouched" — Lance merged PR #5 himself on
2026-08-08 (merge commit 72c736ae) before you wrote it.

## Current state (all verified live)

GitHub repo ShapeShifter499/linux-lg-v30-joan:

- master: 47041183b — merge commit (parents 72c736ae + 7ba1c0f1f).
  Contains the full confirmed joan stack overlaid onto master's
  pre-existing upstream line.
- joan/latest-clean-test: 47041183b — fast-forwarded to master's tip.
  Both branches are now byte-identical (verified).
- Open PRs: none. PR #6 and PR #7 closed (2026-08-10, with comments
  documenting supersession; #7's comment notes the ungated-quirk
  hazard in its old series).

Local repo (canonical: ~/vibe-coding-projects/coding/linux-mainline-v30,
worktree: /tmp/joan-bt-fix):

- ember/joan-fixes-v2 — still your verified 6-commit device-tested
  series. Its TREE is the ground truth: master's joan files are
  byte-identical to it (git diff ember/joan-fixes-v2 <master> on the
  15 joan files is empty).
- ember/joan-integration-v3 — the completed reconciliation; its tip
  equals the old latest-clean-test tip 7ba1c0f1f, now absorbed into
  master. Kept as a landmark.
- ember/joan-integration-v2 — untouched backup of your unfinished
  reconciliation. Can be deleted once you're happy with master.
- ember/joan-touch-fixes — your 3-commit touch series on
  latest-clean-test; content is now in master too. Kept.

## What I did, with the receipts

1. Finished the integration (all three of your remaining steps) on
   ember/joan-integration-v3, then pushed it to joan/latest-clean-test
   (3c5618704..7ba1c0f1f):
   - Root-caused the old conflict: the re-applied gnoc commit
     f1213b9d3 had d38242fb5 (enable modem, 54 DTS lines) folded
     into it — 65 = 54 + 11. Re-applied the ORIGINAL commits in
     original order instead: modem enable (6af5c0517) now sits
     BEFORE gnoc (a059ce57e), then IPA mem, modem GSI, GSI-on-AP.
   - Split 68b940416 per Lance's approval: 52e732ff5 (BT node) +
     7ba1c0f1f (Wi-Fi enable, initial work, stale comment dropped).
   - BT group in your order: crnv21 (38496dfbe), UART/NVM
     (f425ed4d2), gated BD driver (ada616f32), DTS placeholder
     (fd76c0931).
   - Tree invariant: git diff ember/joan-fixes-v2
     ember/joan-integration-v3 was EMPTY. DTB builds clean.
2. Closed PRs #6 and #7 per Lance (2026-08-10).
3. Merged into master per Lance's choice (option 1: merge, no force):
   - master turned out to be 148 upstream commits ahead of the shared
     PR #4 merge base (pre-existing on the fork — I pulled NOTHING
     from torvalds/linux; all fetches were from ghfork).
   - The 15-file joan set had ZERO overlap with that upstream drift,
     so I constructed merge 47041183b = master's existing tree +
     the 8 joan files that differed (7 battery files were already
     byte-identical between PR #5 and the re-applied series).
   - Verification: merged master == latest-clean-test on all 15 joan
     files; merge delta = exactly the 8 joan files; upstream content
     untouched; GitHub API confirms parents and tree.
4. Aligned joan/latest-clean-test to master (7ba1c0f1f..47041183b,
   pure FF). Both branches now point at 47041183b.

## Convention (set by Lance, recorded in memory + docs + Deck)

- joan/latest-clean-test = WORKING/staging branch. Confirmed fixes
  accumulate there, in a sensible order.
- master = STABLE. Receives PRs from latest-clean-test (or branches
  off it) containing ONLY the commits that worked.
- Lance's vision wording: "main matches true linux master, we merge
  in our fixes once proven to the 'main', keep staging work on
  joan/latest-clean-test." NOTE: no torvalds sync has happened and
  none was requested; master currently sits on the fork's existing
  upstream point (v7.2-rc2 era, ~Aug 8).

## Open items for you / Lance

1. DECISION NEEDED (device): master's tree as a whole = newer
   upstream base (148 pre-existing commits) + our 8 overlaid joan
   files. The joan files are byte-identical to the device-tested
   series, but the COMBINED tree has not been booted as a unit.
   Tested combination is preserved at ember/joan-fixes-v2. Options:
   (a) boot-test master's tree when convenient; (b) keep testing on
   the fixes-v2 base and re-merge later; (c) if the newer base is
   unwanted, rebuild branches pinned to the older booted base.
   Lance has not decided — surface it to him.
2. Your lanes are untouched and still yours: Deck cards 88 (ghost
   touch), 89 (rainbow on wake), 90 (wlanmdsp.mbn / WLFW service 69),
   91 (pwrkey IRQ), 94 (GPU runtime PM never suspends —
   CONFIG_PM_ADVANCED_DEBUG next step). Card 86 got three Aurel
   comments (16629, 16630, 16631, 16632) — state updates only.
3. WiFi is initial-work only (top commit). Card 90 owns its reality.
4. Housekeeping: ember/joan-integration-v2 + ember/joan-touch-fixes
   + ember/joan-integration-v3 can be pruned once you're comfortable
   (deletion needs Lance's OK).

## Environment gotchas (learned the hard way)

- ghfork master is SHALLOW-fetched in the canonical repo (parents of
  72c736ae absent; full fetch of master times out — big pack
  negotiation). Any future LOCAL merge touching master's history
  needs `git fetch --unshallow ghfork master` (slow, may time out)
  or the manual construction: fetch tip shallow, verify no file
  overlap, overlay files, `git commit-tree <tree> -p <old> -p <new>`,
  update-ref, push. Documented in
  docs/aurel-handoff-2026-08-10-integration-v3-complete.md.
- Single-dtb build: `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
  qcom/msm8998-lge-joan.dtb` (not the full path form — that doubles
  the path and fails).
- Tree-equality is the cheap oracle: any reconciliation should end
  with `git diff <device-tested-branch> <candidate>` empty.

Docs: this file + docs/aurel-handoff-2026-08-10-integration-v3-complete.md
(which carries the full step-by-step + all SHAs). Mirrored to
Talk/Shared_AI_agents_files/handoffs/.

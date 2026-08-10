# Aurel addendum — 2026-08-10: integration reconciliation finished on ember/joan-integration-v3

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-flash
Date: 2026-08-10

Supersedes the "still to do" section of
handoff-2026-08-10-ember-to-aurel-touch-bt-gpu.md. All three remaining
steps are done, locally, on a NEW branch. `ember/joan-integration-v2`
was left untouched as backup.

## What was done

New branch `ember/joan-integration-v3` from the battery-series tip
(b250bea19), rebuilt top-down:

1. d38242fb5 (enable the modem) re-applied as 6af5c0517, sitting
   BEFORE the gnoc/IPA commits — its original position. Root cause of
   the old conflict: the re-applied gnoc commit f1213b9d3 had the
   modem-enable folded into it (65 DTS insertions = 54 modem + 11
   gnoc). The re-apply of the original 8aab25b4b (a059ce57e) restores
   the 11-line gnoc-only delta.
2. gnoc (8aab25b4b -> a059ce57e), IPA memory-region (c34f96ed8 ->
   21f9ba301), modem GSI (85a03ba90 -> 9507cfb99), GSI on AP
   (9bfc50add -> 46aea260e) — original commits, original order.
3. 68b940416 split per Lance's approval:
   - 52e732ff5 — BT node only (blsp1_uart3 + qcom,wcn3990-bt child)
   - 7ba1c0f1f — WiFi enable (initial work), dropped the stale
     "until MSS is functional" comment
4. BT group appended in Ember's order: split-BT (52e732ff5),
   569fbe2c7 crnv21 (38496dfbe), bcc11817c UART/NVM (f425ed4d2),
   60eb82538 gated BD address (ada616f32 — property-present gate
   confirmed), e048ce43b DTS placeholder (fd76c0931).

## Verification

- `git diff ember/joan-fixes-v2 ember/joan-integration-v3` is EMPTY:
  the integration tree is byte-identical to the device-tested kernel
  tree (fixes-v2 = device-tested kernel minus dead drm_atomic debug
  prints). This is the intended invariant: the reconciliation closes
  the gap so latest-clean-test becomes a superset of what runs on the
  device.
- `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/msm8998-lge-joan.dtb`
  builds clean from the v3 tree.
- Worktree clean; no half-applied state; nothing pushed.

## Open items

- PR #7 (joan/bt-uart-clock-fix) still contains the ungated 240de5d2f
  and must not be merged as-is; the corrected series lives on
  ember/joan-fixes-v2 / the BT group of ember/joan-integration-v3.
- PR #5 (battery-fg) shows MERGED (by Lance, 2026-08-08, merge commit
  72c736ae) — the handoff's "parked, untouched" line is stale on that
  point.
- Nothing pushed: deciding how to land v3 (supersede PR #7 with a
  corrected PR, separate touch PR from ember/joan-touch-fixes, etc.)
  is Lance's call.

## UPDATE 2026-08-10 (Aurel): LANDED on joan/latest-clean-test

Per Lance's direction ("pull in all confirmed fixes into
joan/latest-clean-test in order of what makes sense"), the v3 history
is now the joan/latest-clean-test branch:

- Local: joan/latest-clean-test fast-forwarded 4dcd16654 ->
  7ba1c0f1f (via remote 3c5618704).
- Remote: pushed 3c5618704..7ba1c0f1f to ghfork
  (ShapeShifter499/linux-lg-v30-joan), plain fast-forward, no force.
- Final order (bottom to top): touchscreen (3) -> battery (8) ->
  modem bring-up (5: enable modem, gnoc, IPA mem, modem GSI, GSI on
  AP) -> bluetooth (5: BT node, crnv21, UART/NVM, gated BD address,
  DTS placeholder) -> Wi-Fi initial work (1).
- Tree verified byte-identical to the device-tested ember/joan-fixes-v2;
  joan DTB builds clean.

Still open: PR #6 (joan/integration-20260808) and PR #7 are now stale
relative to latest-clean-test; superseding/closing them is Lance's
call. ember/joan-integration-v3 and ember/joan-integration-v2 remain
as local landmarks (v3 == latest-clean-test tip).

## UPDATE 2026-08-10 (Aurel): PRs closed, latest-clean-test canonical

Per Lance's direction ("close out any current PRs since we are trying
to make joan/latest-clean-test the proper main branch"):

- PR #6 (joan/integration-20260808) — CLOSED 2026-08-10T18:02Z,
  superseded by latest-clean-test.
- PR #7 (joan/bt-uart-clock-fix) — CLOSED 2026-08-10T18:03Z,
  superseded by latest-clean-test; close comment documents the
  ungated-quirk hazard in the old series.
- gh pr list --state open now returns [].
- Deck card 86 comment filed.

Next candidate (not done, Lance's call): repoint master at
joan/latest-clean-test — non-fast-forward (master holds the PR #5
battery variants, latest-clean-test holds the re-applied series of
the same tree), so it needs an explicit decision and a force/merge
strategy before anything touches the default branch.

## UPDATE 2026-08-10 (Aurel): master merged — convention set

Per Lance: option 1 (merge into master) + new convention.

- master merged: 47041183b (parents 72c736ae + 7ba1c0f1f), pushed
  72c736ae..47041183b. Master turned out to be 148 upstream commits
  ahead of the shared PR #4 merge base (v7.2-rc era fixes). The
  15-file joan set had ZERO overlap with that upstream drift, so the
  merge overlays the confirmed joan stack losslessly — only 8 joan
  files actually differed (the other 7 battery files were already
  byte-identical between PR #5 and the re-applied series).
- Verification: merged master == latest-clean-test on all 15 joan
  files; merge delta = exactly the 8 joan files; upstream content
  untouched; GitHub API confirms parents and tree.
- CONVENTION (Lance): joan/latest-clean-test is the WORKING branch
  (confirmed fixes accumulate, in order); master is STABLE and
  receives PRs from latest-clean-test (or branches off it) carrying
  only the commits that worked.
- Note: the canonical repo has ghfork master shallow-fetched (parents
  of 72c736ae absent). Future LOCAL merges touching master's history
  need `git fetch --unshallow ghfork master` (slow) or the manual
  commit-tree construction documented here; GitHub-side PR flow is
  unaffected.




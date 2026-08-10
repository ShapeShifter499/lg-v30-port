# Handoff to Ember — 2026-08-10 (Aurel follow-up to branch-convention-corrected)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-flash
Date: 2026-08-10

Your correction was right and mine was wrong. The convention is now
fixed everywhere — my addendum
(docs/aurel-handoff-2026-08-10-integration-v3-complete.md), my handoff
doc, my long-term memory, and Deck card 86: master = clean verified
fixes; joan/latest-clean-test = the raw "booting but ugly" working
history (experiments, diagnostics, reverts preserved). And thank you
for implementing it with the commit-tree merge instead of
force-pushing — that kept the upstream alignment intact.

## Verified your push independently

- latest-clean-test = 345eb2ddc, parents 47041183b + f4a7d951f,
  tree 80cae2b6f — same tree as master, clean fast-forward, behind 0,
  content byte-identical. GitHub compare API confirms.
- master untouched at 47041183b. joan/bt-uart-clock-fix confirmed
  published as ancestry.

## Local-git gotcha found while checking

The shallow file in the canonical repo now lists 47041183b (your
fetches added to my original 72c736ae fetch), so LOCAL git treats the
master merge as a root and cannot walk to 7ba1c0f1f — an ancestry
check locally says NO while GitHub says YES. Use the compare API when
local ancestry looks wrong. I also synced the local
joan/latest-clean-test ref to 345eb2ddc so stale-ref confusion does
not recur.

## Cleanup, all Lance-approved

- /tmp/joan-bt-fix: make mrproper run — tree clean, .config gone.
  Note: that worktree currently sits on your verify/master-tip
  branch; left untouched, it's yours.
- Pruned local-only branches: ember/joan-integration-v2 (56b64365e),
  ember/joan-integration-v3 (7ba1c0f1f), ember/joan-touch-fixes
  (6f9d93774). Content verified fully covered in
  latest-clean-test/master before deletion; v3's history is published
  ancestry. Nothing of yours deleted.
- Kept: ember/joan-fixes-v2 (device-tested ground truth),
  ember/joan-touch-clean, joan/bt-uart-clock-fix, all joan/*
  experiment branches.

## State now

- master 47041183b (clean verified stack) | latest-clean-test
  345eb2ddc (same content + raw history) | zero open PRs.
- Your lanes untouched: cards 88-91, 94. Boot verification of
  master's tree is yours (/tmp/joan-master-verify +
  build-master-verify) — report results when you have them; the
  14-line hci_ldisc.c delta is the only untested surface on your side
  of the analysis, as you quantified.

Nothing pending on my side. My addendum now carries CORRECTION and
PRUNED sections for the record.

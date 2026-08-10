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

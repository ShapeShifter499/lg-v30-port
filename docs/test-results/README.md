# Candidate test closure index

> **Mandatory read-first source for device work.** Before building, booting, diagnosing, or replaying an LG V30 candidate, read this index, the newest applicable closure packet, and `../kernel-change-ledger.md`. A node, UI, boot, or successful command alone is not a pass.

## Current state — 2026-08-03

- **Newest completed device test:** [A183](A183-2026-08-03.md).
- **A183 closed result:** touch/input ✅; display/DRM ✅; direct freedreno/FD540 identity ✅; owner slider/no-crash behavior ✅; exposed brightness contract ❌ because `max_brightness` remained 251 instead of the established visible 6–255 range; GPU runtime-power and sustained-performance ⏳; suspend/resume ⏳.
- **Current source preparation:** [A184 host-only](A184-2026-08-03-host-only.md) changes only the bounded SW43402 maximum/comment from 251 to 255 while retaining DBV off 3, visible minimum 6, perceptual userspace scaling, and serialized updates. A signed comment-only follow-up records that physical A540 reuses packaged A530 PM4/PFP while A540 GPMU/ZAP remains owner-local; no DT behavior changed.
- **Hardware boundary:** A183's one-shot authorization is consumed. Never invoke its runner again. A184 has no complete image and no device authorization.
- **Communications:** blocked until graphics/input integration, GPU power/performance, and suspend/resume close.

## Status symbols

- `✅ PASS` — direct evidence proves the named scope.
- `❌ FAIL` — direct evidence contradicts the acceptance criterion.
- `⏳ OPEN` — incomplete or not run.
- `➖ N/A` — outside the candidate's scope.

## Active decision chain

| Candidate | Date | Durable result | Next/no-replay pointer |
|---|---|---|---|
| K178 | 2026-07-28 | Historical serialized-slider gate: 180/180 machine samples passed on the then-tested 0–251 exposure. | Lineage evidence only; it did not establish the intended final maximum. See `../handoff-2026-07-28-slider-serialisation.md`. |
| K179 | 2026-07-28 | Historical max-255 source/image lineage exists. | Supports the code lineage, but does not replace current-candidate runtime evidence. See the same handoff and local SHA-sealed manifest. |
| A181 | 2026-08-02 | Display/GPU experiment required coordinated recovery; obsolete K127 path was superseded. | Never boot K127. See `../kernel-change-ledger.md` (A181 section). |
| [A182](A182-2026-08-02.md) | 2026-08-02 | Display/DRM and direct FD540/freedreno passed; touch failed because STMFTS was disabled. | Do not replay A182; A183 is the minimal config correction. |
| [A183](A183-2026-08-03.md) | 2026-08-03 | Touch, display/DRM, owner interaction, and direct FD540/freedreno passed. Brightness ABI remained stale at max 251; GPU power/suspend remained open. | Runner consumed; no retry. A184 corrects the exposed maximum host-side. |
| [A184](A184-2026-08-03-host-only.md) | 2026-08-03 | Device-tested twice (both authorized, same sealed image): boot/touch/slider/brightness 6–255/FD540/lock passed. Idle gate: removed `00-no-blank`, stock idle → blank → lock → wake → unlock PASSED; transient rainbow artifact on blank/wake (recovered) — panel-polish item. Accidental s2idle FAILED (reboot to LineageOS) — secondary power finding. Recovered cleanly both times. | A185 tested the ELVSS off-path fix; hypothesis REJECTED. See [A185](A185-2026-08-03.md). |
| [A185](A185-2026-08-03.md) | 2026-08-03 | Device-tested once: boot + mechanical blank→lock→wake passed; ELVSS off-prep (CA/CB/CC/E8 + 150 ms) did NOT remove the blank/wake rainbow garbage — hypothesis REJECTED. No driver errors; recovered cleanly; authorization consumed. | Owner must report off-vs-wake timing next; then one wake-path/TE/encoder hypothesis per fresh candidate + approval. |

## Closure-packet rule

One immutable packet is required after every K/A test or meaningful host-only candidate checkpoint. Use [`../templates/candidate-test-closure.md`](../templates/candidate-test-closure.md).

A candidate is not administratively closed until all of the following are true:

1. Raw evidence is preserved before interpretation.
2. The packet records exact source/image/config/hashes and the authorization/retry boundary.
3. Every gate is marked `PASS`, `FAIL`, `OPEN`, or `N/A` with scope-specific evidence.
4. Owner-visible behavior is quoted or explicitly recorded as absent; it is never inferred from a node or command.
5. Fixed items, decisions, rejected paths, and “do not replay” conditions are explicit.
6. The packet identifies one next safe action and its stop/approval condition.
7. The docs commit is signed, checked, safety-scanned, and pushed.
8. The corresponding shared Nextcloud Deck card gets the same verdict, decisions, no-replay rule, next step, and immutable GitHub commit/file link.
9. Both GitHub and Deck are read back from their original sources.

Immediate safety recovery may precede documentation, but the next experimental candidate must not.

## Source hierarchy and contradiction handling

When records disagree, use this order:

1. Original SHA-sealed evidence (manifest, log, source commit, owner acceptance record) in an approved durable location.
2. The exact candidate closure packet tied to that evidence.
3. Kernel/change ledger and detailed handoff.
4. Deck summary.
5. Session summaries or recollection.

Do not silently choose between contradictions. Record the conflict, read the original artifact, correct the packet/Deck, and preserve the losing claim as superseded history when useful.

## Cross-project adoption

This pattern is intentionally generic. Future hardware/device projects should copy the template and create a project-local `docs/test-results/README.md` as the mandatory read-first pointer. Shared Deck remains the cross-agent coordination surface; Git is the durable technical record; raw private evidence stays in the approved private store or local evidence tree.

## Public attribution

- Maintainer/owner: Lance / ShapeShifter499
- Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
- Date: 2026-08-03
- Update-scope: Closure workflow and A182/A183/A184 backfill.

## Publication and readback

The A182/A183/A184 packets were published in commit
`3251c9558477aa7be81367f73642bf1170f420e4` (github.com/ShapeShifter499/lg-v30-port,
master, 2026-08-03), verified remotely, and mirrored to shared Deck card 43.

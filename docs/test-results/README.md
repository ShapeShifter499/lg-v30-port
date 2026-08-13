# Candidate test closure index

> **Mandatory read-first source for device work.** Before building, booting, diagnosing, or replaying an LG V30 candidate, read this index, the newest applicable closure packet, and `../kernel-change-ledger.md`. A node, UI, boot, or successful command alone is not a pass.

## Current state — 2026-08-13

- **Newest completed device test:** [Card 94 CX/GX final v4](CARD94-CXGX-V4-2026-08-13.md) — exact clean source and marker-free image booted to graphical pmOS with no SMMU/secure-world reset or GPU/context/internal fault, but the first idle suspend aborted because SP/TP and RBCCU stayed on. Runtime PM entered `error`; VDD_GFX stayed at 3/3 enable/open counts. No workload ran; recovery to LineageOS passed. Do not replay this image/runner.
- **Newest host-only checkpoint:** [GPU-IREF-HOST](GPU-IREF-HOST-2026-08-11.md) — four source-correct MSM8998 GPU IREF commits, full post-commit kernel build, binding/static checks, and exact RAM-only image seal passed. The image is not staged or booted; all device behavior remains open and needs fresh explicit approval.
- **Card 94 split verdict:** the MSM8998 Adreno SMMU retention/reset mechanism survived the tested boot/first-idle scope, but the independent A540 SP/TP/RBCCU collapse defect blocks a valid suspend/resume and VDD_GFX-release result. Next: readback-only GPMU/PC-register instrumentation before any behavioral fix.
- **mas_ipa closed result:** interconnect ✅ (a2noc first-ever QoS write, FIXED/qport 1/prio 1,1, IPA clock from rpmcc; no hang, 6/6 fabrics bound, icc errors 0 — two boots); GPU chain bind ✅; display/DRM ✅ (card0+renderD128, mdss 71.39/s vs 70.44 close-out baseline); recovery ✅ both boots. QoS now covers 17/17 programmable masters. Renderer-identity query and GPU power/suspend remain ⏳/N/A (pre-existing, out of scope).
- **Config baseline correction (binding):** kernel builds must use the exact QoS-era config `coding/build-qos-bimc-v2-24e82e84e/.config` (the stale July tree config lacks `CONFIG_MSM_GPUCC_8998` — boot 1 of mas_ipa consumed an approval proving the failure mode: gpucc never probes, SMMU/adreno -110, no /dev/dri).
- **A183/A184 prior state (superseded by newer work, kept as history):** touch/display/FD540 passed; exposed brightness max remained 251 → A184 host-only 255 correction; GPU power/suspend open.
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
| [A185](A185-2026-08-03.md) | 2026-08-03 | Device-tested once: boot + mechanical blank→lock→wake passed; ELVSS off-prep (CA/CB/CC/E8 + 150 ms) did NOT remove the blank/wake rainbow garbage — hypothesis REJECTED. No driver errors; recovered cleanly; authorization consumed. | Owner confirmed garbage is on WAKE. A186 tested wake-settle; rejected. A187 = continuous DSI clock lane. |
| [A186](A186-2026-08-04.md) | 2026-08-04 | Device-tested once: boot + mechanical blank→lock→wake passed; post-display-on settle 20→120 ms did NOT remove the wake rainbow garbage — hypothesis REJECTED. No driver errors; authorization consumed. | A187 (continuous clock lane) was tried; it REGRESSED wake (screen never re-enabled) and is abandoned. |
| [A187](A187-2026-08-04.md) | 2026-08-04 | Device-tested once: boot + blank passed; continuous DSI clock lane (dropped NON_CONTINUOUS) BROKE wake — display never re-enabled (drm stayed disabled, no lock, no error). REGRESSION, hypothesis abandoned. Recovered to LineageOS gracefully. | Revert clock direction; instrument next candidate (drm.debug); test one of: first-kickoff gating, TE re-arm, 0x55 CTRLD divergence. |
| [A188](A188-2026-08-04.md) | 2026-08-04 | Session INVALIDATED (agent instrumentation error): drm.debug=0x1f + ignore_loglevel flooded the boot console → TTY glitching, userspace never came up, no test data. TE re-arm change never exercised; recovered to LineageOS physically. Authorization consumed. | A189 = same TE re-arm commit with corrected cmdline (drop ignore_loglevel), fresh seal + approval. |
| [A189](A189-2026-08-04.md) | 2026-08-04 | Device-tested once (clean retest of TE re-arm): boot + mechanical blank→lock→wake passed; TE re-arm after display-on did NOT remove the wake rainbow garbage — hypothesis REJECTED. No driver errors; authorization consumed. | Panel-command path now essentially exhausted (prepare() is byte-faithful to downstream; only 0x55 differs, de-prioritized). Remaining: host-side DSI PHY/settle or encoder first-kickoff gating (msm-core, needs sign-off), or accept-and-document (self-recovers). |
| [A190](A190-2026-08-04.md) | 2026-08-04 | Device-tested once: boot + mechanical blank→wake passed; host-side DSI PHY PLL-restore settle (100 ms, msm-core) did NOT remove the wake rainbow garbage — hypothesis REJECTED. No driver errors; authorization consumed. | Six candidates closed. Remaining untested: DPU encoder first-kickoff gating (msm-core, needs sign-off), or accept-and-document (self-recovers within a frame or two; all mechanical gates pass). |
| [A191](A191-2026-08-04.md) | 2026-08-04 | Device-tested once (two blank/wake cycles): DPU first-kickoff TE gate PROVEN to fire (`first kickoff gated on TE edge`, no timeout) yet the wake rainbow garbage STILL appeared both cycles — hypothesis REJECTED. No driver errors; authorization consumed. | SEVEN candidates closed; all plausible timing paths exhausted with machine evidence. Recommendation: accept-and-document as known-cosmetic (self-recovers, all mechanical gates pass, no driver errors in seven sessions). |
| [GPU-FULL3](GPU-FULL3-2026-08-04.md) | 2026-08-04 | Device-tested once: GPU fully operational — all 7 clock levels (257→710 MHz) switch with 260 real transitions, OPP voltage scaling delivers the measured corners (936 mV @ 710, 792 mV @ 515), interconnect qnoc clean with active gfx-mem vote, both GPU thermal zones live, GL_RENDERER=FD540 ES 3.1 renders. PASS. | G4 (GX collapse) REJECTED on device: dropping the runtime-PM hold rebooted the phone before userspace — the hold is load-bearing; interconnect votes alone don't fix the A540 collapse sequence (deferred deep msm-core workstream). |
| [G4](G4-2026-08-04.md) | 2026-08-04 | Device-tested once: GX power-collapse restore test (dropped the A540 runtime-PM hold with interconnect votes in place) — system rebooted itself to LineageOS before userspace SSH; K126/K127 wedge signature reproduced. REJECTED. | Hold (231efbcc6 behavior) stays; GPU-FULL3 remains the proven configuration. GX restore deferred as deep msm-core work. |
| [G5-OC](G5-OC-2026-08-04.md) | 2026-08-04 | Device-tested once: experimental 750 MHz GPU OPP @ 965 mV — REJECTED-WITH-CAUSE at parse: "OPP not supported by regulators" (965000 uV off the pm8005_s1 4 mV grid). GPU otherwise fully healthy; 750 never attempted. | Fix committed 92df37a6a (964000 uV, on-grid). G5-OC2 rebuilds; the 750 MHz clock-chain question remains OPEN. |
| [G5-OC2](G5-OC2-2026-08-05.md) | 2026-08-05 | Device-tested once: 750 MHz GPU OPP @ 964 mV (on-grid) — **PASS**: 750 parses, clock chain runs cur=750000000 held during render, rail delivers exactly 964000 uV (summary-confirmed), zero real GPU faults. +5.6% over stock 710. | 750 device-proven (local-only). Follow-ups: 800/850/900 sweep (G6) — 900 REJECTED (PLL no-lock at probe), 850 DEVICE-PROVEN (G6-OC3). Short-session proof only — soak test if kept. |
| [G6-OC3](G6-OC3-2026-08-05.md) | 2026-08-05 | Device-tested once: 850 MHz GPU corner DEVICE-PROVEN **PASS** (cur=850000048, rail 1036 mV, zero faults, 38-40C); 900 MHz REJECTED (PLL no-lock at probe, GPU session wedged). +19.7% over stock 710. NOTE: phosh/lockscreen did not load this boot (open userspace item, separate from the GPU PASS). | 850 proven local-only (never upstream). Keep 800/850 in table, 850 = top. Open: phosh-no-start needs journalctl on next boot; soak test if kept. |
| [mas_ipa](mas-ipa-2026-08-07.md) | 2026-08-07 | PASS: a2noc first QoS write safe ×2 boots; 17/17 masters; display regression-free (mdss 71.39/s). | Branch joan/mas-ipa-qos local/unpushed; images 4efd83f2 (boot 1, superseded) and a57ea7ca (boot 2, sealed). Do not replay boot 1's config (missing GPUCC_8998). |
| [GPU-IREF-HOST](GPU-IREF-HOST-2026-08-11.md) | 2026-08-11 | HOST-ONLY PASS: exact four-commit IREF series, full `Image.gz dtbs modules`, schema/static checks, and sealed pmOS RAM-only image all passed. No device claim. | Sealed image `1fb50bff...` remains local/not staged; dirty-release attempt `a78cb4e6...` is rejected. Fresh explicit approval is required before one RAM-only boot. |
| [CARD94-CXGX-V4](CARD94-CXGX-V4-2026-08-13.md) | 2026-08-13 | MIXED: exact clean series booted with no SMMU/XPU2 reset or GPU fault, but first idle runtime suspend FAILED (`SPTP/RBCCU still on`, status `error`) and VDD_GFX remained 3/3. | One-shot consumed; no workload ran; LineageOS recovery passed. Do not replay. Instrument GPMU initialization and PC-register readback before changing behavior. |

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

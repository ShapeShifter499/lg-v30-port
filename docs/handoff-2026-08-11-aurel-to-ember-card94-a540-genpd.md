# Handoff to Ember — Card 94 A540 suspend boundary, 2026-08-11

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:moa/deep-flash
Acting model: openai-codex:gpt-5.6-sol (`reasoning=high`)
Reference models: zai:glm-5.2, minimax:MiniMax-M3, deepseek:deepseek-v4-flash (`reasoning=high`)
Date: 2026-08-11
For: Ember Nymbrand (agent-ember)
State: READY FOR EMBER; results banked; no fix promoted

## Read these first

1. `docs/aurel-card94-a540-suspend-evidence-bank-2026-08-11.md`
2. `docs/aurel-card94-retest-2026-08-10.md`
3. `docs/aurel-a540-sptp-gate-result-2026-08-10.md`
4. `docs/aurel-a540-vdd-cycle-result-2026-08-10.md`
5. `docs/aurel-a540-gx-rpm-always-on-result-2026-08-11.md`

The first file is the reconciled index. It also records exact hashes for the
initial three boot images and the raw pstore artifacts copied from nym-nest
`/tmp` into the durable project `out/` directory.

## Executive result

Your confounded early unpin negative has now been replaced by a clean,
source-sealed evidence chain.

- Pin present: stable control.
- Pin removed: the current stack reaches userspace and then resets.
- Pin removed plus gfx-mem ICC vote-drop: also resets and additionally wedges
  RPM/ICC on TSIF (`mas 35`) and SDCC with `-110`; the vote-drop is rejected.
- SPTP/RBCCU readiness gating alone: still resets after userspace; rejected as a
  complete fix.
- Controlled rollback diagnostics clear every driver-local suspend stage through
  regulator-vote removal when PM-core genpd collapse is prevented.
- Therefore the remaining untested destructive boundary is late GPU GX/CX genpd
  collapse after `a5xx_pm_suspend()` returns success.

This supersedes the broad earlier shorthand that the callback/VBIF sequence was
itself the root cause. The evidence now clears the bounded VBIF, devfreq, AXI,
clock, and regulator-vote operations individually.

## Initial Card 94 three-boot retest

| Boot | Variable | Result |
|---|---|---|
| 1 | unpin + your gfx-mem ICC vote-drop | Reached pmOS. At 34.8 s, RPM-SMD `mas 35` / TSIF failed `-110`; at 39.9 s SDCC bandwidth removal failed `-110`; abrupt console end and return to LineageOS. This is Lance's flicker/self-reboot observation. |
| 2 | unpin only | Pstore ends at 9.46 s after `switch_root`; no RPM-SMD `-110` in the captured record; returned to LineageOS. |
| 3 | pin-present master control | Stable at the pmOS lockscreen for 11+ minutes; `runtime_suspended_time=0`; zero RPM-SMD errors. |

Exact image and raw-evidence hashes are in the evidence-bank document. The full
boot 2 and boot 3 outcomes were already committed in the original result; a
later session-summary truncation only made them appear lost.

## Boundary-isolation chain after the retest

The clean gated-unpin source `9f3d891201060dba13e0a28e641914365e9cf6cd`
reached userspace and then exited through the same `0x20` / PS_HOLD class. It did
not hit the SPTP timeout path. That made SPTP readiness necessary evidence, not a
sufficient fix.

The successor diagnostics then exercised one more stage at a time and returned
an error before the PM core could collapse genpd:

1. GDSC predicates / callback entry / error rollback — stable.
2. VBIF halt, all four ACKs, and request clear — stable.
3. Devfreq suspend/restore — stable.
4. AXI/EBI disable/restore — stable.
5. GPU clock/rate disable/restore — stable.
6. Generic PM8005 S1 regulator-vote removal/restore — stable.

The last test also proved that the generic vote cannot physically remove S1:
joan marks it always-on and the OPP framework owns another consumer. So the
physical transition left after the callback is GPU GX/CX genpd collapse.

## Phase 8: do not repeat this discriminator

Phase 8 (`a856f868ec30893be16409b69aa010f9f9d74c54`) added static
`GENPD_FLAG_RPM_ALWAYS_ON` to `gpu_gx`, intending to suppress only runtime
collapse.

It failed before the intended path:

```text
PM: always-on PM domain gpu_gx is not on
gpucc-msm8998 ... failed with error -22
```

Generic genpd requires an always-on domain to report ON at provider
initialization. Joan's `gpu_gx` was initially off, so GPUCC and the GPU never
bound and the Adreno runtime-suspend callback never ran. The kernel itself stayed
alive, but Lance's screen was blank; live state showed no aggregate DRM/KMS
`card0` while lower display components were individually bound.

This is a **precondition failure**, not evidence for or against GX/CX collapse.
Do not promote `a856f868e...` and do not retry a static always-on flag.

## Recommended next discriminator

Please design the next one-variable diagnostic at the late genpd boundary, not
inside the already-cleared Adreno callback. It must:

- preserve normal provider registration and initial GPU_GX power-on;
- keep GPUCC, GPU, and aggregate DRM/KMS bound;
- let `a5xx_pm_suspend()` complete successfully;
- instrument or suppress only the later runtime-PM GPU_GX/GPU_CX power-off; and
- retain an exact rollback path and explicit live-state markers.

One reasonable direction is a diagnostic-only late-runtime gate or tracepoint in
the GDSC/genpd off path scoped to Joan's GPU GX/CX domains. Please re-derive the
safest hook from current upstream rather than carrying the static flag forward.

## Do-not-repeat list

- Ember's gfx-mem ICC vote-drop candidate.
- Static `GENPD_FLAG_RPM_ALWAYS_ON` on initially-off `gpu_gx`.
- The clean SPTP-only unpin as if it were untested.
- A540 VBIF software reset; upstream/downstream deliberately avoid it on A540.
- Any claim that TSIF `mas 35` is the GPU path.
- Any flash operation; all work remains RAM-only with per-image approval.

## Current physical and repository state

- Phone: Phase 8 pmOS RAM boot remained reachable for 6 h 42 min at the banking
  check, kernel `7.2.0-rc2-ga856f868ec30`, screen blank, no DRM `card0`.
- LineageOS: untouched fallback; nothing flashed.
- Host for phone commands: **nym-nest**, not nym-skyforge.
- Documentation repository: clean before this handoff on
  `ember/bt-unconfigured-root-cause` at
  `44928b7dd28c8913cba8377ee1eaea3dc5619310`.
- Experimental source commits are evidence only; none is promoted to the clean
  verified-fixes line.

No further phone transition was performed for this handoff. Obtain Lance's fresh
approval before any new RAM boot or before returning the currently running
Phase 8 boot to LineageOS for another experiment.

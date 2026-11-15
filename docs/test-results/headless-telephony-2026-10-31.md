# External headless telephony contribution closure — 2026-10-31

- Candidate: HEADLESS-VOICE-SMS external source publication.
- Disposition: HOST-ONLY preparation; prior local device acceptance reported separately.
- Source base: harness a5de2cf76da8733dfbf09ce75e08d24eb07d3787;
  kernel dc9c6692dbfba9c114eb116f48be9cf3e283ac0f;
  imsd 2b5de7a60b3d9ecedab5fa34da40b2d3c8b26cab.
- Exact source contents: [manifest](../../device/headless/source-manifest.json).
- Image/image hash: N/A; no image built or booted for this contribution.
- Authority: host-only preparation and publication requested by the contributor.
  Prior local call/SMS/reboot permissions consumed; no replay authorized here.
- Persistence: source files only; no phone writes, flashing or new radio traffic.

| Gate | Verdict | Evidence / limit |
|---|---|---|
| SMS logic | PASS | 23 unittest cases on macOS and Linux |
| Call integration logic | PASS | 6 cases as root on Linux, including failure cleanup and two-call reuse |
| Private bus | PASS | Actual Gio calls to synthetic MM; private network namespace; no real SMS |
| Kernel | PASS within scope | Four target objects compiled; checkpatch strict clean after alignment correction |
| imsd | PASS within scope | Eight suites, five executable builds; manual build, Crafter lint not run |
| Prepared source on latest device/kernel | OPEN | No deployment or device boot attempted |
| Original local voice/SMS | PASS reported | See scoped owner observations in the contribution report |
| Suspend, long-term power/storage, real multipart SMS | OPEN | No evidence in this contribution |
| Recovery | N/A | No hardware action during preparation |

Decisions: publish SMS as opt-in tooling and voice as a version-gated reference;
retain the TTY/Bluetooth profile as local policy. No blanket hardware pass.
Do not replay prior failed immediate-hangup calls or old diagnostic kernels.
Next action: code review, then a maintainer-planned new-base build/boot with fresh
owner coordination. Stop before device changes without that coordination.

Public evidence: source manifest, reproducible test commands and scoped
[contribution report](../headless-telephony-2026-10-31.md). Raw device captures
are private and are not claimed to be durably sealed by this publication.

Assisted-by: Codex:OpenAI/GPT-6
Date: 2026-10-31

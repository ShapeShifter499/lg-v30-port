# GPU-IREF-HOST checkmark closure — MSM8998 Adreno IREF ownership

> **Read first:** This is the host-only closure record for one exact source and RAM-only boot-image candidate. It proves source/build/package identity only. It does not prove device behavior, a Card 94/reset change, or suspend/resume improvement.

- **Candidate:** `GPU-IREF-HOST` — MSM8998 Adreno IREF clock ownership
- **Date tested:** 2026-08-11 America/Los_Angeles
- **Disposition:** `HOST-ONLY`
- **Supersedes:** none
- **Superseded by:** none
- **One-line result:** ✅ HOST PASS — four source-correct commits, complete post-commit kernel build, focused schema/static checks, and exact RAM-only image seal passed; every device gate remains ⏳ OPEN.

## 1. Exact identity

| Field | Exact value |
|---|---|
| Source repository | local `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-aurel-clock-adoption`; local/unpushed |
| Branch | `joan/clock-ownership-v1` |
| Source commit | `35750026c2538ea7666ee6df93f1e1fed5f110ed`; human DCO + canonical Assisted-by trailers; unpushed |
| Kernel release | `7.2.0-rc2-g35750026c253` |
| Configuration delta | none versus archived/current integration config; config SHA-256 `0bf3c4370e774528470558b1b4675ff2bcaafb6212e02d67c9118e40f0689651` |
| Image | `out/audit-20260811/boot-joan-gpu-iref-35750026c-sealed.img` |
| Image SHA-256 | `1fb50bffb570d9d90f2ff26f3e261a7eb239242cd07e398bf3cc1e29a5edeaf4` |
| Manifest | `out/audit-20260811/gpu-iref-35750026c.manifest.txt` |
| Manifest SHA-256 | `26b03a1e8c0263e62e659f9da1a5b37a580a6ec9f83cabd174c4a50fcd7d3684` |
| Construction | fresh post-commit `Image.gz + Joan DTB`; byte-proven battery-working pmOS ramdisk/header/cmdline reused verbatim; no firmware repack or cmdline delta |

Four-commit source stack:

1. `0ab3de5ac732a7bdc67e3a23c963aff58b527c4f` — `dt-bindings: clock: qcom: add MSM8998 GPU IREF clock`
2. `1ae761e14245fc4889e0ce45c05b6917b05c8a3d` — `clk: qcom: gcc-msm8998: add GPU IREF clock`
3. `5eded6318c717b5d1247e979c35ba5c3ac552628` — `dt-bindings: display: msm: allow A540 GPU IREF clock`
4. `35750026c2538ea7666ee6df93f1e1fed5f110ed` — `arm64: dts: qcom: msm8998: add Adreno IREF clock`

## 2. Authority and persistence boundary

- **Authorized action:** host-only audit, implementation, build, and RAM-only artifact preparation.
- **Authorization state:** device authorization unused / not granted.
- **Retry status:** any staging or hardware run requires fresh explicit approval.
- **Persistent writes:** host project/build files only; no phone writes.
- **Explicitly excluded:** staging to another host, `fastboot boot`, flash, erase, slot changes, automatic retry/recovery, or any phone partition action.
- **Controller/client discipline:** not applicable yet; no adb/fastboot client was invoked.

## 3. Checkmark gate matrix

| Gate | Verdict | Exact result and evidence |
|---|---|---|
| Source identity | ✅ PASS | clean worktree at `35750026c253`; embedded release exactly `7.2.0-rc2-g35750026c253` |
| Full host build | ✅ PASS | post-commit `make -j12 ... Image.gz dtbs modules` exited 0 |
| Focused clock/DT build | ✅ PASS | MSM8998 GCC object, Joan DTB, and focused `W=1` build passed; only pre-existing DTC warnings |
| Binding/static quality | ✅ PASS | `gpu.yaml` `dt_binding_check` passed; new compiled-DTB clock/count errors eliminated; per-file strict checkpatch reported 0 errors/0 warnings |
| Image payload identity | ✅ PASS | unpacked kernel equals fresh `Image.gz` concatenated with fresh Joan DTB; uncompressed Image matches fresh output |
| Ramdisk/header lineage | ✅ PASS | ramdisk SHA-256 `43d1a861...` byte-identical to proven battery reference; header v0, offsets, page size, cmdline, and pmOS UUIDs preserved |
| Transport and kernel identity on device | ⏳ OPEN | image not staged or booted |
| Display/DRM | ⏳ OPEN | no device run |
| Owner-visible behavior | ⏳ OPEN | no owner/device report because no run occurred |
| Touch probe/input/events | ➖ N/A | outside this clock candidate’s host-only scope |
| Brightness contract and endpoints | ➖ N/A | outside this clock candidate’s host-only scope |
| Renderer identity | ⏳ OPEN | no device run |
| Fault/submit stability | ⏳ OPEN | no device run |
| Frequency/OPP scope | ⏳ OPEN | no device run; no OPP/isense policy change in this candidate |
| Runtime power | ⏳ OPEN | no device run |
| Suspend/resume | ⏳ OPEN | no device run |
| Recovery/end state | ➖ N/A | phone was untouched |
| Communications gate | ➖ N/A | outside scope and still blocked by broader project criteria |

## 4. What changed and what was decided

### Fixed or changed

- Added the downstream-documented MSM8998 GCC GPU IREF gate at register `0x88010`.
- Added a stable clock binding ID and assigned the clock to the A540 node.
- Extended the A540 binding to permit an optional eighth `iref` clock while retaining compatibility with seven-clock descriptions.

### Decisions

- Keep SDCC, UFS, GPU, and USB-C/PHY as independent clock lanes.
- Treat IREF as host-qualified only until it receives its own device evidence.
- Do not call IREF a Card 94/reset/suspend fix without controlled evidence.
- Keep `isense` separate until mainline A540 limits management and real DVFS can implement downstream’s 200 MHz (levels 0–1) / 19.2 MHz (levels 2+) policy semantically.
- Keep `GCC_GPU_SNOC_DVM_GFX_CLK` separate until the MSM8998 SMMU binding and truthful fourth consumer name are worked out.

### Rejected paths / do not replay

- **DO NOT:** boot `out/audit-20260811/boot-joan-gpu-iref-35750026c.img` (SHA-256 `a78cb4e6...`).
- **WHY:** it carries the byte-correct aggregate diff but embeds pre-series release `7.2.0-rc2-g569fbe2c7fa0-dirty`; exact-source identity is unacceptable.
- **REOPEN ONLY IF:** never; use the sealed post-commit image instead.
- **DO NOT:** add an isense phandle without its rate-policy/limits-management consumer, or relabel an existing SMMU clock as SNOC DVM.

## 5. Failures and open gates

| Item | Why it remains open/failed | Required closure evidence |
|---|---|---|
| IREF device behavior | no hardware run authorized | one fresh-approved RAM-only boot with exact release, GPU/provider probe, clock state, rendering, runtime-PM, and recovery evidence |
| ISENSE adoption | mainline A540 disables GPMU throttling and hardcodes limits-management level | source-correct LM/DVFS implementation plus OPP-correlated 19.2/200 MHz device evidence |
| SNOC DVM ownership | absent from downstream consumer list; current MSM8998 SMMU schema permits only three existing clocks | reviewed binding extension and source-backed fourth consumer name before any code/device test |
| USB3 enablement | clock lists are complete, but PMI8998 Type-C role/orientation path is missing | PMI8998 Type-C/TCPM support, endpoint graph, both plug orientations, roles, SuperSpeed transfer, and USB2 fallback |
| Existing Joan schema debt | compiled-DTB validation still reports unrelated baseline warnings (`gfx-l3`, board compatible, old OPP naming/properties, PMIC fuel gauge, etc.) | separate patches; do not bundle with IREF |

## 6. Next safe action

1. Preserve the sealed image and manifest locally without staging it.
2. Continue source-only GPU SNOC DVM and PMI8998 Type-C audits as separate lanes.
3. Before any IREF hardware run, request fresh explicit approval for exactly one RAM-only boot and a bounded capture plan.

**Stop condition:** do not stage or invoke adb/fastboot until Lance explicitly approves the exact sealed image and one-shot RAM-only plan.

## 7. Evidence ledger

| Evidence | Location | SHA-256 / durable identifier | Scope |
|---|---|---|---|
| Sealed boot image | `out/audit-20260811/boot-joan-gpu-iref-35750026c-sealed.img` | `1fb50bffb570d9d90f2ff26f3e261a7eb239242cd07e398bf3cc1e29a5edeaf4` | exact RAM-only candidate |
| Manifest | `out/audit-20260811/gpu-iref-35750026c.manifest.txt` | `26b03a1e8c0263e62e659f9da1a5b37a580a6ec9f83cabd174c4a50fcd7d3684` | build/package/provenance seal |
| Kernel tip | local kernel repository | `35750026c2538ea7666ee6df93f1e1fed5f110ed` | exact source |
| Image.gz | build output | `3dc7164500ae0cd69a4e418590ee56f0361bd1aaf4ddc1e441e701514575ce72` | compressed kernel |
| Joan DTB | build output | `2ff31c7ea26109eccc2b086dc9aa08d997803341efb10ace78e0164aa98e1d12` | device tree |
| Rejected image note | `out/audit-20260811/boot-joan-gpu-iref-35750026c.UNSEALED.txt` | `b7b47772232c9158fa0d79cfdcbaa383f896a4dcfa0fe067d5e3346f6ba176b2` | prevents dirty-release replay |
| Clock audit | `docs/clock-ownership-audit-2026-08-11.md` | this docs commit when created | four-lane rationale |

Local `out/` files are SHA-sealed evidence but not immutable remote publication. Publication remains pending owner direction.

## 8. Publication and readback

- [x] Packet added to `docs/test-results/README.md` in the same local docs change.
- [x] `git diff --check` and focused repository checks pass before local commit.
- [x] Public/private safety scan: no credentials, private firmware bytes, or owner-private captures added to tracked docs.
- [ ] Signed docs commit pushed to the documentation repository.
- [ ] Shared Deck card updated.
- [ ] GitHub and Deck read back from original sources.

Publication and Deck actions were not authorized in this session and remain pending.

## 9. Public attribution

- **Owner/operator:** Lance / ShapeShifter499
- **Assisted-by:** `Hermes-Agent:moa/deep-flash`
- **Packet date:** 2026-08-11
- **Update-scope:** host-only MSM8998 GPU IREF clock implementation, qualification, and RAM-only artifact seal.

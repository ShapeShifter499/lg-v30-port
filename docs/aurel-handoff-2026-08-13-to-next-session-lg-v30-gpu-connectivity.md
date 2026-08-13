# Aurel handoff: LG V30 CX/GX, A540 runtime PM, and connectivity

- **From:** Aurel Nymvale
- **To:** Lance's next Hermes/Aurel session
- **Harness/model:** Hermes Agent — `openai-codex/gpt-5.6-sol`
- **Date:** 2026-08-13, America/Los_Angeles
- **Standing goal:** upstream-shaped MSM8998/Joan support for CX/GX, A540 suspend, WCN3990 Wi-Fi/Bluetooth, conservative cellular control, and optional media enumeration.

## Read this first

Continuity is safe. The phone is recovered, the evidence is local, and every unsafe image is quarantined.

Current live phone state, verified at handoff time:

- physical USB host: `nym-nest`
- expected serial: `LGUS9986e606d55`
- installed OS: LineageOS
- USB: `18d1:4ee7` present exactly once
- pmOS USB: `18d1:d001` absent
- ADB state: `device`
- `sys.boot_completed=1`
- battery: 100%
- fastboot clients: none
- no partition was flashed during this session

**Do not RAM-boot any existing A540 fix image again.** The tested manual-collapse candidates are rejected. The next source experiment must start from clean final-v4 and receive a new image name, hash-bound runner, and one-shot authorization.

## Lance's requested scope

In order:

1. diagnose and wire GPU_CX/GPU_GX/VDD_GFX/Adreno SMMU in upstream-reviewable form;
2. fix and verify A540 runtime suspend;
3. fix and verify WCN3990 Wi-Fi through passive scan only;
4. fix and verify WCN3990 Bluetooth through controller bring-up/passive discovery only;
5. if feasible, validate cellular offline through MSS/QRTR/QMI/IPA/ModemManager;
6. bonus: host-audit sound, microphones, and cameras; device probes must stay silent and non-capturing.

Safety boundaries remain:

- RAM boot only; no flashing phone partitions;
- one intended `fastboot boot` per runner, no automatic retry;
- no Wi-Fi association unless later justified;
- no cellular registration, service activation, modem NV/provisioning writes, transmission tests, or calls;
- no emergency-call tests;
- no audio playback/recording or camera capture without later approval.

## Repositories and durable state

### Clean upstream-facing base

- worktree: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-card94-final-v4`
- branch: `joan/a540-cx-gx-final-v4`
- HEAD: `76d180923dc2eb2a7033e7a37cf394318a3c2bac`
- tree: `8622155b25dea27e77334107039b9e9b7a5dfbf6`
- state: clean
- exact build: `/data/buildcache/kbuild/build-a540-cxgx-final-v4-76d180923`
- config SHA-256: `0bf3c4370e774528470558b1b4675ff2bcaafb6212e02d67c9118e40f0689651`
- full build: `EXIT=0`
- `Image` SHA-256: `1e60030f9f9bd0cce607f7b0e174818d75622ca223b2414012ca6f8402868704`
- `Image.gz` SHA-256: `f359bf289f68bdf9ad47dfadd8e0bd74f603d92d558173e700dca1304b494e57`
- joan DTB SHA-256: `d56d52932d398f147fbe2f95157bcff69feef570c67c852032e8f9f22db5c15d`

Use this worktree as the base for the next fix. Do not build on the rejected fix branches.

### Documentation/evidence repo

- repo: `/home/kumo02/vibe-coding-projects/coding/lg-v30-port`
- branch: `aurel/card94-reset-script`
- latest pre-handoff commit: `bbcb50bbf40239a72dfb93672ed6c7aef2d3a981`
- signed local commits:
  - `80db70e60b46e37f625e7790d2ba583b8ab23497` — Card 94 final-v4 characterization
  - `bbcb50bbf40239a72dfb93672ed6c7aef2d3a981` — full 2 MiB pstore capture helper
- not pushed/publicly published

Important closure:

- `docs/test-results/CARD94-CXGX-V4-2026-08-13.md`
- SHA-256: `c55ad85163e9795834d404d63ee7d6bbefd3064c90fe0c410329d2a88470916c`

## CX/GX/SMMU topology already established

The clean series models:

- A540 GPU device on `GPU_GX_GDSC`;
- Adreno SMMU on `GPU_CX_GDSC`;
- GPU_GX parented by GPU_CX;
- PM8005 S1 / VDD_GFX as the GPU_GX supply;
- MSM8998 Adreno SMMU compatibility in `arm,smmu.yaml`;
- `vdd-gfx-supply` in the MSM8998 GPUCC binding;
- a Qualcomm SMMU implementation feature that avoids rerunning the firmware-protected reset/probe sequence after initial setup.

Focused schemas and strict checkpatch passed for final-v4. The clean final-v4 source contains no `JOAN-GPU-GATE`, `joan_gpu_gate`, or equivalent late genpd diagnostic gate.

Exact clean package:

- image: `out/audit-20260813/card94-cxgx-v4-76d180923/boot-joan-card94-cxgx-v4-76d180923-clean.img`
- SHA-256: `08bc9f8047fd2be34db63a80b601348928e77ec291cd77a69cccb70191679807`

Its one source-matched RAM boot proved:

- GPUCC, Adreno SMMU, A540, DRM, phoc, and phosh came up;
- the previous secure-world/SMMU reset crash did not recur;
- no workload was run after the idle suspend gate failed;
- A540's separate SPTP/RBCCU problem remained.

Do not call final-v4 a full power-cycle PASS. Its SMMU/reset mechanism survived, but the A540 idle gate failed.

## Decisive A540 diagnostic result

### Diagnostic source/artifact

- worktree: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-a540-suspend-diag`
- branch: `joan/a540-suspend-gpmu-diag`
- HEAD: `dcf275c981634124e5baa7a512d20d0f023ebd4e`
- tree: `799d804bbd7fafc2d66e45fdecb21fe9227ae8fe`
- release: `7.2.0-rc2-gdcf275c98163`
- build: `/data/buildcache/kbuild/build-a540-suspend-diag-dcf275c98`
- build: `EXIT=0`, 1,596 modules
- image: `out/audit-20260813/a540-gpmu-diag-dcf275c98/boot-joan-a540-gpmu-diag-dcf275c98.img`
- image SHA-256: `73596208efcfb531c62bad76a4c3ea8912488c9658f561de481a3419f161099b`
- run: `A540-GPMU-DIAG-20260813T131350Z`
- evidence: `out/audit-20260813/a540-gpmu-diag-dcf275c98/device-run-A540-GPMU-DIAG-20260813T131350Z/`
- classification: `CONFIRMED_NO_SUBMIT_RESUME_GPMU_OFF`

### Exact timeline

The diagnostic logs show many normal cycles where full HW/GPMU init happens before suspend. The failing cycle is:

- `56.487928`: runtime resume with `needs_hw_init=1`, GPMU signature absent (`general0=0`), CM3 reset asserted, SP/RBCCU on, autonomous-PC registers at reset values;
- `56.799740`: runtime suspend begins while `needs_hw_init=1` and GPMU remains off;
- `56.800264`: suspend aborts because SP/RBCCU are still on;
- `56.923930`: full `msm_gpu_hw_init()` finally runs, restores `BABEFACE`, programs GPMU PC, and the domains then collapse.

This proves the primary defect is a **resume-to-autosuspend race**, not missing firmware parsing and not a need for software-forced inner-domain collapse.

## Current leading root cause: perf-counter resume work has no PM ownership

Source anchors in clean final-v4:

- `drivers/gpu/drm/msm/adreno/adreno_device.c:307-334`
  - `adreno_runtime_resume()` powers the GPU and calls `msm_perfcntr_resume()`;
  - `adreno_runtime_suspend()` calls `msm_perfcntr_suspend()` before GPU suspend.
- `drivers/gpu/drm/msm/msm_perfcntr.c:29-44`
  - `msm_perfcntr_resume_locked()` queues `stream->sel_work` asynchronously and immediately returns.
- `drivers/gpu/drm/msm/msm_perfcntr.c:56-75`
  - suspend cancels the work asynchronously with `cancel_work()`.
- `drivers/gpu/drm/msm/msm_perfcntr.c:174-210`
  - `sel_worker()` waits on `pm_runtime_barrier()`;
  - only after that calls `pm_runtime_get_if_active()`;
  - then takes `gpu->lock` + `perfcntr_lock`, calls `msm_gpu_hw_init()`, configures counters, and finally puts autosuspend.

Likely race:

1. runtime resume queues `sel_work` but the work owns no runtime-PM reference;
2. the caller that woke the GPU drops its reference;
3. autosuspend begins while `needs_hw_init=1` and GPMU is still off;
4. A5xx autonomous collapse cannot happen, so suspend aborts;
5. only then does `sel_worker()` run and restore GPMU.

This exactly matches the diagnostic timing.

### Next safe source task

Create a **new clean worktree from final-v4** and fix the generic perf-counter PM-ownership race. Do not modify A5xx power-collapse logic first.

Candidate design to evaluate carefully:

- ensure a successfully queued `sel_work` owns one runtime-PM usage reference before `adreno_runtime_resume()` returns;
- release that reference exactly once when the worker completes or when pending work is canceled;
- preserve submit-WQ serialization for SEL programming;
- handle `queue_work()` returning false (already pending/running);
- handle runtime suspend, system force-suspend, stream release, recovery, and driver teardown;
- do not access hardware if the device was never resumed/active;
- propagate/record `msm_gpu_hw_init()` failure instead of silently configuring counters after failure.

Important pitfall: a naïve `pm_runtime_get_noresume()` before `queue_work()` can pin a device that was already suspended if `msm_perfcntr_resume_locked()` is invoked outside runtime resume. Audit all callers before implementing. A naïve `pm_runtime_resume_and_get()` from the worker can recurse or deadlock. The fix must pair references across `queue_work`, `cancel_work`, worker completion, and stream destruction.

A simpler synchronous `msm_gpu_hw_init()` inside runtime resume is broader and may violate the driver's lazy-init/submit ordering. Do not choose it without a locking and performance audit.

## Explicitly rejected approaches and images

All of these are diagnostic history only. Do not boot or promote them.

### 1. Manual collapse before VBIF drain

- source branch: `joan/a540-suspend-no-submit-fix`
- source commit: `bfd863403e0e679b098d2c1ec6371410a1551110`
- image SHA-256: `5790b0fa36ab54cdfa849c3ca76615635d453b8b9a3b6084c526123906fe761d`
- rejection marker: `out/audit-20260813/a540-suspend-fix-bfd863403/REJECTED-DO-NOT-BOOT.txt`
- result: got past the old suspend abort, then asynchronous SError in `arm_smmu_unmap_pages()` while phoc closed a GEM handle; phone reset to LineageOS.

### 2. Runtime-always-on CX without provider pre-power

- source commit: `c4fc3c98fd2bbac8692acba2137cea9418fa9885`
- image SHA-256: `87cad41a3ae55254c6ec2717955fb80790899afc7171e84056456fa751ebd83f`
- rejection marker: `out/audit-20260813/a540-suspend-cxfix-c4fc3c98f/REJECTED-DO-NOT-BOOT.txt`
- result: GPUCC probe failed with `always-on PM domain gpu_cx is not on`; GPU/DRM did not bind.

### 3. Provider-prepowered CX plus pre-VBIF manual collapse

- source branch: `joan/a540-suspend-no-submit-fix`
- tip: `dbcd9f905b3551c73d68694dd6dfb27f5c542eea`
- image SHA-256: `f23e5f48f9c06761674190b07056a31f196413539fc9e5fd14be3c9e0d12bb95`
- rejection marker: `out/audit-20260813/a540-suspend-cxfix-dbcd9f905/REJECTED-DO-NOT-BOOT.txt`
- result: GPUCC/SMMU/GPU/DRM bound and prior SMMU SError was absent, but the phone reset before the first complete topology/idle capture.

### 4. VBIF-first manual collapse plus runtime CX policy

- source branch: `joan/a540-suspend-ordered-fix`
- tip: `9740d5e6b18fae1ff59fa2d8927230ad38befd54`
- image SHA-256: `09810c9f2925ac4c92ab1378a2a685b28dd02afab28a4687c0f3a7cb7ac435a1`
- rejection marker: `out/audit-20260813/a540-suspend-ordered-9740d5e6b/REJECTED-DO-NOT-BOOT.txt`
- immediate snapshot was healthy and showed increasing GPU suspend time, but the phone later reset to LineageOS before the deterministic no-submit helper or any workload ran.

### Why all manual-collapse work is abandoned

Downstream software collapse is conditional on autonomous SPTP power control being disabled. A540 enables autonomous SPTP/GPMU power control. Three variants that forced software SP→RBCCU collapse all reset. Do not attempt a fourth ordering variation.

## Pstore/evidence tooling correction

The old helper read only 256 KiB of a 2 MiB pstore block partition and contaminated the binary with `dd` stderr.

Fixed helper:

- `scripts/read-pstore-partition.sh`
- signed commit: `bbcb50bbf40239a72dfb93672ed6c7aef2d3a981`
- dynamically reads the block-device size;
- captures exact bytes only;
- writes `*.meta.txt`, `*.strings.txt`, and SHA-256 sidecars;
- passed a real read-only 2,097,152-byte smoke capture on Joan.

Use this helper for any future reset. Do not use the old 256 KiB assumption.

## Wi-Fi next lane

Current source already contains the Joan WCN3990 topology. Prior tests proved modules/rails but stopped before WLFW service 69.

Important correction: service 69 requires the complete MSM8998 userspace firmware service chain, not merely copying `wlanmdsp.mbn`:

- MSS/rmtfs working;
- in-kernel or userspace PD mapper;
- `tqftpserv` serving the WLAN image requested by modem firmware;
- exact-release ath10k/mac80211/cfg80211/rfkill modules.

The earlier service-69 absence was not yet a valid kernel failure because retained evidence did not show `pd-mapper`/`tqftpserv` running.

Prepared host-only payload (not installed on phone):

- `out/audit-20260813/connectivity-transient-userspace/`
- hash-sealed official aarch64 payload:
  - `tqftpserv`
  - `libqrtr.so.1`
  - `libzstd.so.1`
- `SHA256SUMS` verifies.

Wi-Fi acceptance boundary:

- exact matching module tree;
- WLFW service 69 appears;
- `ath10k_snoc` binds;
- `wlan0` appears;
- passive scan succeeds;
- no association.

Reference:

- `docs/aurel-handoff-2026-08-08-wifi-bt-to-ember.md`
- SHA-256: `26b138b1325336a861cf80eb4f35322df110680c3539fd89c2b630dc9f5a510b`

## Bluetooth next lane

Bluetooth has stronger prior evidence than Wi-Fi: controller configuration/address adoption and passive discovery were previously proven. Revalidate against the exact final candidate/module tree rather than replaying old branches.

Current config has:

- `CONFIG_BT=m`
- `CONFIG_BT_HCIUART=m`
- `CONFIG_BT_HCIUART_QCA=y`
- `CONFIG_BT_QCA=m`

Acceptance boundary:

- exact modules load;
- QCA controller initializes;
- expected stable local address adoption succeeds;
- HCI is UP;
- passive discovery only;
- no pairing/connection.

Reference:

- `docs/ember-handoff-2026-08-09-bt-unconfigured-root-cause.md`
- SHA-256: `c3fae6aa6de6b6c6a38392174f2e273284324906365b98454ac8dade8f1fd652`

## Cellular next lane

Prior matching-module bring-up proved:

- MPSS running;
- read-only rmtfs;
- 45 QMI services;
- QRTR/IPCRTR;
- IPA setup and `rmnet_ipa0` on the prior matching baseline.

Current clean config has:

- `CONFIG_QCOM_Q6V5_MSS=y`
- `CONFIG_QRTR=y`
- `CONFIG_QRTR_SMD=y`
- `CONFIG_QCOM_RMTFS_MEM=y`
- `CONFIG_QCOM_IPA=m`
- `CONFIG_WWAN=m`
- `CONFIG_QCOM_BAM_DMUX` disabled
- `CONFIG_RPMSG_WWAN_CTRL` disabled

Therefore, first validate only:

- MSS running;
- read-only rmtfs;
- QRTR service table;
- IPA module load/setup;
- ModemManager debug enumeration over QRTR.

Do not claim WWAN-netdev support until BAM-DMUX/RPMSG config and source are separately qualified. Do not register to a network or change provisioning.

Reference:

- `docs/ember-handoff-2026-08-08-modem-layer1-and-integration.md`
- SHA-256: `f1ab3d72ee164d552b2533c7b1f2e754cabc7982f37bbbc1b438a7d4ca8c4cf4`

## Media bonus

Host audit only for now:

- `CONFIG_VIDEO_QCOM_CAMSS=m`
- `CONFIG_SND_SOC_QDSP6=m`
- Joan DT currently lacks complete board sound/camera topology.

Likely separate projects:

- normal Tavil/SLIMbus/QDSP6 sound-card routing;
- ES9218 Hi-Fi DAC support;
- q6voice/call audio;
- CAMSS + exact sensor/CCI/regulator/clock wiring.

Do not run playback, recording, or capture probes in the next session without later approval.

## Next-session execution plan

1. Read this handoff and `docs/test-results/CARD94-CXGX-V4-2026-08-13.md`.
2. Verify phone remains in LineageOS on `nym-nest`; do not boot anything yet.
3. Create a fresh worktree/branch from final-v4 `76d180923...`.
4. Fully audit the perf-counter work item's PM-reference lifecycle:
   - queue success/failure;
   - worker completion;
   - asynchronous cancel during runtime/system suspend;
   - synchronous cancel during stream release;
   - recovery path;
   - teardown;
   - calls where the GPU may already be suspended.
5. Implement the smallest generic fix in `msm_perfcntr.c`/`.h` or its runtime-PM caller. Do not add A540 magic/manual collapse.
6. Host-qualify with strict checkpatch, W=1 focused objects, exact config, full Image/DTB/modules, and source/image manifests.
7. Build a fresh unique image and one-shot runner. No reuse of existing authorization sentinels.
8. First device gate: no workload. Prove a no-submit resume completes `msm_gpu_hw_init()` before autosuspend, then prove CX/GX/VDD_GFX state and SMMU translation.
9. Only after that, run one bounded compositor-backed submit and prove a subsequent suspend.
10. Recover to LineageOS and bank the full 2 MiB pstore if anything resets.
11. Then proceed to Wi-Fi, Bluetooth, offline cellular, and media audit in that order.

## Administrative/coordination state

- Critical technical state is durable locally and restart/new-session safe.
- Documentation and helper commits are local and signed, but not pushed.
- No Deck update was made during this handoff.
- No public upload/share was created.
- Existing task-list lanes should remain:
  - GPU suspend: in progress
  - Wi-Fi: pending
  - Bluetooth: pending
  - cellular: pending
  - media bonus: pending
  - final handoff/closure: pending after the project work

## Primary handoff sources

- Ember Card 94 handoff:
  `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-aurel-clock-adoption/docs/ember-handoff-2026-08-13-to-aurel-card94-cx-gx.md`
- clean Card 94 closure:
  `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/docs/test-results/CARD94-CXGX-V4-2026-08-13.md`
- Wi-Fi/Bluetooth handoff:
  `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/docs/aurel-handoff-2026-08-08-wifi-bt-to-ember.md`
- Bluetooth root cause:
  `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/docs/ember-handoff-2026-08-09-bt-unconfigured-root-cause.md`
- modem layer-1 handoff:
  `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/docs/ember-handoff-2026-08-08-modem-layer1-and-integration.md`

## Bottom line

CX/GX/VDD_GFX topology and the SMMU reset mechanism are source-qualified and device-characterized, but A540 suspend is not closed. The strongest current explanation is a generic asynchronous perf-counter resume race: SEL work that must restore GPU HW/GPMU is queued without owning PM lifetime, allowing autosuspend to begin first. The manual-collapse branches are disproven and quarantined. Resume from clean final-v4, fix PM ownership/synchronization, and do not boot any existing rejected image.

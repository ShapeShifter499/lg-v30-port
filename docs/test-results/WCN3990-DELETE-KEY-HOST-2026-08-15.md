# WCN3990-DELETE-KEY-HOST checkmark closure — pairwise delete-key wait quirk

> **Read first:** This is the host-only closure record for one exact kernel
> source stack and a clean `Image.gz`/`dtb` build. It does **not** prove
> device behavior, association reliability, or faster tethering. Lance asked
> to hold off on the RAM-only boot.

- **Candidate:** `WCN3990-DELETE-KEY-HOST` — joan pairwise `DISABLE_KEY` wait skip
- **Date tested:** 2026-08-15 America/Los_Angeles (host only)
- **Disposition:** `HOST-ONLY`
- **Supersedes:** none. Does not supersede
  [WIFI-KEYINSTALL-HTT](WIFI-KEYINSTALL-HTT-2026-08-15.md); that packet remains
  the last device classification.
- **Superseded by:** none
- **One-line result:** ✅ HOST PASS — three signed commits, clean full
  `Image.gz dtbs modules` build, and sealed hashes; boot.img not packaged;
  every device/tether gate remains ⏳ OPEN by owner request.

## 1. Exact identity

| Field | Exact value |
|---|---|
| Source repository | local `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-wcn3990-keyfix`; local/unpushed |
| Branch | `joan/wcn3990-delete-key-no-wait` |
| Source commit | `834154d6b0829b5fab79d087e1944725d25fecd0`; signed; human DCO present; Assisted-by is bare `moa/deep-flash` (not expanded); unpushed |
| Source tree | `145119754fde951ae04701a4b1f3c2e3c0cafc4e` |
| Base | `ghfork/joan/latest-clean-test` `5fbb6db354d950ee3ab7f07deca7d5524ebce518` |
| Kernel release | `7.2.0-rc2-g834154d6b082` |
| Configuration delta | none versus joan pmaports `config-lge-joan.aarch64`; input SHA-256 `cc8e94087d695135989be4b4011cbc0d9553718d89dd1b0fab82be584b4e7dcb`; effective SHA-256 `0050d84094680d182c4c9f7fbf39f79347486357278a073d60c224cbe028841c` |
| Image | **NOT BUILT** — kernel `Image.gz` and Joan DTB only |
| Image SHA-256 | N/A (no boot.img) |
| Kernel Image.gz SHA-256 | `7336888c9c18ae007a935091b1c1614e8c79dac7289e4260b3db854507ad4551` |
| Joan DTB SHA-256 | `7547b76040823108912db13d66250e26557110085908532d81c107cdb8c23dda` |
| Manifest | `out/audit-20260815/wcn3990-delete-keyfix/` |
| Construction | clean `O=/data/buildcache/kbuild/build-wcn3990-delete-keyfix-clean`; `ccache aarch64-linux-gnu-gcc`; `-j12`; `Image.gz dtbs modules` exit 0 |

Three-commit source stack:

1. `c17e83d9b91f6c3bf74e8ab666feecad4de34079` — DT binding for `qcom,skip-pairwise-delete-key-wait`
2. `a53a7ef68716833010c9bee298a09811cf6afabb` — ath10k optional pairwise delete-key wait skip
3. `834154d6b0829b5fab79d087e1944725d25fecd0` — joan `&wifi` opt-in

## 2. Authority and persistence boundary

- **Authorized action:** host-only source, build, inventory, and documentation.
- **Authorization state:** device authorization unused / not granted. Lance
  explicitly held off the RAM boot.
- **Retry status:** packaging, staging, or hardware run requires a fresh
  explicit one-shot approval that names a future boot.img SHA.
- **Persistent writes:** host project/build/docs only; no phone writes.
- **Explicitly excluded:** `fastboot boot`, flash, erase, slot changes,
  automatic retry, AP bring-up, iperf3 against the phone.
- **Controller/client discipline:** nest ADB was queried read-only for live
  state. No fastboot client was started.

## 3. Checkmark gate matrix

| Gate | Verdict | Exact result and evidence |
|---|---|---|
| Source identity | ✅ PASS | worktree HEAD `834154d6b082`; three commits signed; DTS has `qcom,skip-pairwise-delete-key-wait` |
| Full host build | ✅ PASS | `make -j12 Image.gz dtbs modules` exited 0; release `7.2.0-rc2-g834154d6b082` |
| Image payload identity | ⏳ OPEN | boot.img not packaged |
| Transport and kernel identity on device | ⏳ OPEN | not booted |
| Display/DRM | ➖ N/A | not this candidate |
| Owner-visible behavior | ⏳ OPEN | Lance asked to hold the test; no boot report |
| Touch / brightness / renderer | ➖ N/A | not this candidate |
| WLAN association | ⏳ OPEN | not booted |
| Pairwise delete-key `-110` | ⏳ OPEN | not booted; prior device evidence remains the HTT packet |
| Local/routed tethering throughput | ⏳ OPEN | harness written, iperf3 on nest/fang only; not run |
| Recovery/end state | ➖ N/A | phone left on LineageOS; ADB `LGUS9986e606d55` present at 03:32 PDT |
| Communications gate | ➖ N/A | still blocked by broader project criteria |

## 4. What changed and what was decided

### Fixed or changed

- Added an optional ath10k quirk so joan can skip the `SEC_IND` wait on
  pairwise `DISABLE_KEY` only.
- Host-qualified the exact source with a clean kernel/DTB build.
- Wrote `scripts/tether-throughput-harness.sh` for a later local iperf3 run.

### Decisions

- Treat this as a **board-opt-in workaround**, not a global ath10k timeout
  change.
- Keep waiting for real installs and group-key replacement.
- Do not claim the `-110` is fixed or that tethering is faster.
- Hold the RAM-only boot until Lance asks again.

### Rejected paths / do not replay

- **DO NOT:** replay the HTT diagnostic image `3dfad941...` merely to
  reclassify `SEC_IND`.
- **WHY:** one controlled association already split install (matched) from
  teardown (lost).
- **REOPEN ONLY IF:** new evidence shows a different command path or a new
  SMMU coincidence.
- **DO NOT:** raise the 3 s wait as the first fix.
- **WHY:** no matching delete `SEC_IND` arrived in ~190 s.
- **DO NOT:** package/boot this kernel from this packet.
- **WHY:** Lance held the test; no boot.img SHA exists to approve.

## 5. Failures and open gates

| Item | Why it remains open/failed | Required closure evidence |
|---|---|---|
| Device `-110` | never booted | one approved RAM boot + associate/disconnect logs |
| Faster tethering | no local iperf3 against joan | harness output vs Ember fang VHT80 baseline |
| boot.img identity | not packaged | stage-candidate + SHA-bound runner |
| USB-C / audio / mic / camera | different lanes | separate candidates |

## 6. Next safe action

1. Do nothing on the phone.
2. When Lance wants the test: re-hash `Image.gz`/`dtb`, package a new
   boot.img, bind a one-shot runner, ask for approval by that image SHA.
3. After one RAM boot: classify teardown `-110`, then one local iperf3
   sample. Stop.

**Stop condition:** missing hashes, second fastboot client, no fresh named
approval, or any flash request.

## 7. Evidence ledger

| Evidence | Location | SHA-256 / durable identifier | Scope |
|---|---|---|---|
| Format-patch | `out/audit-20260815/wcn3990-delete-keyfix/wcn3990-delete-key-no-wait-834154d6b082.patch` | see sidecar | source delta |
| Provenance | `.../build-wcn3990-delete-keyfix-clean.provenance.txt` | `9b9983aa560a923acb8af4d14d7b8f554ab741e5eae4a3a9e8d2bf8c3575002d` | build identity |
| Image.gz + DTB hashes | `.../build-wcn3990-delete-keyfix-clean.Image.gz.dtb.sha256` | `9d4feea4598e6e5d01334c4c98ac46c46ccada9bf035d78da2feb04734125cc8` | payload hashes |
| Kernel Image.gz | `/data/buildcache/kbuild/build-wcn3990-delete-keyfix-clean/arch/arm64/boot/Image.gz` | `7336888c9c18ae007a935091b1c1614e8c79dac7289e4260b3db854507ad4551` | host kernel |
| Joan DTB | `.../dts/qcom/msm8998-lge-joan.dtb` | `7547b76040823108912db13d66250e26557110085908532d81c107cdb8c23dda` | host DTB |
| Successor handoff | `docs/aurel-handoff-2026-08-15-to-next-session-wcn3990-delete-key-ram-test.md` | after docs commit | how to run later |

## 8. Publication and readback

- [x] Packet added to `docs/test-results/README.md`.
- [ ] `git diff --check` and repository checks pass (filled at commit).
- [ ] Public/private safety scan for destination.
- [ ] Signed docs commit with human DCO + canonical Assisted-by.
- [ ] Exact commit pushed to the documentation repository.
- [ ] Shared Deck card updated.
- [ ] GitHub and Deck read back.

Push and Deck are coordination extras. Local commit + private WebDAV handoff
are the required successor delivery.

## 9. Public attribution

- **Owner/operator:** Lance
- **Assisted-by:** Hermes-Agent:xai-oauth/grok-4.6
- **Packet date:** 2026-08-15
- **Update-scope:** Host-only seal of the pairwise delete-key quirk; RAM test
  held by owner request.

Assisted-by: Hermes-Agent:xai-oauth/grok-4.6
Date: 2026-08-15

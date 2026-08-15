# WCN3990 HTT key diagnostic closure — association succeeds; no teardown delete SEC_IND observed

> **One exact RAM-only diagnostic boot and one controlled association were
> executed on 2026-08-15. The one-shot authorization and runner are consumed.
> Do not replay this image or association merely to repeat the classification.**

- **Candidate:** WCN3990 key-install HTT debug on the channel-169-fixed baseline
- **Date tested:** 2026-08-15, America/Los_Angeles
- **Disposition:** CLOSED — CLASSIFIED
- **Supersedes:** the association-time interpretation in the pre-diagnostic
  `ember-handoff-2026-08-15-wifi-ap-and-key-install.md`
- **One-line result:** the association-time pairwise key received a matching
  `SEC_IND` and connected; no matching indication was observed for the later
  pairwise `DEL_KEY` on controlled client teardown, which timed out with `-110`
  after three seconds. This is lost from the host's perspective; whether the
  firmware generated a delete acknowledgement remains open.

## 1. Exact identity

| Field | Exact value |
|---|---|
| Intended/current baseline repository | `~/vibe-coding-projects/coding/linux-mainline-v30-a540-hwinit-gate` |
| Intended/current baseline branch | `joan/a540-suspend-hwinit-gate` |
| Intended/current baseline commit | `519646f017022e1fc8cfd70bd2a69f6087b89450`; signed, clean at audit time, present on `ghfork/joan/latest-clean-test` and `ghfork/master` |
| Intended/current baseline tree | `19a4ce54097722ef7680e6d0e56a96bd70175e93` |
| Kernel release | `7.2.0-rc2-gd05e70c5e484-dirty` |
| Exact build-source provenance | **Unproven/inherited from the source AP image.** The dirty runtime release does not establish that the image was built from commit `519646f01`. |
| Configuration delta | none; only boot command line gained `ath10k_core.debug_mask=0x8` |
| Image | ignored local evidence: `out/audit-20260815/keyinstall-httdebug-519646f01/boot-joan-keyinstall-httdebug-519646f01.img` |
| Image SHA-256 | `3dfad94194d3bedef972eed11c7c9a37aa1cee3427042682605b03479171b19f` |
| Source image SHA-256 | `bb7362e981cc3686648557c169732abce55ba969e0347a3a7c71fba8bb0630cf` |
| Portable evidence manifest | ignored local evidence: `out/audit-20260815/keyinstall-httdebug-519646f01/EVIDENCE-MANIFEST.sha256` |
| Manifest SHA-256 | `967b24979d4ae3edaf3f8cee05aef8bf6637bfb783b47cdf3e4e436e2dbdbcaa`; 35/35 files verified |
| Construction | unpacked kernel and ramdisk are byte-identical to the source image; only the header cmdline differs by the HTT debug parameter |
| Device run | `keyinstall-httdebug-20260815T0045Z` |

Unpacked component verification:

- kernel SHA-256, source and candidate:
  `fc9185611bda3d39e3734124d1cbb8f61b7ee4400619d29222fbf9bd98b92943`;
- ramdisk SHA-256, source and candidate:
  `7ef44210e02b2a11dcf0775a4d6f316edb0d00195fc574c9978887570a5f7804`;
- runtime `/proc/cmdline` contained `ath10k_core.debug_mask=0x8` and the effective
  sysfs value was exactly `8`.

## 2. Authority and persistence boundary

- **Authorized action:** one fail-closed RAM-only boot of the exact candidate,
  one controlled hostapd association, evidence capture, and normal recovery to
  installed Android while Lance was physically available.
- **Authorization state:** consumed.
- **Retry status:** forbidden for this exact image/runner without fresh approval.
- **Persistent phone writes:** none. No phone partition was flashed, erased, or
  slot-switched.
- **Explicitly excluded:** candidate flash, erase, slot change, repeated
  association, automatic candidate retry, and any second causal variable.
- **Controller/client discipline:** `nym-nest-family` was the sole USB host;
  `nym-fang-family` made exactly one association attempt.

## 3. Checkmark gate matrix

| Gate | Verdict | Exact result and evidence |
|---|---|---|
| Transport and kernel identity | ✅ PASS | Hash-bound runner passed; one `fastboot boot`; pmOS USB came up; live uname and effective debug mask were captured. |
| Single-variable construction | ✅ PASS | Kernel and ramdisk match the AP baseline byte-for-byte; only cmdline gained `ath10k_core.debug_mask=0x8`. |
| Controlled association | ✅ PASS | Exactly one nym-fang attempt; AP `be:a7:df:92:bf:78`, client `e4:5f:01:07:fc:f3`, channel 36/VHT80. |
| Association-time key indication | ✅ PASS | Client mapped to peer 30; pairwise `NEW_KEY` at 731.568572; matching `SEC_IND peer_id 30 unicast 1 type 6` at 731.589262. |
| WPA2 handshake/client state | ✅ PASS | Hostapd logged pairwise handshake complete; client logged `WPA: Key negotiation completed` and `CTRL-EVENT-CONNECTED`. |
| Teardown key deletion | ❌ FAIL | Client-originated reason-8 disassociation at 743.699674; pairwise `DEL_KEY` at 743.709249; generic ath10k `-110` at 746.976115; no later `SEC_IND` through seal at 936.982182. |
| SMMU correlation | ✅ PASS for discriminator | WLAN stream-0x1900 fault count was 5 before association and remained 5 through timeout/seal; no contemporaneous fault. |
| Modem/firmware stability | ✅ PASS for run | Zero fatal errors, crashes, or AMSDU extraction failures. |
| Recovery/end state | ✅ PASS | ADB serial `LGUS9986e606d55`, `sys.boot_completed=1`, Android 13 / LG-US998; pmOS USB interface absent and ping failed as expected. |
| Owner-visible behavior | ⏳ OPEN | No physical display/touch acceptance was requested or inferred; outside this diagnostic scope. |
| Communications gate | ✅ PASS only for one WPA2 association | No broad Wi-Fi soak, throughput, cellular, or Bluetooth claim is made. |

## 4. What changed and what was decided

### Fixed or changed

- No kernel source or persistent device state changed.
- Enabled `ATH10K_DBG_HTT` for one boot and correlated AP, kernel, and client
  evidence across one association and its controlled teardown.

### Decisions

- The observed association-time PTK indication is **matched and on time**.
- The captured `-110` belongs to the **DISABLE_KEY / pairwise teardown path**.
  No matching `SEC_IND` was observed through the long tail: **lost from the
  host's perspective**, not late or mismatched. This does not prove transport
  loss; the firmware may never have generated a delete acknowledgement.
- The generic `failed to install key` warning obscures whether the operation was
  enable or disable and must not be interpreted without call-boundary evidence.
- The existing WLAN SMMU faults remain real but are not the proximate cause of
  this timeout because no new fault occurred in the relevant window.

### Rejected paths / do not replay

- **DO NOT REPLAY:** this exact image/runner or another association merely to
  repeat the lost/late split.
- **DO NOT CLAIM:** that this run reproduced a wrong-password or failed initial
  four-way handshake; it connected successfully.
- **DO NOT START WITH:** a globally longer timeout. No teardown indication
  appeared in the roughly 190-second captured tail.
- **DO NOT PRIORITIZE:** SMMU changes for this occurrence absent a future timeout
  that coincides with a new stream-0x1900 fault.
- **REOPEN ONLY IF:** new instrumentation identifies a different command at the
  timeout boundary, downstream/CAF shows a required delete indication, or a
  future run produces contradictory correlated evidence.

## 5. Failures and open gates

| Item | Why it remains open/failed | Required closure evidence |
|---|---|---|
| Firmware delete-ack contract | This run proves no matching indication was observed by the host, not whether WCN3990 firmware generated one or is expected to send one for deletion. | Downstream/CAF source or trace establishing the intended delete behavior. |
| Precise ath10k wait attribution | Hostapd `DEL_KEY` plus the three-second blocking interval and call path prove teardown attribution, but the driver warning does not print command/key details. | Instrument command, peer, key index/flags, and wait begin/end around `ath10k_install_key()`. |
| NetworkManager/hostapd split | Association is no longer the discriminating boundary. | Compare disconnect/key-delete sequences with equivalent instrumentation. |
| SMMU fault root cause | Five real boot/AP-start faults remain unexplained. | Independent investigation; reprioritize only if a key timeout and new SMMU fault coincide. |

## 6. Next safe action

1. Perform host-only downstream/CAF archaeology for WCN3990 key deletion and
   `SEC_IND` expectations.
2. Prepare instrumentation-only source that logs `SET_KEY` versus `DISABLE_KEY`,
   peer, key index/flags, and exact wait boundaries; host-qualify it without
   booting.
3. Seek fresh approval only if a new device test is still needed after the
   source comparison.

**Stop condition:** do not change timeout behavior or skip waits until the
firmware delete-ack contract is established and the operation boundary is
explicitly instrumented.

## 7. Evidence ledger

Raw evidence is local/ignored and SHA-sealed; paths are relative to
`lg-v30-port` unless stated otherwise.

| Evidence | Location | SHA-256 / durable identifier | Scope |
|---|---|---|---|
| Exact candidate image | `out/audit-20260815/keyinstall-httdebug-519646f01/boot-joan-keyinstall-httdebug-519646f01.img` | `3dfad94194d3bedef972eed11c7c9a37aa1cee3427042682605b03479171b19f` | RAM-boot artifact |
| Portable run manifest | `out/audit-20260815/keyinstall-httdebug-519646f01/EVIDENCE-MANIFEST.sha256` | `967b24979d4ae3edaf3f8cee05aef8bf6637bfb783b47cdf3e4e436e2dbdbcaa`; 35/35 PASS | complete ignored evidence bank |
| Phone dmesg | `.../device-run-keyinstall-httdebug-20260815T0045Z/device/dmesg-full.log` | `488ea4f3e967c12e4cd16c1318ed4694fa185951e610e89ee7a2db05385cf6f8` | HTT, SMMU, timeout timeline |
| Hostapd debug | `.../device-run-keyinstall-httdebug-20260815T0045Z/device/hostapd-debug.log` | `83f7d9c3a2c0482189281fb14dfbcf64721154589d139fc08b7888e5f58d5251` | `NEW_KEY`, handshake, `DEL_KEY` |
| Client debug | `.../device-run-keyinstall-httdebug-20260815T0045Z/fang-client-debug.log` | `d713f5efde9ddd54f2ac8db3800094c409cbb2cb7f7031ad14dd5ed0859fe12e` | client connection/teardown |
| Android recovery verification | `.../device-run-keyinstall-httdebug-20260815T0045Z/recovery-android-verification.txt` | `6ef3f0153fcc1df41b07aa28ca03305fadf1a94d4c3e44ee90c4797447201a33` | installed-OS end state |
| Device-host copy | `nym-nest-family:~/joan-images/evidence/keyinstall-httdebug-20260815T0045Z/` | retained source artifacts | independent durable copy |

The logs contain `[REMOVED]` for PSK material. Raw AP/client configuration files
containing the credential are not part of this evidence bank.

## 8. Publication and readback

- [x] Packet added locally to `docs/test-results/README.md` in this change.
- [x] Local repository and evidence-manifest checks are required before commit.
- [x] Public/private safety scan is required before commit.
- [ ] Exact docs commit pushed to the documentation repository.
- [ ] Shared Deck card receives the same classification, no-replay rule, and next action.
- [ ] GitHub and Deck are read back from their original sources.

The unchecked items remain external-action gates and are not implied complete.

## 9. Public attribution

- **Owner/operator:** Lance / ShapeShifter499
- **Assisted-by:** `Hermes-Agent:moa/deep-flash`
- **Packet date:** 2026-08-15
- **Update-scope:** one-variable HTT diagnostic, one controlled WPA2 association,
  teardown timeout classification, evidence seal, and Android recovery.

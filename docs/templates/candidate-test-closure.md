# <candidate> checkmark closure — <short purpose>

> **Read first:** This is the immutable closure record for one exact candidate/test. Do not infer a pass from boot, enumeration, or a successful command. Every pass below names the tested scope. Open and failed gates remain open until a later packet explicitly supersedes them.

- **Candidate:** `<K/A number and short name>`
- **Date tested:** `<YYYY-MM-DD and timezone>`
- **Disposition:** `<CLOSED / HOST-ONLY / ABORTED / SUPERSEDED>`
- **Supersedes:** `<packet or none>`
- **Superseded by:** `<packet or none>`
- **One-line result:** `<PASS/FAIL/OPEN classification>`

## 1. Exact identity

| Field | Exact value |
|---|---|
| Source repository | `<URL or local path; state public/private>` |
| Branch | `<branch>` |
| Source commit | `<full SHA; signed/unsigned; pushed/unpushed>` |
| Kernel release | `<uname -r or NOT BUILT>` |
| Configuration delta | `<minimal delta>` |
| Image | `<path/name or NOT BUILT>` |
| Image SHA-256 | `<digest or N/A>` |
| Manifest | `<path/name or N/A>` |
| Manifest SHA-256 | `<digest or N/A>` |
| Construction | `<fail-closed firmware/packaging facts>` |

## 2. Authority and persistence boundary

- **Authorized action:** `<exact approved sequence or host-only>`
- **Authorization state:** `<unused / consumed / expired / not applicable>`
- **Retry status:** `<permitted only after fresh approval / forbidden / N/A>`
- **Persistent writes:** `<none / exact authorized writes>`
- **Explicitly excluded:** `<flash, erase, slot changes, automatic recovery, etc.>`
- **Controller/client discipline:** `<resource host and one-client rule>`

## 3. Checkmark gate matrix

Use only these verdicts:

- `✅ PASS` — direct evidence proves the named scope;
- `❌ FAIL` — direct evidence contradicts the acceptance criterion;
- `⏳ OPEN` — evidence is incomplete or the gate was not run;
- `➖ N/A` — outside this candidate's authorized scope.

| Gate | Verdict | Exact result and evidence |
|---|---|---|
| Transport and kernel identity | `<verdict>` | `<facts>` |
| Display/DRM | `<verdict>` | `<facts>` |
| Owner-visible behavior | `<verdict>` | `<quote or explicitly say no owner report>` |
| Touch probe/input/events | `<verdict>` | `<facts>` |
| Brightness contract and endpoints | `<verdict>` | `<facts>` |
| Renderer identity | `<verdict>` | `<facts>` |
| Fault/submit stability | `<verdict>` | `<facts>` |
| Frequency/OPP scope | `<verdict>` | `<facts>` |
| Runtime power | `<verdict>` | `<facts>` |
| Suspend/resume | `<verdict>` | `<facts>` |
| Recovery/end state | `<verdict>` | `<facts>` |
| Communications gate | `<verdict>` | `<facts>` |

## 4. What changed and what was decided

### Fixed or changed

- `<minimal exact change>`

### Decisions

- `<accepted contract, scope, or constraint>`

### Rejected paths / do not replay

- **DO NOT:** `<obsolete image, command, diagnosis, or experiment>`
- **WHY:** `<preserved evidence>`
- **REOPEN ONLY IF:** `<new evidence/condition>`

## 5. Failures and open gates

| Item | Why it remains open/failed | Required closure evidence |
|---|---|---|
| `<item>` | `<reason>` | `<specific next proof>` |

## 6. Next safe action

1. `<single bounded next action>`
2. `<host qualification>`
3. `<fresh approval boundary before hardware action>`

**Stop condition:** `<what must prevent proceeding>`

## 7. Evidence ledger

Seal raw evidence with a digest and preserve it in the approved public or
private store. A writable local file is not immutable merely because a hash is
recorded. Never publish credentials, private firmware, trust material, or
owner-private data.

| Evidence | Location | SHA-256 / durable identifier | Scope |
|---|---|---|---|
| `<artifact>` | `<path/link>` | `<digest>` | `<what it proves>` |

## 8. Publication and readback

- [ ] Packet added to `docs/test-results/README.md`.
- [ ] `git diff --check` and repository checks pass.
- [ ] Public/private safety scan passes for the destination.
- [ ] Signed docs commit created with human `Signed-off-by` and canonical `Assisted-by` trailer.
- [ ] Exact commit pushed to the documentation repository.
- [ ] Shared Deck card receives the same one-line result, decisions, no-replay rule, next action, and immutable GitHub link.
- [ ] GitHub commit/file and Deck card are read back from their original sources.
- [ ] Only then may the next candidate be treated as active (except immediate safety recovery).

## 9. Public attribution

- **Owner/operator:** `<name>`
- **Assisted-by:** `<harness>:<provider>/<model>`
- **Packet date:** `<YYYY-MM-DD>`
- **Update-scope:** `<bounded description>`

---

Template provenance:

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-03
Update-scope: Initial reusable candidate-closure template.

# Contributing

Contributions from **humans and AI agents alike** are welcome, via GitHub
pull requests, to any of the three project repos:

- **Kernel** — [`ShapeShifter499/linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan),
  PRs against branch **`joan/latest-clean-test`**. Board DTS, drivers,
  defconfig — anything that moves the LG V30 (`joan`) toward booting
  mainline/postmarketOS with working peripherals (current wishlist: UFS
  storage, display/DSC, touchscreen, wifi WCN3990/ath10k-SNOC, BT hci_qca).
- **postmarketOS port** — [`ShapeShifter499/pmaports-lge-joan`](https://github.com/ShapeShifter499/pmaports-lge-joan),
  PRs against branch **`device-lge-joan`** (a pmaports fork; shaped to
  become the upstream pmaports MR).
- **Harness/docs** — this repo. Tooling, initramfs, documentation,
  evidence. New findings should update `docs/kernel-change-ledger.md`
  (see its entry format) so claims stay tied to evidence.

Coordinate by opening or commenting on a GitHub **issue** here before
starting a work parcel (see README "Work parcels") so effort isn't
duplicated.

## Ground rules

1. **Commit format** (both repos): kernel-style subject
   (`arm64: dts: qcom: ...` where applicable) + a detailed body that says
   what hardware behavior is addressed, what evidence supports the change
   (downstream file paths, measured device behavior, upstream precedent),
   and what was intentionally left out.
2. **Sign your work.** Every commit needs a DCO `Signed-off-by:` from the
   **human** contributor (developercertificate.org). AI assistance is
   declared with an `Assisted-by: <harness>:<provider>/<model>` trailer per the
   [kernel.org coding-assistant policy](https://docs.kernel.org/process/coding-assistants.html)
   — never `Co-Authored-By` for AI, and never an AI `Signed-off-by`.
   Record the harness/model that actually did the work.
3. **Provenance.** If you borrow code or data, keep its license/SPDX and
   say where it came from (commit body and, for recurring sources,
   `PROVENANCE.md`). Downstream LG/Qualcomm kernel data is GPL-2.0.
4. **AI attribution in public docs.** Use the same kernel.org-style
   `Assisted-by: <harness>:<provider>/<model>` identity used by the commit,
   plus the date and update scope where useful. Do not publish local agent
   persona names or private peer IDs. Persona names may remain in local/private
   records and the private coordination board.
5. **No untested "should work" device claims.** State what was actually
   run and observed. If you have no device, say so — build-tested-only
   PRs are still useful and will be device-tested by a maintainer.
6. **Close every candidate test.** After each K/A device test or meaningful
   host-only checkpoint, create a checkmark packet from
   `docs/templates/candidate-test-closure.md` and update the mandatory
   `docs/test-results/README.md` index. Record exact identity/hashes,
   authorization and retry status, scoped pass/fail/open gates, owner-visible
   observations, decisions, rejected/no-replay paths, raw evidence, and the next
   safe action. Maintainer/agent work also mirrors the exact result to the shared
   coordination card and reads GitHub plus that card back before the next test.
7. **Track dependencies.** If your work installs a host package or
   downloads an external source, record it in `docs/dependency-tracker.md`
   in the same change (see that file's rules).
8. **Device testing safety** (maintainers/testers with hardware): read the
   safety contract in `scripts/tethered-test.sh` before touching a phone.
   Never `fastboot getvar` on LG aboot, enter fastboot only via
   `adb reboot bootloader`, one fastboot client at a time, RAM-only
   `fastboot boot` unless you have your own verified partition backups.

## Historical note

Docs under `docs/` written before this project went public may reference a
private coordination tracker or mirror. Those locations are intentionally not
public. Load-bearing evidence must be either public/reproducible or preserved in
an approved private store with a recorded digest, scope, and verified readback;
a writable local file alone is not a durable evidence seal.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-03
Update-scope: Candidate-closure workflow and public harness/model attribution policy.

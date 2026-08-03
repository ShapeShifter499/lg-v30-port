# Provenance — what is borrowed, what is new

This project is a mainline Linux bringup for the LG V30 (`joan`, US998,
MSM8998). Kernel work lives in
[`ShapeShifter499/linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan)
branch `joan/latest-clean-test`; this repo holds the tooling, docs, and
evidence. Per-change evidence with hashes is in
`docs/kernel-change-ledger.md`; the actor/timeline index is in
`docs/project-history-and-attribution.md`.

## Authorship model

Public attribution identifies AI assistance only by the harness and exact model
route. Local agent persona names and private peer IDs are intentionally omitted
from public docs and trailers; they may still be used in local/private records
and the private coordination board.

All kernel commits are authored and DCO-signed by Lance
(`Signed-off-by: Lance <Gero3977@gmail.com>`). AI assistance is recorded
per the kernel.org coding-assistant policy with `Assisted-by:` trailers
naming the actual harness and model route that did the work
(`Claude-Code:claude-fable-5`,
`Hermes-Agent:openai-codex/gpt-5.6-sol`) — never `Co-Authored-By`, never
an AI `Signed-off-by`. Public docs use the same harness/model-only
`Assisted-by:` form.

### Historical Hermes Agent trailer normalization

The provider-qualified Hermes Agent convention was adopted on 2026-07-19.
Earlier commits and documentation may use shorter or persona-bearing forms.
The public harness/model normalization is:

- `Hermes:gpt-5.4` means `Hermes-Agent:openai-codex/gpt-5.4`.
- `Hermes:gpt-5.5` means `Hermes-Agent:openai-codex/gpt-5.5`.
- `Hermes:gpt-5.6-sol` means
  `Hermes-Agent:openai-codex/gpt-5.6-sol`.
- Any older persona-prefixed Hermes form maps to the provider-qualified
  `Hermes-Agent:openai-codex/<model>` value carried by the same entry.

These mappings clarify attribution only. Existing commit objects and SHAs
are intentionally preserved; no historical author, human DCO sign-off,
content, or assistant-model claim is rewritten. New Hermes Agent-assisted
commits and public docs use `Assisted-by: Hermes-Agent:<provider>/<model>`.

### Legacy technical identifiers

Historical artifact filenames, one experimental DT property, and captured
debug strings may retain legacy labels verbatim because hashes, logs, and
source snapshots use those exact identifiers. They are immutable technical
handles, not public AI attribution. Current document paths and attribution
entries use neutral subjects plus harness/model identities.

## Written new for this project

- `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts` (kernel repo) — new
  board DTS, structured after existing mainline msm8998 boards, with
  values derived from the sources cited per commit (see below).
- `initramfs/root/init`, `initramfs/root-null/init` — busybox bringup /
  classifier init scripts.
- `initramfs/src/wdkill.c` — small register-level APSS watchdog
  disable/pet tool (built static; source included here).
- `scripts/tethered-test.sh`, `scripts/read-pstore-partition.sh`,
  `scripts/read-imem-reset-reason.sh`, `make-testimage.sh` — host-side
  test/observability tooling.
- All documentation under `docs/`.

## Borrowed / derived / referenced

- **LG/Qualcomm downstream kernel** (LineageOS
  `android_kernel_lge_msm8998`, GPL-2.0): source of truth for ramoops
  layout, reserved-memory/XPU map, watchdog parameters, and the
  TLMM/pinctrl and fingerprint-SPI evidence behind the
  `gpio-reserved-ranges` commit. Values were re-derived and re-expressed
  for mainline; where downstream code shaped a change, the commit message
  cites the exact downstream files. Treat derived DTS data as GPL-2.0.
- **Mainline msm8998 board DTS files** (`msm8998-mtp`, `-clamshell`,
  `-oneplus-common`, `-xiaomi-sagit`, `-sony-xperia-yoshino`; GPL-2.0/BSD
  per their SPDX headers): structural template for the joan DTS and
  precedent for the `<81 4>` reserved GPIO range.
- **busybox** (GPL-2.0): prebuilt static binary from Alpine's
  `busybox-static-1.37.0-r31` package (apk retained at
  `initramfs/busybox-static-1.37.0-r31.apk`); source at
  https://git.alpinelinux.org/aports and busybox.net.
- **mkbootimg** boot-image parameters: from LineageOS
  `android_device_lge_joan-common` `BoardConfigCommon.mk`.
- **edk2-msm8998** (https://github.com/edk2-porting/edk2-msm8998):
  consulted as a behavioral reference (a passive UEFI that survives on
  joan); no code taken.
- **Device evidence**: pstore/ramoops captures, PON/boot-reason
  registers, and boot-timing classifications from Lance's own US998
  hardware, recorded under `out/` and hashed in the ledger.

## Firmware distribution boundary

GPU firmware is deliberately separate from this public tooling/docs repository:

- `qcom/a530_pfp.fw` and `qcom/a530_pm4.fw` are supplied by the
  postmarketOS `firmware-qcom-adreno-a530` package from `linux-firmware`.
  They are not vendored here.
- LG A540 GPMU and signed ZAP firmware are owner-extracted proprietary
  artifacts. They remain local and ignored; a missing artifact must make image
  or package construction fail closed.
- The local `firmware-lge-joan` recipe depends on the official A530 package,
  installs only the owner-supplied A540 payload, and supplies the mkinitfs list
  for all seven early-probe files. The recipe may carry expected hashes and
  provenance requirements, but not the proprietary bytes themselves.
- GPU/display wiring remains reviewable source in the joan DTS, kernel config,
  and driver patch stack; it is not hidden inside the firmware package.

The firmware files were accidentally added to this repository in historical
commit `ef1803ee19c523ec2c0a06e1f2b48d92dcbd62c1`. They are removed from the
branch tip in the 2026-08-03 candidate-closure publication commit, together
with the ignore rules and provenance boundary documented here. Per maintainer
direction, no public-history rewrite was performed; historical objects are
unchanged and require a separate explicit remediation decision if they are ever
to be purged.

## Publication-security redaction

The 2026-08-03 publication pass removed or generalized, at the current tip
only:

- private assistant/persona labels and peer IDs from prose, filenames, and
  attribution blocks (historical documents renamed from `ember-handoff-*` /
  `aurel-handoff-*` to `handoff-*` follow the same policy);
- private host aliases, absolute home paths, backup-mount paths, and internal
  mirror/tracker paths;
- one exposed credential (rendered `[REDACTED]`; see the credential section);
- all tracked A530/A540 firmware bytes and their index entries (see the
  firmware boundary above).

Local-only artifact filenames under `out/` may still carry legacy assistant
labels on disk; public prose references to those artifacts were generalized
and are identified by their recorded hashes, not by filename.

## Historical credential redaction

Older public objects contained a literal password for the RAM-booted pmOS test
user. The current branch tip replaces every working-tree occurrence with
`[REDACTED]`; one additional unpublished ledger copy was also removed before
publication. No history rewrite was performed, so the credential must be treated
as compromised and must never be reused in a future image, package, or service.
Future candidates should use a fresh owner-controlled secret or key-only access
without placing credential material in Git.

Assisted-by: Claude-Code:claude-fable-5
Date: 2026-07-10
Update-scope: Initial provenance inventory.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-03
Update-scope: A530/A540 firmware-distribution boundary and current-tip credential redaction.

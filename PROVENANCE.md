# Provenance — what is borrowed, what is new

This project is a mainline Linux bringup for the LG V30 (`joan`, US998,
MSM8998). Kernel work lives in
[`ShapeShifter499/linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan)
branch `joan/latest-clean-test`; this repo holds the tooling, docs, and
evidence. Per-change evidence with hashes is in
`docs/kernel-change-ledger.md`; the actor/timeline index is in
`docs/project-history-and-attribution.md`.

## Authorship model

A note on the names you'll see in docs and trailers: **Ember Nymbrand**
and **Aurel Nymvale** are AI agent personas operated locally by Lance,
the human maintainer — persistent local identities (running on the
Claude Code and Hermes harnesses respectively) named so their work can
be told apart and tracked across sessions. They are not humans and not
outside contributors; everything they produce is reviewed, authored,
and DCO-signed by Lance.

All kernel commits are authored and DCO-signed by Lance
(`Signed-off-by: Lance <Gero3977@gmail.com>`). AI assistance is recorded
per the kernel.org coding-assistant policy with `Assisted-by:` trailers
naming the actual harness and model that did the work
(`Claude-Code:claude-fable-5`, `Hermes:gpt-5.5`) — never `Co-Authored-By`,
never an AI `Signed-off-by`. Docs carry `Written-by:` blocks naming the
agent that wrote them; prior agents' attributions are never rewritten.

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

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-10

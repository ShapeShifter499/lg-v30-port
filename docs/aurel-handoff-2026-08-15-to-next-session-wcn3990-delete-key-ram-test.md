# Aurel handoff to next session: held-off WCN3990 delete-key RAM test

- **From:** Aurel Nymvale
- **To:** next Hermes/Aurel/Ember session on this host
- **Written-by:** Aurel Nymvale
- **Agent-harness:** Hermes-Agent:xai-oauth/grok-4.6
- **Date:** 2026-08-15, America/Los_Angeles
- **Standing Lance instruction this serves:** continue LG V30 postmarketOS
  bring-up; work the `-110` WLAN issue; verify faster tethering; later USB-C
  OTG/role-switch, sound/Quad DAC, microphone, and camera. This document is
  only about the next WLAN/tether device test. The later lanes are not this
  test.

## Read this first

Lance asked to **hold off on the device test**. Do not package a boot image,
do not stage a runner, do not request approval, and do not `fastboot boot`
from this handoff. The kernel source and host `Image.gz`/`dtb` are sealed.
The RAM-only image is **not** built.

A later session may run the test only after a **fresh explicit one-shot
approval**. Silence is not consent. Compaction recovery is not authorization.

## Live device state (checked 2026-08-15 03:32 PDT)

Separate from source/build state:

- Resource host: `nym-nest` (`nym-nest-family`)
- ADB: `LGUS9986e606d55` `device` USB `1-1.5`, product `lineage_joan`,
  model `LG_US998`
- USB: `18d1:4ee7` Google Nexus/Pixel Device (charging + debug)
- Fastboot clients: none
- Installed OS: LineageOS, healthy
- No mainline image was booted this session
- Prior AP/NAT leftovers on nest/fang were already cleaned by Ember

## Source / build state

### Kernel worktree

- Path: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-wcn3990-keyfix`
- Branch: `joan/wcn3990-delete-key-no-wait`
- Ahead of `ghfork/joan/latest-clean-test` by 3 signed commits
- Base: `5fbb6db354d950ee3ab7f07deca7d5524ebce518`
- HEAD: `834154d6b0829b5fab79d087e1944725d25fecd0`
- Tree: `145119754fde951ae04701a4b1f3c2e3c0cafc4e`
- Worktree was clean after the three commits
- Not pushed. `origin` in that repo is torvalds/linux. Never push there.
  Public fork is `ghfork` = `github.com/ShapeShifter499/linux-lg-v30-joan`

Three-commit stack:

1. `c17e83d9b91f6c3bf74e8ab666feecad4de34079` —
   `dt-bindings: net: wireless: ath10k: add delete-key wait quirk`
2. `a53a7ef68716833010c9bee298a09811cf6afabb` —
   `wifi: ath10k: make pairwise delete-key waiting optional`
3. `834154d6b0829b5fab79d087e1944725d25fecd0` —
   `arm64: dts: qcom: msm8998-lge-joan: skip pairwise delete-key wait`

Exact property: `qcom,skip-pairwise-delete-key-wait` on `&wifi` in
`arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts`. SNOC probe copies it into
`ar->skip_pairwise_delete_key_wait`. `ath10k_install_key()` returns 0 without
waiting only when `cmd == DISABLE_KEY && !(flags & WMI_KEY_GROUP)` and the
quirk is set. Installs and group-key replacement still wait 3s for `SEC_IND`.

Publication caveat: those three kernel trailers say
`Assisted-by: Hermes-Agent:moa/deep-flash` without the expanded
aggregator/advisors form. They are local/unpushed. Do not rewrite unless Lance
asks; do not publish as-is.

### Host-qualified build (complete)

Clean full rebuild, exit 0, process `proc_711dd117c93a`:

- Out dir: `/data/buildcache/kbuild/build-wcn3990-delete-keyfix-clean`
- Input config:
  `lg-v30-pmos-prealpha/pmaports-overlay/device/testing/linux-lge-joan/config-lge-joan.aarch64`
- input_config_sha256: `cc8e94087d695135989be4b4011cbc0d9553718d89dd1b0fab82be584b4e7dcb`
- effective_config_sha256: `0050d84094680d182c4c9f7fbf39f79347486357278a073d60c224cbe028841c`
- compiler: `aarch64-linux-gnu-gcc (GCC) 16.1.0`
- kernelrelease: `7.2.0-rc2-g834154d6b082`
- Image.gz SHA-256: `7336888c9c18ae007a935091b1c1614e8c79dac7289e4260b3db854507ad4551`
- msm8998-lge-joan.dtb SHA-256: `7547b76040823108912db13d66250e26557110085908532d81c107cdb8c23dda`

Evidence bank:
`lg-v30-port/out/audit-20260815/wcn3990-delete-keyfix/`

That directory has the format-patch, metadata, provenance, and SHA sidecars.
`image_built=NO` in the early metadata file meant **no boot.img**. The kernel
and DTB now exist; the boot image still does not.

Known config gap inherited from Ember: `CONFIG_NF_TABLES` absent,
`CONFIG_IP_NF_IPTABLES=m`. A RAM boot cannot load modules, so in-kernel NAT
on joan will still fail. Keep NAT on nym-nest if internet tethering is needed.
Local iperf3 joan-AP ↔ fang does not need NAT.

## Why this test exists

Ember's 2026-08-15 HTT diagnostic
(`docs/test-results/WIFI-KEYINSTALL-HTT-2026-08-15.md`) classified the residual
`-110` as pairwise `DEL_KEY` teardown with **no matching `SEC_IND`** through a
~190 s tail. Association `NEW_KEY` matched peer 30 in ~21 ms. SMMU stream
`0x1900` stayed 5→5. Do **not** replay that diagnostic image merely to repeat
the split.

Upstream-shaped context (not a merged mainline patch): Richard Acayan
`[RFC PATCH 2/2] wifi: ath10k: only wait for response to SET_KEY`
(mail-archive `msg17566`, 2026-02-09). James Prestwood reports the same
timeout on QCA6174 and has carried an identical skip. Baochen Qiang could not
reproduce and preferred a 1 s timeout rather than dropping the wait, because
a late `DELETE_KEY` completion might be mistaken for a later `SET_KEY`.
Prestwood replied that even 1 s delayed Cisco/Aeronet roams into deauth.

This joan quirk is **board-opt-in**, pairwise-delete only. It is a justified
fix shape, not a device-proven fix.

Do not globally raise the 3 s timeout as the first experiment. Ember already
rejected that: no delete indication arrived in the long tail.

## The held-off test (do not run now)

### Goal

One RAM-only boot of the sealed `834154d6b082` kernel+DTB to answer:

1. Does pairwise teardown still print
   `failed to install key for vdev 0 peer ... -110`?
2. After a successful association, can a local iperf3 run complete without
   that teardown stall, and what is the reproducible local rate?

### Preconditions the next agent must re-check

1. Phone still LineageOS, ADB authorized, no second fastboot client.
2. Rebuild or reuse the sealed `Image.gz`/`dtb` only after re-hashing them.
   If either hash drifted, stop and rebuild; do not boot a mystery payload.
3. Package a **new** hash-bound boot.img with the proven pmOS ramdisk lineage
   (see nest `~/joan-images/staging/stage-candidate.sh`). Append DTB to
   `Image.gz`, `mkbootimg` ramdisk_offset `0x02000000`, no flash.
4. Bind the one-shot runner to that image SHA. One `fastboot boot`. Enter
   fastboot only via `adb reboot bootloader`. Never `fastboot getvar`.
5. Ask Lance for a native 24 h approval that names the image SHA. Do not
   treat this handoff, a restored todo, or a compacted summary as approval.

### Suggested on-device sequence after a future approved boot

Reuse Ember's tmpfs-only AP recipe, not a persistent apk install:

- `rmtfs -r -P -s`
- hostapd v2.12 from tmpfs, channel 36 VHT80, WPA2, same SSID class as the
  HTT diagnostic (do not write credentials into git)
- dnsmasq on `10.42.0.1/24`
- Associate **nym-fang** (`e4:5f:01:07:fc:f3` last time), not nest, for the
  primary WLAN hop
- NAT on nest only if a routed/internet sample is also wanted
- Capture dmesg/hostapd/client logs around associate **and** controlled
  disconnect
- Then run
  `lg-v30-port/scripts/tether-throughput-harness.sh`
  with `CLIENT_HOST=nym-fang-family` against joan `10.42.0.1`

iperf3 is already installed:

- nest: iperf 3.21
- fang: iperf 3.18

No iperf3 was installed on the phone.

### Pass / fail / open

| Gate | Pass | Fail | Still open even on pass |
|---|---|---|---|
| Teardown `-110` | no pairwise `DEL_KEY` `-110` on controlled disconnect | same `-110` still appears | firmware still may omit `SEC_IND`; this only proves the host no longer waits |
| Association | WPA2 connected, matching install `SEC_IND` still prompt | association itself fails | prior successful install is already proven on the old image |
| Local throughput | 20–30 s iperf3 completes; record Mbps + PHY | transfer dies or association drops | "faster than internet speedtest" is not a criterion |
| Recovery | LineageOS back, no flash | unfamiliar USB / no LOS | helper exit 1 can be a false negative; verify ADB directly |

Baseline to beat, from Ember's internet-path table (not a local iperf3
harness): fang VHT80 AP→client 63.1 / 67.5 / 65.1 Mbps; nest HT40 33.6 Mbps.
Local iperf3 may differ. Do not claim "faster tethering" from one WAN test.

### Cleanup after a future run

Restore nest/fang routes and rfkill as Ember documented. Do not leave
`10.42.0.0/24` NAT installed.

## Do not repeat / quarantine

- Do not replay
  `boot-joan-keyinstall-httdebug-519646f01.img` /
  SHA `3dfad94194d3bedef972eed11c7c9a37aa1cee3427042682605b03479171b19f`
  just to reclassify `SEC_IND`.
- Do not raise the 3 s timeout as the first fix.
- Do not enable `cryptmode=1` (`raw 0` firmware).
- Do not treat SMMU `0x1900` as the cause of this timeout unless a new fault
  coincides.
- Do not trust station-dump `tx duration` or all-zero PDEV TX stats.
- Do not install hostapd/iw on the phone; tmpfs extract only.
- Do not `pkill -f` over SSH (kills the session). Use `pkill -x`.
- Do not use busybox `ip -br` on the phone.
- Do not flash, erase, or switch slots.
- Do not start USB-C, audio, mic, or camera device work on this same boot
  unless Lance explicitly widens the approval. Those are separate lanes.

## Not this test (standing later work)

Inventory only, no device claim:

- **USB-C / OTG / role switch / USB 3+:** requested 2026-08-15, not started.
  Joan DTS currently forces USB2 bring-up (`qcom,select-utmi-as-pipe-clk`,
  unused USB3 PHY dropped). LineageOS-like charger / gadget / host switching
  needs PMI8998 TCPM + PD-PHY work. Independent of the WLAN quirk.
- **Sound / Quad DAC / mic:** downstream has WCD9340 (SLIMbus), ES9218P
  Quad DAC, TFA98xx speaker at I2C 0x34. No joan `sound` node in mainline.
  ADSP/QDSP6 is a prerequisite. No microphone verification exists.
- **Camera:** US998 rear IMX351 + S5K3M3, front HI553. No
  `qcom,msm8998-camss` in upstream CAMSS. No sensor drivers.

Partial notes also live in
`docs/aurel-handoff-2026-08-15-wcn3990-audio-camera-throughput.md`. Treat
that file as research scratch; this file is the test handoff.

## Docs / tracker state at handoff

- Docs checkout: `/home/kumo02/vibe-coding-projects/coding/lg-v30-port`
  on `aurel/card94-reset-script` (same branch Ember used for the 2026-08-15
  Wi-Fi docs).
- Host-only packet:
  `docs/test-results/WCN3990-DELETE-KEY-HOST-2026-08-15.md`
- Prior device classification remains
  `docs/test-results/WIFI-KEYINSTALL-HTT-2026-08-15.md`
- Ember narrative:
  `docs/ember-handoff-2026-08-15-wifi-ap-and-key-install.md`

## Next safe action

1. Stop. Do not boot.
2. When Lance wants the test: re-hash Image.gz/dtb, package a new boot.img,
   write a new one-shot runner bound to that image SHA, ask for approval by
   that SHA, then run exactly one RAM boot.
3. After the boot, classify teardown `-110` and take one local iperf3 sample
   before any other lane.

**Stop condition:** missing/changed hashes, a second fastboot client, no
fresh named approval, or any request to flash.

## Sources

- https://www.mail-archive.com/ath10k@lists.infradead.org/msg17566.html
- https://www.mail-archive.com/ath10k@lists.infradead.org/msg17572.html
- https://www.mail-archive.com/ath10k@lists.infradead.org/msg17574.html
- https://www.mail-archive.com/ath10k@lists.infradead.org/msg17580.html
- https://www.mail-archive.com/ath10k@lists.infradead.org/msg17581.html
- Local Ember packet: `docs/test-results/WIFI-KEYINSTALL-HTT-2026-08-15.md`

Assisted-by: Hermes-Agent:xai-oauth/grok-4.6
Date: 2026-08-15

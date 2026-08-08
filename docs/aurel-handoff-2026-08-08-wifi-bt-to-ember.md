# Handoff: LG V30 (joan) — Wi-Fi/BT bring-up state (Aurel → Ember)

Date: 2026-08-08
From: Aurel Nymvale (agent-aurel)
To: Ember (agent-ember)
Scope: continue Wi-Fi/Bluetooth bring-up on mainline pmOS for the LG V30.

## TL;DR

Wi-Fi/BT (WCN3990) infrastructure is DONE and device-proven; the
kernel hangs at the logo were root-caused to a hard boot-chain size
cliff and fixed via a module strategy. TWO walls remain:
(1) the WLAN firmware file (wlanmdsp.mbn) is not yet sourced;
(2) Bluetooth needs either serdev support in msm_serial or the
tty/hciattach path. Everything is pushed upstream (PRs below).

## What is DONE (device-proven on RAM boots)

- BATTERY LANE CLOSED: PMI8998 fuel gauge (Joel Selvaraj RFC v1,
  adopted verbatim) — UPower 99%/4.337 V matching LineageOS ground
  truth; charging control (qcom,usb-icl-ua 1.8 A, qcom,fcc-max-ua
  3.3 A, LG-sourced) + SDP-exclusion fix; charging verified
  end-to-end (92→95% cycle, float 4.397 V, 32-33 °C, zero errors).
- SIZE CLIFF ROOT-CAUSED: the V30 boot chain hard-caps the
  uncompressed kernel at ~55.5 MB (55 boots, 56+ hangs at the logo;
  DT nodes and ramdisk offset IRRELEVANT — proven across 5 boots).
- FIX PROVEN: wifi/BT built as MODULES, kernel stays 55 MB — the
  full wifi/BT DTB boots clean (PMOS up ~10 s).
- Module tree installed on the SD rootfs:
  /lib/modules/7.2.0-rc2-gd3e8c6694473/ (depmod'ed) — but NOTE the
  running kernel version string will change on the next build (git
  describe), so rebuild modules + modules_install + depmod for the
  new release string, and re-install into the rootfs if the kernel
  is rebuilt.
- /lib/firmware/crnv21.bin on the rootfs: SHA-256
  43f429abcf72c6a0e93e6de2875a174369dc83002ab539826c40da30677337e9
  (device-exact, from the V30's own /vendor/firmware via adb pull).
- modprobe ath10k_snoc: LOADS, probes 18800000.wifi (dummy
  regulator note for missing ch1 is harmless — LG wires a single
  3.3 V ch0 rail). Probe then blocks in the QMI/firmware wait —
  needs wlanmdsp.mbn (wall #1).
- modprobe hci_uart: LOADS, BT core + HCI UART driver up. No hci0:
  msm_serial has NO serdev controller support, so the
  qcom,wcn3990-bt DT child never binds (wall #2). The BT UART
  exists as /dev/ttyMSM1 (blsp1_uart3 / serial@c171000 — confirmed
  from the live LineageOS device tree).

## WALL #1 — WLAN firmware wlanmdsp.mbn

ath10k_snoc (wcn3990) requests qcom/WCN3990/hw1.0/wlanmdsp.mbn.
EVERY route tried failed on 2026-08-07 night:
- git.kernel.org linux-firmware: Anubis anti-bot blocks the browser;
  raw URLs 404 (file not at qcom/WCN3990/hw1.0/).
- GitHub mirror linux-firmware: qcom tree 404s on main+master.
- CodeLinaro (qcomlt/linux-firmware): auth-gated ("confidential").
- pmOS GitLab pmaports: Anubis block; raw APKBUILD paths 404.
- repo.postmarketos.org: DNS does not resolve (browser AND host).
- sdm845-mainline/linux-firmware fork: 404.
- batocera fsoverlay: only ships SLPI firmware (qcom/sdm845/AYN/Odin),
  no wlanmdsp.mbn.
Best next routes: (a) fetch from a DIFFERENT network (phone hotspot,
another host), (b) the batocera release ISO, (c) ask Joel Selvaraj
(the RFC author / Odin maintainer) directly for the source URL.
The device's own bdwlan.bin (persist, CLD format) is NOT usable as
the mbn — different firmware packaging.

## WALL #2 — Bluetooth serdev

msm_serial (drivers/tty/serial/msm_serial.c) has ZERO serdev refs.
The qcom,wcn3990-bt DT child therefore never becomes a serdev
device. Options:
(a) Add serdev controller support to msm_serial (bounded driver
    work; hci_qca's serdev side is already upstream — see
    patchwork.kernel.org/patch/10280561/ for the reference pattern).
(b) The tty line-discipline path: hciattach-style setup on
    /dev/ttyMSM1 (needs the bluez hciattach tool — NOT currently on
    the rootfs; apk add = persistent system change, get Lance's
    approval first).

## Kernel state

- Tree: ~/vibe-coding-projects/coding/linux-mainline-v30
- Branch: joan/battery-fg — 8 clean commits, **MERGED into master
  as linux-lg-v30-joan#5** (2026-08-08). mas_ipa QoS also merged
  (#4). ALL joan kernel work is now upstream in
  ShapeShifter499/linux-lg-v30-joan master — branch new work from
  master, not from the local branches.
- History was cleaned before push (TEMP-DIAG + mystery reverts
  dropped).

## Port repo state (IMPORTANT — merge timing)

- lg-v30-port PR #3 was MERGED at 2026-08-08T01:06:56Z — at that
  moment the branch carried up to d2d33a9 (battery audit, WCN3990
  fw injection, dtb overlap checker).
- TWO LATER COMMITS landed on the branch AFTER the merge and are
  NOT in master: the 2026-08-08 handoff (949c4aa) and the
  D-series/C2 recovery commit incl. sd-throughput fix (5e848b3).
  They were re-applied on top of master in the branch
  aurel/handoff-merge-status → PR lg-v30-port#6 (or whatever PR
  this lands in) — MERGE THAT to close the gap.
- Ember's overlap-scan work (32caa47, branch
  ember/overlap-scan-reserved-memory) sits on top of the merge;
  coordinate through Lance if it needs the late commits.
- .config currently: wifi/BT as MODULES (ATH10K=m, ATH10K_SNOC=m,
  BT=m, BT_HCIUART=m, BT_HCIUART_QCA=m, MAC80211/CFG80211/RFKILL=m,
  POWER_SEQUENCING=y, QCOM_RPROC_COMMON=m) — do NOT flip back to
  built-in: the kernel would exceed the size cliff.
- Config-baseline rule (binding): always build from
  ~/vibe-coding-projects/coding/build-qos-bimc-v2-24e82e84e/.config
  + the required enables, NOT the tree's stale .config.
- Sealed images in lg-v30-port/out/audit-20260807/:
  boot-joan-wifi-modules-rx.img = bcf5c487ccfff72d9e930f877ccc6fa3d
  795b9da87c40375f0911b836e450417 (the proven 55 MB modules image,
  wifi DTB). Also wifi-ath10k (2cf98b6b, 58 MB, HANGS), wifi-btonly
  (5bdc1002, 56 MB, HANGS), wifi-isolate (3ce3fb93, 55 MB, boots),
  diag (5dc88f86), full-battery (55f300db), fg (9b3f1f36) + manifests.

## Port repo / docs

- ~/vibe-coding-projects/coding/lg-v30-port — PR #3 updated:
  https://github.com/ShapeShifter499/lg-v30-port/pull/3
  (battery audit doc, WCN3990 fw injection + RAMDISK_OFFSET in
  make-pmos-image-fw.sh, dtb-check-reg-overlaps.sh restored).
- make-pmos-image-fw.sh: WCN_FW_DIR (default $HERE/firmware/wcn,
  crnv21.bin — gitignored) + RAMDISK_OFFSET (default unchanged).
- Deck cards: 86 = wifi/BT lane (full history incl. hang matrix),
  85 = full battery cycle test (pinned, Someday), 87 = backup
  restore (pinned, Someday).

## Standing practices (bind)

- Silence ≠ consent for device boots; nothing flashed (RAM boot
  only: fastboot boot); recover to LineageOS after every test
  (adb reboot bootloader → fastboot boot; recovery via pmOS
  `sudo reboot` or 10 s power-hold).
- scripts/dtb-check-reg-overlaps.sh every boot (PASS required).
- Persistent-rootfs writes need Lance's approval; SD logs removed
  after tests; script files over inline SSH quoting (scp then run).
- Commit convention (per Ember's hook, b92017b — VERIFIED against
  the live hook on 2026-08-08): EVERY commit needs BOTH trailers —
  "Signed-off-by: Lance <Gero3977@gmail.com>" (the human certifies
  the DCO; an AI must never sign as itself) AND
  "Assisted-by: Hermes-Agent:deepseek/deepseek-v4-flash" (names
  the model actually running; a model-less variant is rejected).
  Unaided human commits use "Assisted-by: none". No Co-Authored-By.
  Merges / in-flight revert-cherry-pick / fixup+squash are exempt.
  --no-verify is the escape hatch. Hook is global
  (core.hooksPath = ~/.config/git/hooks, all 24 repos).
- Phone on nym-nest: adb serial LGUS9986e606d55; USB IDs
  18d1:d001 (pmOS/fastboot) / 18d1:4ee7 (LineageOS); pmOS SSH via
  nym-nest-family → sshpass user@172.16.42.1, sudo via
  ssh -tt + /tmp/pmos-pass (credential present on nym-nest).
- WiFi node was historically commented "leave disabled until MSS
  functional" — now enabled; the QMI wait without firmware behaves
  like a block, so testing wifi without the mbn will look hung at
  the probe (check dmesg, not just the missing wlan0).

## Heads-up for Lance (mutations)

Two mystery mutations on 2026-08-07: git reverts at 22:25 under the
repo-default identity (Lance denies; not from any visible Aurel
call) and a memory-store clobber. Both fixed forward. If Ember was
working the same host concurrently, please coordinate: check with
Lance whether Ember touched linux-mainline-v30 or the memory store.
Nothing else is believed affected.

## Backup (pinned, card 87)

Backup infra did NOT follow the hardware migration: no backups
since ~July; /mnt/aurel-backup-ssd is on the old hardware. Plan:
re-point to /data/backups (717 G free), first rsync (~/.hermes,
~/.openclaw, quarantine-2026-07-31), daily schedule with 14-point
retention. Code is safe (GitHub PRs); non-git state is not backed
up yet.

## Next concrete steps (recommended order)

1. Source wlanmdsp.mbn (different network / Joel Selvaraj / batocera
   ISO) → drop at /lib/firmware/qcom/WCN3990/hw1.0/wlanmdsp.mbn on
   the rootfs → reboot the bcf5c487 image → modprobe ath10k_snoc →
   wlan0 should appear. This also unblocks the APSD/charging
   follow-ups if needed.
2. BT: pick serdev-vs-hciattach with Lance; implement, test hci0.
3. Then the pinned battery CC test (card 85) when convenient.

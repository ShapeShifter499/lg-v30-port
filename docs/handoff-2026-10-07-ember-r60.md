# Handoff 2026-10-07 — joan mainline: r60, CLAT, qrtr regression, open IPA RX stall

Ember (Claude-Code:claude-opus-5-5), picking up Fulgor's session (usage cutoff, 09:00) through 19:15.
Detailed day log: nest `~/.zcode/journal/joan-mainline-goal-2026-10-07.md`. Deck #190 has running comments.

## TL;DR

- **r60 is the kernel to use.** r59 crash-loops the modem (qrtr HELLO backport) — never ship r59 alone.
- **IPv4 on IPv6-only SIMs works** (clatd + glue in lg-joan-cellular-data 0.2-r7), robust across
  reconnects, Wi-Fi switches, radio toggles, modem restarts and reboots. Idle cost ~0.
- **Top blocker for a working default install: boot-time cellular RX stall** (~60-70% of boots the
  bearer connects but downlink stops after a few packets). Root cause NOT found; 9 hypotheses and
  3 workarounds disproven (table below). Only a modem restart restores data, and that kills Wi-Fi.
- **Nothing is pushed.** Everything below is local on nym-skyforge.

## Phone / bench state (19:15)

- US998 in pmOS, RAM-booted **r60** (`~/joan-images/r60/boot-joan-r60-ondevice.img` on nest). SD has
  linux-lg-joan **r60** installed, lg-joan-cellular-data **0.2-r7** (+ clatd), stock r60 `ipa.ko`
  (instrumented one removed; original backup `/root/ipa-r60.ko.zst`), 81voltd **enabled** (was masked
  for a test, unmasked and started). The running boot still has the debug ipa.ko loaded until the
  next reboot. Extra test tools installed: libcamera-tools, i2c-tools, tcpdump.
- Fulgor's earlier clatd bench files: `/root/fulgor-clat-bench-backup/`.
- Wi-Fi: works; no saved autoconnect profile (home "LG's Wifi 5GHz" profile, autoconnect off).

## Bench cautions (learned today)

- **Scripted pmOS reboots dropped the phone off USB three times** (no fastboot, no LineageOS) until
  Lance power-cycled it. Budget for that; don't loop reboots unattended for long.
- `ramboot.sh` now arms 420 s (shutdown once took 2 min 45 s). Never "send late" into an enumerated
  aboot (hangs the session; needs Lance).
- A pmOS panic reboots into LineageOS, whose ramoops wipes ours: crash logs are lost. Only the
  persistent journal (often truncated) survives.
- `devmem` on IPA registers while IPA is runtime-suspended can hang the SoC — don't.
- A modem remoteproc restart leaves ath10k Wi-Fi dead until reboot (rmmod leaks MSA permissions).

## What landed (local commits)

### Kernel (`~/vibe-coding-projects/coding/linux-mainline-v30`, branches on ee468f34 = r57)
| branch | tip | content |
|---|---|---|
| `joan/r60-candidate` | d351a20a06ae | **r60**: glink-smem FIFO order 786439ad, qrtr ns limits ff194cff/7fc1c937 (NO 544d85de HELLO), ath10k pairwise delete-key-wait opt-out (binding/driver/joan DT), rmnet IFF_NOARP, CPU Energy Model (opp-microwatt) + `.register_em` |
| `joan/rmnet-noarp` | 2cdfec0ab5a9 | rmnet IFF_NOARP alone (verified hot-loaded: accept_dad=-1, 6/6) |
| `joan/cpu-energy-model` | c77bb2415e75 | opp-microwatt for all 53 CPU OPPs (from stock sched-energy-costs) + register_em fix |
| `joan/camss-csiphy-csi-rate` | 3f7fcabf3f6a | r60 + msm8998 CSIPHY rates its csiN clock (front path ran csi2 at 19.2 MHz) — correct, but not sufficient for HI553 frames |
| `joan/r59-candidate` | 86893aef5bd3 | r59 + HI553 0x20 address (27812851) + 4-lane (6d1f1d5f) + energy model. **Contains the qrtr HELLO commit — unsafe.** Keep for the HI553 commits only. |
| `joan/debug-ipa-rx-stall` | acc4de0f64dd | DEBUG instrumentation of ipa (open/stop, QMI ready, TX drops, RX, runtime PM, replenish). Not for merging. |
| `joan/ipa-irq-level` | = r60 + **stash@{0}** | level-triggered IPA IRQ experiment — disproven, do not commit |

### pmaports
- `pmaports-lg-v30-clean` (joan/readme-build-guide): c0d77b7540 CLAT package (0.2-r6), 2d6ae212b3 README,
  f76d16d38e nfc-tags icon, 3eb8f30664 CLAT retry timer (r7), 41255e2c46 RX-check + **1e2928707f revert**.
  APKBUILD is back at pkgrel=7 — **the next lg-joan-cellular-data release must be pkgrel>=10** (r8/r9
  test builds were installed on the bench).
- `pmaports-r59-candidate` (joan/r59-candidate worktree): 98fb6aaa8b r59 (unsafe), **3ba943cd13 r60**.
  Push r60, never r59 alone. Tarball = `git archive --prefix=linux-lg-v30-joan-<sha>/ | gzip -n`
  (byte-identical to GitHub's, checked), so checksums hold once the kernel branch is pushed.
- Uncommitted in pmaports-lg-v30-clean (other agents' work, untouched): device-lg-joan, linux-lg-joan
  r58 prep, fm-radio, joan-adsp-watchdog.

### lg-v30-port (claude/lucid-dijkstra-bxx3r9): 85258d6 … f4cae43 (13 commits)
CLAT evidence, qrtr evidence, IPA stall evidence, matrix rows (EAS, Wi-Fi, front/rear-wide cameras,
modem/data stall), tools: ramboot.sh 420 s, bootloop.sh, em-from-stock-costs.py, apply-em.py.

## Verified on the bench

- r60: 0 modem crashes in 41 min; sound card up 11/12 boots; Wi-Fi 3/3 clean disconnects; EAS on
  (EM 22/31 states, 5/8 inefficient marked, no warning); CLAT: reconnects 8/8, Wi-Fi<->cell 5/5,
  radio toggle, modem restart, reboot; tayga 1 wakeup/min.
- Boot-log warnings classified; only new one (EM) fixed. See matrix.
- Rear camera (IMX351) streams 30 fps; "washed out" = imx351.yaml has a black level but no CCM.
- NFC: neard bus-activates, PN547 powers and polls.

## Open problems (with evidence)

### 1. Boot-time cellular RX stall — TOP BLOCKER
Evidence: `lg-v30-port/docs/evidence/2026-10-07-ipa-rx-stall/README.md`.
Pattern: after `ipa_open` a few (2-18) downlink packets arrive, then none; MM/NM say connected.
Only consistent correlate: modem attach time (stalled boots attach ~28-30 s, good ~38 s).
Disproven: interface bounce (1/7), NM reconnect, IPA runtime PM forced on (after and from boot),
level-triggered IPA IRQ, RX replenish/doorbells, late connect, our CLAT userspace, band/CA,
81voltd. Modem restart cures it (kills Wi-Fi). Next: compare the modem-side QMI/WDS/DPM setup on a
stalled vs good boot (qmicli wds/dpm queries, MM debug log), and what the restart path resets
(ipa_table_reset + ipa_mem_zero_modem) — e.g. try performing that reset before the first start.

### 2. Front camera HI553
Probes at 0x20 (address from LG lib), 4 lanes / 220 MHz (camera_config.xml), csi2 clock fixed;
still no frames (VFE sof timeout, no CSID errors, all writes ACKed, stream bit set). Kept out of
r60 because CAMSS will not link the rear camera while a front sensor fails to bind.

### 3. Others
S5K3M3 wide driver not started (address 0x2d, ID 0x30d3 known); Wi-Fi recovery after modem restart
(ath10k MSA leak); ADSP sound-card race (1/12); USB-C DP unported; speed bins 0/1 tables (untestable here).

## Needs Lance
Cameras on screen (Snapshot, rear, lit scene) + colour tuning; NFC tag read/write; FM radio audio
(SoC-hang risk); CLAT on other SIMs/roaming/hotspot clients; USB-C display sink; overnight battery
soak; power-cycles when the bench phone drops off USB.
Decisions: push (r60 not r59); upstream reports (qrtr 544d85de regression; pmOS CLAT draft at nest
`~/.ember/workspace/joan-clat-2026-10-07/pmos-upstream-issue-DRAFT.md`); bins 0/1; fm-radio landing;
Chatty/Snapshot hard deps.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5-5

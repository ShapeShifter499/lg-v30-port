# Handoff — Milestone 1 reached; postmarketOS plan

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-10

## Where things stand (evidence in ledger K051-K053)

- Kernel `joan/latest-clean-test` @ `950cf8554` (public:
  ShapeShifter499/linux-lg-v30-joan) boots to **mainline userspace** on the
  US998 via RAM-only `fastboot boot`: USB ECM+ACM gadget enumerates
  (18d1:4e26), network + root shell work, full diag dump captured
  (`out/k053-diag-2026-07-10.bin`, sha in ledger). The TLMM
  `gpio-reserved-ranges` commit was the whole early-boot wall.
- Only dmesg failures: TZ-owned SMMUs `5040000.iommu` + `cd00000.iommu`
  (deferred-probe timeout -110, tolerated). APSS WDT never armed.
- Both repos are public with PROVENANCE.md + CONTRIBUTING.md; PRs welcome.
- Owner authorizations on record (ledger K051-K053): unattended tethered
  tests; flashing allowed with backups taken first (23 partitions saved +
  mirrored) — but NEVER xbl/abl/tz/hyp/rpm/modem or anything that could
  block recovery (owner correction 2026-07-10: laf MAY host the pmOS
  boot image — see Boot model below — since recovery + fastboot both
  remain as restore paths and laf/lafbak are backed up). End goal: **postmarketOS with full wifi + BT** (cellular
  later).

## Next: storage is the gate (start here)

K053 diag shows UFS did NOT come up: `ufshc@1da4000` ⇄ `phy@1da7000`
dependency cycle, `gcc sync_state pending due to 1da4000.ufshc`, no ufshcd
host registration. No sdhci/mmc lines at all (SD slot not in the joan DTS
yet). Without storage there is no rootfs, so:

1. **UFS bring-up**: compare `&ufshc`/`&ufsphy` in msm8998-lge-joan.dts
   against working msm8998 boards (oneplus-common, sagit, yoshino —
   they enable both with per-board regulators); we currently set only
   `status = "okay"`. Likely missing: vcc/vccq supplies, reset-gpios(?),
   PHY supplies. CAUTION: UFS writes are how you could hurt the LOS
   install — bring it up read-only in the initramfs (no mounts, no fsck)
   and treat /dev/sd* as look-don't-touch except the pstore partition.
2. **SD card (microSD via sdhc_2)**: add the `sdhc_2` node from downstream
   `msm8998-joan-common` (pinctrl + vmmc/vqmmc). A rootfs on SD keeps
   pmOS entirely off the internal UFS = safest daily-driver coexistence.

## postmarketOS plan (P6)

- **Boot model** (corrected by owner 2026-07-10): kernel from
  `fastboot boot` while tethered; once stable, flash the pmOS boot image
  to the **laf (download-mode) partition** — NOT recovery, which stays
  intact for LG/LOS recovery flows. Enter it with the download-mode key
  combo (power off, hold Vol-Up, insert USB). Both `laf` and `lafbak`
  are in the verified 2026-07-10 backup; while pmOS occupies laf,
  download mode is unavailable until laf is restored (via
  `fastboot flash laf`, recovery, or dd from LOS root — all remain
  usable). LineageOS `boot` and `recovery` stay untouched. Rootfs on
  **microSD** first; internal UFS later only with explicit owner
  sign-off per partition.
- **pmaports skeleton**: `device/testing/device-lge-joan/` — deviceinfo
  (arch=aarch64, boot method fastboot, appended dtb, pagesize 4096, base
  0x0 per BoardConfig), `linux-postmarketos-lge-joan` APKBUILD building
  branch `joan/latest-clean-test` of ShapeShifter499/linux-lg-v30-joan.
  pmOS's initramfs debug-shell uses the same 172.16.42.1 USB-network
  convention as our bringup initramfs, so the existing tethered workflow
  carries over (SSH instead of our busybox shell once rootfs mounts).
- **Milestone order**: (M2) storage: UFS probes + SD rootfs mounts →
  (M3) headless pmOS: boots to sshd over USB ECM → (M4) display
  (SW43402 DSC cmd-mode panel on MDP5 — parcels P2/P3, the hard one;
  headless is fine until this lands) + touch (P4, stmfts) →
  (M5) **wifi/BT**: WCN3990 — WLAN via ath10k SNOC, BT via hci_qca UART.
  M5 depends on the TZ-owned SMMU situation (the two -110 probes) plus
  remoteproc/firmware from the LG partitions; expect this to need the
  most new investigation. Cellular explicitly deferred.

## Standing safety (unchanged)

Never `fastboot getvar`; fastboot only via `adb reboot bootloader`; one
fastboot client; RAM-only boots unless a flash is explicitly planned
against the backup inventory; raw pstore read after every failed boot;
don't touch `/sys/kernel/debug/tzdbg/*`. Gadget-image sessions: interact
after ~t+75s (gadget re-bind), `touch /keep` to hold, self-reboots at
15 min otherwise.

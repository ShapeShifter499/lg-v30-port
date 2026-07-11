# Handoff — M3 done, M4 gated on the mmss SMMU (for Lance + Aurel)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

## Current milestone state

- **M1** (mainline userspace + USB gadget): done (K052).
- **M2** (storage: UFS + microSD): done (K054).
- **M3** (headless postmarketOS): **done** (K057) — pmOS edge boots on our
  kernel, ssh over USB works, root grew to 180 GB of the 200 GB SD.
- **M4** (display): **in progress, blocked** (K058-K059). Panel driver + DTS
  written and validated-on-device to be structurally correct; the ONLY
  blocker is the mmss SMMU. See below.
- **M5** (wifi/BT): not started. WCN3990 — ath10k SNOC + hci_qca. Also depends
  on SMMU/remoteproc, so the SMMU work below unblocks both M4 and M5.

## THE task for next session: make the mmss SMMU probe

Diagnostic boot K059 proved the display chain is sound and fails at exactly
one point:

```
arm-smmu cd00000.iommu: probe with driver arm-smmu failed with error -110
msm-mdss c900000.display-subsystem: probe ... failed with error -110
```

Both TZ-owned SMMUs (`5040000.iommu` = anoc, `cd00000.iommu` = mmss) hit
deferred-probe timeout -110. They never bind, so any master behind them
(display now, wifi/remoteproc later) can't probe.

Direction (NOT the K030 blanket skip — that was a debug hack):
- These are Qualcomm secure SMMUs with bootloader/TZ-configured stream
  mappings. Mainline's `qcom_smmu` impl handles "the bootloader left it on,
  inherit the stream mapping" via the qcom impl-def path
  (`ARM_SMMU_OPT_STALL`/`qcom,smmu-500` handling, `impl->cfg_probe`,
  `qcom_smmu_cfg_probe` reserving in-use SMRs).
- Check: does our `msm8998.dtsi` SMMU node use the right compatible for the
  qcom impl (`qcom,msm8998-smmu-v2`, `qcom,smmu-v2`)? Is `arm,mmu-500`
  vs qcom-v2 correct? The -110 is a *deferred-probe timeout*, i.e. a
  dependency (clock/power-domain/interconnect) never arrives — investigate
  the SMMU node's clocks/power-domains first (likely a missing mmcc clock or
  gdsc), it may not be a stream-mapping problem at all.
- First concrete step: boot with the display image (recipe below) and read
  *why* the SMMU defers — grep dmesg for what `5040000`/`cd00000` waits on
  (`sync_state pending`, clk, genpd). The -110 is a symptom; find the unmet
  dependency.

## How to reproduce / test (device workflow)

- Device is RAM-only `fastboot boot` throughout; nothing flashed. LineageOS
  is the untouched daily driver on the boot partition.
- Enter fastboot ONLY via `adb reboot bootloader`. Never `fastboot getvar`
  (wedges LG aboot). One fastboot client at a time.
- Boot image packaging MUST use `--ramdisk_offset 0x02000000` (K056: LG aboot
  loads the ramdisk over the kernel for >16 MiB kernels; our kernels are
  ~19 MiB with the display/debug config).
- Display test image build (bringup initramfs, module-less, so DRM must be
  built-in): `./scripts/config --set-val DRM y --set-val DRM_MSM y
  --set-val QCOM_LLCC y --set-val QCOM_OCMEM y --set-val
  DRM_PANEL_LG_SW43402 y` then `make ... Image.gz dtbs`, then cat
  Image.gz+dtb and mkbootimg with the offsets above (see
  `out/boot-joan-k059-display.img` and K059 in the ledger for the exact
  invocation).
- Pull dmesg over USB: bring up host `172.16.42.2/24` on the usb-if, phone
  serves `nc -l -p PORT < /tmp/dmesg.txt`, host `ncat 172.16.42.1 PORT`.
  (Host ufw drops phone->host, but host dialing OUT to the phone is fine.)
- Large file TO the phone (e.g. rewriting the pmOS SD image): use HTTP, not
  nc — host `python3 -m http.server`, phone `wget -O /dev/mmcblk0 URL`
  (needs a temporary `iptables -I INPUT ... -s 172.16.42.1 -j ACCEPT` on the
  usb-if, removed after). busybox `nc` truncates; see K054-K056 for the
  full saga.

## postmarketOS boot recipe (M3, working)

- SD already holds a verified pmOS image (fs root UUID `9a5df9d1`). Boot it
  with `fastboot boot out/boot-joan-pmos-ramdiskfix.img` (or rebuild via
  pmbootstrap — but a fresh `pmbootstrap install` churns UUIDs, so boot.img
  AND the SD must come from the same build).
- ssh: `ssh user@172.16.42.1`, password `147147`, key `id_pi_migration`.
  sudo needs the password + a tty (`ssh -tt ... 'echo 147147 | sudo -S ...'`).
- pmaports device pkg: bump `pkgrel` to force a rebuild into the rootfs when
  changing deviceinfo (a checksum update alone won't reinstall it).

## Repos (all public, normal commits only — NO force-push, Lance directive)

- Kernel: `github.com/ShapeShifter499/linux-lg-v30-joan` branch
  `joan/latest-clean-test` @ `86fbeea5b` (push remote `ghfork`).
  Local: `~/vibe-coding-projects/coding/linux-mainline-v30`.
- pmOS port: `github.com/ShapeShifter499/pmaports-lge-joan` branch
  `device-lge-joan` @ `25f24b1d26` (push remote `ghjoan`).
  Local: `~/.local/var/pmbootstrap/cache_git/pmaports`.
- Harness/docs: `github.com/ShapeShifter499/lg-v30-port` @ `6fd5794`
  (push remote `ghpub`). `docs/kernel-change-ledger.md` is the truth.

## Conventions (binding — same for Aurel)

- Commit trailers: `Signed-off-by: Lance <Gero3977@gmail.com>` +
  `Assisted-by: <harness>:<model actually running>` (Aurel =
  `Hermes:gpt-5.5`). NEVER `Co-Authored-By`. Detailed body: what + why +
  evidence + what was left out.
- Borrowed code/data: keep license/SPDX, cite the downstream file in the
  commit body, and add a row to `docs/dependency-tracker.md`. Downstream
  LG/Qualcomm data = GPL-2.0; verbatim copies live in `docs/downstream-refs/`.
- Any host package install or external download → a row in
  `docs/dependency-tracker.md`, same session.
- Docs carry `Written-by:`/`Agent-harness:`/`Date:`; never rewrite another
  agent's attributed text, append beneath.
- Ledger every kernel-impacting change (K0xx entry with hashes + evidence +
  class) before handoff.

## Safety

- Flashing is authorized with backups-first; laf is the sanctioned pmOS boot
  slot (recovery stays intact). NEVER xbl/abl/tz/hyp/rpm/modem. But nothing is
  flashed yet — still RAM-only. 2026-07-10 23-partition backup is in
  `backups/` (gitignored) + mirrored to NC.
- Do not read `/sys/kernel/debug/tzdbg/*` (made adb/device vanish before).

## Device state at handoff

Phone is in LineageOS, healthy, nothing flashed. adb may show `unauthorized`
until the on-screen "Allow USB debugging" is accepted after a re-plug.

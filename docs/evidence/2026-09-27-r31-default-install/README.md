# 2026-09-27: linux-lge-joan r31 (FM receiver) — default-install verification

Written-by: Fulgor Nymvale (agent-fulgor-zcode)
Agent-harness: ZCode:GLM-5.3-Flash
Date: 2026-09-27

First default-install boot of the FM-receiver kernel package. pmaports
commit `242715e4e3` (pkgrel 31, pin `4aef1e1c44eb`), built with
pmbootstrap, installed on the joan bench SD rootfs with
`tools/bench/joan-pkgboot.sh` — i.e. exactly the user path: `apk add`
runs mkinitfs + boot-deploy, the device generates its own boot.img, and
that image is RAM-booted (`fastboot boot`). Nothing flashed.

- Package: `linux-lge-joan-7.2.0_rc2-r31` (upgrade from r30, installed
  over `device-lge-joan-1-r19`).
- Device-generated `boot.img` sha256 `326c596f925c…`, RAM-booted.
- Raw log: `pkgboot-r31-fm.log` (before/after apk state, mkinitfs +
  boot-deploy output, boot result).

## Verification matrix (on the r31 default install)

| Check | Result |
|---|---|
| Boot | `uname -r` = 7.2.0-rc2, systemd `running`, no failed units |
| Camera | IMX351 enumerates; `Rotation = 270` (fix 0e456d986954 through the pmaports path); stock-tuning capture rc=0 |
| CPU DVFS | policy0/policy4 both active, schedutil (CPR3/OSM stack carried from r30 unchanged) |
| FM device | `/dev/radio0` registered at 12 s after Bluetooth power-on (`radio_qca_fm hci_uart.fm.0: FM receiver registered as radio0`) |
| FM compliance | v4l2-compliance 48/48, 0 warnings |
| FM tune/seek | 103.5 MHz set+read back; hwseek found 6 stations across the band; mute control works |
| FM RDS | 0 groups decoded — see below |

Note: capturing as non-root gives `VIDIOC_S_FREQUENCY` failures
(`set to -1`); `/dev/radio0` is `root:video`. Bench scripts run as root.

## RDS A/B against bl17 — environmental, not a package regression

The r31 install decoded zero RDS groups on 103.5 MHz; the bl17 bench
kernel (same driver commit) was re-RAM-booted and gave the identical
result with the same script and invocation (`rds-ctl -b -R
/dev/radio0`): signal strength 56% on both kernels, 0 blocks on both.
A band seek found 6 stations on both (bench best-case last night was
15 with the headphones held as antenna). Raw capture files were lost
to the documented "/tmp is empty after every reboot" hazard; the
numbers above are from the bench transcript. Conclusion: the RDS
subcarrier SNR at the bench changed since the 2026-09-26 capture
(109 groups in 25 s); the FM stack behaves identically on r31 and
bl17.

## State after verification

Phone RAM-booted on the r31 default install, systemd running.
pmaports commit is local (branch `joan/readme-build-guide`, HEAD
`242715e4e3` on top of `1c56389204`) — push needs Lance's approval per
the profile rule. `temp/libcamera/imx351.yaml` (LG colour matrices)
remains uncommitted and untested on purpose.

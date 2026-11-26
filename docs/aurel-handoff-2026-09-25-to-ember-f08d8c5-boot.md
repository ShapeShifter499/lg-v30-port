# Handoff: Joan f08d8c5 RAM boot stopped after the debug shell

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:xai-oauth/grok-4.7
Date: 2026-09-25
For: Ember
Status: FYI and pickup. Aurel stopped on Lance's request. Do not treat this as a finished userspace boot.

## Context

Lance asked to keep porting the LG V30 (joan) kernel to mainline / postmarketOS, copy the new kernel onto the SD card, and RAM-boot it. Phone is US998 `LGUS9986e606d55` on `nym-nest-family`. This was a RAM boot only. No partition was flashed.

At handoff time the phone is off USB: no adb, no fastboot, gadget interface down. Last screen report from Lance: blank. Hold power to return to Lineage before another boot.

## What booted

Kernel tip, also `joan/latest-clean-test`:

```text
f08d8c5f0da9074b0cad557e31699ebdfebf7d23
phy: qcom-qmp-usbc: add the MSM8998 USB3+DP PHY
```

Kernel repo: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30`
Branch: `claude/lucid-dijkstra-bxx3r9`, tracking origin, not dirty except untracked `.orig`/`.rej` files. Do not commit those.

pmaports pin already matches that commit:

```text
/home/kumo02/vibe-coding-projects/coding/pmaports-lg-v30-clean
branch joan/readme-build-guide
9eaabed77a9f607f654d1e53a319c55938119928
linux-lge-joan: bump to f08d8c5f0da9074b0cad557e31699ebdfebf7d23
```

Working tree clean and matches `ghjoan/joan/readme-build-guide`.

## Images

All on nest under `/home/kumo02/joan-images/`:

- `boot-joan-f08d8c5-dp-cam.img`
  - sha256 `d037392c92c877d1f52d70ff7a9bdf9b760cb709f17bc14244d4dc5a4c232ab8`
  - full kernel + card initramfs
  - cmdline: `panic=5 ignore_loglevel pmos.force-partition-resize pmos_root=LABEL=pmOS_root pmos_rootfsopts=defaults log_buf_len=8M deferred_probe_timeout=30`
- `boot-joan-f08d8c5-nophy.img`
  - sha256 `67f1e887d6787a6644efa49420225973cc012ba45093f2591b87bdb5e16b8e9a`
  - same kernel, diagnostic DTB with combo PHY and DisplayPort controller `status = "disabled"`
  - this one reached the on-screen debug shell
- `boot-joan-f08d8c5-recovery.img`
  - sha256 `f2dd75d2e5bcfa72d2e114d1d153ed6c7e9773236cbe0e5dca94c9c8321e7bc1`
  - same full kernel as the first image, initramfs patched with `scripts/make-pmos-image-recovery.sh`
  - kernel hash inside the image stayed `2e8c7659ca1420b9463487b6c8d782c2c189b8bda1e37a77f2108816459ae233`

Packed kernel (Image.gz + DTB) hash: `2e8c7659ca1420b9463487b6c8d782c2c189b8bda1e37a77f2108816459ae233`

Build outdir: `/data/buildcache/kbuild/joan-lct-f08d8c5`
Built-in, verified in `vmlinux` and `.config`: `CONFIG_DRM=y`, `CONFIG_DRM_MSM=y`, `CONFIG_DRM_MSM_DSI=y`, `CONFIG_DRM_PANEL_LG_SW43402=y`, `CONFIG_TYPEC=y`, `CONFIG_PHY_QCOM_QMP_COMBO=y`, `CONFIG_DRM_AUX_BRIDGE=y`.

## SD card

US998 SD is `mmcblk0`, type SD, removable=0 misreport, 183 GiB.

- p1 `pmOS_boot` ext2, UUID `73f76e17-43b6-41cb-b922-7159565b09e9`
- p2 `pmOS_root` ext4, UUID `6e2245d1-2d4a-4263-9f65-1cb595ee083d`

Kernel files on p1 were verified before the last boot:

- `vmlinuz` sha256 `2e8c7659ca1420b9463487b6c8d782c2c189b8bda1e37a77f2108816459ae233`
- `msm8998-lge-joan.dtb` sha256 `a959928b426a6ae3a6e54f4a19babc7f9d5905afe25056ebc8c852eb00f6f550`
- previous kernel saved at `pmOS_boot/backup-20260925-pre-f08d8c5/`
- initramfs on the card was not replaced

fsck used the card initramfs `e2fsck 1.47.4`, not Lineage's 1.46.2.

- p1: `e2fsck -fn` exit 0
- p2: first check found orphan inode 12 and `/.SIGN.RSA.pmos@local-6a8029b2.rsa.pub` pointing at it
- Lance approved repair
- `e2fsck -fy` twice, then `-fn` exit 0
- `lost+found` empty
- the bad signature directory entry was removed
- no I/O errors in Lineage dmesg

## Boot evidence

Fastboot accepted the images (`Sending` / `Booting` OKAY, about 5.8 s). The first attempt never sent an image because the phone dropped out of fastboot; that "any key to shutdown" screen was a bootloader timeout, not a kernel rejection.

Full PHY image:

- kernel `7.2.0-rc2-gf08d8c5f0da9` reached the initramfs debug shell
- USB gadget was `1d6b:0104`, but the host interface stayed down until `ip link set enp0s29u1u5 up` and `172.16.42.2/24`
- ping to `172.16.42.1` worked; telnet :23 open; ssh :22 refused
- `mmc0` came up UHS-I SDR104, `mmcblk0` p1 p2 present
- `blkid` saw both pmOS labels
- initramfs log: `Trying to mount subpartitions for 10 seconds...` then `ERROR: failed to mount subpartitions!`
- that search is the Android nested-image path in `mount_subpartitions()`. This card is a normal partitioned SD, so the error is expected and is not card damage
- `pmos_continue_boot` printed `Continuing boot...` and killed telnet
- USB then dropped and the screen went blank

No-PHY diagnostic image:

- same kernel, combo PHY and DP controller disabled in a one-off DTB
- reached the on-screen debug shell (photo `img_352276a3503e.jpg`)
- screen text included kernel `7.2.0-rc2-gf08d8c5f0da9`, missing `vfat` and `uinput` modules, and `Couldn't write new UDC`
- display driver is not missing. The panel lit and showed the shell

Recovery image:

- same full kernel, recovery-patched initramfs
- ping answered, gadget present, ports 22 and 23 refused
- Lance reported the screen still blank
- this image auto-continues the debug shell after 90 s, then the stock shell teardown still removes the USB gadget and splash
- it does not leave a console through the post-shell mount

## What not to misread

- Blank screen after continue-boot is not proof the panel driver failed. The no-PHY image already drew the debug shell.
- `failed to mount subpartitions` is not an SD failure. The partitions and labels were visible.
- `modprobe: vfat/uinput not found` is because this RAM image does not carry `/lib/modules` for `7.2.0-rc2-gf08d8c5f0da9`. It did not block the shell.
- Host USB link often enumerates DOWN. Bring `enp0s29u1u5` up before concluding the gadget is dead.
- Do not RAM-boot without Lance's explicit go. Do not flash `boot`, `laf`, or the SD partitions.

## Next step

1. Return the phone to Lineage and confirm adb `LGUS9986e606d55`.
2. Re-run read-only `e2fsck -fn` on p1 and p2 with the 1.47.4 binary before another boot. p2 was clean after the second repair; a hard power cut may have dirtied it again.
3. Pack a new initramfs that does not stop at `mount_subpartitions()` for 10 seconds when `pmOS_root` is already a real partition, and that leaves the console up after the debug shell. The current recovery patch only bounds the wait; it still tears the gadget down.
4. RAM-boot that image. Success is ssh on `172.16.42.1:22`, not just ping.
5. If ssh works, then test the combo PHY and camera. Those are not proven. The no-PHY shell only proves the kernel and panel can reach the initramfs.

## Do not

- Do not commit `msm8998.dtsi.orig`, `msm8998.dtsi.rej`, `phy-qcom-qmp-usbc.c.orig`, or `phy-qcom-qmp-usbc.c.rej`.
- Do not start a pmbootstrap build from `e6e796df`. That commit is the pre-PHY merge. The pin is `f08d8c5f`.
- Do not restore the removed signature file. `lost+found` was empty and the entry pointed at a bad inode.

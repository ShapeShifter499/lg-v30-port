# Handoff: Joan DisplayPort boot freeze resolution (2026-09-25)

## State of the Phone
* We attempted to RAM-boot pmOS from the SD card using `pmbootstrap flasher boot`, but it failed because pmbootstrap generated a boot image with an initramfs that used stale UUIDs instead of partition labels.
* We successfully extracted the label-based `initramfs` from the SD card's `pmOS_boot` partition (`mmcblk0p1`).
* We packed our new kernel (`vmlinuz`) with this label-based `initramfs` using `mkbootimg`, and booted it.
* **The phone hung entirely (no USB gadget appeared, even with a 30s deferred probe timeout).**

## Root Cause & The Plot Twist
I investigated the `msm8998.dtsi` changes for the DisplayPort combo PHY. 
When the PHY was switched to the combo driver (`qcom,msm8998-qmp-usb3-dp-phy`), the top-level block reset `GCC_USB3_PHY_BCR` ("phy") was dropped because the `phy-qcom-qmp-usbc.c` driver didn't list it in its `usb3dpphy_reset_l`. Without this reset being toggled, the PHY never comes up, hanging the bus on any access and killing the boot.

**However, another agent (Claude) has already reverted the DisplayPort changes** in commit `42eff31685a7` ("Revert the MSM8998 DisplayPort attempt") and subsequently added new commits for `bq25890`, `sx9320`, and `mmcc` clock restructuring. 

This means the current `claude/lucid-dijkstra-bxx3r9` branch *no longer has the broken DP PHY wiring*.

## What's Done
1. **linux-lg-v30-joan**: The local branch was re-synced with `origin` to pick up Claude's revert and new commits. HEAD is `e6e796df38f49b51f2b251447dfe697961deacc0`.
2. **pmaports-lge-joan**: I bumped `_commit` to `e6e796df38f49b51f2b251447dfe697961deacc0`, bumped `pkgrel=22`, and pushed to `ghjoan joan/readme-build-guide`.

## Next Agent Tasks
1. Run `pmbootstrap zap --lax` or `sudo umount /data/buildcache/pmbootstrap-joan/chroot_native/var/cache/distfiles` to clean up the chroot.
2. Rebuild the kernel package: `pmbootstrap build linux-lge-joan --force`.
3. Extract `vmlinuz` from the built APK.
4. Pack a new `boot.img` using the known-good SD card `initramfs` (/tmp/joan-initramfs on nym-nest-family) and the label-based cmdline:
   ```bash
   mkbootimg \
     --kernel vmlinuz \
     --ramdisk /tmp/joan-initramfs \
     --cmdline "panic=5 ignore_loglevel pmos.force-partition-resize pmos_root=LABEL=pmOS_root pmos_rootfsopts=defaults log_buf_len=8M deferred_probe_timeout=30" \
     --base 0x00000000 \
     --kernel_offset 0x00008000 \
     --ramdisk_offset 0x02000000 \
     --tags_offset 0x00000100 \
     --pagesize 4096 \
     -o boot-joan-r22-label.img
   ```
5. `fastboot boot` the image and verify pmOS comes up!

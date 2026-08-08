# SD card fsck and recovery for joan (the pmOS rootfs card)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:deepseek-v4-flash
Date: 2026-08-07
Supersedes: nothing — complements the standing pre-boot check in
`ember-handoff-2026-08-07-bimc-qos-closed.md` ("Standing practice").

## Quick path (preferred)

    # read-only check, safe any time, no authorization:
    scripts/sd-fsck-repair.sh check
    # repair — persistent write, Lance must be present + approving:
    AUTH=yes-i-have-owner-authorization scripts/sd-fsck-repair.sh repair

Both need the pmOS initramfs e2fsck source: `RD=<unpacked-ramdisk-dir>`
or `IMG=<boot.img>` (the script unpacks it itself). Defaults: host
`nym-nest-family`, serial `LGUS9986e606d55`, partition
`/dev/block/mmcblk0p2`. The manual steps below are the reference
procedure the script automates.

## When you need this

The pmOS rootfs lives on the microSD (`mmcblk0`). After a hard power cut
(or a hung boot that ends in a forced reboot), the ext4 journal on `p2`
can be left dirty, and the pmOS initramfs fsck can fail with card I/O
errors. The failure signature on a stock initramfs is an infinite
key-wait wedge ("Filesystem needs manual repair (fsck)" + no input
path). On a recovery-patched initramfs it is a bounded, readable failure:

    I/O error on the SD card, FSCK repair wait timed out

That message is the 30 s auto-continue from
`scripts/patch-initramfs-recovery.sh` firing — it means the boot-time
fsck hit `rc >= 4` (uncorrected errors). The card itself is usually
fine: LineageOS boots with zero I/O errors and enumerates the card
cleanly. The damage is to the filesystem state, and the fix is a real
fsck run with a *modern* e2fsck.

## Why LineageOS's own e2fsck is not enough

LineageOS ships e2fsck 1.46.2, which bails on the newer ext4 features
the pmOS rootfs uses. Its output on `p2` ("still has errors") is a
scary but meaningless "could not check", never a result in either
direction. The pmOS initramfs carries e2fsck 1.47.4 (Alpine musl build)
which handles it — you can run that same binary from LineageOS via adb.

## Card layout (verified 2026-08-05)

    mmcblk0   SD200, SDXC, SDR104, 183 GiB
    mmcblk0p1  248832 sectors (121.5 MiB)
    mmcblk0p2  192002031 sectors (91.6 GiB)  <- pmOS rootfs "pmOS_root"

## Procedure (proven 2026-08-05; repairs the card, then re-boots pmOS clean)

All host commands run on the port host (`ssh nym-nest-family`), adb
serial `LGUS9986e606d55`. Get the phone to LineageOS first (hard power
button ~10 s if it is hung), then:

1. adb root and confirm the card:

       adb -s LGUS9986e606d55 root
       adb -s LGUS9986e606d55 shell "cat /proc/partitions | grep mmcblk"
       # expect: mmcblk0 / p1 / p2 as above
       adb -s LGUS9986e606d55 shell "dmesg | grep -iE 'mmcblk0|mmc0|I/O error' | tail"
       # expect: clean enumerate (SDR104, SDXC) and NO I/O errors under LineageOS

2. Extract e2fsck 1.47.4 + friends from a pmOS boot image ramdisk.
   The unpacked tree from the last build works (e.g. `/tmp/bimg/rd`):

       # dependency walk first (aarch64):
       readelf -d sbin/e2fsck | grep NEEDED
       # needed: libext2fs.so.2, libcom_err.so.2, libblkid.so.1,
       #         libuuid.so.1, libe2p.so.2, libc.musl-aarch64.so.1
       # NOTE: libblkid.so.1 additionally pulls libeconf.so.0 at
       # runtime — this is the hidden dep that breaks a naive push.

       # stage on the port host, then adb push into /data/local/tmp/musl/
       sbin/e2fsck                              -> /data/local/tmp/e2fsck
       lib/ld-musl-aarch64.so.1                 -> /data/local/tmp/musl/lib/
       usr/lib/{libext2fs.so.2, libcom_err.so.2, libblkid.so.1,
                libuuid.so.1, libe2p.so.2, libc.musl-aarch64.so.1,
                libeconf.so.0}                  -> /data/local/tmp/musl/usr/lib/

3. Sanity-check the loader works on-device:

       adb -s LGUS9986e606d55 shell "chmod 755 /data/local/tmp/e2fsck \
           /data/local/tmp/musl/lib/ld-musl-aarch64.so.1; \
           /data/local/tmp/musl/lib/ld-musl-aarch64.so.1 \
           --library-path /data/local/tmp/musl/usr/lib \
           /data/local/tmp/e2fsck -V"
       # expect: e2fsck 1.47.4 (6-Mar-2025)

4. Run it. Preen first, then full (`-fy` = auto-yes; do not run without
   `-y` — a 183 GB card will not wait for prompts). The partition must
   not be mounted (LineageOS leaves it unmounted; never fsck a mounted
   fs):

       adb -s LGUS9986e606d55 shell "
       /data/local/tmp/musl/lib/ld-musl-aarch64.so.1 \
           --library-path /data/local/tmp/musl/usr/lib \
           /data/local/tmp/e2fsck -p /dev/block/mmcblk0p2
       echo FSCK_PREEN_RC=\$?
       /data/local/tmp/musl/lib/ld-musl-aarch64.so.1 \
           --library-path /data/local/tmp/musl/usr/lib \
           /data/local/tmp/e2fsck -fy /dev/block/mmcblk0p2
       echo FSCK_FULL_RC=\$?"

   Expected on a dirty-journal card (what actually happened 2026-08-05):
   bitmap/block/inode-count fixes, an "Orphan file (inode 12) block 52
   is not clean. Clear?" step, then:

       pmOS_root: ***** FILE SYSTEM WAS MODIFIED *****
       pmOS_root: 24810/10618320 files (0.2% non-contiguous), 1132671/48000507 blocks
       FSCK_FULL_RC=1

   RC semantics (also what the initramfs checks): 0 clean, 1 errors
   corrected, >= 4 uncorrected (needs investigation / card replacement
   if hard read errors appear mid-scan).

5. Orphaned files. `-fy` can orphan directory trees whose journal
   state was inconsistent — on 2026-08-05 that included `/home/user`
   (the pmOS user home), which had to be recovered from the fsck orphan
   fragments (`/lost+found`) under explicit owner authorization.
   **Standing rule: restoring anything into the pmOS rootfs is a
   persistent-rootfs write — get explicit user authorization first,
   like every other persistent change.** After a repair, check the card
   from pmOS for `/lost+found` contents and confirm `/home/user` exists
   before relying on the install.

6. Verify. The next RAM-only boot is the test: it should reach
   userspace with the fsck line logging `rc 0/1`, and SSH port 22 on
   172.16.42.1 should open within ~5-15 s of ping (2026-08-05: clean
   boot, `PORT22_OPEN at check 1`).

## Standing practice (pre-boot, every RAM boot)

Before every RAM boot, from LineageOS adb root: check partition UUIDs,
`e2fsck -fn` on `p1`, and superblock state + surface scan on `p2`.
Remember the 1.46.2 caveat above when reading its output. This document
is the deep-repair path for when that check (or a boot) says the card
is dirty.

## Related but separate

- SD *throughput* is fixed via ICC wiring (5.7 -> 52.3 MB/s, see
  `ember-handoff-2026-08-07-icc-workstream-close.md`); benchmark with
  `scripts/sd-throughput.sh` (read-only by design).
- The initramfs self-heal patches (`scripts/make-pmos-image-recovery.sh`,
  `scripts/patch-initramfs-recovery.sh`) are standard on all images;
  keep them — they convert wedges into diagnosable 30 s bounded
  failures.

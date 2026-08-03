# Handoff — postmarketOS first-boot attempt (M3), 2026-07-11

Assisted-by: Claude-Code:claude-fable-5
Date: 2026-07-11

## One-line state

pmOS image built, written to the 200GB SD (verified), first `fastboot boot`
FAILED on a boot.img kernel/ramdisk load overlap — **diagnosed and fixed**;
phone is **wedged and needs a physical Power+VolDown ~8s reset** before the
next attempt. LineageOS on the boot partition is untouched.

## What happened this session (in order)

1. K054 (prior): mainline kernel `ce78c1369` boots to userspace; UFS + microSD
   both work; SD ext4 mount/write verified.
2. Built postmarketOS (pmbootstrap), device `lge-joan`, UI=console, OpenRC.
   Kernel APKBUILD builds the public fork; needed pahole/python3/elfutils-dev
   +zlib-dev and a `kernel.release` install line to package cleanly.
3. Wrote the 1.2 GB rootfs image to the SD over USB. **Transfer lesson:**
   busybox `nc -l | dd` truncates (stdin EOF half-closes it, or `tail -f`
   never EOFs to dd). RELIABLE = HTTP: host `python3 -m http.server`, phone
   `wget -O /dev/mmcblk0 http://172.16.42.2:PORT/img` (content-length →
   deterministic). Needs a temporary host iptables ACCEPT on the usb-if for
   phone→host (removed after). Verified byte-for-byte via phone-side
   `dd ... count=1151 | sha256sum` == host hash.
4. Full-disk use: pmOS only auto-grows root if the kernel cmdline has
   `pmos.force-partition-resize`. Added it to deviceinfo. GOTCHA: had to bump
   `pkgrel` for the device pkg to actually reinstall into the rootfs (checksum
   update alone won't). Rebuild churns rootfs UUIDs, so the SD was rewritten +
   re-verified (fs UUID `9a5df9d1…`, image sha `0dcecdb8…`).
5. First `fastboot boot`: aboot showed transient `18d1:d00d`, then USB
   disconnected, phone went fully dark. Not a slow boot — kernel never ran.

## Root cause + fix (K056 in the ledger)

- boot.img header math: kernel_offset 0x8000 + kernel 18,981,009 B ends at
  **0x1222091 (~19.0 MiB)**; ramdisk_offset was **0x01000000 (16.0 MiB)** →
  ramdisk load address is INSIDE the kernel image → aboot overwrites the
  kernel tail with the ramdisk → corrupt kernel → hang.
- Our bringup images never hit this (that kernel is 14.8 MiB, fits under
  16 MiB). The pmOS kernel is larger mostly from BTF/DWARF5 debug info that
  pmOS's kconfig check requires.
- FIX 1 (ready to test NOW, matches the current SD/UUID): repackaged
  `out/boot-joan-pmos-ramdiskfix.img` (sha `9bdc4a58…`) — pmOS
  kernel+ramdisk+cmdline re-`mkbootimg`'d with `--ramdisk_offset 0x02000000`
  (32 MiB), verified overlap=False, same `pmos_root_uuid=9a5df9d1…`.
- FIX 2 (durable): `deviceinfo_flash_offset_ramdisk` 0x01000000 → 0x02000000
  in pmaports device-lge-joan. NOTE: a fresh full build will churn UUIDs and
  need an SD rewrite; the ready-to-test image above avoids that.

## EXACT next step (when the phone is physically reset)

1. Physically reset: hold Power+VolDown ~8s → phone returns to LineageOS.
   Wait for `adb devices` to show it.
2. Start a serial logger, then:
   `adb reboot bootloader` → wait for `fastboot devices` →
   `fastboot boot ~/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-pmos-ramdiskfix.img`
3. Watch for a pmOS USB network device and sshd. pmOS default net is
   172.16.42.1; static-assign the host (e.g. 172.16.42.2/24) and
   `ssh user@172.16.42.1` (password `[REDACTED]`, key `<device-ssh-key>` baked in).
   First boot runs parted resizepart 2 100% + resize2fs (can take minutes on
   199 GB) before the login comes up.
4. If it hangs again with the same signature, re-check the boot.img header
   overlap and the pmOS initramfs debug shell (telnet 172.16.42.1).

## Repo / history note

Going forward: **no force-push, normal commits only** (Lance wants full
history). Earlier in this session the pmaports `device-lge-joan` branch was
built up via `commit --amend` + force-push while it was still a pre-MR WIP;
from here each change is its own commit. Public repos:
kernel `linux-lg-v30-joan` (branch `joan/latest-clean-test` @ ce78c1369),
pmaports `pmaports-lge-joan` (branch `device-lge-joan`), harness/docs
`lg-v30-port`.

## Safety state

No partitions flashed this session. Backups from 2026-07-10 intact. laf is
the sanctioned pmOS boot slot (recovery stays intact) but we have NOT flashed
anything yet — still RAM-only `fastboot boot`. Standing rules unchanged
(no getvar; fastboot only via adb reboot bootloader; one client).

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-03
Update-scope: Redacted the compromised historical test-user password; no technical conclusion changed.

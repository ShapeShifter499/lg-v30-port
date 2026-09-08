# Handoff: joan bench — night of 2026-09-07/08 (Fulgor → next session)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: ZCode:zai-coding-plan/GLM-5.3
Date: 2026-09-08 (written at end of the 09-07 night session)

## Where the phone is RIGHT NOW

US998 bench, SD-card pmOS prealpha install, RAM-booted from the v2 label
image (kernel `2f1308c271d8` = `joan/latest-clean-test`). It boots to Phosh
and Lance reached the lockscreen/login, but:

- **The USB gadget tears down ~56 s after boot.** Nest dmesg shows cdc_ncm
  register at boot, then `usb 1-1.5: USB disconnect` at +56 s, never
  re-enumerates. This is USERSPACE (ALPHA-STATUS says "USB profile:
  charging only") — prime suspects: usb-moded / a gadget re-init unit.
  The NetworkManager fence I installed (`unmanaged-devices=
  interface-name:usb0` in `/etc/NetworkManager/conf.d/10-unmanage-usb0.conf`)
  is NOT sufficient — NM is not (or not the only) culprit.
- The phone is too slow to type on (squeekboard + Phosh on this build), so
  the teardown culprit has NOT been captured yet. First diagnostic, from
  the on-screen terminal (doas pw 147147) or any gained shell:

      doas sh -c 'journalctl -b --no-pager | grep -iE "usb|gadget|moded|ncm" | tail -20; systemctl status usb-moded --no-pager | head -20'

  Fix shape: mask/stop the unit that rewrites the gadget config, or install
  a correct multi-function gadget config (ncm+acm+adb) it agrees with.

## Access lanes (all proven this night)

1. **LOS root adb** (normal LOS boot): `adb root` works; SD rootfs mountable
   (see ext4 note) for file injection.
2. **Recovery adb** (LOS recovery): same, plus e2fsck/tune2fs available.
   adb may need on-screen authorization after a reboot — needs Lance.
3. **fastboot RAM boot**: LOS → `adb reboot bootloader` →
   `sudo -n fastboot boot <img>`. RAM only, nothing flashed (house rule).
4. **Initramfs telnet**: while an initramfs debug shell is up:
   `nc 172.16.42.1 23` from the nest; `pmos_continue_boot` continues.
   NOTE: `pmos_continue_boot` currently KILLS the gadget — do not rely on
   the network across the handoff.
5. **pmOS sshd**: enabled + host keys generated on the SD install; the
   moment the gadget stays up, `ssh user@172.16.42.1` (pw 147147) works.

CRITICAL: nest-side USB network setup needs **sudo**:
`sudo ip link set enp0s29u1u5 up; sudo ip addr add 172.16.42.2/24 dev enp0s29u1u5`
— unprivileged ip fails silently; several "dead network" conclusions last
night were partly this.

## Images staged on nest: ~/joan-test-assets/audio-wake-20260907/

- `boot-joan-pmos-audio-wake-20260907-v2-label.img` (sha256 05f85d7703…)
  — **use this one**: kernel 2f1308c271d8, label-based root discovery
  (no stale UUID → no emergency shell).
- `boot-joan-pmos-audio-wake-20260907.img` (fdc0758d…) — v1, stale UUID,
  lands in initramfs emergency shell (also usable as debug-shell entry).
- `boot-joan-busybox-debug.img` (7ed5f6d4…) — busybox+telnet, no SD
  dependency, gadget stays up; for wedged-system triage.
- apks: alsa-ucm-conf-lge-joan-1.0-r4, device-lge-joan-1-r12,
  -h932-1-r8, joan-imsd-0.1-r3 + SHA256SUMS + test protocol doc.

## What is already IN the SD rootfs (applied via recovery/LOS adb)

- `/etc/fstab`: LABEL=pmOS_root / LABEL=pmOS_boot (was stale UUIDs —
  that was the emergency-mode boot failure; fstab fix verified working —
  the v2 boot reached Phosh).
- sshd enabled (multi-user.target.wants) + host keys generated.
- `calls-daemon.service` + `gnome-calls.service` masked in
  /etc/systemd/user/ — root cause of the login crash: the greeter's
  gnome-calls hung 90 s ignoring SIGTERM during handoff and serialized
  the session (phosh.service sat in "Starting", zero output; NO oom;
  GPU/phoc healthy). Cores on nest forensics dir (gnome-calls = SIGKILL
  corpse; plymouthd core too).
- UCM r4 untarred into /usr/share/alsa/ucm2/Qualcomm/sdm845-lge-joan/
  (8 SectionDevices: Mic/Headset/DualMic/Camcorder×2 + 3 outputs).
- NM usb0 fence (see caveat above — insufficient alone).

## ext4 runtime-bit surgery (Android recovery/LOS can't rw-mount)

After any hard power-off, the fs carries orphan_present (ro_compat
0x10000) + needs_recovery (incompat 0x4) + sometimes orphan_file (compat
0x1000). Android's old e2fsprogs treats these as unknown features and
refuses rw (and even e2fsck). Recipe: 4-byte dd writes at superblock
offsets 1116 (compat→0x3c), 1120 (incompat→0x2c6), 1124 (ro_compat→0x63);
base64-stage the bytes (`echo YwAAAAA= | base64 -d > file` — NEVER
ASCII-encode hex; 0x63 ≠ "63"). e2fsck journal replay RE-SETS the bits —
clear after replay, or skip replay (the journal tail is expendable if
already pulled). Full backup of the p2 superblock region:
nest forensics-20260907/p2-superblock-backup-4M.img.
LOS proper: vold holds the device — use RECOVERY, not LOS, for this.

## The actual goal next session: the audio test (Ember's order)

All pieces are in place; the moment any shell into pmOS exists:

1. `amixer -c0 cset name='TX COPP Topology' None`
2. `alsaucm -c 0 set _verb HiFi set _enadev Mic` (then Headset, DualMic)
3. `arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 5 /tmp/<dev>.wav` — scp
   wavs out, analyze RMS/spectrogram objectively (no ears needed).
4. Then MBHC (needs Lance's hands + headset), then `DM_Fluence` (fails
   CLOSED — recovery is cset None; a silent input there ≠ broken routing).
Full protocol: docs/2026-09-07-audio-wake-test-protocol.md.
Also capture on next good boot: the stmfts `error code: 0x00dec000d0ba`
console loop (already rate-limited in-driver — cosmetic but identify the
event), the phoc 3 s configure timeout, and WHY the gadget dies at 56 s.

## Repo state (all local work STAGED, nothing pushed except kernel)

- kernel `linux-mainline-v30`: `joan/latest-clean-test` = `joan/wake-path-v1`
  = `2f1308c271d8` — **pushed** (Lance-authorized) with full history:
  micbias/gnd/AMIC4 → q6routing TX COPP topology → DPU TE gate.
- pmaports `joan/readme-build-guide`: pinned to 2f1308c271d8 (pkgrel 12);
  0002/0003/0004 all retired; 0001 (ipa.imem_addr) remains. Commits
  e55c824fc3, 04495813d0, checksum-refresh, re-pin. NOT pushed.
- lg-v30-port `ember/pmaports-joan-gpu-publish-handoff`: patch archive +
  test protocol + this handoff. NOT pushed. NOT pushed = stage-don't-push
  default; ask Lance before pushing anything but the kernel branch.
- lg-v30-pmos-prealpha `main` @ 2c93880: patch_installer.py now versioned
  + carries fix_rootfs_quirks (fstab UUID→LABEL + NM usb0 fence at
  install time; sed verified against the exact broken lines; idempotent).
  NOTE: scripts/build-images*.sh have unrelated local modifications from
  before — do not commit blindly.
- Stock DTB evidence: ~/.hermes/workspace/reviews/joan-stock-dtbs-2026-09-07/
  (ten decompiled DTBs + board-2-stock.bin). RE paydirt already extracted:
  haptics = LRA on PM8998 `qcom,qpnp-haptics@c000` (params in journal);
  NFC = NXP PN547@0x28, IRQ gpio116, VEN gpio12, BBCLK2. Port queue:
  leds-qpnp-haptics.c (2551 lines, downstream) and nxp-nci-i2c DT node.

## House rules (unchanged, they bind the recipient)

Trailers `Signed-off-by: Lance <Gero3977@gmail.com>` +
`Assisted-by: <harness>:<model>`; never `Co-Authored-By: Claude`.
Stage, don't push (kernel latest-clean-test push was explicitly
authorized). SD-card path ONLY until Lance says otherwise; quirks before
alpha; never flash during qualification; do not point IPA DMA at guessed
addresses (that wiped a phone once).

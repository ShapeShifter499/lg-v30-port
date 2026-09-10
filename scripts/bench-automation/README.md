# joan bench automation (2026-09-10)

Drives the LG V30 bench from nym-nest with no typing on the phone and no hands
on the hardware, as long as the phone is reachable on adb from LineageOS.

| script | runs on | does |
|---|---|---|
| `skyforge-build-and-stage-modules.sh` | skyforge | waits for `make modules`, installs to a staging dir stripped, tars it |
| `nest-pull-pmos-journal-readonly.sh` | nest | waits for adb, mounts the pmOS rootfs **read-only** via a loop device (beats vold's `O_EXCL`), pulls `/var/log/journal` + config evidence, unmounts |
| `nest-boot-masked-and-load-audio.sh` | nest | `adb reboot bootloader` → `fastboot boot` with `systemd.mask=usb-signaller.service` → waits for sshd → opens live `dmesg`/heartbeat channels → runs the staged module load |
| `onphone-load-audio-modules.sh` | phone | tmpfs bind-mount of `/lib/modules`, then loads the ADSP/APR/q6/codec chain one step at a time |
| `onphone-capture-mics.sh` | phone | UCM `_enadev` **then** `TX COPP Topology None`, then `arecord` per device |

Hard-won rules, see `docs/HANDOFF-2026-09-10-next-session.md`:

- never `udevadm trigger --action=add` — it reboots this SoC
- never `setprop ctl.stop vold` — vold is critical, it reboots the phone
- SLIMbus modules are required or the card never registers
- set `TX COPP Topology None` **after** `alsaucm _enadev`, never before
- it is `sudo`, not `doas`, on this image

The password is passed via `sshpass`/`sudo -S` for unattended runs; these are
bench scripts for a development handset on a private link, not a pattern to
copy elsewhere.

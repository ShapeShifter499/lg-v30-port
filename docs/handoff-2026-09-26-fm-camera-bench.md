# Handoff 2026-09-26: FM radio driver, camera fixes, how the bench works

Paused at Lance's request after the FM work. Written by Ember
(Claude-Code:claude-opus-5-5) for the next session or agent.

## State at pause

- **Phone** (US998, on nym-nest's USB): RAM-booted bench kernel **bl17**,
  wired headphones plugged in (they are the FM antenna). The SD rootfs
  has bl17's modules in `/lib/modules/7.2.0-rc2-joan-bl+`, with the final
  `radio-qca-fm.ko.zst` installed over the bl17 one. That matches
  `joan/bootlog-fixes` at 4aef1e1c44eb.
- **Kernel** `joan/bootlog-fixes` pushed to origin
  (ShapeShifter499/linux-lg-v30-joan) at **4aef1e1c44eb**.
- **pmaports** (`joan/readme-build-guide`, last pushed 1c56389204): the
  kernel package still builds 989ceae882e6 (r30). **Uncommitted, untested**:
  `temp/libcamera/imx351.yaml` with LG's colour matrices (see camera
  below). Leave it or test it; do not ship it untested.
- **Venus** branch `joan/venus-wip` (0fb72d205be7) unchanged; bisect
  stood at stop_at=5 OK.
- **Firewall**: no changes this session
  (`~/.ember/workspace/joan-bench-firewall-changes.md` untouched).
- **Security**: the copy of `jssh` in nest's `/tmp/ember-f08d8c5-unpack`
  had the bench password hardcoded and it was printed into this
  session's transcript. It now reads `~/.config/joan-bench-pw`. The old
  copy is kept as `jssh.bak-hardcoded` (mode 0600) for Lance to delete.
  The repo's `tools/bench/jssh` never had it.

## Done this session

Kernel (`joan/bootlog-fixes`, all author Lance, kernel.org trailers):

| Commit | What | Verified |
|---|---|---|
| ffee469280a5, d464a5fe2f6d | CCI clock order (camss_ahb off last) | 0 "stuck at on" warnings over 5 sessions |
| 0e456d986954 | main camera rotation 90 -> 270 | `cam -p`: Rotation = 270. **Not yet seen in an app.** |
| 5344583b8215 | binding `qcom,fm-receiver` | dt_binding_check, dtbs_check |
| 4a04a4310739 | hci_qca: FM channel + auxiliary device | on the phone |
| 621a3778bf10 | `radio-qca-fm` V4L2 driver with RDS | on the phone, v4l2-compliance 48/48 |
| 4aef1e1c44eb | joan DT: `qcom,fm-receiver` | on the phone |

Docs: `evidence/2026-09-26-fm-radio-driver/`,
`evidence/2026-09-26-camera-quality/` (rotation, LG colour matrices,
focus controller protocols), matrix rows for FM, camera and apps, bench
scripts in `tools/bench/`.

## How we bench test the phone

### Hosts and wiring

- **Build** on nym-skyforge. Kernel worktree
  `~/vibe-coding-projects/coding/linux-mainline-v30-ember-bootlog`
  (branch `joan/bootlog-fixes`), built out of tree (`O=`). This session's
  build dir was in a session scratch directory that will not survive;
  make a new one (for example under `/data/buildcache/`) from the pmaports
  `config-lge-joan.aarch64` plus the bench options you need (netconsole
  as a module, `CONFIG_MEDIA_RADIO_SUPPORT=y`, `CONFIG_RADIO_QCA_FM=m`).
- **Flash/test** from nym-nest (`ssh nym-nest-family`): the phone hangs
  off its USB. Working dir `/tmp/ember-f08d8c5-unpack` (jssh, test
  scripts, kernels, ramdisks, `mkbootimg`). Boot images live in
  `~/joan-images/`.
- **Phone storage**: UFS holds LineageOS 22.2 (the fallback; every reset
  lands there). postmarketOS lives on the microSD. We never flash the
  boot partition: bench and default-install kernels are RAM-booted with
  `fastboot boot`. The SD rootfs keeps modules between boots.

### Boot flow

1. The phone is in LineageOS (adb device `LGUS9986e606d55`) or in
   fastboot.
2. `sudo adb -s LGUS9986e606d55 reboot bootloader`, then
   `sudo fastboot boot ~/joan-images/boot-joan-<name>.img`.
3. USB networking comes up: phone 172.16.42.1, nest 172.16.42.2 on
   `enp0s29u1u5` (the scripts add the address).
4. `tools/bench/bootwait.sh` (run on nest) does 1-3 unattended: it waits
   up to 40 min for LineageOS or fastboot, boots `IMG` (default bl17)
   and waits until ssh answers. Start it before asking Lance for a hard
   reset.

`tools/bench/joan-testboot.sh <outdir> <name>` does the whole cycle
from a build dir: packs Image.gz+dtb, makes the boot image
(`mkbootimg` header v0, pagesize 4096, kernel 0x8000, ramdisk
0x2000000, tags 0x100), installs modules on the running pmOS, reboots
and RAM-boots it. This session did the same by hand, reusing bl16's
ramdisk and cmdline
`panic=5 pmos.force-partition-resize ipa.lowmem=1 log_buf_len=8M
modprobe.blacklist=venus_core,venus_dec,venus_enc`.

### Access

`./jssh "<cmd>"` and `./jssh scp <file> user@172.16.42.1:/tmp/` on nest
(password auth, sshpass). For root:
`export JOAN_PW=$(cat ~/.config/joan-bench-pw); ./jssh "echo $JOAN_PW |
sudo -S -p '' <cmd>"`. Never echo the password or print `jssh`.

### Iterating

- Kernel release is `7.2.0-rc2-joan-bl+` for every bench build, so all
  bench builds share one module directory on the SD: install the modules
  that match the kernel you boot (`modules_install` to a staging dir,
  tar, untar into `/lib/modules`, `depmod`).
- Module-only change: `make ... modules`, strip, `zstd`, scp, `install`
  into `/lib/modules/.../kernel/...`, `rmmod`/`modprobe`. A single-module
  target (`make .../foo.ko`) fails modpost; build `modules`.
- **Keep make flags identical** between builds. Dropping `W=1` once
  rebuilt every object (15 min). For a W=1 check of one file:
  `make W=1 path/to/file.o`.
- The phone's `/tmp` is empty after every reboot: copy the scripts again.
- Logs: `sudo dmesg` over jssh; dynamic debug:
  `echo 'module radio_qca_fm +p' > /sys/kernel/debug/dynamic_debug/control`.
  Netconsole (for hangs) is captured with tcpdump on nest
  (`tools/bench/netlite.sh`), no firewall change needed.
- Camera frames: `cam --file=/tmp/x#.ppm`, copy back, view with
  `tools/bench/ppm2png.py in.ppm out.png [scale]`.

### Test scripts (`tools/bench/`, run as root on the phone)

| Script | Does |
|---|---|
| `fmtest.sh` | radio info, tune, tuner status, seeks, mute, Bluetooth off/on, v4l2-compliance |
| `fmsweep.sh` | signal per channel 87.9-107.9, then six seeks |
| `rdscap.sh` | bench only: loads a debug build and logs every FM event |
| `camq.sh` | libcamera Rotation property, frames with stock and candidate tuning |
| `ccichk.sh` | read-only: IMX351 EEPROM versions and the focus controller at 0x3e/0x24 (not run yet) |
| `camcap.sh`, `camvfstress.sh`, `camrace.sh`, `protoY.sh` | capture and the close/reopen stress tests |
| `venus-bisect.sh` (nest side) | one Venus bisect round with `modprobe venus_core <args>` |

### Hazards (each cost time)

- **Never `rmmod` a half-probed driver** (venus_core): it hung the module
  lock. Symptom: ping answers, ssh times out in the banner exchange, the
  UI still works. Only a reboot clears it; `systemd-run --on-active=2
  systemctl reboot` got through in about 8 minutes, otherwise Lance holds
  Power 10-15 s.
- A V4L2 driver must not give its control handler the same mutex as
  `vdev->lock`: the core holds `vdev->lock` around control ioctls too, so
  the first `VIDIOC_QUERY_EXT_CTRL` deadlocks in D state (fixed in
  radio-qca-fm before commit; cost a reboot).
- After reloading `hci_uart`, FM commands were refused as "Bluetooth is
  off" even though setup completed; a reboot fixed it. Unverified guess:
  the controller comes back unconfigured (joan has no BD address and a
  boot-time service sets one). Reboot rather than reload.
- The kernel cmdline carries `androidboot.serialno`; scrub it from
  anything published.
- Never `pkill -f`/`pgrep -f` on the bench (self-match). On LineageOS,
  `ctl.stop vold` and `udevadm trigger --action=add` reboot the SoC.

## What's left to wire up

In rough priority order.

1. **pmaports kernel bump** to 4aef1e1c44eb (adds ffee469280a5,
   d464a5fe2f6d, 0e456d986954 and the four FM commits) with
   `CONFIG_MEDIA_RADIO_SUPPORT=y`, `CONFIG_RADIO_ADAPTERS=m`,
   `CONFIG_RADIO_QCA_FM=m`; build with pmbootstrap, RAM-boot the default
   install, verify camera orientation and `/dev/radio0`.
2. **Default-install audio test with Lance** (still pending from the r30
   round): Firefox/YouTube through the loudspeaker, Sound Recorder. Mic
   read zeros while the greeter's PipeWire was alive; test logged in.
3. **Camera**
   - Look at a Snapshot preview on bl17 or the bumped build: upright?
   - Run `camq.sh`, compare frames with and without LG's colour
     matrices; if better, commit `imx351.yaml` as libcamera r6.
   - Run `ccichk.sh`: which focus controller this unit has (EEPROM map
     version at 0x0BE2; ROHM at 0x3e or Renesas at 0x24).
   - Write the lens driver (V4L2 subdev with `V4L2_CID_FOCUS_ABSOLUTE`,
     `lens-focus` link from the IMX351 node). For ROHM, carry the three
     `bu24235_dl_program_*` pairs in firmware-lge-joan. Protocols in
     `evidence/2026-09-26-camera-quality/README.md`.
   - libcamera's simple pipeline has no autofocus; one has to be added
     for apps to focus.
   - Wide S5K3M3 and front HI553: no drivers anywhere; front will need
     `rotation = <90>` (LG mount angle 270).
4. **FM**
   - Audio: the WCN3990 sends FM audio over the second SLIMbus
     (slim@17240000) to the ADSP; downstream uses the btfmslim codec
     driver. Nothing in mainline yet. Deck #163.
   - Seek sensitivity: stations are detected by SINR; expose the channel
     detection threshold (0x13/0x17) if weak stations matter.
   - A default app: none known in Alpine; `v4l2-ctl`/`rds-ctl` work.
   - FM transmit: the firmware does not answer transmit commands; not
     possible.
5. **Venus**: continue the bisect on `joan/venus-wip` at stop_at 6..10,
   rebooting between rounds (never rmmod), then clk_limit, boot_stage,
   preset_limit. Hardware decode should help video smoothness.
6. **UI/video choppiness**: after Lance uses the UI, collect GPU devfreq
   `trans_stat` and CPU `time_in_state`.
7. **Rest of the matrix** (`joan-hardware-support-matrix.md`): DP alt
   mode (`handoff-2026-09-25-dp-altmode.md`), SLPI sensors (Deck #162,
   15 MiB carve-out), LAB/IBB (#166), SX9320, MMSS SMMU bus vote,
   callaudiod crash, Wi-Fi SMMU faults, Bluetooth `Frame reassembly
   failed (-84)` (seen again at hci_uart probe), boot-log warnings
   (dtc unit addresses, GPU vddcx), config trim (nouveau and other
   community-config bloat), UFS speed, gold boost rows, EAS.

# LG V30 (joan) pmOS port — session handoff (2026-10-03 → next agent)

Written-by: Fulgor Nymvale (agent-fulgor-zcode, ZCode:GLM-5.3-Flash)
Date: 2026-10-03 (night)
Covers: everything known about BOOTING the device + complete issue list.
Canonical deep-history: `lg-v30-port/docs/kernel-change-ledger.md`,
`joan-hardware-support-matrix.md`, journals in `~/.zcode/journal/`
(joan-btfm-fm-audio-port-2026-10-02.md is this arc's running log) and
`~/.hermes/journal/` (earlier arcs).

## 0. Where things live (READ FIRST)

- **All joan code lives on nym-skyforge** (`ssh nym-skyforge-family`,
  `~/vibe-coding-projects/coding/`). nym-nest = harnesses only; its
  lookalike repos are STALE. Bench phone = USB to nym-nest.
- Kernel: `linux-mainline-v30-ember-bootlog` (main working repo).
  **Canonical branch `joan/latest-clean-test`** (everything, all
  history; pushed to origin ShapeShifter499/linux-lg-v30-joan). Only
  decided-fixed work merges to `master`. Naming: pmOS packages are
  "lg-joan-*" (Lance: "lg" not "lge").
- Docs/port repo: `lg-v30-port` (branch claude/lucid-dijkstra-bxx3r9).
- pmaports: `pmaports-lg-v30-clean` branch joan/readme-build-guide
  (remote ghjoan = ShapeShifter499/pmaports-lge-joan). pmbootstrap work
  dir: /data/buildcache/pmbootstrap-joan (device lge-joan-h932).
  **pmbootstrap distfiles = /data/buildcache/pmbootstrap-joan/
  cache_distfiles** (NOT ~/.local/...; a missing distfile makes abuild
  fetch from codeload → 404 for unpushed shas).
- Packages-source repo: `lg-v30-joan-pmos-packages` (ghpkg). New in
  526cbdf: **lg-joan-cellular-data** (rmnet DAD-off udev rule +
  carrier-agnostic NM profile).
- Push policy: Lance approves pushes (he OK'd this session's); never
  push pmbootstrap-built branches without asking.

## 1. How to boot the device (proven procedures)

### Bench topology
Phone USB-plugged into **nym-nest** (adb/fastboot there, `sudo adb`).
Skyforge drives nest over ssh. USB-net: phone = 172.16.42.1, nest =
172.16.42.2, interface `enp0s29u1u5` (name from the gadget). All pmOS
shell access via `/tmp/ember-f08d8c5-unpack/jssh` on nest (recreate from
`lg-v30-port/tools/bench/jssh` if /tmp was wiped; needs sshpass +
JOAN_PW from nest ~/.config/joan-bench-pw). After every boot jump:
`ip link set IF down && up` + ensure 172.16.42.2/24, then wait 60-120 s
for sshd.

### RAM-boot flow (NEVER flash)
`adb reboot bootloader` → `fastboot boot <img>`. Images in
`~/joan-images/` on nest AND skyforge. Healthy known-good:
boot-joan-r31-fm.img (sha 326c596f). Latest line: boot-joan-r36.img
(0a5ce32b) + boot-joan-r36-netc.img (netconsole +6666 UDP to nest).
**Flaky USB is the enemy**: failed writes ("Write to device failed"),
mid-boot disconnects, "second attempt works". First attempt dies →
retry. If the phone ends hung pre-USB (dark, no enumeration): Lance
power-holds it back to LineageOS. LG's boot-failure screen ("any key to
shutdown") = aboot, not pmOS. Watch: **if a reboot lands on the OLD
flashed UFS boot image**, the system LOOKS like the new userland with
the old kernel (same release string!) — always verify /proc/device-tree
nodes, never package lists.

### pkgboot flow (install a new kernel apk the way a user would)
`lg-v30-port/tools/bench/joan-pkgboot.sh <name> <apk>` (runs on
skyforge, drives nest): apk add on the SD rootfs → on-device
mkinitfs+boot-deploy regenerate /boot/boot.img → pull → RAM-boot it.
Modules/initramfs are handled (initramfs needs only 6 .ko; storage is
built-in). After a pkgboot reboot the phone may land on the old UFS
image instead of fastboot — drive it back manually.

### Diagnostics
- **Netconsole**: boot-joan-r36-netc.img pattern — append
  `netconsole=@172.16.42.1/usb0,@172.16.42.2/6666` to the EXACT cmdline
  bytes of the target image (mkbootimg, header v0, pagesize 4096,
  kernel_offset 0x8000, ramdisk 0x2000000, tags 0x100); listener
  `nc -u -l 6666 > log` on nest. USB net is configured by the pmOS
  initramfs, so netconsole works pre-userspace.
- **pstore/ramoops**: matched to downstream layout; only captures PANICS.
  The NGD bus-hang never panics → pstore empty. Kernel hangs pre-USB =
  blind; netconsole is the only eye.
- **SD fsck** (after power cuts): Ember/Aurel's method —
  `lg-v30-port/scripts/sd-fsck-repair.sh check|repair` (AUTH var; uses
  the pmOS initramfs e2fsck 1.47.4 from LineageOS via adb root;
  LineageOS's own 1.46 can't parse the new ext4 features and the LOS
  kernel can't even mount it — EINVAL). Verified clean 2026-10-03.
- sudo on pmOS: `echo "$JOAN_PW" | sudo -S -p ''` with JOAN_PW EXPORTED
  for the jssh wrapper.

## 2. Current canonical kernel content (joan/latest-clean-test =
   229e33997a7a after tonight)

Base: latest-clean-test display line + FM/camera/DVFS line (eeb0335) +
venus enable (3711b3ae443d) + slim2-safe-off merge (229e33997a7a):
- CPU DVFS/CPRh/OSM/LMh stack (schedutil, gold 2361 MHz, thermal 85°C
  junction + LG skin ladder) — boot-validated.
- Display: sw43402 DSC panel driver + panel settle per btfm-line bench
  evidence; NO DPU frame-done flood; MDSS BCR reset not needed.
- GPU A540: UP and validated (GPMU fw, open-loop mV table, GPU VM);
  GX collapse fix 996720c982c1 needs one re-validation on joan.
- Audio: WCD9340 + ES9218P (quad-DAC LPB idle patch d00fb16818b7) +
  TFA9872 speaker (tert MI2S) + UCM package. **Defects pending** (see §3).
- Cellular: modem/ADSP up; DATA WORKS (T-Mobile verified: registered,
  IPv6 ping 55-67 ms, DNS+HTTP) with lg-joan-cellular-data installed.
- Venus video codec: DT enabled (firmware packaged), NOT yet
  boot-validated; userspace still needs the V4L2-request VA-API plugin
  (Alpine libva-v4l2request) for Firefox decode.
- FM radio0 (tuner/RDS) works (needs BT power); FM AUDIO is deferred
  (slim2, see §3).
- Cameras: IMX351 rear works (libcamera CCM "r5" tuning committed; LG
  CCM overlay UNCOMMITTED in pmaports worktree temp/libcamera/imx351.yaml
  awaiting A/B bench test). HI553 front + S5K3M3 wide NOT ported (plan:
  lg-v30-port/docs/camera-completion-plan-2026-10-03.md).
- slim2 (second slimbus engine) is DT-DISABLED on purpose (§3).

## 3. Open issues (ranked)

1. **r34/r36-kernel boot-kill mechanism — bisect VERDICT STILL PENDING.**
   r34 (NGD base formula fixed) hard-hangs ~10 s after `fastboot boot`
   (ADSP ACKs instance-1 QMI but never clocks engine 2; first MMIO
   hangs the bus; no panic). r32/r36 (old formula, harmless wrong
   block) boots. The direct comparison never completed because the
   flaky USB killed every transfer. **Next session first task:** new
   cable/port, boot boot-joan-r36-netc.img (or the slim2-safe-off
   image, which is the SHIP candidate) with 2-3 retries → confirm.
2. **FM audio (slim2)**: deferred by design — slim2-safe-off DT-gates
   the engine off (a dangling codec DAI defer-probes the whole sound
   card). Re-enable lead: per-engine `appsngdN` PDR client naming
   (downstream ngd_dom_init L268-283) vs mainline's shared lookup —
   first bench check: does joan's ADSP fw publish an appsngd3 servreg
   entry? Doc: `lg-v30-port/docs/slim2-access-ordering-2026-10-03.md`.
3. **Audio defects** (agent running — read
   `docs/audio-defects-2026-10-03.md` when it lands): TFA9872 tert
   MI2S set_fmt -524 ×50 (choppy speaker), es9218p reg 0x07 -ENODEV,
   GNOME Settings>Sound empty while pulldown lists devices (UCM/profile).
4. **Venus**: enable-ride pending boot test; userspace V4L2-request
   plugin for browsers.
5. **Cellular package**: DONE + pushed; remaining = VoLTE/SMS via
   joan-imsd (stays inert without operator identity config).
6. **Cameras** (plan doc banked): color CCM A/B test (uncommitted yaml
   in pmaports worktree!), zoom = ScalerCrop plumbing, wide S5K3M3 port
   after HI553 recipe lands (HI553 agent was still running).
7. **Small stuff**: sx9320 SAR (driver only matches sx9324; reg-init
   table is in the downstream dtsi), WiFi MAC/board-data (ath10k picks
   random MAC), DP alt-mode (qmp phy init -16 contention), touch stmfts
   status spam, wireless charging (IDT P9223 driver modernization),
   fingerprint (needs TEE — park).

## 4. Repo/branch map (kernel, after tonight)

- joan/latest-clean-test = 229e33997a7a (canonical; pushed)
- joan/latest-clean-test-merged = same (working branch name)
- joan/ngd-bisect-oldbase = 0bee0898a680 (r36 bisect; pushed)
- joan/slim2-safe-off = 0f648bc9c5d1 (pushed)
- joan/bootlog-fixes = d0d7d4922faa (pre-merge FM line)
- joan/hi553-on-merged = 98b59e81e1a4 (front camera, awaiting agent)
- pmaports joan/readme-build-guide = 53535bb045 (pkgrel 34 pin
  eeb0335... NOTE: uncommitted bisect scratch pkgrel 36/0bee sits in
  the worktree; stash or commit deliberately next session)

## 5. First tasks for the next session, in order

1. Read slim2 + audio defect docs (§3.2/3.3).
2. Boot window (needs USB fixed): boot r36-netc → NGD bisect verdict →
   then build+boot the slim2-safe-off image (ship candidate: expect
   identical boot, no slim2 activity, WCD audio intact).
3. Audio defect fixes from the agent report → bench A/B.
4. Venus boot validation + libva-v4l2request userspace.
5. Camera: color CCM A/B; launch wide-camera agent (HI553 recipe).
6. Sweep remaining dmesg items (wifi MAC, sx9320, DP).
7. Update support matrix + Deck cards as items close.

## 6. Audio defects — digested (agent report: docs/audio-defects-2026-10-03.md)

- set_fmt -524 x50 = -ENOTSUPP: tfa989x HAD NO set_fmt op; sdm845
  machine asks for BT_FC|NB_NF|I2S on every stream open, logs, swallows
  (audio always worked). NOT the choppiness root cause — candidates
  there are amp start/stop churn + device flapping (see report).
  FIXED: 7eda115e6a1c (tfa989x set_fmt validating the wiring) +
  f2b3b9424402 (sdm845: ENOTSUPP from set_fmt = nothing to configure).
- es9218p reg 0x07 -6 = -ENXIO, real I2C NACK: since d00fb16818b7 the
  quad-DAC idles in LPB with RESET_N low (I2C dead), and WirePlumber's
  mixer-restore writes NACK once per boot. FIXED: 0412335d91d7 (regmap
  cache-only while reset, regcache_sync on power-up — idle volume/mute
  writes land when the chip wakes; also enables the pending UCM diff
  that parks the DAC back to LPB on close so MBHC jack detect resumes).
- GNOME Sound panel empty = (a) those NACKs + (b) a boot race with the
  slim-ngd QMI window (~12 s) leaving no sink at login. Bench
  discrimination steps in the report (clean-dmesg restart of
  wireplumber/pipewire-pulse vs stale ~/.local/state/wireplumber).
- Merged into joan/latest-clean-test (42a0c3ec33c1, pushed). Bench:
  build r37 from the canonical tip, expect zero set_fmt/ASoC errors,
  working idle volume, populated sound panel.

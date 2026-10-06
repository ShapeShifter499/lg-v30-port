# Handoff 2026-10-06 (Ember, Claude-Code:claude-opus-5-5) — paused on Lance's request

Goal (Lance): mainline + pmOS default install on the V30 from pmaports. Clean boot
logs, full rated CPU/GPU clocks, thermal, credited code, repos updated, default apps.
Details: `docs/ember-2026-10-06-venus-and-boot-log.md`, `docs/volte-pmos-design-2026-10-06.md`,
ledger entries dated 2026-10-06. Journal: nest `~/.hermes/journal/joan-pmos-mainline-goal-2026-10-06.md`.

## State of the bench
- US998 runs a **fresh pmbootstrap install** on its SD (r47 kernel `75307f90`, device
  r22 + nfc-tags/joan-imsd r6 installed by hand). Password = joan-bench-pw, jssh works,
  Wi-Fi profile restored, cellular data auto-connects.
- Old-SD backup: nest `~/.ember/workspace/joan-sd-backup-20261006/` (NM connections,
  app settings, /home/user without apks, package list). NOT backed up:
  `/etc/joan-imsd/` (may have held isim.env).
- RAM boot = armed send (`tools/bench/ramboot.sh`; memory joan_bench_ramboot_gotchas).
  SD reinstall recipe: memory joan_bench_in_pmbootstrap_marker (read back + md5;
  `adb exec-in` dropped the last 2 KiB).

## Everything is UNPUSHED (Deck #190 awaits Lance)
- **kernel** skyforge `linux-mainline-v30-ember-bootlog` branch `joan/latest-clean-test-merged`,
  `01fd102a..75307f90`. Last pushed = `origin/joan/latest-clean-test` at 01fd102a.
  Local safety tag `ember/pre-rewrite-20261006`.
  - 896747fa GDSC HW_CTRL_TRIGGER (Giuseppe Maggio) → **Venus works** (decode bit-exact, encode OK)
  - 5 DEBUG reverts; 7474d148 bisect knobs removed; 13bca0d0 venus interconnect DT (Giuseppe)
  - be74d03d stmfts 0xba → dev_dbg; f59a1b9b msm fbdev FBINFO_VIRTFB
  - 6c9d1bca venus bitstream floor (unsized stream no longer resets the SoC)
  - 75307f90 **qcom_smbx float voltage rounded up to 4402.5 mV → now 4395 mV** (upstream bug)
- **pmaports** `joan/readme-build-guide`: r47 pin 2fae02d32c, device-lg-joan r22 (neard
  D-Bus activation) + r23 (nfc-tags), nfc-tags 8a3a488173, joan-imsd r5 (decline
  incoming calls with 480, 9f0b2b452b) + r6 (runtime bearer/WDS/mux/IPv6, 43a41ff190).
  Many local "debug pin cycle" commits: **squash before publishing**. The device r22
  APKBUILD half sits in debug commit eebb044cb2.
- **lg-v30-port** docs: 6da58ac, da7dd9e, bad6f67, 3fcabe5, 5f724ed, 1b1c960, 88cbcb4 + this file.
  Remote = ghpub. Untracked earlier-agent files left alone.

## Measured facts (don't redo)
- Boot err+warn 127 → ~46-53 (the rest triaged in the findings doc).
- CPU: speed bin 2; 2361.6 MHz all-core = rated max (we run it). LG's 2.45 GHz is a
  single-core boost; LMh/thermal in place (85 °C passive, 110 critical, skin ladder).
- FM TX: **not in hardware** (positive-controlled HCI probe). AM impossible.
- TV tuner: KR/JP boards only; the US998 has no I2C tuner bus (LDO28 pull-up test).
- WCN3990 FM RX tuner works (radio-qca-fm); **FM audio blocked**: slim2 NGD hard-hangs
  the SoC (no watchdog recovery) → bench only with Lance present (plan in findings doc).
- The modem has **no IMSA/IMSS** → VoLTE must be AP-side (LG/AOSP model). PDC: 7 MCFGs,
  TMO active, hVoLTE-Verizon present.

## Next, in order
1. **Lance decisions:** push approval; joan-imsd auto IMS bearer + REGISTER on the bench;
   try a modem MCFG switch for modem-side IMS; phone-in-hand tests (SMS in, incoming
   call → 480/voicemail, NFC tag read/write, slim2 FM audio).
2. **CPU single-core boost** (was in progress at pause): gold OPPs 2323.2/2342.4/2361.6
   map to cprh_opp28/29/30. LG perfcl-speedbin2 adds 1-core rows 2419.2/2438.4/2457.6
   at the same corners (LUT word [18:16] = 1). `qcom-cpufreq-osm.c` writes
   core_count=4 and VC=row index, so it needs row≠corner support (an OPP property for
   core count + VC from required-opps). Same voltages as the twins; never exceed bin 2.
3. VoLTE design steps 2-3: D-Bus API on joan-imsd → GNOME Calls "ims" provider
   (reuse the SIP media pipeline). SMS over IMS (SIP MESSAGE is unhandled today).
4. DP alt-mode (qmp-usbc "configured for USB, cannot enable DP"), camera pipeline,
   per-model DTBs (Lance decision: wifi calibration variant + H932 model string).
5. Open mystery: one unexplained reset into Lineage ~02:15 (not reproduced).

### The 02:15 reset was not the TV-tuner probe (timeline)
02:13 final r47 RAM boot plus check set, all passing. Tuner research then ran on
skyforge only (LG DT/defconfig greps, nothing on the phone). ~02:16 the first
phone-side tuner command (read-only GPIO/regulator) found the phone already reset
into LineageOS. The only active tuner test (LDO28 at 1.8 V) was at 02:30 on a later
boot, and the phone stayed up through it. The cause is still unknown and was not
reproduced (10+ min idle plus the same tests under a live dmesg stream).

## Addendum 08:20 — CPU/GPU/media pass (paused at 95% usage)

**Kernel (skyforge, local, unpushed):** `joan/latest-clean-test-merged` =
`56b9e9e5` (gold 2457.6 MHz rows, verified) → `b9bd3534` (Venus EOS on a real
zero-length buffer, verified: GStreamer v4l2h264dec to clean EOS, decodebin picks it)
→ `d6e7bf12` **DEBUG (do not ship)** icc write-debugfs test client. **Drop d6e7bf12
before any release.** Parked: branch `ember/gpu-bw-wip` (367616ca, GPU per-OPP
bandwidth on gfx-mem only).
**pmaports:** linux-lg-joan pin currently points at a DEBUG build. **Re-pin r47 to
b9bd3534** (`/tmp/build-cycle.sh` with a proper message) before publishing.
New `temp/ffmpeg` (Alpine 8.1.2-r3 + v4l2-m2m-default-timebase.patch, pkgrel 4).
Its aarch64 build was started 08:03 (log
`/data/buildcache/pmbootstrap-joan/build-ffmpeg.log`), not yet tested or committed.
**Bench:** the phone may be in LineageOS or hung after the last icc test. Release r47
boot.img: skyforge-built 56b9e9e5; the SD /boot holds the DEBUG kernel → reinstall.

### Findings (all measured)
- **GPU bandwidth hang = DDR downward frequency switch**, not the GPU. icc test client
  on mas-oxili→slv-ebi with the GPU idle: static 8.1 → 12.4 → 14.4 GB/s ok;
  toggling 3.3↔14.4 hangs; a **single step 14.4→12.4 hangs**. Upward steps pass. Our
  msm8998 icc driver is local (7d9b74b7, Aug 4), not upstream; nobody upstream or in
  pmOS scales a5xx/msm8998 DDR. The adreno placeholder (fast_rate*8 = 5.68 GB/s) is
  never released in our a5xx_gpu.c, so DDR never drops below ~710 MHz today (a power
  cost). The earlier GPU lockup with per-OPP votes was this hang plus the unused
  gfx-l3 path. Next: compare the downward BIMC request sequence with downstream msm_bus
  / RPM (active vs sleep set, keep_alive, channels=2 rate math), then retry
  ember/gpu-bw-wip.
- **Firefox HW decode:** WebRender + WebGL on FD540 OK. V4L2 decode needs
  `media.hardware-video-decoding.force-enabled`. With FFmpeg 8.1 the DRM-PRIME frame
  now arrives (Mozilla bug 1852765's old blocker is gone), but pts=NOPTS because
  Firefox sets no timebase and upstream v4l2_get_timebase divides by 0/1. The RPi
  FFmpeg fork already falls back to microseconds (`tb.num && tb.den ? tb :
  v4l2_timebase`); our temp/ffmpeg patch does the same. Then: test Firefox playback
  (decoder must hold /dev/video* for the whole clip) and decide on a device pref for
  force-enabled.
- **Venus encoder via GStreamer** (v4l2h264enc) asserts the firmware mid-stream
  (vbuffer.c:1219) → failed recovery → SoC reset. Lower its GStreamer rank in the
  device package until fixed. Venus firmware-crash recovery resets the SoC (separate bug).
- **CPU:** done (see the earlier sections). GPU = FD540 GLES 3.1, no Vulkan, glmark2 119.
- Research sources: Mozilla bugs 1852765 and 1852560; jc-kynesim/rpi-ffmpeg
  v4l2_buffers.c; msm8939 Venus RFC (uses HW_CTRL, msm8998 needs HW_CTRL_TRIGGER).

### Banked state (08:35, supersedes the "drop/re-pin" notes above)
- Kernel `joan/latest-clean-test-merged` reset to **b9bd3534** (shippable). The debug
  commit is kept as local tag `ember/icc-debugfs-client-20261006`.
- pmaports `aa10320088` pins linux-lg-joan r47 to b9bd3534 (distfile staged, sha512
  set; **not built yet**: run `pmbootstrap build linux-lg-joan --force`). The debug
  pin commits db6834cbfa..c3a453d428 should be squashed before pushing.
- `temp/ffmpeg/` stays **uncommitted**. The timebase patch applies cleanly, but
  configure fails with `SvtAv1Enc >= 0.9.0 not found using pkg-config` (a build
  dependency problem, not the patch). Next: check the svt-av1-dev version and .pc
  name in the aarch64 buildroot, or drop `--enable-libsvtav1` for this override.
- Nothing pushed. Push and squash need Lance's approval (Deck #190).

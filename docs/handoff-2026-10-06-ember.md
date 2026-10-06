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

# Session 2026-10-03 (Ember) — r37→r41, rename to lg-joan, memory map

Written-by: Ember (Claude-Code:claude-opus-5-5)
Picks up: `docs/handoff-2026-10-03-boot-and-open-issues.md` (Fulgor)

## Bench results (US998, RAM boot only — nothing flashed)

| build | kernel | result |
|---|---|---|
| r32 baseline | `#32` (phone was on the old UFS image while the SD had r36) | 52 `set_fmt`, es9218p reg 0x07 `-6`, 68 err/fail lines |
| r37 | `42a0c3ec33c1` | `set_fmt` 0; es9218p now `-16`; Venus firmware-name absent (`venus.mbn`); **silver OSM `-110`**, no policy0 |
| r38 | `b05c2695e4bf` (venus.mdt) | **reset into LineageOS within ~1 min**, pstore empty |
| r38 + `modprobe.blacklist=venus_core,venus_dec,venus_enc` | same image | `running`; es9218p errors 0 → Venus is the r38 reset |
| r39 | `3334adbe68f2` (Venus off, OSM ACD fix) | `running`; policy0 300–1900.8, policy4 300–2361.6 (schedutil); cooling cpu0+cpu4+gpu; 0 WARN, 0 ASoC, 12 err/fail |
| r41 | `4c3d1585c595` (rename + memory map) + all packages renamed | `running`; modem/ADSP up; Wi-Fi OK; both clusters OK. Cellular IPv6 got no replies and PipeWire listed no device — see Open |

The silver OSM failure was 1 of 3 untreated boots: intermittent. The fix
(`36be1fd7879e`, ACD programmed via `work_on_cpu()` on the target cluster)
has 2 clean boots so far; keep it off `master` until several more.

## Commits

linux-lg-v30-joan, `joan/latest-clean-test` (pushed to `4c3d1585c595`):
- `df9cb24dd699` ASoC: es9218p: seed the system-mute register cache before going cache-only
- `b05c2695e4bf` arm64: dts: msm8998-lge-joan: load Venus firmware from venus.mdt
- `36be1fd7879e` cpufreq: qcom-osm: program each cluster's ACD from a CPU of that cluster
- `3334adbe68f2` arm64: dts: msm8998-lge-joan: keep Venus disabled, it wedges the SoC
- `74dc95f2789a` arm64: dts: rename lge-joan to lg-joan, compatible lg,joan
- `4c3d1585c595` arm64: dts: msm8998-lg-joan: take the memory map from LG's final builds

`master` (verified only) pushed to `1492105184d6`: tfa989x `set_fmt` op +
sdm845 `-ENOTSUPP` handling (bench-verified on r37). The es9218p cache fixes
depend on the LPB-idle patch `d00fb16818b7`, which is not on master.

Topic branches (local, not merged):
- `joan/venus-porthole-canonical` — porthole's 24-patch Venus series rebased onto canonical (applies clean)
- `joan/slpi-enable` (`d1cdbea80ebd`) — boot the sensor DSP; test image `boot-joan-r41-slpi.img`

pmaports-lge-joan `joan/readme-build-guide`: pushed to `d601b0f73c` (rename,
kernel pinned `74dc95f2789a`). Local only: `6c961a4fa2` (pin `4c3d1585c595`,
waits for the A/B). The default branch `device-lge-joan` is still the
2026-09-06 pre-alpha (134 commits behind) — moving or renaming it is Lance's call.

lg-v30-joan-pmos-packages `master`: pushed `260ecfd` (rename + resync; this
copy had drifted behind the fork).

## Rename to lg-joan

postmarketOS uses `lg-<codename>` for LG devices and the kernel DT prefix is
`lg,` (`lge,` is not in vendor-prefixes.yaml). Each renamed package has
`provides=<old>=$pkgver-r$pkgrel` + `replaces=<old>`. Upgrade tested on the
bench SD: `apk upgrade` from a repository holding the new packages purges every
lge-joan package and installs its successor in one transaction.

Bench-only gotchas found on the way:
- Packages installed from a local `.apk` file are pinned in `/etc/apk/world`
  by checksum (`name><Q1…`) and never upgrade; `apk add <name>` unpins.
- A local test repository needs a `noarch` path (symlink to `aarch64`) or noarch
  packages fail with "package mentioned in index not found".
- `apk add -u` upgrades dependencies too — it pulled 14 distro updates
  (incl. pipewire 1.6.8→1.6.9) onto the bench SD. That is a confound for the
  r41 audio observation.

## Open (ordered)

1. **Phone off USB since ~09:53** after failed `fastboot boot` sends + `fastboot
   reboot-bootloader`. Needs a manual power-hold back to LineageOS.
2. **r41 A/B**: `boot-joan-r41-oldmapdtb.img` (same boot.img, pre-map DTB).
   Order new→old→new. Check cellular IPv6 (`validate.sh`) and audio.
3. **Audio on r41**: kernel bring-up identical to r39 → check
   `journalctl --user -u wireplumber` (pipewire 1.6.9 / spa skew; UCM path now
   `Qualcomm/sdm845-lg-joan`). `70-joan-rmnet-nodad.rules.apk-new` was not applied.
4. **SLPI**: boot `boot-joan-r41-slpi.img`. Userspace: SMGR (sensor1) QMI —
   libssc only speaks SEE (sdm845+), so this needs RE.
5. **Venus**: bisect on `joan/venus-porthole-canonical`. `stop_at=N` runs the
   checkpoints *below* N, so joan surviving `stop_at=5` means only steps 1-4 ran
   (clocks/IRQ/runtime PM/bus votes); `core_power()` (5) was never exercised.
   Next: `stop_at=6`; if that wedges, porthole's `clk_limit` / `preset_limit`
   inside step 5 (the Pixel 2 wedge was there: first VBIF preset write). If 5
   passes, suspect step 6, the probe-time `set_remote_state(RESUME)` on a
   never-booted core: porthole notes Google's TZ answers -EINVAL, and LG's TZ
   is a different build.
6. **Gold single-core boost (2457.6 MHz)**: needs the OSM driver to stop equating
   LUT row with virtual corner — MEM-ACC pairs, APM threshold and the LUT VC field
   all key on `i`; downstream keys them on `virtual_corner` and interleaves 1-core
   rows on the same corner as their 4-core partner. Not a DT-only change.
7. SX9320 SAR: disabled (`f184bc3341bb`) — orphan LG dtsi, absent from all 20 stock DTBs, NACKs on the US998.
8. DP alt mode: driver + DT are in; the boot-time `phy init failed -16` is the DP side meeting the USB3-held PHY (exclusive on this PHY). Needs a USB-C→HDMI/DP adapter on the bench.
9. Kernel config trim: the pmaports config builds nouveau, mlx5, XFS, …;
   ccache already hits 90%, the rest of the build time is the module set.

## Bench queue for the next window (all RAM boot; nest `~/joan-images/`)

Tools: `tools/bench/ramboot.sh <img>`, `tools/bench/validate.sh <tag>`.
Phone must first be back in LineageOS (power-hold) — Deck #180.

1. **Memory-map A/B** (order new → old → new):
   `boot-joan-r41-lg.img` (new map) / `boot-joan-r41-oldmapdtb.img` (same image,
   pre-map DTB). Per boot: `validate.sh`, then cellular IPv6 ping over
   `qmapmux0.0`, `wpctl status`, and `journalctl --user -u wireplumber -b`.
   If audio is empty on both, it is the pipewire 1.6.9 / UCM side, not the map.
2. **bootmac**: install `device-lg-joan-1-r21.apk`; after reboot `ip link show
   wlan0` twice across reboots — same `02:00:…` address both times.
3. **SLPI**: `boot-joan-r41-slpi.img`; expect `remoteproc … slpi is now up`;
   any reset → try adding the `aggre2` NoC clock vote stock uses.
4. **Venus bisect**: install `linux-lg-joan-7.2.0_rc2-r42.apk` (Venus test
   build), repack the device boot.img with
   `modprobe.blacklist=venus_core,venus_dec,venus_enc`, then
   `modprobe venus_core stop_at=6` (reboot between rounds; never rmmod).
   Go back to r41 afterwards.
5. **DP alt mode**: needs a USB-C→HDMI/DP adapter (Lance).
6. Read `/mnt/vendor/persist-lg/wifi/wlan_mac.bin` from LineageOS (`adb root`,
   drm partition) to confirm its format — read only.

## Decision needed: per-variant Wi-Fi calibration (and model string)

The blob mirror carries three different stock WLAN board files —
`h930` (`a0413c22…`), `h932` (`36ed7a78…`), `us998` (`0ff6ab82…`) — and a
`common/…/board-2.bin` holding all three as
`bus=snoc,qmi-board-id=ff,qmi-chip-id=30214,variant=LG_joan_{h930,h932,us998}`.
ath10k only picks a variant when the DT sets `qcom,calibration-variant`; the
single joan DT sets none, so the lookup misses (the boot-time "failed to fetch
board data … board-2.bin" line) and ath10k falls back to `board.bin`, which on
a US998 is the **H930** file from `firmware-lg-joan-h930` — non-US
regulatory/power tuning on a US unit.

Upstream-style fix: `msm8998-lg-joan.dtsi` + per-model `msm8998-lg-joan-h930.dts`,
`-h932.dts`, `-us998.dts`, each with its `qcom,calibration-variant` and a true
`model` (today every unit reports "LG V30 (US998)"). All variants share the
same board-ids, so aboot cannot choose between appended DTBs: the US998 needs
its own pmbootstrap device (`lg-joan-us998`, firmware = h930 set, which matches
US998's NON-HLOS byte for byte per the blob README). That adds a device a user
has to pick, so it is Lance's call; nothing is changed yet.

## Clocks, thermal, FM — checked against stock (2026-10-03, offline)

- **Clock ceilings vs stock:** GPU 710 MHz = stock's only v2 table (no GPU bins).
  Silver 1900.8 MHz = stock's single `pwrcl-speedbin0` table (no other silver bins).
  Gold 2361.6 MHz all-core = bin-2 max; only the 1-core 2457.6 boost is missing
  (design: `docs/cpu-gold-boost-design-2026-10-03.md`).
- **Thermal vs LG's `thermal-engine-8998.conf`:** skin ladder (vts weighted sensor),
  CPU 85/80 and GPU 85/65 junction rules were already ported. Added the missing
  SS-POPMEM rule: `233f7e59dfa7` (gold cluster throttled at 85 C pop_mem, release 65 C;
  pop_mem = tsens1 hw ch2 via downstream's client map `<0 1 3 4 5 6 7 2>`).
  Not ported: CHG_MONITOR/WLCHG_MONITOR (charge-current limits by skin temp) —
  needs a charger cooling device.
- **FM transmitter:** joan has none. WCN3990 Helium FM is receive-only; LG builds only
  `SND_FM_RX_MI2S`, and the `*tx*` strings in stock `libfm-hci.so` are the HCI command
  path. FM RX tuner works (radio0); FM audio still blocked on slim2.
- **r44 package** (PCI off + SAR off + bu24235): 44 MB vs 51 MB, 1262 modules; staged
  on nest `~/joan-images/linux-lg-joan-7.2.0_rc2-r44.apk`, not booted.

## Bench tooling added

- `tools/bench/ramboot.sh <img>` — from pmOS/LineageOS/fastboot to RAM boot;
  `--reboot-argument=bootloader` (systemd 262 rejects a positional argument),
  getvar before every send, 90 s send limit, fastboot reset between tries.
- `tools/bench/dtbswap.py <base.img> <dtb> <out.img>` — DT-only variants of a
  known kernel without rebuilding.
- `tools/bench/validate.sh <tag>` + `validate-remote.sh` — one-shot subsystem check.
- `tools/bench/usbwatch.sh` — passive log of the phone's USB identity.

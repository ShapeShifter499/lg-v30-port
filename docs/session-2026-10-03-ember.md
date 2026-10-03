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
7. Kernel config trim: the pmaports config builds nouveau, mlx5, XFS, …;
   ccache already hits 90%, the rest of the build time is the module set.

## Bench tooling added

- `tools/bench/ramboot.sh <img>` — from pmOS/LineageOS/fastboot to RAM boot;
  `--reboot-argument=bootloader` (systemd 262 rejects a positional argument),
  getvar before every send, 90 s send limit, fastboot reset between tries.
- `tools/bench/dtbswap.py <base.img> <dtb> <out.img>` — DT-only variants of a
  known kernel without rebuilding.
- `tools/bench/validate.sh <tag>` + `validate-remote.sh` — one-shot subsystem check.
- `tools/bench/usbwatch.sh` — passive log of the phone's USB identity.

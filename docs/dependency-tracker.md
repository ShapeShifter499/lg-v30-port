# Dependency tracker — packages and sources this project pulled in

Every host package installed and every external source downloaded for this
project gets a row here, at the time it happens. This keeps the build host
reproducible, makes cleanup possible, and tells the next contributor what
they'll need. **Maintaining this file is a binding convention** (see README
"Conventions"): if your session installs or downloads something, add a row
in the same session, with your attribution.

Rules:

- Record host-level installs (pacman/apk/pip/etc.), external repo clones,
  and one-off source/binary downloads. Chroot-internal packages managed
  automatically by a tool (e.g. pmbootstrap's Alpine chroots) get one row
  for the tool's cache location, not one per package.
- If you find an untracked dependency from before this file existed, add
  it with whatever provenance is known and mark the unknowns.
- Removal/cleanup also gets a row (don't delete history rows).

## Host packages

| Date | Item | How | Why | By |
|---|---|---|---|---|
| pre-2026-07-04 | `aarch64-linux-gnu-gcc` 16.1 + binutils | pacman | kernel cross-toolchain | Ember (exact date unrecorded) |
| 2026-07-04 | `android-tools` (adb/fastboot) | pacman | device access | Ember |
| pre-2026-07-06 | `mkbootimg` | pacman (likely with android-tools; unrecorded) | Android boot.img packaging | unrecorded |
| 2026-07-11 | `pmbootstrap` 3.10.3 | pacman | postmarketOS build tooling (M3) | Ember |
| 2026-07-11 | `pahole` | pacman | kconfig BTF resolution for the pmOS kernel config (PAHOLE_VERSION) | Ember |

## Sources / repos / downloads

| Date | Item | From | Where it lives | Why | By |
|---|---|---|---|---|---|
| 2026-07-04 | mainline kernel tree | kernel.org/torvalds git | `~/vibe-coding-projects/coding/linux-mainline-v30` | the port itself | Ember |
| 2026-07-04 | LG downstream kernel (LineageOS 22.2, lineage-22.2 merge) | github.com/LineageOS | `~/vibe-coding-projects/coding/android_kernel_lge_msm8998` | read-only reference | Ember |
| 2026-07-06 | `busybox-static-1.37.0-r31.apk` (aarch64) | Alpine package mirror | `lg-v30-port/initramfs/` (apk retained in-repo) | bringup initramfs userland | Ember |
| 2026-07-07 | edk2-msm8998 UEFI port | github.com/edk2-porting | `~/vibe-coding-projects/coding/edk2-msm8998` | behavioral reference / escape hatch | Ember |
| 2026-07-11 | pmaports checkout | gitlab.postmarketos.org/postmarketOS/pmaports | `~/.local/var/pmbootstrap/cache_git/pmaports` (fork: github.com/ShapeShifter499/pmaports-lge-joan) | pmOS device port | Ember (via pmbootstrap) |
| 2026-07-11 | linux-lg-v30-joan source tarball @ ce78c1369 | github.com/ShapeShifter499 (our own fork) | pmbootstrap cache (`cache_distfiles`) | pmOS kernel package build | Ember (via pmbootstrap) |
| 2026-07-11 | Alpine chroots + packages (native + aarch64) | Alpine/postmarketOS mirrors | `~/.local/var/pmbootstrap/` (managed by pmbootstrap; `pmbootstrap zap` cleans) | pmOS rootfs/kernel build environment | Ember (via pmbootstrap) |
| 2026-07-11 | joan panel/DSC/board dtsi (3 files) | LG/LineageOS downstream `android_kernel_lge_msm8998` (GPL-2.0) | `docs/downstream-refs/` | SW43402 panel data for the mainline driver (P2) | Ember |

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-11

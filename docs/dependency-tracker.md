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
| pre-2026-07-04 | `aarch64-linux-gnu-gcc` 16.1 + binutils | pacman | kernel cross-toolchain | Claude Code (exact date unrecorded) |
| 2026-07-04 | `android-tools` (adb/fastboot) | pacman | device access | Claude Code |
| pre-2026-07-06 | `mkbootimg` | pacman (likely with android-tools; unrecorded) | Android boot.img packaging | unrecorded |
| 2026-07-11 | `pmbootstrap` 3.10.3 | pacman | postmarketOS build tooling (M3) | Claude Code |
| 2026-07-11 | `pahole` | pacman | kconfig BTF resolution for the pmOS kernel config (PAHOLE_VERSION) | Claude Code |
| 2026-08-02 | `dtschema` 2026.6 and `yamllint` 1.38.0 | `uv pip install` into disposable `/tmp/v30-dtschema-venv` | kernel `gpu.yaml` schema, style, example-DTB validation | Hermes Agent |
| 2026-08-11 | `dtschema` 2026.6 and `yamllint` 1.38.0 | `uv pip install` into isolated `/data/buildcache/venvs/dtschema`; no Arch-repository package existed, so no machine-wide install was made | repeatable MSM8998 GPU binding and compiled-DTB validation for the clock-ownership audit | Hermes Agent |
| 2026-08-13 | `dtschema` 2026.6 and dependencies | `uv pip install dtschema` into isolated `/data/buildcache/tools/dtschema-venv` | redundant Card 94 validation environment created after the already-tracked `/data/buildcache/venvs/dtschema` was missed during PATH discovery; retained pending owner-approved cleanup, and the existing tracked venv was used for qualification | Hermes Agent |

## Sources / repos / downloads

| Date | Item | From | Where it lives | Why | By |
|---|---|---|---|---|---|
| 2026-07-04 | mainline kernel tree | kernel.org/torvalds git | `~/vibe-coding-projects/coding/linux-mainline-v30` | the port itself | Claude Code |
| 2026-07-04 | LG downstream kernel (LineageOS 22.2, lineage-22.2 merge) | github.com/LineageOS | `~/vibe-coding-projects/coding/android_kernel_lge_msm8998` | read-only reference | Claude Code |
| 2026-07-06 | `busybox-static-1.37.0-r31.apk` (aarch64) | Alpine package mirror | `lg-v30-port/initramfs/` (apk retained in-repo) | bringup initramfs userland | Claude Code |
| 2026-07-07 | edk2-msm8998 UEFI port | github.com/edk2-porting | `~/vibe-coding-projects/coding/edk2-msm8998` | behavioral reference / escape hatch | Claude Code |
| 2026-07-11 | pmaports checkout | gitlab.postmarketos.org/postmarketOS/pmaports | `~/.local/var/pmbootstrap/cache_git/pmaports` (fork: github.com/ShapeShifter499/pmaports-lge-joan) | pmOS device port | Claude Code (via pmbootstrap) |
| 2026-07-11 | linux-lg-v30-joan source tarball @ ce78c1369 | github.com/ShapeShifter499 (our own fork) | pmbootstrap cache (`cache_distfiles`) | pmOS kernel package build | Claude Code (via pmbootstrap) |
| 2026-07-11 | Alpine chroots + packages (native + aarch64) | Alpine/postmarketOS mirrors | `~/.local/var/pmbootstrap/` (managed by pmbootstrap; `pmbootstrap zap` cleans) | pmOS rootfs/kernel build environment | Claude Code (via pmbootstrap) |
| 2026-07-11 | joan panel/DSC/board dtsi (3 files) | LG/LineageOS downstream `android_kernel_lge_msm8998` (GPL-2.0) | `docs/downstream-refs/` | SW43402 panel data for the mainline driver (P2) | Claude Code |
| 2026-07-11 | `msm8998-mainline/linux` public reference @ `2b7263ccccbdafba3e8696349d9a3e9b115c6dd8` (clock commits `878adc31071b` and `707f3fc86f6a`) | `https://gitlab.com/msm8998-mainline/linux.git` | `/tmp/msm8998-mainline-linux-ref` (filtered/sparse reference clone) | compare known MSM8998 MMCC/DSI clock fixes after K062; preserve the exact 10nm VCO fix and original author | Hermes Agent |
| 2026-07-11 | MSM8998 DSI regulator mapping | mainline `drivers/gpu/drm/msm/dsi/dsi_cfg.c`, downstream `msm8998-mdss.dtsi`, and public working MSM8998 OnePlus DTS | source trees already listed in this tracker | prove joan's controller `vdd` rail maps to PM8998 L1 while `vdda` maps to L2; basis for K067 | Hermes Agent |
| 2026-07-11 | MSM8998 DSI PLL pre-lock output-divider ordering | downstream `drivers/clk/msm/mdss/mdss-dsi-pll-8998.c` compared with mainline `drivers/gpu/drm/msm/dsi/phy/dsi_phy_10nm.c` | source trees already listed in this tracker | explain K068's stale `/4` state and select the next bounded diagnostic; no downstream code copied | Hermes Agent |
| 2026-07-11 | upstream 10nm DSI initial VCO-rate fix `8a48e35becb214743214f5504e726c3ec131cd6d` | `https://github.com/torvalds/linux/commit/8a48e35becb214743214f5504e726c3ec131cd6d` / linked lore and Patchwork discussion | read-only network reference; current upstream raw source compared, no new checkout | explain K070's zero initial `vco_current_rate` and its interaction with local/public-reference VCO formula fix | Hermes Agent |
| 2026-08-02 | Linux master source snapshot `2d2338c93da79b3bfe4b6099a931d9468d539952` | `https://github.com/torvalds/linux` raw/API | `out/audit-20260802/upstream-linux-2d2338c93da79b3bfe4b6099a931d9468d539952/` plus disposable `/tmp/v30-upstream-audit` | compare joan brightness/GPU changes with current upstream and validate binding shape | Hermes Agent |
| 2026-08-02 | `linux-firmware` `WHENCE` at `a968c5c2962e0bad2482f4b05a3fb627b871ca89` | `https://gitlab.com/kernel-firmware/linux-firmware` | disposable `/tmp/linux-firmware-WHENCE-20260802`, SHA-256 `b78facd5dcc32f3cb079f0727104408acbedde17547569557c28f02030c099f9` | verify redistributability boundary: A530 PM4/PFP are listed; joan A540 GPMU/ZAP are not | Hermes Agent |

Assisted-by: Claude-Code:claude-fable-5
Date: 2026-07-11

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-11

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-02

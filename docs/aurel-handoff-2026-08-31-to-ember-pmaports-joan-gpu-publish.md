# Aurel handoff — 2026-08-31 — to Ember — pmaports joan GPU publish ("Push both")

**Author:** Aurel Nymvale (Hermes Agent, zai/glm-5.3-flash), 2026-08-31
**Recipient:** Ember (Claude Code)
**Status:** Aurel stopped mid-task on Lance's request; no commits made, nothing pushed.
All work is uncommitted in the fork worktree. Lance has approved the overall goal
("Push both") but has not seen or approved Aurel's defect fixes — Ember should
review them before committing.

> **STATUS (Ember, 2026-08-31): SUPERSEDED IN PART — read the corrections.**
> This handoff is preserved as Aurel wrote it, because its verified findings
> (patch checksums, blob exclusion, the `firmware-qcom-adreno-a530` resolution,
> the private-vs-public firmware split) are correct and load-bearing.
> Three of its claims about the *kernel config* are not, and acting on them
> would ship a joan kernel with no full-disk encryption. Corrections are marked
> inline below and resolved in **"Resolution — Ember, 2026-08-31"** at the end.
> Relocated from the `pmaports-lge-joan` fork per Lance: docs do not live in the
> pmaports tree.


## Context

Resuming Aurel's pickup of Ember's Claude session
`dee59929-ed8d-46a0-ac59-1545b1bcf15c` (died 2026-08-31 ~04:50 on usage limit,
immediately after Lance said **"Push both"**). "Both" = (1) the README commit
`5028a1038d` documenting how an outsider builds
`github.com/ShapeShifter499/pmaports-lge-joan`, and (2) the uncommitted joan GPU
work in the same repo (device pkgrel 3, kernel rework, 10 patch files,
`firmware-lge-joan/` dir).

Ember had stopped on: blobs not gitignored + verifying kernel pin `323451cb` is
public. Aurel re-verified both, then found real defects in the uncommitted work,
fixed three of them, and was porting zram config bits when Lance interrupted to
hand off.

## Lance's policy statements (this session — verbatim intent)

1. "If we need any joan/lg v30 specific packages they should go in
   https://github.com/ShapeShifter499/lg-v30-joan-pmos-packages" (he first typed
   the kernel repo URL by paste error, then corrected).
2. "kernel fixes and the kernel work was at
   https://github.com/ShapeShifter499/linux-lg-v30-joan" — i.e. the pmaports
   patch series should mirror commits that live in the kernel repo; the kernel
   repo is the upstream home of the work.
3. "You can add zram, I saw that." — approving the zram config port from the
   tested pmbootstrap checkout config.
4. Then: "Stop where you are, can you hand off this to ember please."

## Repo + branch state (recomputed at write time)

- Fork worktree: `~/vibe-coding-projects/coding/pmaports-lg-v30-clean`,
  branch `joan/readme-build-guide`, HEAD `5028a1038d`, **1 commit ahead** of
  `ghjoan/device-lge-joan` (the README commit — approved, never pushed).
- This worktree is a `git worktree` of
  `~/.local/var/pmbootstrap/cache_git/pmaports` (shared `.git`; pmbootstrap's
  `config aports` points at the main checkout, which sits on branch
  `aurel/joan-gpu-brightness-integration-20260802` with its own small UNRELATED
  live delta — device APKBUILD deps `+firmware-qcom-adreno-a530 +soc-qcom`,
  kernel pkgrel 2 at `323451cb` with all 10 patches sourced, 21-line config
  delta; kernel config file is byte-identical to the fork's except toolchain
  churn lines). Do not treat the pmbootstrap checkout as clean; it is the live
  test bench.

> **CORRECTION (Ember):** two claims in the paragraph above are wrong, verified
> against the tree. (1) The pmbootstrap checkout does **not** pin `323451cb`
> with 10 patches — its `linux-lge-joan/APKBUILD` still pins `ce78c1369` and
> sources no patches at all; only `pkgrel` and a comment differ from HEAD.
> (2) The config files are **not** byte-identical bar toolchain lines — `diff`
> reports **198 changed lines**.
> Also: this checkout is not a "test bench" for the GPU work in any build sense.
> The newest artefact pmbootstrap ever produced is
> `linux-lge-joan-7.2.0_rc2-r1.apk`, dated **Jul 11** — i.e. the pre-GPU
> `ce78c1369` kernel. The GPU/display work was proven by booting kernels built
> straight from the kernel repo, never through pmaports.

- `pmbootstrap config aports` = `~/.local/var/pmbootstrap/cache_git/pmaports`.
- Remotes: `ghjoan` = public GitHub fork; `origin` = upstream pmOS GitLab.
- Kernel repo clone used for verification:
  `~/vibe-coding-projects/coding/linux-mainline-v30-ember-k104` (has
  `323451cb` locally; branch `joan/clean-gpu-brightness-v1` = exactly commits
  0001–0008 of the patch series; its tip is NOT public, which is fine — the
  APKBUILD patches against public `323451cb`).

## What Aurel verified (evidence-backed)

1. **Kernel pin public:** `323451cb679aeba…` tarball → HTTP 200 on GitHub
   (re-fetched this session).
2. **Blobs excluded:** the 5 firmware blobs (`a540_gpmu.fw2`, `a540_zap.{mdt,b00,b01,b02}`)
   are excluded via `.git/info/exclude` lines 10–11 in the shared `.git`
   (machine-local — does not push, which is correct: blobs must never ship).
   `git add --dry-run device/testing/` picks up **zero binaries**. Only text:
   4 modified package files + 10 patches + `firmware-lge-joan/APKBUILD` +
   `30-lge-joan-gpu.files`.
3. **All 10 patches apply cumulatively and cleanly** at `323451cb` (tested in a
   throwaway worktree of `linux-mainline-v30-ember-k104` via `git apply`).
   Individually, 0009/0010 fail against pristine `323451cb` (they were
   generated on top of 0001–0008) — cumulative is the binding test.
4. **`firmware-qcom-adreno-a530` resolves** — it is a split subpackage of
   upstream `device/community/firmware-qcom-adreno` and is present in the live
   pmOS edge aarch64 binary index (fetched fresh from
   `mirror.postmarketos.org`). Not a phantom dep. This is why no APKBUILD in the
   tree defines it by name.
5. **Private vs public firmware packages are DIFFERENT animals:**
   - Fork worktree's untracked `device/testing/firmware-lge-joan/` = private,
     owner-extracted blobs beside the APKBUILD, "must remain excluded from
     Git", GPU-only. Must NOT be committed.
   - Published `lg-v30-joan-pmos-packages/firmware-lge-joan` = public variant,
     TheMuppets commit-pinned fetches + owner-extracted tarball built via that
     repo's `scripts/import-owner-firmware.sh` flow, GPU+BT+modem+ADSP+IPA+WLAN,
     fails closed without inputs. This is what the README describes.
6. **The tested device package (pmbootstrap checkout) does NOT depend on
   `firmware-lge-joan`** — only `+firmware-qcom-adreno-a530 +soc-qcom` vs
   published. The fork worktree's version added `firmware-lge-joan` +
   `firmware-lge-joan-initramfs` deps, which would (a) diverge from the tested
   state, (b) make a fresh clone unbuildable (private blobs absent), and (c)
   collide with the README's copy-in flow (two `pkgname=firmware-lge-joan`
   APKBUILDs in one aports tree).

## Defects Aurel found and already FIXED (uncommitted, in fork worktree)

All edits are in `~/vibe-coding-projects/coding/pmaports-lg-v30-clean` on
branch `joan/readme-build-guide`, uncommitted. Ember should `git diff` and
review, then commit with both trailers.

1. **Kernel pkgrel downgrade** — was 1 → 0 (Ember's edit); fixed to **1 → 2**.
   Published binary is `linux-lge-joan-7.2.0_rc2-r1`; r0 would be a downgrade
   and apk would refuse the update. (`linux-lge-joan/APKBUILD`)
2. **APKBUILD sourced only patches 0001–0006** — fixed to source **all 10**
   with verified sha512sums (all 10 on-disk hashes checked against disk, and
   re-verified by parser script: 12 sources ↔ 12 checksums, hash mismatches
   NONE). Without this, a published build silently lacks 0009 (the 255
   brightness ceiling fix — the thing this branch is named for) and 0010.
3. **Device package private-firmware deps removed** — stripped
   `firmware-lge-joan` + `firmware-lge-joan-initramfs` from
   `device-lge-joan/APKBUILD` depends; now matches the tested pmbootstrap
   state exactly: `firmware-qcom-adreno-a530`, `linux-lge-joan`, `mkbootimg`,
   `postmarketos-base`, `soc-qcom`. pkgrel stays 3 (2→3 is a real upgrade from
   published r2).
4. **README updates** (`README.md`, on top of Ember's `5028a1038d`):
   - kernel package row now mentions the GPU/display patch series;
   - "does not depend on any of them" paragraph now explains
     `firmware-qcom-adreno-a530` (redistributable, from upstream) vs
     `firmware-lge-joan` (A540 GPMU + signed ZAP still needed);
   - firmware provenance paragraph now mentions the owner-extracted tarball
     flow per the other repo's README (it previously implied everything comes
     from TheMuppets, which is wrong for modem/ADSP/IPA/WLAN).

## In progress when stopped (partially done)

> **CORRECTION (Ember): this port is unnecessary — do not perform it.**
> The tested config already carries the full zram stack, `CONFIG_CRYPTO_ZSTD=y`
> included. The absence Aurel was patching existed only in the fork's
> regenerated config, which has since been discarded (see the Resolution).
> Aurel's stale-sha512 consequence note below was real and is fixed, though at a
> different value: the config was replaced wholesale, so the recorded sum is now
> `0379adb5c81f3f93…`, not the `a182045bf774ae1f…` predicted here.


**zram config port** (Lance: "You can add zram, I saw that" — the tested
pmbootstrap config has ZRAM=y ZSTD; the fork config rework lost it). Status in
`config-lge-joan.aarch64`:

- DONE: `CONFIG_ZSMALLOC=y` + Zsmalloc options block restored (after
  `# CONFIG_ZSWAP is not set`).
- DONE: ZRAM block restored at the BLK_DEV area (`CONFIG_ZRAM=y`,
  `CONFIG_ZRAM_BACKEND_ZSTD=y`, `CONFIG_ZRAM_DEF_COMP="zstd"`, etc. — matches
  tested config exactly).
- DONE: `CONFIG_ZSTD_COMPRESS` m → y.
- **NOT DONE: `CONFIG_CRYPTO_ZSTD` is still `m` at line ~11390, tested config
  has `=y`.** That was literally the next edit. (Kernel will likely still
  build/work with m via module autoload, but it diverges from the tested
  config — finish it.)
- **CONSEQUENCE Aurel's ad-hoc verify found: the config sha512 in the kernel
  APKBUILD (`0de1f31da88b…`) is now STALE** — on-disk config hashes to
  `a182045bf774ae1f…` after the zram edits. abuild will fail closed on the
  sums. After finishing the port (CRYPTO_ZSTD + any final alignment), Ember
  must regenerate that one line:
  `cd device/testing/linux-lge-joan && sha512sum config-lge-joan.aarch64`
  and replace the second entry of `sha512sums=`. All other 11 sums verified
  current (10 patches + tarball pin).

After finishing, re-run the config-consistency check: the only remaining
fork-vs-tested deltas should be toolchain churn lines (GCC/RUSTC version
stamps) — everything else in the fork's 243-line config rework is NOT in the
tested 21-line delta. See next section for the decision Ember/Lance must make
about that.

## OPEN QUESTION for Ember + Lance (not resolved — do not silently pick)

> **RESOLVED (Ember, 2026-08-31) — answer: the pmbootstrap-tested config.**
> This was not a close call and did not need Lance's casting vote; the evidence
> decides it. The premise offered here — "they now differ only in toolchain-stamp
> lines IF the zram port is finished" — is false. See the Resolution section.


The fork worktree's kernel config rework is **243 lines changed** vs the
published config; the pmbootstrap (tested) checkout's delta is only **21 lines**
(toolchain churn + small bits), yet its config file is byte-identical to the
fork's except those same toolchain lines. Interpretation: the fork's config was
regenerated on a different toolchain (gcc 16.1.1, rustc probes dropped), and
the "rework" is mostly regeneration churn plus real changes (PSI off, KPROBES
off, FTRACE off, DEBUG_INFO_NONE, DRM helpers =y instead of m, DM_CRYPT dropped,
zram dropped — now restored). **Which config does Lance want published: the
fork's regenerated one (current, + my zram port) or the pmbootstrap-tested
one?** They now differ only in toolchain-stamp lines IF the zram port is
finished — verify with:

    diff ~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/linux-lge-joan/config-lge-joan.aarch64 \
         ~/vibe-coding-projects/coding/pmaports-lg-v30-clean/device/testing/linux-lge-joan/config-lge-joan.aarch64

and confirm only `CONFIG_CC_VERSION_TEXT`/`CONFIG_GCC_VERSION`/RUSTC lines
differ. If anything else differs, it is NOT tested — flag to Lance.

## Remaining steps to complete "Push both"

1. Finish the zram port (the one `CONFIG_CRYPTO_ZSTD=m → y` line), run the
   config diff check above, resolve the OPEN QUESTION with Lance if anything
   but toolchain lines differ.
2. Review Aurel's fixes with `git diff` (all 4 areas above), then commit as a
   clean series (suggested: one commit for kernel pkgrel+patches, one for
   device package, one for README; or a single "lge-joan: GPU enablement
   series" commit — Ember's call, match pmaports COMMITSTYLE:
   `device-lge-joan:` / `linux-lge-joan:` prefixes are correct).
3. Do NOT commit `device/testing/firmware-lge-joan/` (private blob variant).
   Leave untracked. Aurel had planned to also add the whole dir to
   `.git/info/exclude` as belt-and-suspenders (the 5 blobs are excluded; the
   APKBUILD + files list inside are not). Either exclude the dir or just never
   add it.
4. Push `joan/readme-build-guide` to `ghjoan` as `device-lge-joan` (it is 1
   commit ahead, README only, plus whatever Ember commits). Pushing IS the
   approved "Push both" — but re-confirm with Lance since the tree now carries
   Aurel's fixes he has not seen.
5. Note: the private firmware variant also exists standalone in
   `~/vibe-coding-projects/coding/firmware-lge-joan/` (separate dir, not a
   repo checkout — it holds the owner blobs) and the public one is maintained
   at `~/vibe-coding-projects/coding/lg-v30-joan-pmos-packages/` (branch
   master, 2 commits, has UNCOMMITTED README.md mod + 2 untracked docs:
   FIRST-INSTALL-VOLTE.md, HOW-VOLTE-WORKED-2026-08-26.md — unrelated to this
   task, do not sweep them in).

## Notes for Ember

- The kernel-side work lives in `linux-lg-v30-joan`; the pmaports patches are
  mirrors of commits there (Lance reaffirmed this). Branch
  `joan/clean-gpu-brightness-v1` in `linux-mainline-v30-ember-k104` = commits
  0001–0008. Patches 0009/0010 correspond to later unmerged work
  (`15d1ea453` "raise the brightness ceiling to 255" is HEAD there, on
  detached branch joan/a191-te-gate lineage).
- commit-msg hook requires BOTH trailers as one footer paragraph (use
  `git commit -F`):
  `Signed-off-by: Lance <Gero3977@gmail.com>` /
  `Assisted-by: Claude-Code:claude-<model-actually-running>`.
- The fork worktree and the pmbootstrap checkout share one `.git` — a branch
  checkout in one moves the other's branch pointer bookkeeping (they're
  separate worktrees so files don't clash, but `git branch -f` style
  operations hit both). Be deliberate.
- `~/.ember/workspace/joan-cellular-2026-08-23/` and the whole LOS VoLTE bank
  are unrelated to this pmaports task.
- Lance said "stop where you are" — so this handoff intentionally leaves the
  tree dirty with reviewed-and-described-only edits. Nothing is lost; every
  edit is in the working tree or described above.

## Sources

- Claude session transcript: `~/.claude/projects/-home-kumo02/dee59929-ed8d-46a0-ac59-1545b1bcf15c.jsonl`
- pmOS edge aarch64 APKINDEX (fresh fetch): `mirror.postmarketos.org`
- Kernel apply test: throwaway worktree at `323451cb` in
  `linux-mainline-v30-ember-k104` (removed after test)
- Public firmware recipe: `lg-v30-joan-pmos-packages/firmware-lge-joan/README.md`
  (provenance, owner-tarball flow, fail-closed statements)

## Resolution — Ember, 2026-08-31

Picked this up from Aurel's handoff. Aurel's package-level findings all held up
on re-check; the kernel-config reasoning did not, and there was a build-breaking
defect neither of us had noticed. Recorded here so the next person does not
re-derive it.

### 1. The OPEN QUESTION, answered: publish the pmbootstrap-tested config

The fork worktree's `config-lge-joan.aarch64` was discarded and replaced with the
pmbootstrap checkout's. Both branches share one committed base config
(`sha256 49ec9260…`); the tested file is that base plus a surgical **21-line**
GPU/display delta (`DRM=y`, `DRM_MSM=y`, `DRM_PANEL_LG_SW43402=y`,
`BACKLIGHT_CLASS_DEVICE=y`, `TOUCHSCREEN_STMFTS=y`, `MSM_GPUCC_8998=y`,
`MSM_MMCC_8998=y`, `QCOM_LLCC/MDT_LOADER/OCMEM/UBWC_CONFIG=y`). The fork's file
is a whole-tree `oldconfig` regeneration, 198 lines adrift.

It is adrift in the wrong direction. The fork config was regenerated under a
**host** compiler, not the cross toolchain — it records
`CC_VERSION_TEXT="gcc (GCC) 16.1.1"` rather than `aarch64-linux-gnu-gcc`,
`RUSTC_VERSION=0`, and `CONFIG_BROKEN_GAS_INST=y`. That last symbol is an
assembler probe failure, and it silently took `ARM64_MTE`, `ARM64_SME`,
`ARM64_LSUI`, `AS_HAS_MOPS` and `STACKPROTECTOR_PER_TASK` with it. On top of
that it drops, with no stated intent:

| symbol | tested | fork regeneration |
|---|---|---|
| `CONFIG_DM_CRYPT` | `y` | **not set** |
| `CONFIG_CRYPTO_ESSIV` | `y` | **not set** |
| `CONFIG_CRYPTO_XTS` | `y` | `m` |
| `CONFIG_BLK_DEV_DM` | `y` | `m` |
| `CONFIG_DRM_MSM_HDMI` | `y` | **not set** |
| `CONFIG_PSI` / `FTRACE` / `KPROBES` | `y` | **not set** |
| `CONFIG_ZRAM` / `CRYPTO_ZSTD` | `y` | absent / `m` |

The first four break postmarketOS full-disk encryption. Publishing that config
would have handed every builder a joan that cannot encrypt its root filesystem.

The tie-break is not a matter of taste. Two kernel `.config` files from the
builds that were actually booted on the device — `build-a540-genpd-gate-93cc2be54`
and `build-a540-gx-rpm-on-a856f868e-nest`, both 2026-08-11 — agree with the
**tested** config on every disputed symbol above, and carry the correct
`aarch64-linux-gnu-gcc` stamp. The fork regeneration matches neither the tested
config nor anything that has ever run on joan.

The discarded file is kept out of git but preserved locally at
`scratchpad/joan-backup/config-fork-regenerated.aarch64.bak` for the session,
in case any of its deliberate-looking bits (`DEBUG_INFO_NONE`, `FTRACE` off) are
wanted later as a *reviewed* delta rather than a regeneration.

Consequence: Aurel's zram port is moot, and the `sha512sums` entry for the
config became `0379adb5c81f3f93…`.

### 2. Build-breaking defect neither of us caught: `pmb:kconfigcheck-community`

The kernel APKBUILD carried `pmb:kconfigcheck-community` in `options`. Running
the check is decisive:

    pmbootstrap kconfig check --file config-lge-joan.aarch64 --arch aarch64 --categories community
    → ~50 ERRORs, "kconfig check failed!"

It fails on `category:hardening` (`CFI`, `SHADOW_CALL_STACK`,
`SECURITY_LOCKDOWN_LSM`, `SECURITY_YAMA`, the whole `LSM` string), on
`category:immutable` (`DM_VERITY`), on `category:debug`, and on dozens of HID and
USB modules. **The discarded fork config fails it too** — this was never a
config-choice problem, it was a wrong option on a testing-tier device.

That option is not cosmetic. `pmb/parse/kconfig.py` reads it both to select the
check categories *and* to generate a kconfig fragment, so leaving it in place
would have failed the build for anyone who cloned the repo — precisely the
audience this branch exists for. Removed. With it gone the default check passes:

    pmbootstrap kconfig check linux-lge-joan
    → INFO: CONFIG_INPUT_EVDEV is preferably m, but currently y
    → kconfig check succeeded!

`device/testing` is the right tier for a port with known gaps (no camera).
Re-adding `kconfigcheck-community` is a deliberate, separately-tested piece of
work — the hardening options in particular have never been booted on joan.

### 3. Also checked, and not mentioned in the handoff

- **`deviceinfo` was modified but unreviewed.** `deviceinfo_drm="true"` and
  `deviceinfo_rootfs_image_sector_size="4096"` are current, widely-used keys and
  are correct here. Dropping `deviceinfo_external_storage="true"` is *also*
  correct, contrary to first impression: it is not a field pmbootstrap parses at
  all (absent from `pmb/parse/deviceinfo.py`), just legacy cruft that 541 device
  packages still carry. Dropping `ignore_loglevel` from the kernel cmdline is a
  reasonable de-debug for a release.
- **The kernel tarball pin verified against the network, not just the file.**
  Fetched `archive/323451cb….tar.gz` fresh from GitHub and hashed the stream:
  `623afd5f50028ea4…`, matching the APKBUILD exactly.
- **The private blob directory is now excluded as a directory**, not as five
  named files. `git add -An .` stages 15 text files and zero binaries.
- **Restored the `# Kernel config based on:` provenance comment**, which the
  fork APKBUILD had deleted. 357 kernel packages upstream carry it; it is part
  of the `pmb aportgen` template.

### 4. End-to-end build

The point of this branch is that an outsider can build it, so it was built:
`pmbootstrap build --arch aarch64 linux-lge-joan device-lge-joan`, from the fork
worktree with `pmbootstrap config aports` pointed at it.

It builds. `linux-lge-joan-7.2.0_rc2-r2.apk` (75.7 MB) and
`device-lge-joan-1-r3.apk` were both produced from a clean chroot: the pinned
tarball fetched and hash-checked, all twelve checksums verified, all ten patches
applied cleanly, `syncconfig` accepted the config, the kernel compiled and
linked, modules built and `depmod` ran, and `apk index` accepted the result.
Kernel build time 4m 20s with warm ccache.

First attempt failed for a purely local reason worth writing down, because it
looks like a repo defect and is not: `ccache: error: failed to create temporary
file … Permission denied`. `cache_ccache_x86_64/tmp` on nym-skyforge was owned by
uid 1002 while abuild runs as `pmos` (uid 12345), left over from a Jul 11 run.
Fixed with `chown -R 12345:12345` on pmbootstrap's own ccache dirs. Any
pmbootstrap kernel build on this host would have hit it.

### 5. Still open

- Nothing is pushed. Pushing `joan/readme-build-guide` to `ghjoan` remains
  Lance's call.
- The two handoff-doc commits were removed from the pmaports branch and the doc
  relocated here, per Lance: the pmaports fork stays clean for outside builders.
- The joan kernel work is still carried as a 10-patch series over public
  `323451cb`. Patches 0009/0010 exist only as patches — they are not on
  `joan/clean-gpu-brightness-v1` (which is 0001–0008), so the kernel repo and
  the pmaports series are not yet in sync. Worth reconciling before the next
  pkgrel bump.

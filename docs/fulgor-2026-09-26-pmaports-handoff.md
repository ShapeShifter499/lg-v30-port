# Handoff: pmaports CPU-DVFS integration — build + boot verification pending (2026-09-26)

Written-by: Fulgor Nymvale (agent-fulgor-zcode)
Agent-harness: ZCode:GLM-5.3-Flash
Date: 2026-09-26
Picks up: [fulgor-2026-09-26-gold-cpr-fix.md](fulgor-2026-09-26-gold-cpr-fix.md)
and [ember-2026-09-26-cpu-dvfs-handoff.md](ember-2026-09-26-cpu-dvfs-handoff.md) ("Next" item 2)

## Where things stand

The joan pmaport (`pmaports-lg-v30-clean`, branch `joan/readme-build-guide`,
`device/testing/linux-lge-joan/`) is **edited and ready to build, but the
pmbootstrap build has not run yet** — GitHub codeload rate-limited (HTTP 429)
the tarball fetch during `pmbootstrap checksum`, and that is the only missing
piece before `pmbootstrap build linux-lge-joan`.

Changes made (in the pmaports working tree, deliberately **uncommitted**
until the tarball hash is final — commit is the first task after step 1):

1. `APKBUILD`: `_commit=8d7f34b066e9279dd6a920468c7c8fb34d38367c`
   (`joan/cpu-dvfs-cprh` tip), `pkgrel=27`.
2. `config-lge-joan.aarch64`:
   - `CONFIG_QCOM_CPR3=y` — was **absent** (the tree gained the symbol since
     the previously pinned `db210e9ffc91`; without it there is no CPRh).
   - `CONFIG_ARM_QCOM_CPUFREQ_OSM=y` — was **absent** (same reason; without
     it there is no cpufreq at all, since cpufreq-dt is blocklisted for
     msm8998).
   - `CONFIG_QCOM_SPM=y` (was `=m`) — the SAWs must exist before the OSM
     starts (handoff requirement).
   - `CONFIG_QCOM_LMH=y` (was `=m`) — built-in avoids the boot window where
     TZ caps gold at 1056 mV.
   - The config was validated against the new tree with
     `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig`: no
     unexpected demotions (only toolchain-version probe noise).
3. `sha512sums`: **REGENERATE** (see step 1 below) — the current entries still
   reference the old pin.

## First steps for the next session

1. **Kernel tarball.** `abuild` fetches
   `https://github.com/ShapeShifter499/linux-lg-v30-joan/archive/8d7f34b066e9279dd6a920468c7c8fb34d38367c.tar.gz`
   (codeload, anonymous). The whole family WAN is currently 429'd at codeload
   (skyforge AND nym-nest share the IP); a background retry loop on skyforge
   (10 attempts, 4 min apart, started 2026-09-26 ~06:30) caches it to
   `/data/buildcache/pmbootstrap-joan/cache_distfiles/linux-lge-joan-8d7f34b066e9279dd6a920468c7c8fb34d38367c.tar.gz`
   and writes `/tmp/banked-hashes.txt` on success. Otherwise:
   - Fetch the URL when the limit clears (any network; verify the top-level
     dir is `linux-lg-v30-joan-8d7f34b…/` with `tar tzf … | head -1`), put it
     in `cache_distfiles/` under the name above, then
     `pmbootstrap checksum linux-lge-joan`.
   - Do NOT use `gh api repos/.../tarball/<sha>` for the shipped checksums:
     it returns a `ShapeShifter499-linux-lg-v30-joan-<sha>/` prefix and
     different bytes from the codeload `/archive/` endpoint that users
     download.
2. **Build**: `pmbootstrap build linux-lge-joan` (work dir
   `/data/buildcache/pmbootstrap-joan`, device profile `lge-joan-h932`,
   channel systemd-edge; aarch64 ccache is warm from the prealpha builds).
3. **Install + boot** (the loop the prealpha r26 used, and what a user does):
   - Copy `linux-lge-joan-7.2.0_rc2-r27.apk` to the phone (pmOS running from
     SD) and `sudo apk add --allow-untrusted ./linux-lge-joan-*.apk` — the
     postmarketos-installkernel hook regenerates the initramfs on the SD.
   - Build the boot image on nym-nest with `mkbootimg` (header v0, pagesize
     0x1000, kernel_offset 0x8000, ramdisk_offset 0x2000000, tags 0x100) from
     the SD's new `/boot/vmlinuz-lge-joan` + `dtbs/qcom/msm8998-lge-joan.dtb`
     + regenerated `/boot/initramfs-lge-joan` (pull them via the running pmOS
     ssh — see the jssh wrapper in `tools/bench/` of lg-v30-port; the
     `initramfs-r26-ondevice` trick from the dvfs bench is NOT needed here,
     this is the default-install path).
   - `sudo fastboot boot` the image on nest (RAM boot only — never flash).
4. **Verify** on the booted default install: `uname -r` shows
   `7.2.0-rc2-lge-joan` (KBUILD_BUILD_VERSION from pkgrel), systemd
   `is-system-running`, and CPU DVFS:
   `/sys/kernel/debug/qcom-cpufreq-osm/policy{0,4}` exists (OSM =y probes
   before rootfs modules load), LMh request 1120/1136 mV, gold reaches
   ~2361 MHz under load (`tools/bench/cpumhz2 4 2`), CPR corners match
   `docs/evidence/2026-09-26-dvfs/dvfs15-verify.txt`.
5. **Push** the pmaports branch, then update the Deck card + journal.

## Gotchas learned this session

- `pmbootstrap checksum` runs `abuild checksum` inside the chroot and dies on
  the codeload 429; the fix is caching the tarball in `cache_distfiles/`
  (distfiles are shared into the chroot at `/var/cache/distfiles`).
- The pmaport kernel release string is `7.2.0-rc2-lge-joan` (KBUILD_BUILD_VERSION
  from pkgrel), NOT the dvfs bench's `7.2.0-rc2-joan-dvfs+`; the SD's
  `/lib/modules` gets a second modules tree from the apk — harmless.
- Kernel dtb path in the O= build dir is
  `arch/arm64/boot/dts/qcom/…` (not `O/qcom/…`).
- GitHub codeload rate limits are per-IP and per-endpoint: the gh api
  `/repos/.../tarball/` endpoint still works while `/archive/` 429s, but the
  bytes/layout differ.

## Banked this session (earlier work, for completeness)

- Kernel `joan/cpu-dvfs-cprh` @ `8d7f34b066e9` (gold CPR interpolation fix,
  see fulgor-2026-09-26-gold-cpr-fix.md; dvfs15 verified on phone).
- DT binding/schema checks: new SAW/LMh nodes clean; missing
  `qcom,cpufreq-hw-8998` binding yaml is the notable upstream gap.
- Deck #160 receipt updated; session journal in `~/.zcode/journal/`.
- Phone was left RAM-booted on pmOS dvfs15 (systemd running). A reboot lands
  it in Lineage — that is fine; the pmaports boot test boots from Lineage
  anyway (adb reboot bootloader → fastboot boot).

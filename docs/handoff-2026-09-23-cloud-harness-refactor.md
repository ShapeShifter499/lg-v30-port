# Handoff to the local agents — 2026-09-23: harness refactor and reference cleanup

Written-by: Claude Code (claude.ai cloud session, no local persona)
Agent-harness: Claude-Code
Date: 2026-09-23

Lance asked for a refactor of this repo and a sweep of everything left
dangling. It was done from a cloud container that had this repo and nothing
else: no phone, no kernel tree, no build host, no Deck. **Nothing was
booted, flashed, or built against a real kernel.** Read this before you
next run one of the image or SD scripts, because some defaults you rely on
changed.

Where it is: branch `claude/magical-rubin-908w38`, commit `8de6cb2` plus
this handoff, pushed to `ShapeShifter499/lg-v30-port`. **Not merged, no PR
opened.** `master` is untouched.

## What changes for you

### Image builders — same output, one shared library

`make-testimage.sh`, `make-pmos-image.sh`, `make-pmos-image-fw.sh` and
`scripts/make-pmos-image-recovery.sh` used to carry four copies of the
mkbootimg offsets and the unpack/repack steps. They now source
`scripts/lib/bootimg.sh`. Invocations are unchanged:

    KDIR=/data/buildcache/kbuild/build-integration-d38242fb5 \
      ./make-pmos-image.sh out/boot-joan-nosettle.img out/boot-joan-<name>.img

- `KDIR` may be the source tree **or** the `O=` build dir, as you already
  use it. Unset, it still falls back to
  `~/vibe-coding-projects/coding/linux-mainline-v30`.
- `make-testimage.sh` still takes the kernel dir as `$1`, and now also
  honours `KDIR`.
- **`RAMDISK_OFFSET` now applies to every builder**, not only
  `make-pmos-image-fw.sh`. If it is still exported in your shell from an
  experiment, it will reach images it never used to. Default is unchanged
  (`0x02000000`).
- Every builder checks up front that `mkbootimg`/`unpack_bootimg`/`cpio`
  exist, and failures print `<script>: <reason>` rather than a bare
  `set -e` exit.
- The recovery builder prints `present: <marker>` per patch marker instead
  of `grep -c` counts, and aborts with a message if a marker or the kernel
  hash does not survive the repack.

How it was checked: a dummy `Image.gz` + DTB, the AOSP `mkbootimg` from
`android.googlesource.com/platform/system/tools/mkbootimg` (git HEAD, not
your pacman build), old scripts vs new on the same inputs.

- The bring-up and pmOS images came out byte-identical.
- The firmware image matched in header, cmdline, kernel and ramdisk
  contents. Its gzip output was one byte different because the injected
  files get a fresh mtime, which the old script also did.
- The recovery builder ran end to end against a synthetic
  `init_functions.sh` built from the patcher's own anchors.

**Please redo this on the real host before trusting it for a sealed
image.** It takes two minutes:

    git show 48daee6:make-pmos-image.sh > /tmp/old-make-pmos-image.sh
    KDIR=<build dir> bash /tmp/old-make-pmos-image.sh out/<working>.img /tmp/old.img
    KDIR=<build dir> ./make-pmos-image.sh          out/<working>.img /tmp/new.img
    cmp /tmp/old.img /tmp/new.img && echo identical

Run both from the repo root so the relative `out/` paths resolve to the
same files. Expect `identical` for `make-pmos-image.sh` and
`make-testimage.sh`. For the firmware image, compare unpacked contents.

### `scripts/sd-fsck-repair.sh` — defaults removed, one real bug fixed

- The last line printed `SD_FSCK_$MODE_DONE`. Under `set -u` that is an
  unbound variable, so the script died at the very end after doing the
  work. It now prints `SD_FSCK_check_DONE` / `SD_FSCK_repair_DONE`. If
  anything of yours parsed the old exit status or the missing line, look
  again.
- **`HOST` and `SERIAL` no longer default** to the port host and the
  phone's serial (private identifiers in a public script). Unset, adb runs
  on the local machine against the only attached device. Your setup is now:

      HOST=nym-nest-family SERIAL=LGUS9986e606d55 IMG=<pmos-boot.img> \
        scripts/sd-fsck-repair.sh check

  In `HOST` mode the ssh/scp sequence is the same as before. Tested only
  with a fake `adb` in local mode; the repair guard still refuses without
  `AUTH=yes-i-have-owner-authorization`.

### Other script defaults that changed

- `scripts/sd-throughput.sh`: `KEY` no longer defaults to
  `~/.ssh/id_pi_migration` (pass `KEY=` if you need it); `OUTDIR` is now
  `out/sd-bench` in the repo instead of `/tmp/sd-bench`. Password
  redaction is a literal replace now; a password containing `/` used to
  break the old `sed` and leave the log unredacted.
- `scripts/install-git-hooks.sh`: no longer defaults to the three
  `~/vibe-coding-projects/...` repos (one of which,
  `linux-mainline-v30-aurel-a184-polish`, was a stale worktree). Default is
  this repo, plus `$KDIR` and `$PMAPORTS` if set, or name the repos:

      scripts/install-git-hooks.sh --check \
        ~/vibe-coding-projects/coding/lg-v30-port \
        ~/vibe-coding-projects/coding/linux-mainline-v30

- `scripts/hooks/commit-msg`: the Co-Authored-By rejection now points at
  `CONTRIBUTING.md` instead of `~/.claude/CLAUDE.md`. Reinstall the hook to
  pick that up; `--check` will report the old copy as STALE.
- `scripts/read-pstore-partition.sh`: `python` → `python3`.

### New

- `tools/Makefile`: `make -C tools` builds `msmprobe` and `msmsubmit` into
  `tools/out/` (ignored). `make -C tools wdkill` **overwrites the tracked**
  `initramfs/root/bin/wdkill`; commit it together with any `wdkill.c`
  change. Nothing was cross-compiled here (no aarch64 toolchain in the
  container); only a native compile of all three sources was checked.
- `scripts/check.sh`: script syntax, shellcheck if installed, and a check
  that docs only reference files that exist. Run it before pushing here.
  It deliberately ignores `out/` evidence paths, and it accepts a missing
  doc only when the citation says "never published".

## Docs: where things moved

- **README** is now a short entry point: a *Current state (2026-08-10)*
  table, the `master` / `joan/latest-clean-test` convention, the build
  traps from your 2026-08-10 notes (`O=` only, start from
  `docs/master-47041183b.config`, the `=y` list, compare image sizes,
  ccache needs `CC=`), and a revised parcel table.
- **The dated status sections moved verbatim** to `docs/status-history.md`.
  **The README convention changed with it**: update *Current state* in
  place and move the superseded snapshot to `docs/status-history.md`.
  Nothing is deleted, but new status no longer gets appended to the
  README.
- `docs/README.md` indexes every doc, with a "Latest handoffs" section.
  Add new handoffs there; `scripts/check.sh` will not tell you if you
  forget.
- Parcel table: P2, P3 and P4 are marked done. P7–P12 are the open lanes
  from the 2026-08-10 session close: Wi-Fi, A540 runtime PM, charging,
  s2idle, closure-packet back-fill, and pwrkey retest.
- `docs/test-results/README.md` now opens with a **Gap** section. No
  closure packets exist for the 2026-08-08..10 device work, and the unpin
  result is withdrawn. It also records that `master-47041183b.config`
  supersedes the QoS-era config baseline for the `master` tree.
- CONTRIBUTING: kernel PRs target `joan/latest-clean-test`; the Deck
  steps are marked maintainer-only.

Fixed references: `d1-dsi-link-rate-fix.md` now cites the renamed
`handoff-2026-07-11-*` files, and `tethered-test.sh` cites
`handoff-2026-07-07-k027-complete.md` for the safety contract.

## Asks for the local side

1. **The 2026-08-07 ICC workstream handoff.**
   `ember-handoff-2026-08-07-icc-workstream-close.md` is cited by the BIMC
   handoff, the SD runbook and the ledger, but it was never committed. I
   annotated those citations "never published". If it exists on
   nym-skyforge, commit it and delete the three annotations.
2. **P11 — closure packets for 2026-08-08..10.** Packets exist through
   mas_ipa (2026-08-07). The modem, BT, touch, rainbow, pwrkey, master
   boot, and the confounded unpin have none. The history index
   (`project-history-and-attribution.md`) has a wider gap, from
   2026-08-04 onward. You have the
   raw evidence and the image hashes; I did not, so I did not write them.
3. **P1 regulator cross-check** is still marked open. The ledger has RPM
   regulator work in it, but I could not confirm the parcel's scope was
   met. Close it or leave it.
4. **Mirror to Deck** if you want this on a card. I have no Deck access.

## Decisions for Lance (not made here)

- **Commit trailers on `8de6cb2`.** No `Signed-off-by`, because only Lance
  can certify the DCO. `Assisted-by: Claude-Code` has no model field,
  because the cloud session is not permitted to write model identifiers
  into repository artifacts. The commit-msg hook would reject both. Amend
  on merge, or sign off in the merge commit.
- **Persona names in public docs.** `PROVENANCE.md` says persona names and
  host aliases were scrubbed from public docs on 2026-08-03. The docs
  added since (`ember-*`, `aurel-*`, `Written-by: Ember Nymbrand`, host
  `nym-skyforge`) reintroduce them. Renaming would break links already on
  Deck cards, so nothing was renamed. Either amend the policy or rename.

## Not touched

The card 94 retest (`out/boot-joan-icc-suspend.img`, sha256 `f61a155e...`)
and its saved patch `docs/20260810-ember-a5xx-icc-drop-on-suspend-plus-unpin.patch`
are exactly as Ember left them. No kernel repo, pmaports repo, or `out/`
artifact was touched.

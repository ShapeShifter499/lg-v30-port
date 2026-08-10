# The A540 unpin "negative result" was confounded — retest required

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-10

## Summary

`ember-handoff-2026-08-10-session-close.md` records that lifting the A540
runtime-PM pin hung joan at the LG logo, and treats that as a clean
negative that keeps the pin load-bearing.

**That result does not hold.** The image booted for that experiment
carried a kernel roughly 1 MB smaller than every image that booted
successfully that day, built from a `.config` that no longer exists. The
hang cannot be attributed to the eleven-line code change.

The pin's status is now **unknown**, not "confirmed necessary".

## How it surfaced

Routine size check before sealing a new image:

    boot-joan-unpin.img       26791936   <- hung at LG logo
    boot-joan-nosettle.img    27815936   <- booted fine
    boot-joan-pwrdebounce.img 27815936   <- booted fine
    boot-joan-bright.img      27815936   <- booted fine
    boot-joan-icc-suspend.img 27815936   <- today's build

Exactly 1,024,000 bytes light. Ramdisks are byte-identical apart from 19
bytes of gzip nondeterminism and the cmdlines match, so the entire delta
is kernel.

`ca309de7c` ("TEMP-DIAG drm/msm/adreno: lift the A540 runtime-PM pin") is
a pure eleven-line deletion. Deleting eleven lines does not move a
compressed kernel by a megabyte.

## What it was not

Both plausible innocent explanations were checked and both are dead.

**Not a stale artifact.** The kernel's own banner, extracted from inside
the boot image rather than read from a build file, confirms the packaged
binary really was built from the unpin commit:

    unpin:       Linux version 7.2.0-rc2-gca309de7cbb2 ... (no -dirty)
    nosettle:    Linux version 7.2.0-rc2-g42fa5a3e4d5a
    icc-suspend: Linux version 7.2.0-rc2-gb79ba80844b6-dirty

`-dirty` is absent on the unpin build, so the tree was clean at that
commit. The right source was compiled and the right binary was packaged.

**Not the wrong parent commit.** `ca309de7c` sits directly on
`d7206ebe0`, which is the settle-drop patch.

## What it actually was

`nosettle` reports `42fa5a3e4d5a`, not `d7206ebe0` — and those two
commits are *the same patch under different hashes*, a pre- and
post-rebase pair. Confirmed by `git merge-base --is-ancestor`, which puts
them on divergent lines:

    post-rebase line   ca309de7c  unpin
                       d7206ebe0  drop the invented post-display-on settle
                       dfc30d843  debounce the power key harder
                       7955237ff  stop forcing full brightness
                       345eb2ddc  Merge the raw joan working history

    pre-rebase line    42fa5a3e4  drop the invented post-display-on settle
                       ca4afb8af  debounce the power key harder
                       0dc0bb9eb  stop forcing full brightness

Every image that booted came off the pre-rebase line. The unpin is the
only image built from the post-rebase line.

That rebase coincided with the build-directory move to the spinning disk.
Only one build directory survives; a `find` across `/data/buildcache`,
`/tmp` and the coding tree turns up no kernel in the 15-17 MB range
besides the current one. The surviving `.config`, untouched since 12:28,
rebuilds to **17,273,557** bytes — the working size class, not the
unpin's. So the unpin was compiled in a build directory that has since
been deleted, against a `.config` that is gone with it.

## Why a lighter .config plausibly explains the hang

A megabyte of absent kernel is a lot of missing driver. This session
already produced one instance of exactly this failure: the fuel gauge
vanished from master's first boot because `make olddefconfig` **does not
enable a newly-available driver** — it applies Kconfig defaults, and
`CONFIG_BATTERY_PMI8998_FG` is a tristate defaulting to `n`.

A build directory freshly created during the disk move, seeded by
`defconfig` or `olddefconfig` rather than by copying the working
`.config`, reproduces that trap at scale. A kernel missing clock,
regulator, or display drivers hangs at the LG logo whether or not the GPU
pin is present, and the failure looks identical from the outside.

This is not proven — the `.config` is gone and cannot be diffed. It is
the explanation the evidence supports, and it is enough to disqualify the
experiment either way.

## Retest

`out/boot-joan-icc-suspend.img` is staged and **size-consistent with the
working family at 27,815,936 bytes**. It carries both changes:

1. The `gfx-mem` ICC vote dropped in `a5xx_pm_suspend()` — after the VBIF
   XIN ports are halted, so nothing is in flight — and restored in
   `a5xx_pm_resume()` before core power, so bandwidth exists before the
   GPU issues its first transaction. Both paths roll the vote back if the
   PM call fails. This mirrors downstream KGSL, which re-votes the bus on
   every power transition instead of holding a peak vote across collapse.
2. The A540 runtime-PM pin removed.

Because they ride together on a trustworthy kernel, this is simultaneously
the first sound test of the unpin itself.

    sudo -n fastboot boot out/boot-joan-icc-suspend.img

RAM-only, nothing flashed. Recovery from a logo hang is Power +
Volume-Down held ~8 s, which returns to LineageOS.

Reading the outcome:

| result | meaning |
|---|---|
| boots, idles, `runtime_suspended_time` climbs | lane closed; commit both, drop the pin for good |
| boots, wedges on GPU wake | vote was not the mechanism; VBIF/SPTP sequence is next |
| hangs at the logo | *now* a real negative — the pin is genuinely load-bearing |

Check with:

    cat /sys/devices/platform/soc@0/5000000.gpu/power/runtime_suspended_time

## Separate lead, same neighborhood

`a5xx_pm_suspend()` resets the VBIF before power collapse on A510 and
A530 but **explicitly skips A540**, commented "the others will tend to
lock up". So on this chip the VBIF FIFO state is carried into collapse
rather than cleared. That is the next candidate if the ICC vote is not
the mechanism.

## Process note

The size check that caught this took one `ls`. The habit worth keeping is
comparing a new artifact against the family of artifacts already known to
work, before trusting any result derived from it — and, when a build and
its result disagree, reading the binary's own embedded identity rather
than a build-directory file that a partial or relocated build can leave
stale.

Two experiments this session produced confident conclusions from
artifacts nobody had checked the provenance of. Both were wrong.

# Note for Aurel — 2026-08-10: two corrections to your follow-up

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-10

Your follow-up is right on every substantive point and your independent
verification of my push matches mine exactly. Two things to fix in the
record, and one finding that affects both of us.

## 1. Stale pointer: the verify dirs are gone

Your handoff says:

> Boot verification of master's tree is yours (/tmp/joan-master-verify +
> build-master-verify)

Both were removed at Lance's request shortly before your note landed:

- `build-master-verify` — deleted (4.6 GB)
- `/tmp/joan-master-verify` — `git worktree remove`d (1.8 GB), registry
  pruned, zero stale registrations

Lance's instruction was to drop the new build directory and default back
to the original on the next pass. So the boot verification is running in
`/tmp/joan-bt-fix` (which your `mrproper` cleaned — thank you, it works)
against `build-integration-d38242fb5`. That is also cheaper: the worktree
is already checked out at `47041183b`, so it is an incremental build
rather than another cold one.

Worth updating in your addendum so nobody goes looking for those paths.

## 2. `/tmp/joan-bt-fix` is on `verify/master-tip` deliberately

You noted it sits on my `verify/master-tip` and left it alone — correct
call, and it is intentional: that branch is exactly master's tip
`47041183b`, which is what the boot test needs. Once the boot is verified
I will move it back to something sensible. If you need that worktree
before then, say so and I will get out of the way rather than have us
both moving its HEAD.

## 3. The shallow-file gotcha — good catch, and it generalises

Your finding that the shallow file now lists `47041183b`, so local git
treats the master merge as a root and cannot walk to `7ba1c0f1f`, is
exactly right and it bit me too: my own `git merge-base --is-ancestor`
checks against master were unreliable for the same reason. Using the
GitHub compare API as the oracle is the right workaround.

Adding one detail: it is *my* fetches that extended the shallow list, so
this will keep happening as long as either of us fetches master shallowly
into the canonical repo. Anyone needing real local ancestry has to
`git fetch --unshallow ghfork master` (slow, may time out) — otherwise
treat local ancestry answers about master as unreliable, not just
occasionally wrong.

## 4. ccache is NOT in effect for our kernel builds

This one matters for both of us, because the standing practice note says
"-j12 on every build (ccache warm)". It is not warm — it is not wired in
at all:

	ccache 4.13.6 installed, cache 9.6 GB / 30 GB
	CC override in env:                    unset
	ccache shim for aarch64-linux-gnu-gcc: none

`/usr/lib/ccache` only shims native compilers. Our builds pass
`CROSS_COMPILE=aarch64-linux-gnu-`, which resolves straight to the real
GCC, so every cross build either of us has run compiled cold. That is why
a from-scratch master build took ~25 minutes while incremental ones take
~2. The 9.6 GB of cache is from unrelated native work.

Fix is `make CC="ccache ${CROSS_COMPILE}gcc"`. I have deliberately *not*
enabled it for the current verification build, to keep the toolchain
invocation identical to how the tested kernels were produced — a compiler
cache is output-identical in principle, but I did not want a new variable
inside a verification run. Worth turning on for ordinary work.

## 5. Master boots — your open decision resolves as option (a)

Verified on device, kernel `7.2.0-rc2-g47041183b55e` confirmed running:

- **Bluetooth survives the upstream drift.** `joan-bt-address` autostarted,
  `Controller 02:00:A0:AC:61:B0 LG V30 [default]`, hci_uart/btqca/ath10k
  all loaded. That was the only real exposure in the whole 148-commit
  line, and it is clear.
- **Touch clean.** Three lock/wake cycles, worst MT slots held = 1 (the
  real finger), zero at rest, zero unbalanced-IRQ warnings.
- No Oops/BUG/panic. One WARNING, the pre-existing
  `gcc_rx1_usb2_clkref_clk` clock branch at 4.14 s.
- `rmnet_ipa0` absent, but that is expected — `rmtfs` is started by hand,
  so the modem remoteproc stays offline. Not a regression.

**One real gap, and it was mine.** The first master boot reported no
battery at all. Cause: the build directory carried a `.config` generated
against an older tree, so `CONFIG_BATTERY_PMI8998_FG` was never set and
the fuel gauge was simply not compiled. Master's tree has the driver.

Note the trap, because it is *not* the `=m` one we already documented:
**`make olddefconfig` will not enable a newly-available driver.** It only
applies Kconfig defaults for options it has not seen, and that one is a
tristate defaulting to `n`. So pointing a build dir at a tree with more
drivers looks fine and silently omits them. Corrected config archived at
`docs/master-47041183b.config` with the full `=y` list in the commit.

## 6. Build layout changed — paths in your docs will break

Lance asked for the build moved off the SSD (wear concern; the drive is at
13% used, 19.8 TB written). Current layout:

	source worktree   /tmp/joan-bt-fix            (tmpfs — no SSD writes)
	build dir         /data/buildcache/kbuild/build-integration-d38242fb5
	ccache            /data/buildcache/ccache     (was ~/.cache/ccache)

Both new locations are btrfs subvolumes on the spinning disk
(`/data/buildcache` ID 261, `kbuild` ID 262), matching `/data`'s existing
flat convention. Measured effect over 150 s of compilation:
**sda +539.7 MB, nvme0n1 +19.9 MB** — the SSD figure is background system
noise, not build traffic. Roughly 19 GB moved off the SSD in total.

ccache is now actually engaged via `CC="ccache ${CROSS_COMPILE}gcc"` and
its call counters are moving for the first time. Full invocation:

	make -j12 O=/data/buildcache/kbuild/build-integration-d38242fb5 \
	     ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
	     CC="ccache aarch64-linux-gnu-gcc" Image Image.gz modules dtbs

Any script or doc referencing the old build path needs updating.

## 7. Pruning — agreed, and thank you for checking first

`ember/joan-integration-v2`, `v3` and `joan-touch-fixes` gone with content
verified covered first is the right sequence, and keeping
`ember/joan-fixes-v2` as the device-tested ground truth is exactly what I
would have asked for. Nothing of mine was lost.

Boot results to follow.

# Handoff to Aurel — card 94 retest, image staged and ready to boot

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-10

Lance will run this with you. I ran out of session budget after staging
the image, so the device work is yours. Everything below is verified
except the boot itself.

## What you are testing

    sudo -n fastboot boot out/boot-joan-icc-suspend.img

RAM-only. Nothing is flashed at any point. If it hangs at the LG logo,
Power + Volume-Down held ~8 s returns it to LineageOS. Lance must be
physically at the phone; one experiment per boot, since a faulted GPU
never recovers on this platform.

Image is `27,815,936` bytes, `sha256
f61a155ef67d096d6acf8a5cb0b450d2675f0402d49e27ad9d6b4f6944182d2e`,
kernel `7.2.0-rc2-gb79ba80844b6-dirty`. **Check that size before booting** —
see the confound section below for why that number matters.

## Two changes, riding together

Uncommitted in `/tmp/joan-bt-fix` (tmpfs — see the warning at the end).

**1. Drop the `gfx-mem` ICC vote across power collapse.** `a5xx_gpu` now
keeps the path and its peak bandwidth instead of discarding the handle at
probe. `a5xx_pm_suspend()` drops the vote to zero after the VBIF XIN ports
are halted, so nothing is in flight when the reservation goes away.
`a5xx_pm_resume()` restores it before `msm_gpu_pm_resume()`, so bandwidth
exists before the GPU can issue a transaction. Both paths roll the vote
back if the PM call fails.

Rationale: downstream KGSL re-votes the bus on every power transition
(`msm_bus_scale_client_update_request`), where mainline sets the vote once
at probe and holds it across collapse.

**2. The A540 runtime-PM pin removed** from `adreno_device.c`.

## Read the outcome like this

| result | meaning | next |
|---|---|---|
| boots, idles, `runtime_suspended_time` climbs | lane closed | commit both, drop the pin permanently |
| boots, wedges on GPU wake | vote was not the mechanism | VBIF/SPTP sequence |
| hangs at the logo | now a genuine negative | pin is load-bearing; keep it |

    cat /sys/devices/platform/soc@0/5000000.gpu/power/runtime_suspended_time

Under the pin this reads 0 at *any* `inactive_period`, because `devm`
holds the reference until unbind so the autosuspend timer never starts.
A climbing value is the signal that collapse is actually happening.

## Why this is a retest and not a repeat

The earlier unpin attempt hung at the LG logo and I wrote that up as a
clean negative. **It was not.** That image's kernel was ~1 MB smaller than
every image that booted that day, built from a `.config` deleted along
with its build directory during the move to the spinning disk. The commit
was a pure eleven-line deletion, which cannot move a compressed kernel
that far, and a kernel missing that much driver hangs at the logo whether
or not the pin is there.

Ruled out along the way: not a stale artifact (the binary's own embedded
banner reads `7.2.0-rc2-gca309de7cbb2`, no `-dirty`, so the right source
was compiled and packaged) and not a wrong parent. The real story is that
every image that booted came off a pre-rebase lineage (`42fa5a3e4`) while
the unpin was the only one built from the post-rebase lineage
(`d7206ebe0` / `ca309de7c`) — same patches, different hashes.

Full write-up: `ember-2026-08-10-unpin-result-was-confounded.md`.

Practical consequence for you: **the pin's necessity is an open question,
not settled fact.** Do not treat a logo hang as expected.

## If it hangs again

Rebuild the unpin *alone* on the current `.config` before concluding
anything, so the ICC change is not confounding it in the other direction.
The surviving build directory is the reference:

    make -j12 O=/data/buildcache/kbuild/build-integration-d38242fb5 \
         ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
         CC="ccache aarch64-linux-gnu-gcc" Image.gz modules dtbs

    KDIR=/data/buildcache/kbuild/build-integration-d38242fb5 \
      ./make-pmos-image.sh out/boot-joan-nosettle.img out/boot-joan-<name>.img

ccache only applies when the make line carries `CC="ccache ..."` —
`/usr/lib/ccache` shims native compilers only, so `CROSS_COMPILE` resolves
straight past it.

Sanity-check every image against the working family's `27,815,936` bytes
before booting. That one `ls` is what caught this.

## Next lead if the vote is not it

`a5xx_pm_suspend()` resets the VBIF before power collapse on A510 and
A530 but **explicitly skips A540**, commented "the others will tend to
lock up". So on our chip the VBIF FIFO state is carried into collapse
rather than cleared. VBIF is the GPU's AXI master interface to the NoC —
the same path the `gfx-mem` vote reserves bandwidth for, one layer down.

Worth pairing with the downstream SPTP gate on
`A5XX_GPMU_SP_PWR_CLK_STATUS`, which mainline does not implement.

## Correction carried from earlier

I published the never-dropped ICC vote as a candidate *cause* of the
original wedge. Chronology rules that out: the pin is `c3f1b45f0`
(2026-08-02), the vote arrived with our own msm8998 ICC driver in
`7d9b74b7f` (2026-08-04). On 08-02 there was no interconnect driver for
this SoC at all, so whatever wedged then was the hardware NoC. The vote is
still worth dropping — but as "does this help now", not as the
explanation.

## Warning

The source worktree is `/tmp/joan-bt-fix` — **tmpfs, evaporates on
reboot**, and the ICC change is uncommitted there. Commit it somewhere
durable before rebooting nym-skyforge, or it is gone. I deliberately left
it uncommitted so master stays verified-fixes-only until the device says
yes; that trade needs your judgement now that it may sit overnight.

Repo state otherwise: `master` and `joan/latest-clean-test` both at
`c861d1217`, PR #8 merged.

# WLAN: the lost delta is recovered — it is a config difference, not lost source

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-16

## Summary

`docs/ember-handoff-2026-08-16-audio-bringup-and-wlan-negative.md` concluded that
the only image ever to bring `wlan0` up was built `-dirty` from uncommitted
changes that no longer exist, and therefore that "the only artifact that has ever
brought `wlan0` up cannot be rebuilt from any committed state... a provenance
problem, not a code one."

**That conclusion is wrong on both counts.** The working image is a *clean* build
of `d05e70c5e484`, and the difference between it and every failing build is a
two-symbol kernel config change.

| | working | failing |
|---|---|---|
| image | `boot-joan-wifi-d05e70c5e.img` | `boot-joan-control-mine.img`, `boot-joan-wifidbg-d05e70c5e.img` |
| version string | `7.2.0-rc2-gd05e70c5e484` | `7.2.0-rc2-gd05e70c5e484` |
| `CONFIG_ATH10K_DEBUG` | not set | `=y` |
| `CONFIG_ATH10K_DEBUGFS` | not set | `=y` |

Nothing else differs across 4,932 set symbols.

## How it was recovered

`CONFIG_IKCONFIG=y` is set in this build lineage, so **every one of these kernels
carries its own complete `.config` embedded in the image**, between the
`IKCFG_ST` and `IKCFG_ED` markers as a gzip blob. No source tree, worktree or
stash is needed to recover what a given image was built with.

```sh
unpack_bootimg --boot_img boot-joan-wifi-d05e70c5e.img --out W
zcat -q W/kernel > wifi.Image          # Image.gz-dtb -> raw Image
# then slice between IKCFG_ST / IKCFG_ED and gunzip
```

Both images report a version string with no `-dirty` suffix and name the same
commit. Same commit plus not-dirty means the source is identical by
construction, so the embedded config is the *only* variable that can differ.
That makes this a proof of what the delta is, not an inference.

The `-dirty` reading in the previous handoff appears to have come from a
neighbouring image: several `d05e70c5e484-dirty` images do exist
(`apmode-519646f01`, `chan169`, `shadow`, `hostcap`, `regtest*`, …), but the one
whose sha256 matches the successful run `WIFI-20260814T183233Z`
(`7d7280e2626a7d2d614c4ad0091d949ed12d177c15d5c0c80f218edf3b599e35`) is
`boot-joan-wifi-d05e70c5e.img`, and it is clean.

## Why the bisect came back negative

The ath10k debug symbols were turned on *in order to debug the WLAN problem*.
Every bisect candidate build inherited them. So all six candidate boots and both
control boots ran a configuration that independently breaks WLAN, and the reverts
under test could not have shown a difference either way. The bisect was measuring
the instrumentation, not the commits.

This is the same class of mistake as `feedback_ab_order_confound`: a variable
that tracks the treatment in every arm.

## Mechanism (hypothesis, not yet confirmed)

`CONFIG_ATH10K_DEBUG` turns `ath10k_dbg()` from a no-op into real work, and
`ATH10K_DEBUGFS` adds init that runs during bring-up. WCN3990 bring-up on this
device is already documented as timing-sensitive — see
`docs/ember-wifi-modem-crash-rootcaused-2026-08-14.md`, where MSA permission
assignment races a modem watchdog roughly 2.5 s later. Added work in the
QMI/MSA path is a plausible way to lose that race.

**Not yet proven.** What is proven is *which* variable differs; that flipping it
back restores `wlan0` still needs one confirming boot.

## Next step

Build current `joan/latest-clean-test` with `CONFIG_ATH10K_DEBUG` and
`CONFIG_ATH10K_DEBUGFS` unset and boot it. If `wlan0` comes up, WLAN is
reproducible from committed state and the lane reopens with a real target: find
why bring-up is timing-fragile enough that logging breaks it.

Note that the current audio build lineage (`build-snd-pdm`, and `build-adsp-only`
before it) still carries `CONFIG_ATH10K_DEBUG=y`. Any build intended to have
working Wi-Fi needs both symbols cleared.

## Retractions this supersedes

- "The working image reports `d05e70c5e484-dirty`." It does not; it is clean.
- "The only artifact that has ever brought `wlan0` up cannot be rebuilt from any
  committed state." It can.
- "That is a provenance problem, not a code one." It is a configuration problem,
  and it is fully recoverable from the binaries.

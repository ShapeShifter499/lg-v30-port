# Card 94 — the SD-I/O framing is withdrawn; the death looks like GPU *resume*

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-11
State: HYPOTHESIS REVISED from banked evidence; no new boot performed; no fix promoted

## What is withdrawn

`ember-a540-genpd-gate-result-2026-08-11.md` (Addendum 2) concluded "the death
tracks SD-card I/O" and offered a refined hypothesis that a completed A540
suspend degrades a shared NoC/BIMC path which the next heavy SD transfer trips.

Re-reading the same capture line by line, that does not survive. From
`pstore-clkignore-2026-08-11T173545Z`:

```text
[   11.130833] pmOS_root: recovering journal
[   12.313492] pmOS_root: clean, 43903/10618320 files, 1564428/48000507 blocks
[   12.479275] Resize 'ext4' root filesystem (/dev/mmcblk0p2)
[   12.685730] EXT4-fs (mmcblk0p2): mounted filesystem ... r/w with ordered data mode
[   12.758954] Switching root
[   14.597000] udevd[480]: starting version 3.2.14
[   19.858054] EXT4-fs (mmcblk0p1): mounting ext2 file system using the ext4 subsystem
[   19.873904] EXT4-fs (mmcblk0p1): mounted filesystem ... r/w without journal
<death>
```

A journal recovery and fsck across a 183 GiB card at 11.1-12.3 s is far heavier
SD I/O than mounting a small ext2 boot partition, and it completes without
incident. The correlation with "SD I/O" was an artifact of the /boot mount
simply being the **last line logged** before userspace starts, in all four runs.

There is also no `qcom_icc_rpm_smd_send` error and no `-110` anywhere in this
capture, so the RPM-timeout thread that motivated the NoC-degradation story is
absent from the run it was inferred over.

## What the timing actually points at

`switch_root` at 12.76 s, udev at 14.6 s, fstab mounts finishing at 19.87 s.
What a pmOS userspace does immediately after that is start its services --
including the display stack. The GPU completed its runtime suspend at ~2.3 s and
nothing touched it for the next seventeen seconds.

So the revised hypothesis is that the fatal transition is the GPU **resume** --
the first DRM client opening the device after a completed suspend -- not the
suspend, and not storage.

This fits every result in the bank without special pleading:

- Pin present (mainline default): the GPU never suspends, so there is no
  suspended state to resume from. These boots reach Phosh and stay up; the
  clock-ownership boot earlier today ran for over an hour and rendered.
- Pin removed: the GPU suspends at ~2.3 s, and dies when userspace first opens
  DRM around 20 s.

## Why the gate A/B could not see this

Addendum 2 read the same-binary `joan_gpu_gate=1` vs `=0` comparison as proof
that GPU genpd collapse is not the killer. That inference is weaker than stated,
because the two arms have *different* resume hazards rather than a shared one:

- `gate=0`: resume from a genuinely collapsed GX rail.
- `gate=1`: collapse was suppressed, but genpd still believes the domain is off,
  so the next `gdsc_enable()` pulses `SW_RESET` and `AON_RESET` on a rail that is
  physically still powered. `93cc2be54`'s own commit message records this as a
  known caveat of the diagnostic.

Both arms therefore reach a broken resume by different routes and die in the
same window. The A/B ruled out nothing about collapse; it only showed that
suppressing collapse does not rescue the boot, which is exactly what you would
expect if the fault is on the resume side.

**Consequence:** "GPU genpd collapse is not the killer" should be downgraded from
a conclusion to an open question.

## The cheap decisive test

The hypothesis predicts the death time tracks *when the first DRM client starts*,
not when storage is touched. That is testable without building a kernel and
without consuming a GPU experiment on a kernel change:

1. Mount the pmOS rootfs on the SD card from a host.
2. Disable the display manager / phosh service so no DRM client starts.
3. Boot the existing `gate0` image, unchanged, and let it sit.

- Survives well past 20 s and stays reachable over the USB gadget: the fault is
  on GPU resume. Then re-enable the service and confirm the death returns.
- Dies at ~20 s anyway: resume is exonerated and the trigger is something else in
  early service startup.

Either way it is one bit of information for one boot, it needs no new kernel, and
the image is already built and hash-recorded.

A second, sharper variant once that is known: keep the display manager disabled
and provoke a GPU resume by hand at a chosen moment, so the resume is isolated
from everything else userspace does at 20 s.

## Not claimed

- No claim that resume *is* the cause. This is a hypothesis derived from banked
  evidence, not a device result.
- No claim about SDCC. The SDCC2 100 MHz bus-vote correction committed today is
  a separate correctness fix; this capture shows the card running SDR104 at the
  200 MHz operating point, so that fix is not implicated in this failure either
  way.

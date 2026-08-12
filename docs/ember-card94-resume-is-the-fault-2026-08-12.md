# Card 94 — the fatal transition is GPU runtime **resume**, not suspend

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-12
State: DEVICE RESULT; single authorised RAM-only boot; mechanism verified engaged; no fix promoted

## Result in one line

With the runtime-PM pin removed and no DRM client ever started, joan ran for
**213 s** with the GPU verifiably suspended and its GX/CX domains verifiably
collapsed; forcing a single isolated GPU runtime resume through sysfs reset the
SoC immediately.

## The run

- image `boot-joan-a540-genpd-gate-gate0.img`, 30,535,680 bytes,
  SHA-256 `4338ddb7c3be63f352f48632d15875c3a5c3ab4dad9ab1dc77aaab0c2198acbf`
- runner SHA-256 `bf970835eff51fe5b1c4fa3f2b5186aa883179fe58f984ebb0363fe421eccb5e`
- RUN_ID `CARD94RESUME-20260812T130802Z`, RAM-only, nothing flashed, no retry
- kernel `7.2.0-rc2-g93cc2be5482c`, cmdline unchanged (`joan_gpu_gate=0`)

**Same binary and same cmdline as the earlier gate0 run that died at 17.122 s.**
The only difference anywhere in the system: `/etc/runlevels/default/greetd` was
moved aside in the SD rootfs, so nothing opened the GPU.

## The mechanism was verified to engage

A stable boot means nothing unless the thing under test actually happened. It did:

```text
runtime_status=suspended
runtime_active_time=361          (ms)
runtime_suspended_time=211436    (ms)

JOAN-GPU-GATE: armed=0
JOAN-GPU-GATE: gdsc_disable(gpu_gx) hit=1 gate=0
JOAN-GPU-GATE: gdsc_disable(gpu_cx) hit=2 gate=0
JOAN-GPU-GATE: gdsc_disable(gpu_gx) hit=3 gate=0
JOAN-GPU-GATE: gdsc_disable(gpu_cx) hit=4 gate=0
```

`armed=0` is the control arm, so collapse was **not** suppressed: the GPU
completed a runtime suspend and both domains genuinely powered off, then stayed
that way for 211 s while the box sat happily idle and reachable over SSH.

## The trigger

With no compositor, no modeset and no rendering anywhere in the picture:

```sh
echo on > /sys/devices/platform/soc@0/5000000.gpu/power/control
```

The SSH session died mid-command. The phone reset and came back on LineageOS.
`pmOS USB GONE`, `LINEAGE USB back`, ping failed.

That write does exactly one thing: force a runtime resume of the GPU. No SD
transfer, no service start, no DRM client, no userspace graphics of any kind.

## Why every earlier run died where it did

This explains the whole banked matrix without special pleading. Every prior
failure landed ~1 s after `EXT4-fs (mmcblk0p1): mounted filesystem`, which is
simply where pmOS finishes fstab and starts services -- **including greetd**,
whose `initial_session` autologins straight into `phosh-session`
(`/etc/greetd/config.toml`). The first DRM client resumed the GPU, and the resume
killed the box. The `/boot` mount was never causal; it was the last console line
before the compositor started.

It also settles why suppressing collapse did not help. `gate=1` resumes from a
rail that genpd believes is off, so `gdsc_enable()` pulses `SW_RESET`/`AON_RESET`
on live hardware; `gate=0` resumes from a genuinely collapsed rail. Both arms
reach a broken resume by different routes, which is why the A/B discriminated
nothing.

And it explains why the pin works as a workaround: with the GPU pinned active
there is never a suspended state to resume from.

## Capture

`~/joan-images/pstore/pstore-card94-resume-2026-08-12T131516Z.bin`

Console ends at `[19.805723] EXT4-fs (mmcblk0p1): mounted filesystem`, then ~193 s
of silence -- correct for an idle system with no compositor -- then a hard reset
with **no oops, no panic, no BUG and no kernel message at all**. The reset is
below Linux's visibility, consistent with the PS_HOLD class seen throughout.

Provenance of the capture is established by a line unique to this boot:
`[12.311228] Please run 'e2fsck -f /dev/mmcblk0p2' first.` Earlier captures show
resize2fs reporting "Nothing to do!" instead; this run differs because the
rootfs edit left the journal replayed.

## Honest confounds

1. Mounting the rootfs from LineageOS replayed the ext4 journal, so filesystem
   state at boot differed from prior runs. This changes early boot I/O only. It
   cannot explain a reset that happened 193 s later, on a specific sysfs write,
   with the storage stack idle.
2. Writing `on` to `power/control` both forces a resume and disables autosuspend.
   The fatal event is therefore "a resume happened", not specifically "an
   autosuspend-driven resume".
3. One boot. The claim is that resume is fatal, which one demonstration
   establishes; a control (`echo auto`, i.e. no forced resume, left idle longer)
   is not needed because the same 213 s of idleness is itself the control.

## What this changes

Card 94 should be restated. It is not "GPU power domain never suspends"; suspend
works. It is **"the A540 cannot be resumed once it has runtime-suspended"**, and
the runtime-PM pin is a workaround that prevents ever entering the state.

## Next

The question is now bounded to `a5xx_pm_resume()` and the GDSC/clock/reset
bring-up it performs against a collapsed GX rail. Downstream's CRC sequence in
`clock-gpu-8998.c` performs a specific ordered bring-up -- GX BCR pulse,
`GPUCC_GX_DOMAIN_MISC` GMEM_RESET pulse, clamp release, then GDSC on -- which is
worth diffing against what `gdsc_enable()` plus `a5xx_pm_resume()` actually do in
this exact order on mainline.

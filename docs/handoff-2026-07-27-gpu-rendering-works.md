# Handoff: joan GPU rendering works — the blocker was one unclaimed clock

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-07-27

Read with `docs/kernel-change-ledger.md` K141–K143 (authoritative, evidence-linked).

## The fix, in one line

`clk_disable_unused()` was switching off **GCC_GPU_BIMC_GFX_SRC_CLK** — the
GPU's gate to BIMC — at late_initcall, because no mainline driver claims it.
Adding it to the msm8998 GPU node fixes the whole wedge.

## Why it hid for so long

The failure is a function of **elapsed time**, and every experiment we ran was
unknowingly split across the moment the clock died (~3 s into boot):

- Kernel ring tests ran inside `a5xx_hw_init()` at ~1.4 s and passed.
- Userspace submits ran seconds later and failed.

That produced a beautiful, entirely false story about the submit path, and
before that an equally false one about mapping age. The measurement that broke
it: run the *same known-good ring IB* from a **delayed work** instead of from
hw_init. Executes at 1.4 s, hangs at 4.5 s — no submit path anywhere in it.

**Generalise this:** when two code paths differ in outcome, check whether they
also differ in *when* they run before concluding anything about *what* they do.

## Instruments that earned their keep

- `msm.k142_delayed_ib=N` + `msm.k142_period=P`: repeat a ring-direct IB with a
  unique marker read back from `CP_SCRATCH_REG(3)`, stopping at the first hang.
  A 3 s sweep brackets the transition in one boot.
- `msm.k141_submit_probe=1`: one submit reported end to end, with the fence
  **polled** rather than waited on so a dead retire IRQ can't hide a completion.
- `tools/msmsubmit.c`: walks the DRM submit path one ioctl at a time with a
  built-in empty-submit positive control, so a run that measures nothing cannot
  look like a pass.

## Traps found the hard way — do not repeat

1. **`drm-engine-gpu` is always 0 on a5xx.** `a5xx_submit` never writes
   `rbmemptr_stats`. It is not evidence of anything.
2. **A faulted submit still reports SIGNALLED** to `WAIT_FENCE`, because
   `recover_worker` force-retires it. Cross-check every fence claim against
   dmesg for `gpu fault` / `hangcheck recover`.
3. **`PM4_PARITY` is not bit parity** — nibble-fold indexed into 0x9669.
   `PKT4(CP_SCRATCH_REG(3),1)` is `0x400B7B01`; the `0x480B7B81` in the old
   ledger is malformed and the CP rejects it.
4. **`CP_SCRATCH` writes are illegal from an unprivileged IB.**
5. **`msm.k130_no_powercycle=1` means a faulted GPU never recovers in that
   boot** — one GPU experiment per boot, or the result is contaminated.

## State at close

- Kernel `joan/gpu-bringup`: `38de6f7f5` (the DTS fix), `4245f40ab` (a real
  NULL-deref DoS in `msm_ioctl_gem_submit`), `e44713936` (instrumentation).
  **Not pushed** — both fixes are upstreamable and want review first.
- Phone: RAM-booted pmOS, Phosh live on freedreno FD540 at 1440x2880, left
  running for Lance. Restart with `/tmp/start-gpu-phosh.sh` on the device.
- Session gotchas: `XDG_RUNTIME_DIR` must be outside `/run/user/10000`
  (elogind unmounts it at ssh logout); **never set `WLR_BACKENDS=drm`** — it
  drops the libinput backend and the compositor gets no input devices;
  `/etc/environment` still pins `WLR_RENDERER=pixman`.

## Next

- Re-validate `k127_no_suspend`, `k130_*`, `k131_no_preempt` one at a time.
  Every one was tuned against a GPU whose memory path was already dead, so
  some may now be unnecessary — including the GX collapse workaround.
- Review the `mem_src` clock-name and `gpu.yaml` (now at its 7-clock maxItems
  limit) before sending the DTS patch upstream.

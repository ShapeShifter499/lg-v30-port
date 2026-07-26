# Handoff: LG V30 (joan) GPU bring-up — the hunt is down to the userspace submit path

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-26

Read this with `docs/kernel-change-ledger.md` entries K123–K140 (same day,
authoritative, evidence-linked). This doc is the operational summary so the
next agent can act without re-deriving anything.

## Where the bug is, in one paragraph

The Adreno 540 powers up, hw_init completes, and **kernel-written IBs execute
with register-readback proof** (K139: two BOs, mapped before AND after CP
start, PKT4 scratch markers both landed). The **identical IB content submitted
from userspace through `msm_gpu_submit`/`a5xx_submit` never signals its fence,
in the same boot**. Empty userspace submits (no IB) DO signal (K131). So the
defect lives in the delta between "packets written straight into the ring +
a5xx_flush + a5xx_idle" and "the msm submit path with an IB": kick/wptr
handling, rptr-shadow (whereami) interaction with the single-ring config, BO
pinning/fence attachment, or completion delivery rather than execution.

## Do this first (one boot, already specified)

Instrument `a5xx_submit()`: log ring wptr before/after the kick, and make the
submitted IB write a marker to `CP_SCRATCH_REG(3)` (pattern in
`a5xx_k139_test()`, same file). Then run `tools/msmprobe.c` (already on the
device at /tmp/msmprobe and on nym-nest at /tmp/msmprobe).
- scratch advances but fence never signals → execution is FINE; the whole
  remaining bug is completion/retire delivery (CACHE_FLUSH_TS / IRQ / memptr).
- scratch does not advance → the CP never consumed the userspace-submitted
  packets; diff what a5xx_flush does vs the submit path's kick.

## Working baseline (all required, all default-off)

Cmdline via `EXTRA_CMDLINE=` to `make-pmos-image-fw.sh` (no root needed):
```
msm.k127_no_suspend=1        GPU never power-collapses (restore resets the SoC)
msm.k128_no_ubwc_scanout=1   force linear scanout negotiation
msm.k130_no_powercycle=1     recovery must not suspend/resume (SoC-fatal)
msm.k130_no_crash_capture=1  crashstate register dump wedges a faulted GPU
msm.k131_no_preempt=1        nr_rings=1; preemption breaks ALL submits
```
Diagnostics available: k123_stage, k124_pm, k134_boot_ib (now the K139 paired
test), k135_zap_first, k136_no_secure_switch, k132_tlbi_on_map.

## Refuted — do not re-litigate (each was a single-variable boot)

Zap/secure-mode transition (K123, K135, K136 — pre-switch IBs hang too);
UBWC/modifiers/scanout (K128 + measured MDSS_HW_VERSION 0x30000001);
GPMU (K124 mask 7); LG vendor CP ucode (newer than linux-firmware,
`firmware/lg-vendor/`, UNTRACKED pending licensing — identical behavior);
TLBI-on-map (K132); mapping age (K139 killed it); GPU_READONLY (K137);
PKT7-vs-PKT4 content (userspace PKT4 still hangs); preempt-wrapper null
save-addr (K140 — gate kept on principle, measured not the bug);
burst length PFE-vs-PFD; SMMU stream IDs; ME_INIT ordinals, HWCG, VBIF, ROQ,
SECVID (all byte-identical to downstream).

Open lead, honestly flagged: K138 (RO+PKT4, stage-6 map) hung where K139-BO1
(RW+PKT4) executed — different boots, so it is a lead, not a conclusion.

## Environment essentials

- BUILD on nym-skyforge: worktree `~/vibe-coding-projects/coding/linux-mainline-v30-ember-k104`
  (branch `joan/gpu-bringup`, pushed @ 9dc8eb3bc), build dir `../build-k104`,
  26 s incremental. FLASH/BOOT only from nym-nest (xHCI cannot talk to LG aboot).
- Boot: `/tmp/boot-dev.sh <img> <sha256>` on nym-nest (RAM-only `fastboot boot`;
  never `timeout`-wrap fastboot, one client, never `getvar`, enter bootloader
  only via `adb reboot bootloader`). Phone returns to LineageOS on reboot.
- Device access: `ssh user@172.16.42.1` (key `id_pi_migration`, nym-nest);
  root = `echo 147147 | sudo -S …` (needs `ssh -tt`). Clean return to
  LineageOS: `sudo reboot`. Password documented in
  `docs/ember-handoff-2026-07-11-m4-smmu-next.md`.
- Host gadget link comes up DOWN: `ip link set enp0s29u1u5 up` +
  `ip addr add 172.16.42.2/24` on nym-nest.
- STREAM ALL LOGS OFF-DEVICE PER-LINE (`/tmp/nest-cmd.sh`, `/tmp/nest-probe.sh`
  on nym-nest); the SoC resets hard enough to destroy on-device logs. Positive-
  control every probe: two false passes this session (EINVAL-everything, and a
  "surviving" run that logged nothing).
- `MSM_PIPE_3D0` = 0x10. Params are `msm.*` (builtin). K101 image stays
  quarantined. Standing user config: `WLR_RENDERER=pixman` + greetd disabled —
  correct until submits work; do not flip.

## State at close

Phone: LineageOS, healthy, nothing flashed. Repos: lg-v30-port master @
cd695e6+K139/K140 entry, kernel fork joan/gpu-bringup @ 9dc8eb3bc, both pushed.
Memory (`project_lg_v30_mainline_port.md`) current. Deck epic #43 not updated
this session (credit budget) — the ledger is the source of truth.

# Card 94 A540 suspend evidence bank — 2026-08-11

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:moa/deep-flash
Acting model: openai-codex:gpt-5.6-sol (`reasoning=high`)
Reference models: zai:glm-5.2, minimax:MiniMax-M3, deepseek:deepseek-v4-flash (`reasoning=high`)
Date: 2026-08-11
State: BANKED DEVICE EVIDENCE; no fix promoted; no new boot performed

## Why this bank exists

The original three-boot Card 94 result was already committed as
`docs/aurel-card94-retest-2026-08-10.md` at
`bb346a6a5428468c619fd35bf9c743cac5e9292d`. A later session-summary
truncation made that complete record look as if it stopped during boot 2. It did
not: all three outcomes were already preserved.

This bank adds two things:

1. copies the surviving ignored raw images and pstore records out of nym-nest
   `/tmp` into this project's durable `out/` directory; and
2. reconciles the initial three-boot result with the subsequent staged
   suspend-path discriminators through Phase 8.

Nothing was flashed and no additional device boot was performed while banking.

## Initial three-boot matrix

All three attempts used RAM-only `fastboot boot`.

| Boot | Exact image and source | Outcome |
|---|---|---|
| 1 | `out/boot-joan-icc-suspend.img`, 27,815,936 bytes, SHA-256 `f61a155ef67d096d6acf8a5cb0b450d2675f0402d49e27ad9d6b4f6944182d2e`; A540 runtime-PM pin removed plus Ember's gfx-mem ICC vote-drop; durable source anchor `joan/a540-unpin-test` at `3f0954cfa` | Reached pmOS userspace. At 34.8 s, `qcom_icc_rpm_smd_send mas 35 error -110` occurred on the TSIF path, not the GPU path. At 39.9 s SDCC bandwidth removal also failed with `-110`. The console ended abruptly and the phone returned to LineageOS through the reset/watchdog class Lance observed as flicker plus self-reboot. |
| 2 | `out/boot-joan-unpin-only.img`, 27,815,936 bytes, SHA-256 `b40123586dc18b864321c8dcc918e611671bf5af464e7fdcbc9ee9f1c4041c5d`; ICC hunks reverted, pin removal retained; `joan/unpin-only-test` at `3d55e94d6` | The pstore console ended at 9.46 s immediately after `switch_root`. No RPM-SMD `-110` appeared in the captured record. The phone returned to LineageOS. This proves the ICC vote-drop was not required for the failure, while boot 1 also shows that the vote-drop introduced or exposed a separate RPM/ICC wedge. |
| 3 | `out/boot-joan-master.img`, 27,807,744 bytes, SHA-256 `a352406d7348d3a4f91cd20ed18dd31db96ec49dea2bce7186b072c6c93551b2`; kernel `7.2.0-rc2-g47041183b55e`, runtime-PM pin present | Stable at the pmOS lockscreen for more than 11 minutes. `runtime_suspended_time` remained zero because the pin held the reference. Zero `qcom_icc_rpm_smd_send` errors were observed. |

The defensible initial conclusion remains: removing the pin exposes a fatal
runtime-power transition in the current stack. The ICC vote-drop is not the
fix and must not be promoted.

## Raw evidence copied from nym-nest tmpfs

These files now exist under `lg-v30-port/out/` on durable local storage.
`out/` is intentionally git-ignored; this committed manifest is the durable
index.

```text
f61a155ef67d096d6acf8a5cb0b450d2675f0402d49e27ad9d6b4f6944182d2e  boot-joan-icc-suspend.img                         27815936 bytes
b40123586dc18b864321c8dcc918e611671bf5af464e7fdcbc9ee9f1c4041c5d  boot-joan-unpin-only.img                          27815936 bytes
a352406d7348d3a4f91cd20ed18dd31db96ec49dea2bce7186b072c6c93551b2  boot-joan-master.img                              27807744 bytes
aec12e05b8cf572a7a424e14964fe0887a6a823e2275af0ef5a2bba03dac4224  pstore-icc-suspend-2026-08-10.bin                    262224 bytes
6d421c9f4e10668a70fd839b641c8e7332fe434c7b9249f763ec2ac994047ccc  pstore-icc-suspend-2026-08-10.meta.txt                  807 bytes
d8a5e75f0496795025956fc60e259c5cd3f4e988c96f4180588f6a157eb74add  pstore-icc-suspend-2026-08-10.strings.txt            244714 bytes
92e53a1980379ca8ae9d5aa8766e41bb87e0ac4318b9ec97c85d311a74140faa  pstore-unpin-only-2026-08-10.bin                      262224 bytes
3e80988584b0109fb0f13eb0d0e601999a7d52f51d0a68bcc7280897cd3212ff  pstore-unpin-only-2026-08-10.meta.txt                    804 bytes
4c55569c538b7fdd429db79a63aa62c77863852a6041114d25d51e06b24201cb  pstore-unpin-only-2026-08-10.strings.txt              245602 bytes
```

## Successive device-proven boundary isolation

The initial Card 94 wording reasonably pointed at the A540 suspend path, but the
later controlled series narrowed that broad statement. Each diagnostic returned
an error after exercising a bounded stage, preventing the PM core from advancing
to physical genpd collapse.

| Stage | Source / result document | Device result |
|---|---|---|
| Clean SPTP/RBCCU-gated unpin | `9f3d891201060dba13e0a28e641914365e9cf6cd`; `docs/aurel-a540-sptp-gate-result-2026-08-10.md` | Reached userspace, then returned to LineageOS through the same `0x20` / PS_HOLD reset class. Gate alone rejected as a fix. |
| Stop before VBIF | `0b010f5de`; `docs/aurel-a540-pre-vbif-stop-result-2026-08-10.md` | Stable beyond five minutes. GDSC predicates and callback/error rollback cleared. |
| Execute VBIF halt/ACK/clear, then stop | `6afe80c0e`; `docs/aurel-a540-post-vbif-stop-result-2026-08-10.md` | Stable beyond five minutes. A540 VBIF halt path cleared without adding the forbidden A540 software reset. |
| Add devfreq suspend/rollback | `d0defdafd`; `docs/aurel-a540-devfreq-cycle-result-2026-08-10.md` | Stable beyond five minutes. |
| Add AXI/EBI disable/restore | `6e8a6df9e`; `docs/aurel-a540-axi-cycle-result-2026-08-10.md` | Stable beyond five minutes. |
| Add GPU clock/rate disable/restore | `6c4503196`; `docs/aurel-a540-clock-cycle-result-2026-08-10.md` | Stable beyond five minutes. |
| Remove and restore the generic PM8005 S1 regulator vote | `f8fe4956e5aa471e96483e3b9b899aaadb0bc43a`; `docs/aurel-a540-vdd-cycle-result-2026-08-10.md` | Stable. The generic vote was exercised, but the physical rail remained enabled because joan marks S1 always-on and the OPP framework owns another consumer. |

Together, these results clear the driver-local callback through its normal
regulator-vote removal when PM-core genpd collapse is prevented. The remaining
untested destructive boundary is the later GPU GX/CX genpd transition after
`a5xx_pm_suspend()` returns success.

## Phase 8 precondition failure

Phase 8 attempted to suppress only runtime collapse by adding
`GENPD_FLAG_RPM_ALWAYS_ON` statically to `gpu_gx` on top of the clean gated
unpin candidate:

- source: `a856f868ec30893be16409b69aa010f9f9d74c54`
- image: `out/boot-joan-a540-gx-rpm-on-a856f868e.img`
- image SHA-256: `8ff54bfa1ba1475cbb354c5b0d49b0012b2f03c148591ac0b9d2b809f6b54982`
- full result: `docs/aurel-a540-gx-rpm-always-on-result-2026-08-11.md`

The kernel reached pmOS and stayed reachable, but the intended discriminator was
not exercised. `gpu_gx` was off when its provider initialized, so generic genpd
rejected the static always-on flag with `-EINVAL`. GPUCC and the GPU remained
unbound. Lance observed a blank screen; live evidence showed no DRM `card0` or
framebuffer while the lower DPU/DSI components were individually bound. The
missing aggregate KMS device was consistent with the absent Adreno component.

Classification: **rejected diagnostic / precondition failure**. It says nothing
about whether late physical GX/CX collapse is safe. Do not promote or repeat the
static flag approach.

## Current device state at banking time

At 2026-08-11 08:18 PDT, the Phase 8 pmOS RAM boot remained reachable over the
USB gadget after 6 h 42 min:

```text
kernel=7.2.0-rc2-ga856f868ec30
drm_card0=no
```

The screen remained blank by the already-recorded observation. The untouched
LineageOS installation remains the fallback because nothing was flashed.

## Successor boundary

A valid next discriminator must:

1. keep GPUCC and the GPU bound;
2. permit normal initial GPU_GX power-on;
3. allow the complete Adreno runtime-suspend callback to return success; and
4. instrument or suppress only the later runtime-PM GX/CX genpd-off transition.

It must not repeat the ICC vote-drop candidate, the already-rejected SPTP-only
unpin, the forbidden A540 VBIF software reset, or the static
`GENPD_FLAG_RPM_ALWAYS_ON` precondition failure.

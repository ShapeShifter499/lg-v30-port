# Gold CPR interpolation fix — implemented and verified (2026-09-26)

Written-by: Fulgor Nymvale (agent-fulgor-zcode)
Agent-harness: ZCode:zai-start-plan/GLM-5.3-Flash
Date: 2026-09-26
Implements: "Next" item 1 of
[ember-2026-09-26-cpu-dvfs-handoff.md](ember-2026-09-26-cpu-dvfs-handoff.md)

## The change

Kernel `joan/cpu-dvfs-cprh`, commit `1c3956d058b2` (pushed):
**pmdomain: qcom: cpr3: interpolate from unclamped fuse voltages on MSM8998**.

msm-4.4 interpolates corner open-loop voltages from the raw fused voltages
(`cprh_kbss_calculate_open_loop_voltages`) and clamps each corner afterwards
(`cpr3_adjust_open_loop_voltages`). Mainline clamped the fuse corner voltage
to the fuse corner maximum first (`cpr_populate_fuse_common`), so every gold
corner interpolating against the TURBO_L1 endpoint was pulled toward 1136 mV
instead of the fused 1198 mV.

The fix adds `unclamped_fuse_uv` to `struct cpr_desc` (cpr3.c): when set,
`cpr_populate_fuse_common` keeps the raw fuse voltage, the fuse-corner range
check tolerates `uV > max_uV`, and the per-corner clamp in
`cpr3_corner_init` (already present) does the limiting after interpolation.
It is set only for msm8998; the msm8916 CPR1 caller passes `false` and every
other SoC keeps the old behavior.

Source credit: the algorithm and clamp ordering derive from the msm-4.4
vendor kernel (The Linux Foundation / Code Aurora Forum, GPL-2.0) —
`cprh_kbss_calculate_open_loop_voltages()` and
`cpr3_adjust_open_loop_voltages()` in `drivers/regulator/
cprh-kbss-regulator.c` and `drivers/regulator/cpr3-util.c`. No vendor code
was copied; the mainline-side implementation is new and was guided by the
vendor functions' documented ordering.

## Verification

Offline simulation first: reimplementing both algorithms in Python with the
DT tables, thread descriptors and the chip's fuse readings reproduced the
dvfs14 dump on all ten measured gold corners (proving the model), then
predicted the fixed values.

Measured on the phone (dvfs15 RAM boot, evidence
[evidence/2026-09-26-dvfs/dvfs15-verify.txt](evidence/2026-09-26-dvfs/dvfs15-verify.txt)),
gold thread, open-loop voltage in mV (Lineage corner N is 1-based):

| level | freq MHz | dvfs14 | dvfs15 | Lineage | delta |
|---|---|---|---|---|---|
| 21 | 1804.8 | 848 | 856 | 856 | 0 |
| 22 | 1881.6 | 892 | 908 | 904 | +4 |
| 23 | 1958.4 | 924 | 948 | 948 | 0 |
| 24 | 2035.2 | 964 | 996 | 996 | 0 |
| 25 | 2112 | 1008 | 1044 | 1044 | 0 |
| 26 | 2208 | 1036 | 1084 | 1084 | 0 |
| 27 | 2265.6 | 1064 | 1120 | 1116 | +4 |
| 28 | 2323.2 | 1092 | 1136 | 1136 | 0 |
| 29 | 2342.4 | 1100 | 1136 | 1136 | 0 |
| 30 | 2361.6 | 1108 | 1136 | 1136 | 0 |

- The 28-52 mV stability deficit from the handoff is gone: eight corners
  exact, two one 4 mV step high (safe side).
- Silver corners are bit-identical to dvfs14 (still within 4 mV of Lineage);
  the flag provably does not touch them (their fuses were never clamped).
- Gold under all-core load: ~2357 MHz at 1136 mV; OSM current point
  1136 mV @ 2361 MHz; LMh request unchanged (1120/1136 mV).
- systemd running, no new failures.

Lower gold corners (levels 1-20) are within one 4 mV step of Lineage except
level 14 (1344 MHz), which sits one step low (704 vs 708 mV). Our frequency
table has 1728/1804.8 MHz where the sibling tables have 1747.2/1824 MHz —
the two known differing rows — which shifts interpolation weights slightly.
Not tuned further; closed-loop CPR corrects within the window at runtime.

## State after this fix

Handoff "Next" item 1 is done. Item 2 (pmaports integration: pin the branch,
`QCOM_CPR3=y`, `ARM_QCOM_CPUFREQ_OSM=y`, `QCOM_SPM=y`, `QCOM_LMH=y`) is now
unblocked. Phone left RAM-booted on dvfs15.

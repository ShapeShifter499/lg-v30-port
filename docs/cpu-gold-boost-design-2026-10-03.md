# Gold single-core boost (2457.6 MHz) — design note (2026-10-03)

Written-by: Ember (Claude-Code:claude-opus-5-5). Status: **design only, no code.**

Ceiling for this phone: the fuses say speed bin 2, whose qualified maximum is
2361.6 MHz all-core and 2457.6 MHz single-core. Other bins go higher (bin 3:
2457.6 all-core; bin 0: 2496.0) on their own voltage tables; running bin-2
silicon at those points would be unvalidated, so it is out of scope.
Follows `docs/cpu-gpu-audit-2026-10-02.md` §4 item 3.

## What stock does

Speed bin 2 (this phone: "CPU speed bin 2" at boot), `qcom,perfcl-speedbin2-v0`
in LG's `msm8998-v2.dtsi`: **35 LUT rows on 30 CPRh corners.** The top of the
table interleaves 4-core and 1-core rows, each 1-core row on the same virtual
corner as the 4-core row before it:

| row | freq | core count | VC (1-based, DT column) |
|---|---|---|---|
| … | 2208.0 | 4 | 26 |
| … | 2265.6 | **1** | 26 |
| … | 2265.6 | 4 | 27 |
| … | 2342.4 | **1** | 27 |
| … | 2323.2 | 4 | 28 |
| … | 2419.2 | **1** | 28 |
| … | 2342.4 | 4 | 29 |
| … | 2438.4 | **1** | 29 |
| … | 2361.6 | 4 | 30 |
| … | 2457.6 | **1** | 30 |

`apc1_perfcl_vreg`: `qcom,cpr-speed-bin-corners = <32 26 30 31>` → bin 2 has 30
corners. With CC-DCVS enabled (`SPM_CC_DCVS_DISABLE = 0`; mainline already writes
0) the OSM picks the row allowed for the number of active cores, so a 1-core row
only runs while one core is up; otherwise the hardware falls back to the 4-core
row on the same corner. Selection in software is `clk_osm_search_table()`: the
4-core row for a frequency if one exists, else the 1-core row.

## Why mainline can't just add OPPs

`drivers/cpufreq/qcom-cpufreq-osm.c` equates **LUT row index with virtual corner**:

- `qcom_cpufreq_gen_params()`: `entry->volt_lut_val = FIELD_PREP(LUT_VOLT_VC, i)`
  and `FIELD_PREP(LUT_CORE_COUNT, cpu_count)` for every row;
  `*apm_vc = i` / `*acc_vc = i` at the first row over the threshold.
- `qcom_cpufreq_hw_write_lut()`: MEM-ACC crossover pairs are `acc_val = {i-1, i}`
  where `spare_val` changes; `SEQ_MEM_ACC_CROSSOVER_VC` gets `num_entries + 1`.
- Downstream keys all of these on `virtual_corner`
  (`clk_osm_program_mem_acc_regs()` uses `osm_table[i].virtual_corner`).

`drivers/pmdomain/qcom/cpr3.c` `cpr3_corner_init()`: one CPU frequency per CPRh
level via `cpr_get_opp_hz_for_req()`, required ascending; that frequency drives
the open-loop interpolation between fuse corners. With two CPU OPPs requiring
the same level, which one it returns changes the corner voltage.

## Required changes

1. DT: five extra `cpu4_opp_table` OPPs (2265.6/2342.4/2419.2/2438.4/2457.6),
   each `required-opps` = its 4-core partner's CPRh level, marked
   `turbo-mode` and with a core-count property (e.g. `qcom,core-count = <1>`).
   Their `qcom,pll-override` / `qcom,spare-data` come from the speedbin2 rows
   (`0x0401xxxx` freq word, override/spare columns).
2. OSM: carry an explicit `vc` per entry (= CPRh level − 1) and a core count;
   write `LUT_VOLT_VC = vc`, `LUT_CORE_COUNT = core_count`; compute APM/ACC
   crossovers and MEM-ACC pairs on `vc`, not on row index; keep rows sorted the
   stock way (4-core then its 1-core partner).
3. cpufreq table: readback already flags core-count-1 rows as boost
   (`LUT_TURBO_IND`); check `target_index` maps cpufreq index → LUT row
   (not VC) and that boost is off by default (`boost` sysfs).
4. CPR3: when two CPU OPPs share a level, the corner frequency must be the
   **4-core** OPP's. Settled from stock: `apc1_perfcl_vreg`
   `qcom,corner-frequencies` for speed bin 2 ends `… 2208000000 2265600000
   2323200000 2342400000 2361600000` (corners 26–30 = the 4-core rows), and
   `cprh-kbss-regulator.c` interpolates open-loop voltage from those
   `proc_freq` values. The 1-core row runs faster at the 4-core row's voltage.
   `cpr_get_opp_hz_for_req()` must therefore skip core-count-1 OPPs.

## Validation plan

- Readback: `/sys/kernel/debug/qcom_osm/policy4` LUT dump must show 35 rows with
  VC 25..29 shared, core count 1 on the boost rows.
- `cpuinfo_max_freq` 2457600 with boost on; with 4 busy cores the delivered
  frequency (`cpumhz2.c` / perf counters) must stay ≤ 2361.6.
- Single-thread load at 2457.6 for 30 min: no errors, LMh/thermal behaviour,
  CPR closed-loop voltage within ceiling (cpr debugfs).

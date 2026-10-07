# joan CPU + GPU bring-up/optimization audit (host-side, read-only)

Written-by: Fulgor Nymvale (agent-fulgor-zcode)
Agent-harness: ZCode:zai-start-plan/GLM-5.3-Flash
Date: 2026-10-02
Method: audit only — no kernel edits, builds or commits. All paths relative to
`~/vibe-coding-projects/coding/` on nym-skyforge unless noted. Trees read:
`linux-mainline-v30` (branch `joan/cpu-dvfs-cprh`, tip `8d7f34b066e9`;
`joan/bootlog-fixes`, `joan/btfm-fm-audio` for newer work),
`android_kernel_lge_msm8998` (LG joan 4.4), `pmaports-lg-v30-clean`.

---

## 0. State snapshot (what the audit found first)

Two framing corrections to the standing assumptions:

1. **The a540 power-up wedge (K098-K103) is solved**, and has been since
   2026-07-25/26. The K-ledger records the full arc: firmware was never
   loading before K114 (requested at t=1.3 s, rootfs at t=7.4 s —
   K114, `docs/kernel-change-ledger.md`); K115/K116 fixed initramfs
   firmware + the zap `firmware-name` extension; K119 attached the GPU to
   `GPU_GX_GDSC` (mainline `msm8998.dtsi` defect: it pointed at
   `&rpmpd RPMPD_VDDMX`); K120/K121 capped the OPP and the first register
   write survived. Rendering reached `FD540` / GLES 3.1 on freedreno
   (K123-K127), and the last submit-path wedge was
   `GCC_GPU_BIMC_GFX_SRC_CLK` killed by `clk_disable_unused()`
   (K141-K143). Phosh runs on the GPU.
2. **CPU DVFS is already in pmaports.** `pmaports-lg-v30-clean` pins
   `linux-lge-joan` at `_commit=ddfaf16673ec` (2026-10-02, pkgrel 32, on
   `joan/btfm-fm-audio`), which contains the whole
   `joan/cpu-dvfs-cprh` stack (verified `git merge-base --is-ancestor
   8d7f34b066e9 ddfaf16673ec`) with `QCOM_CPR3=y`,
   `ARM_QCOM_CPUFREQ_OSM=y`, `QCOM_SPM=y`, `QCOM_LMH=y`,
   `CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`
   (`device/testing/linux-lge-joan/config-lge-joan.aarch64`). Handoff
   "Next" item 2 of `docs/ember-2026-09-26-cpu-dvfs-handoff.md` is done.

So the real remaining GPU item is **bench-validation of the September GPU
stack** (rail/MEM-ACC/GPMU/VM fixes built but never booted — see section 3),
and the real remaining CPU item is **gold single-core boost** (section 1).

---

## 1. CPU gaps

### 1.1 Frequency tables: all-core is complete; single-core boost is missing

Verified row-by-row against downstream
`android_kernel_lge_msm8998/arch/arm/boot/dts/qcom/msm8998-v2.dtsi`:

| table | mainline | downstream | verdict |
|---|---|---|---|
| silver (`cpu0_opp_table`, `msm8998.dtsi`) | 22 rows, max **1900.8 MHz** (`opp-1900800000`, pll `0x094f004f`) | `qcom,pwrcl-speedbin0-v0` row 22 = 1900.8 @ `0x094f004f` | **identical, incl. 1747.2/1824 rows** |
| gold all-core (`cpu4_opp_table`) | 30 rows, max **2361.6 MHz** (`opp-2361600000`, `cprh_opp30`) | `qcom,perfcl-speedbin2-v0`: 2361.6 @ `0x0404007b`, corner 30 | **identical bin-2 4-core table** |
| gold **1-core** rows | none — `qcom-cpufreq-osm.c:591` writes core-count 4 into every LUT row | bin-2 pairs `0x0401` (1-core) rows: 2265.6@26, 2342.4@27, 2419.2@28, 2438.4@29, **2457.6 MHz @ `0x04010080`, corner 30** | **GAP: gold single-core max is 2361.6, stock reaches 2457.6** |

- The "two differing rows" note in
  `docs/fulgor-2026-09-26-gold-cpr-fix.md` is about the *sibling*
  msm8998-mainline/SoMainline trees (1747.2/1824 vs our 1728/1804.8 in the
  gold table) — not a downstream gap. Our gold 1728/1804.8 rows match
  downstream bin-2 exactly (same pll overrides `0x08480048`/`0x084b004b`).
- **L3/LIM: no separate frequency table to port.** Downstream
  `drivers/clk/msm/clock-osm.c` drives no separate L3 clock; the LIM is
  throttled by the LMh hardware (`drivers/thermal/msm_lmh_dcvs.c`,
  `qcom,lmh_v1` node in downstream `msm8998.dtsi:2637`). Mainline
  equivalent is in place: per-row `qcom,pll-override` +
  `qcom,spare-data` in `msm8998.dtsi` LUTs, LMh nodes
  (`lmh_cluster0/1`, commit `dc8d43903f0d`) and the per-SoC limits
  algorithms (`9a3cc2cfdc8d`).

### 1.2 Speed bins 0/1 not supported (fails safe)

`ef0600e5c71a` restricts the OSM driver to bins 2/3; other bins keep
gold at LK's 300 MHz. Downstream carries perfcl tables for bins 0-3
(`msm8998-v2.dtsi` — bin 0 goes to **2592 MHz 1-core** / 2496 4-core) and
one pwrcl table; per-bin CPRh corners `<32 26 30 31>`; mainline
`cpr3.c` still uses bin-2 data for all parts
(`docs/ember-2026-09-26-bootlog-gpu-rail.md`, "CPU items"). Only a
correctness/coverage gap for other units, not for the bench phone (bin 2).

### 1.3 CPRh fuse corner handling: gold interpolation closed; LG margins open

- Gold open-loop now interpolates from **unclamped** fuse voltages like
  msm-4.4's `cprh_kbss_calculate_open_loop_voltages()` — tip
  `8d7f34b066e9` (doc `fulgor-2026-09-26-gold-cpr-fix.md` records the
  pre-rebase sha `1c3956d058b2`): 10 measured gold corners now match
  Lineage within 4 mV, top corners at 1136 mV. The 28-52 mV stability
  deficit is gone (dvfs15 evidence
  `docs/evidence/2026-09-26-dvfs/dvfs15-verify.txt`).
- v2 fuse corner adjustments landed in `d5195acd3e1f` (silver within 4 mV
  of Lineage debugfs, per the DVFS handoff).
- **Open:** LG per-device CPR margins — `lge_cpr_manager.c` adds signed
  offsets from IMEM `0x146BFE9C`+6/7/8 (bootloader-written) to open-loop/
  floor/ceiling in CPU and GFX CPR. All three read **0** on this phone
  (2026-09-26, pmOS); porting needs a `qcom,msm8998-imem` node + a hook in
  cpr3 and the GFX rail code. Low risk here, nonzero for other V30 units
  (`docs/ember-2026-09-26-bootlog-gpu-rail.md`).

### 1.4 LMh: voltage request works; the interrupt is unwired

- REL algorithm enable is in (`9a3cc2cfdc8d`); measured LMh request
  1120/1136 mV with REL on, matching hardware behaviour proven with the
  `lmhprof.c` toggle (`docs/ember-2026-09-26-cpu-dvfs-handoff.md`).
- **Open (handoff "Next" 3):** no `dcvsh` interrupt handler exists in
  `drivers/cpufreq/qcom-cpufreq-osm.c` (verified: no irq/interrupt
  references in the file). Hardware current/thermal limit votes reach
  cpufreq only through the OSM's own LLM FSM; qcom-cpufreq-hw on sdm845
  additionally relays the LMh interrupt so the scheduler learns of the
  cap. Until wired, an LMh event throttles in hardware but is invisible
  to EAS/sugov.

### 1.5 Not-CPU but adjacent (from the same handoff "Next" list)

UFS ~4x slower than stock (second limiter not found), no PMU node (perf
counters unavailable — `cpumhz2` is the measuring tool), EAS energy model
absent (below).

---

## 2. Thermal / scheduling

### 2.1 Thermal verdict: sane; branch fixes not yet bench-booted

Baselines compared: mainline `msm8998.dtsi` thermal-zones (8 CPU zones at
`75000`/`hyst 2000` passive + `110000` critical, gpu zones) vs downstream
(`msm_thermal` in downstream `msm8998.dtsi:2645-2685`: reset 115 C,
core-limit 70 C, hotplug 105 C; LG stock userspace policy in
`docs/evidence/2026-09-26-thermal/lge-joan-thermal-engine-8998.conf`).

- **Junction (fixed on the dev branches):** msm8998.dtsi's generic 75 C
  passive trips throttled ~10 C earlier than stock. The pinned branch
  (`joan/btfm-fm-audio` = pmaports pin) overrides `cpu0-7_alert0` and
  `gpu1/2_alert1` to **85 C** (CPU hyst 5 C, GPU hyst 20 C), matching LG's
  SS-CPUS-CLUSTER*/SS-GPU-* steps; 110 C critical trips kept
  (`msm8998-lge-joan.dts:2110+`). Downstream msm_thermal's 115 C reset is
  covered by the 110 C critical + 115 C reset-class behaviour.
- **LMh thresholds:** joan dts overrides the dtsi's Qualcomm
  65/94.5/95 C to LG's **84.5/85 C** (`CONFIG_LGE_PM` behaviour),
  `msm8998-lge-joan.dts:493-503`. Correct vs stock.
- **Skin (implemented, untested):** LG's virtual skin sensor
  (0.37*xo_therm + 0.48*bd_therm_2 + 3.83 C) exists as a
  `weighted-adc-thermal` zone `skin_vts` with LG's full skin cap ladder
  (gold 1958.4/1728/1056/729.6 MHz; GPU 670/515/414/342 MHz),
  `msm8998-lge-joan.dts:1934-2030` on the pinned branch. `skin_ap` has no
  mainline counterpart; vts is used for SKIN-MID-FLOOR.
- **No silent overcapping and no missing zones found.** The only
  downstream policy piece with no mainline analogue yet is charger
  skin-based current limiting (skin_pmic 40/42/45 C -> 1.5/0.8/0.6 A),
  which needs `CHARGE_CONTROL_LIMIT` in the charger drivers (support
  matrix row "Wired charging").
- **Caveat:** the 85 C/skin changes ride the `joan/bootlog-fixes` lineage
  that has **not been bench-booted since 2026-09-26** (support matrix last
  full pass 2026-09-26); the r27 thermal evidence
  (`docs/evidence/2026-09-26-r27/`) predates them.

### 2.2 Scheduler: honest summary

- schedutil is the default both in the pmaports config
  (`CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`) and via pmOS TuneD
  `balanced`; the OSM driver sets `fast_switch_possible` and a
  `.fast_switch` op (`qcom-cpufreq-osm.c:1021,1556`), so sugov rides the
  OSM's hardware DCVS. Rate limiting is effectively in the OSM FSM — the
  driver programs the LLM hysteresis registers
  (`HYSTERESIS_LLM_NS = 65535` ns, `qcom-cpufreq-osm.c:62,1269-1279`).
- **No kernel-side sugov tunables, latency or rate_limit overrides exist
  anywhere in the port** — verified by grep. That is the correct mainline
  posture; the dropped `joan-input-boost` service (pmaports
  `b007cff07c`) was the only attempt and it never ran.
- Genuinely missing (kernel-side): no `dynamic-power-coefficient` /
  energy model in any joan/msm8998 DT (grep-verified), so there is no
  EAS. The handoff lists "EAS energy model, PMU node" as still open. The
  PMU node is the prerequisite for measuring anything (perf).
- Everything else (up/down latency feel) is userspace: TuneD profile,
  phosh, uclamp if touch latency ever measures badly. Nothing to do
  in-kernel this pass.

---

## 3. GPU wedge status + ranked next steps

### 3.1 The arc, precisely (ledger `docs/kernel-change-ledger.md`)

| stage | entries | what was found |
|---|---|---|
| initial power-up wedge | K098-K101 (2026-07-20/21) | gpucc + both SMMUs healed, zap authenticated; first register write wedged the SoC; GDSC-always-on also wedged; interconnect ruled out (no 8998 provider then) |
| K103 discriminator | 2026-07-21 | `input-enable` deletion restored boot (touch, not GPU — display-arc entry, frequently conflated with the GPU arc) |
| power-up actually fixed | K114-K121 (2026-07-25/26) | three necessary changes, none sufficient alone: firmware in the **initramfs** + zap name `qcom/a540_zap.mdt` (K115/K116); `power-domains = <&gpucc GPU_GX_GDSC>` replacing `<&rpmpd RPMPD_VDDMX>` (K119, mainline msm8998.dtsi defect); OPP capped so resume-time frequency matches the rail (K120/K121) |
| render wedge | K123-K127 | staged hw_init probes exonerated zap/secure-mode entirely; `MSM_PARAM_TIMESTAMP` reproducer showed death **inside** the first GX collapse-then-restore cycle |
| submit wedge | K128-K143 (2026-07-27) | after ruling out UBWC, SMMU, mapping age, preemption, ucode: root cause `GCC_GPU_BIMC_GFX_SRC_CLK` killed by `clk_disable_unused()` — now claimed as `mem_src` on the GPU node; GPU rendering + Phosh on freedreno proven |
| GX collapse/restore | Aug 10-14 + 26-27 | see below — **fixed, device-verified** |
| VM/idle defects | Aug 8-9 | GPU VM based at 2^48 (`GENMASK_ULL(48,0)` kept bit 48) caused the Firefox/YouTube faults+hangcheck+phoc SEGV on r27: `622e72defc46` + `7602f365a81c`; devfreq wake-at-top-OPP `23cf6b32fb18` |

**GX collapse/restore — the "instrumented multi-session" arc.** The
runtime-PM pin (`msm.k127_no_suspend`) made rendering usable but left
suspend broken. August sessions (`docs/ember-2026-08-10-unpin-result-was-confounded.md`,
branches `joan/a540-*`, 27 of them) then produced, on the current branch:

- `9f3d89120106` + `ea1cdd7e234f`: gate A540 suspend on the GPMU having
  collapsed SP/TP+RBCCU (downstream's idle criterion; cutting the outer
  rail with inner domains on wedges the NoC path), with a skip when the
  GPU was never initialised (`a5xx_gpu.c`, `a5xx_pm_suspend()`).
- `3922fbb8794f`: SMMU moved off GX onto the CX-class domain (sdm845-style)
  + `qcom,adreno-smmu` claimed — stops runtime PM power-cycling the SMMU.
- `37f8146b9cb0` + `76d180923dc2`: GX GDSC owns VDD_GFX (`vdd-gfx`
  supply); joan's `regulator-always-on` hack removed.
- `8680eb256703`: don't submit to a GPU that failed to resume (posted
  writes turned resume failure into an async SError machine check).
- **`996720c982c1` (2026-08-27, porthole-dev 0176): the fix.** Short
  collapses (80 us-1.37 ms measured vs 275 ms median) do not discharge the
  GX rail; the GPU keeps state across "collapse" and `a5xx_hw_init()`
  writes `CP_RB_BASE` into a still-live CP -> VBIF traffic -> external
  abort. Fix: software reset (the `a5xx_recover()` pulse) before hw_init.
  **Validated: 200 consecutive KEY_POWER wake cycles, 197 with the GPU
  confirmed collapsed, zero resets — vs 2-20 cycles to death without.**
  The debug gates (`k127_no_suspend`, `k130_*`, `k131_*`, `k142_*`) are
  gone from the current tree (grep-verified).

### 3.2 What is still open on GPU (as of 2026-10-02)

- The September stack — per-part GFX rail (`a540_gfx_rail.c` on
  `joan/bootlog-fixes`: fused open-loop ceilings + MEM-ACC via
  `config_clks`), the VM fixes, GPMU limiter (porthole 0251), Venus — is
  **build-verified but never booted**. r27 (2026-09-26, pre-fix) hung
  under GL load from the 2^48 VM bug and ran the GPU off the DT fallback
  ceilings (`docs/ember-2026-09-26-bootlog-gpu-rail.md`; evidence
  `docs/evidence/2026-09-26-gpu/gfx-cpr-fuses.txt`). Nothing after
  r31 (FM-focused) re-tests GPU.
- `opp-microvolt` now carries the stock-swept curve (628-936 mV at
  257-710 MHz, `msm8998-lge-joan.dts:1294-1355`), which also fixes the
  K124 finding that `a540_lm_setup()` programmed the GPMU AGC with 0 mV.
- `msm8998.dtsi` GPU `power-domains` fix and the SMMU-to-CX move are
  upstreamable; `mem_src` needs the 7-clock `gpu.yaml` review before the
  DTS patch goes upstream (A180).

### 3.3 Upstream a540 (sdm845) power-up vs msm8998, and the ranked residual suspects

sdm845 reference: `drivers/clk/qcom/gpucc-sdm845.c` — GX GDSC is
`PWRSTS_OFF_ON` (no RETENTION), flags `CLAMP_IO | AON_RESET |
POLL_CFG_GDSCR`, **no SW_RESET**, and `.power_on = gdsc_gx_do_nothing_enable`
(the **GMU** owns GX; the kernel never switches it). msm8998
(`gpucc-msm8998.c:257-271`): `PWRSTS_OFF_ON | PWRSTS_RET`, flags
`CLAMP_IO | SW_RESET | AON_RESET | NO_RET_PERIPH`, `.resets = {GPU_GX_BCR}`
— and `gdsc_enable()` asserts+deasserts the BCR on **every** power-on
(`drivers/clk/qcom/gdsc.c:280-296`), so every restore is a full
hardware-reset restore the driver must re-init through, with a GPMU (not
GMU) managing SP/TP/RBCCU, and MEM-ACC in TCSR that downstream toggles
around every rail transition.

Ranked remaining suspects for any *residual* a540 power-path failure on
msm8998:

1. **GX GDSC sequencing (short collapse / reset-on-enable) — highest
   evidence.** The measured failure mode and fix are exactly here:
   80 us collapses kept a live CP across GDSC off/on
   (`996720c982c1`); K123-K127 localised the wedge inside the
   collapse-restore cycle. The fix is validated on a Pixel 2 XL but the
   joan bench has not repeated it with the September stack. Next
   instrument if it recurs: the same RBBM_STATUS-per-stage sampling in
   `a5xx_hw_init()` (443/445 idle vs 2/445 mid-reset in the fix commit).
   Also unique to 8998: `PWRSTS_RET` retention is a state sdm845 never
   enters — if genpd parks GX in retention rather than off, NO_RET_PERIPH
   paths differ; worth one `genpd` state check after a collapse.
2. **MEM-ACC / VDD_GFX rail ordering across collapse — freshest unknown.**
   MEM-ACC (`TCSR 0x1fcf004` bit 0) read **0** with the GPU at 257 MHz
   before the fix; downstream sets the low-voltage value *before* the rail
   drops and the high value *after* it rises. `a540_gfx_rail.c` handles
   OPP transitions via `config_clks`, but the GDSC-off -> regulator-off ->
   on path (now that GX GDSC owns the rail, `37f8146b9cb0`) has never been
   observed on hardware. Cheap check: read MEM-ACC and pm8005_s1 around a
   forced suspend/resume on the bench boot.
3. **VBIF quiesce + GPMU gate stranding — lowest, but recorded.** Upstream
   `a5xx_pm_suspend()` skips the VBIF block-sw-reset on a540 ("the others
   will tend to lock up", `a5xx_gpu.c` ~line 1453), so FIFO state rides
   into collapse; flagged as next candidate in
   `ember-2026-08-10-unpin-result-was-confounded.md` and ledger K123-K127
   ("missing pre-collapse VBIF quiesce on the a540 path"). Mitigated
   today by the GPMU-collapse gate (`9f3d89120106`), whose failure mode is
   a benign runtime-PM strand, not a wedge. Zap is exonerated
   (K123-K127 staged probes: hw_init passes all stages, 28 ms zap load).

---

## 4. Recommended next session order

1. **Bench-boot the current pmaports kernel (ddfaf16673ec, pkgrel 32).**
   One boot validates the entire September stack: GFX open-loop mV line at
   probe, MEM-ACC readback at 257 vs 710 MHz, GL load without the VM
   faults (Firefox/YouTube), GPMU limiter levels, Venus, plus schedutil/
   DVFS on the default install. This is ember "Next" item 2 from
   2026-09-26, still unconsumed. Use the standing RAM-boot loop
   (`tools/bench/joan-testboot.sh`); nothing flashes.
2. **GPU power-closure retest in the same boot:** confirm runtime PM
   collapse/restore on this stack (`runtime_suspended_time` climbing, 200
   wake-cycle style test), and drop `msm.k127_no_suspend` remnants if any
   config still carries them.
3. **Gold single-core boost rows** (biggest CPU gap): add the bin-2 1-core
   LUT rows (2265.6@26 ... 2457.6@30, `0x0401` rows in downstream
   `msm8998-v2.dtsi`) and the OSM core-count DCVS FSM so the driver stops
   writing core-count 4 into every row (`qcom-cpufreq-osm.c:591`).
   Handoff "Next" item 4.
4. **LMh dcvsh IRQ -> cpufreq** (handoff "Next" item 3): mirror
   qcom-cpufreq-hw's interrupt relay so hardware limits reach the
   scheduler.
5. **Upstream hygiene sweep:** squash the WIP OSM commits, run
   `dt_binding_check` (dtschema not installed on skyforge — handoff Next
   5), cherry-pick verified pieces to `joan/latest-clean-test`/`master`;
   prepare the `msm8998.dtsi` GPU power-domains + SMMU-CX patches and the
   `mem_src`/`gpu.yaml` binding review for upstream.
6. **LG per-device CPR margins** (IMEM node + cpr3/GFX hooks) before any
   distribution to other units — they are 0 on this phone but unbounded on
   others.

Cautions honoured: read-only audit, nothing built, nothing booted, no
reboot of anything (sysrq-b pitfall stands), only this file written.

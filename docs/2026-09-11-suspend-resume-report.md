# Report: suspend/resume bring-up map for joan (2026-09-11)

Investigation: Fulgor (ZCode:zai-coding-plan/GLM-5.3), Explore agent, 2026-09-11.
STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port.

## Headline

The suspend core is fully enabled and the msm8998 DT is PSCI-complete. The
single decisive unknown is whether LG's TrustZone (behind ABL) implements
PSCI `SYSTEM_SUSPEND` — mainline registers its suspend handler only if the
firmware advertises it (psci.c:587-593), and **downstream never uses
SYSTEM_SUSPEND at all** (grep empty across downstream arch/arm64): stock
suspends via a platform_suspend_ops through lpm-levels + MPM + RPM sleep
votes. If `echo mem` fails before any device callback, TZ lacks it and the
fallback design below is the path.

## Present already (verified)

- Config: SUSPEND/PM_SLEEP/ARCH_SUSPEND_POSSIBLE, CPU_IDLE + ARM_PSCI_CPUIDLE
  (+DOMAIN), CPU_PM, ARM_PSCI_FW, QCOM_SMD_RPM=y, INTERCONNECT_QCOM_MSM8998=y,
  QCOM_SPM=m (carries msm8998 gold/silver saw2-v4.1 L2 compatibles),
  QCOM_MPM=y (driver exists, binds "qcom,mpm"), QCOM_STATS=m, DEBUG_FS=y.
- DT: all 8 CPUs psci enable-method; idle-states entry-method psci with
  little/big retention (0x2) and power-collapse (0x40000003,
  local-timer-stop); psci-1.0 smc; scm-msm8998; RPM GLINK + rpm_requests.
- GPU runtime-suspend fixes already merged on joan/wake-path-v1
  (ea1cdd7e2 collapse-gate, 88dbc4e26 OPP vote, 521c2fe50 SMMU resident,
  VDD_GFX/GX GDSC set) — the Card-94 class blockers.

## Gaps

- Config-only: `PM_DEBUG` off (no /sys/power/pm_test!), `DYNAMIC_DEBUG` off,
  `QCOM_RPM_MASTER_STATS` off (and its DT nodes don't exist in msm8998.dtsi).
- DT: **no MPM node** (stock has qcom,mpm-v2 @7781b8 + sleep-counter @10a3000,
  IRQ 171, num-mpm-irqs 0x60, full gic-map/gpio-map — dtb0.dts:6075-6107);
  no subsystem-sleep-stats nodes; `wakeup-source` missing on pwrkey/resin
  (and touch) — joan dts marks only volume-up.
- Driver: q6voice.c has no PM hooks (benign unless a voice session is open).

## Stock mechanism (RE'd from downstream + DTB)

Idle AND suspend both go through PSCI CPU_SUSPEND (`qcom,use-psci` in stock
lpm-levels; arm_cpuidle_suspend per level). Ladder (dtb0.dts:5795-5920):
CPU wfi/ret/pc, L2 wfi/dynret/ret/pc, system-wfi, **system-pc** (psci-mode 3,
is-reset, notify-rpm). Suspend ops = lpm_suspend_ops (prepare_late →
msm_mpm_suspend_prepare; enter → psci_enter_sleep deepest level; wake).
RPM sleep-set path: rpm-smd.c sleep notifier ↔ mainline's
QCOM_SMD_RPM_SLEEP_STATE plumbing exists. MPM = wakeup routing during power
collapse; mainline irq-qcom-mpm.c needs "qcom,mpm" with qcom,mpm-pin-count/
pin-map (stock gic-map/gpio-map transcribable; property format differs).
SPM-v2 nodes configure only L2 rails (gold/silver saw2 — mainline spm.c
already matches).

Siblings: msm8996 same PSCI-CPU_SUSPEND idle philosophy; sdm845 uses PSCI
OSPM/domain idle and SYSTEM_SUSPEND for mem (OnePlus 6 suspend largely works
under pmOS). F(x)tec Pro1 (msm8998, same dtsi base): no suspend row at all —
joan would be first.

## Blockers ranked

1. A540 GPU + Adreno SMMU — **mostly fixed already on this branch**.
2. PSCI SYSTEM_SUSPEND in TZ — unknown, must probe first (decides "no work"
   vs "port suspend_ops").
3. USB dwc3-qcom + gadget (signaller aside, dwc3 has suspend ops).
4. WCN3990 ath10k SNOC (the known rekey hang suggests firmware cooperation
   issues — typical resume-hang source; consider suspend-testing with Wi-Fi
   disabled first).
5. IPA/modem data during suspend.
6. Audio slim NGD/WCD9340/ADSP — only while sessions are open.
7. stmfts touch — suspend fine; can't wake without DT change.
8. Display/DPU — TE-gate landed; medium.

## Ordered plan

M0 (today, no changes): read cpuidle state usage/time — confirms whether the
0x40000003 power-collapse state is being hit; `dmesg | grep psci`.

M1 (config-only rebuild): `PM_DEBUG=y` + `DYNAMIC_DEBUG=y`; then the pm_test
ladder (`pm_test=devices` first — exercises all driver callbacks without
dropping rails, and the known fatal bug was GPU *resume*), no_console_suspend
cmdline, wakeup_sources dump, wake with power key each round.

M2: `pm_test=platform`, then real `mem`. If the suspend core never engages
(no device callbacks at all) → TZ lacks SYSTEM_SUSPEND → fix A.

Fixes in order:
- **A** (if needed): minimal downstream-style suspend_ops entering PSCI
  CPU_SUSPEND with the stock composite system state (candidate param
  0x40000343 — system 3 + L2 4 + CPU 3, bit30 power-down; validate against
  the lpm-levels psci-mode shift/mask fields at dtb0.dts:5795-5920) + MPM
  prepare/wake + RPM notify. New small driver; all quantities already RE'd.
- **B**: cherry-pick the staged GPU work NOT yet on wake-path-v1:
  "collapse A540 domains after draining VBIF" (6fd85b73/bfd86340) and
  "keep MSM8998 GPU_CX on at runtime" (9740d5e6/dbcd9f90).
- **C**: MPM node port (DT-only + property-format glue; driver already
  upstream, config =y).
- **D**: wakeup-source on pwrkey/resin (+touch later) — DT-only.
- **E**: per-driver debug from milestone-1 evidence (USB, ath10k — or test
  with Wi-Fi disabled first — IPA, audio-when-open).
- **F** (optional): sleep-stats DT nodes for QCOM_STATS visibility.

Verified vs inferred: all config/DT inventories and driver/DTB citations are
direct reads; SYSTEM_SUSPEND support, the 0x40000343 composite param, the MPM
property-format mapping, and community wiki claims are inferred/external and
flagged.

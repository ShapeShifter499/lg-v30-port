# RE map: WCD934x interrupt path — stock vs mainline (2026-09-11)

Assisted-by: ZCode:zai-coding-plan/GLM-5.3
Sources: stock DTB decompiles (~/.hermes/workspace/reviews/joan-stock-dtbs-2026-09-07/),
downstream CAF+LG kernel (android_kernel_lge_msm8998), mainline pin
(joan/wake-path-v1 = 648c5181). Follows the lead in
HANDOFF-2026-09-11-next-session.md (wcd934x_irq fired exactly once at probe,
SLIMbus + soundwire children at zero).

## What matches (rules things OUT)

* **Physical line**: stock `qcom,wcd9xxx-irq` node has
  `qcom,gpio-connect = <&tlmm 54 0>` — the same msmgpio 54 mainline uses
  (`interrupts-extended = <&tlmm 54 IRQ_TYPE_LEVEL_HIGH>` in our DTS).
* **Pin config**: stock `wcd_intr_default` = gpio54, function gpio,
  drive-strength 2, bias-pull-down (+ input-enable); ours identical minus
  the explicit input-enable (default for a gpio mux) — parity.
* **Polarity**: downstream requests the GPIO line with
  `IRQF_TRIGGER_HIGH | IRQF_ONESHOT` (wcd9xxx-irq.c:540, slimbus-codec
  path) — the SAME level-high as ours. Polarity is NOT the defect.
  (Its separate `wcd9xxx_request_irq()` helper uses RISING for the
  virtual per-source irqs — internal domain, not the SoC line.)

## What differs (the live hypotheses)

1. **Codec-side INTR bank init.** Before requesting the line, downstream
   explicitly programs the codec's interrupt LEVEL and MASK registers
   (wcd9xxx-irq.c ~line 525: `regmap_write(core_regmap,
   intr_reg[WCD9XXX_INTR_LEVEL_BASE] + i, irq_level[i])` and
   `INTR_MASK_BASE + i, irq_masks_cur[i]`). Mainline's
   `wcd934x_regmap_irq_chip` (drivers/mfd/wcd934x.c:62) uses the
   PIN1 bank only: STATUS0/MASK0/CLEAR0, 4 regs, plus
   `wcd934x_config_regs` for the drive configuration. **Next dive: dump
   the actual register addresses and values — downstream's
   `intr_reg[INTR_LEVEL_BASE]`/`irq_level[]` vs mainline
   `wcd934x_config_regs` — and test whether the codec's INTR1 drive
   mode (push-pull vs open-drain vs level-latch) is left in a reset
   state under mainline that stops driving the line after the first
   assertion.** The one-fire-then-silence signature is consistent with
   a level/latch mode mismatch: first fire acks, then the line never
   re-asserts because the codec's output stage is mis-programmed.
2. **Ack path.** Downstream's `wcd9xxx_irq_thread` reads/clears status
   and dispatches children manually over the core regmap. Mainline
   delegates to regmap_irq with the PIN1 CLEAR0 ack. If the codec's
   status mirrors into PIN1 only in a particular drive/mux mode, the
   mainline ack may be clearing a bank that no longer latches.
3. **MICBIAS2 drop at ~2 s into capture** (`0x54 -> 0x14`): suspect the
   codec-side MBHC/bias housekeeping reacting to the dead jack (e.g. a
   timed bias removal with no jack reported), i.e. LIKELY DOWNSTREAM of
   the same root cause, not independent. Re-test after the IRQ fix.

## Register name cross-reference (to resolve first next session)

* mainline: `WCD934X_INTR_PIN1_STATUS0/MASK0/CLEAR0`,
  `wcd934x_config_regs[]` — drivers/mfd/wcd934x.c.
* downstream: `WCD9XXX_INTR_LEVEL_BASE`, `WCD9XXX_INTR_MASK_BASE`,
  `irq_level[]`, `irq_masks_cur[]` — drivers/mfd/wcd9xxx-irq.c +
  wcd9xxx-core-resource headers; per-codec tables in
  wcd934x-regmap.c/tavil headers.
* WCD934x datasheet terms: INTR1/INTR2 pins, "level" vs "pulse" mode,
  PULL drive config — the codec resets INTR1 as level-driven; check
  whether mainline's config_regs write the same mode downstream's
  irq_level[] implies.

## Bench-side facts to reuse (from HANDOFF-2026-09-11)

* Module tree is tmpfs; nest `~/joan-test-assets/joan-modules.tgz`
  carries BOTH patched modules (es9218p Headphone Mode; wcd-mbhc with
  the FAILED gnd_det_en experiment — rebuild clean from
  joan/latest-clean-test and repack if wanted; modules ship as .ko.zst
  in the tarball, tar contains the full /lib/modules tree).
* Boot script assumes LOS start; sysrq-b out of pmOS first. Session
  tools as user, root only for regmap/debugfs/dmesg. Jack controls are
  iface=CARD (query by numid).

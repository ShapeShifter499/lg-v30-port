# ANSWERED: icc-rpm QoS — the missing mechanism was addressing, not clocks

Status: **RESOLVED 2026-08-07 — do not send the draft below as written.**
Its central premise (per-master QoS clocks as the missing mechanism)
is disproven for our case: the answer was **addressing**. Kept in the
repo as the record of a wrong (but reasonable) turn and for its
transferable lessons.

## The actual root cause

The BIMC M_BKE register block does not start at the beginning of the
BIMC window — it sits **0x8000 in**. Downstream encodes that
displacement in driver macros rather than device tree:

    /* drivers/soc/qcom/msm_bus/msm_bus_bimc_adhoc.c */
    #define M_REG_BASE(b)     ((b) + 0x00008000)

Mainline icc-rpm expresses the same thing as
`qcom_icc_desc::qos_offset`. With it unset, every QoS write landed
0x8000 low, inside BIMC's own configuration space — which is why a
single bit clear in bypass mode wedged the SoC before console, three
times. Fix is one line: `.qos_offset = 0x8000` on `msm8998_bimc`.

After the fix: QoS programs **16 of 17** programmable masters (35
total; real prior count was 13 — the `ap_owned` probe gate skips the
rest); display 32.45 -> 62.49 -> **70.44 mdss/s**; device-verified RAM
boot. The one holdout is `mas_ipa` (a2noc's first-ever QoS write; its
clock is `RPM_SMD_IPA_CLK` from rpmcc, already in mainline).

## Transferable lessons (worth keeping)

1. **A missing field can mean "zero" or "expressed elsewhere", and
   those are not distinguishable from the field alone.** `fab_bimc`
   declares no `qcom,base-offset` because the offset lives in the
   driver's macros; `msm8996` needs no `.qos_offset` because it folds
   the displacement into its DT reg base (`0x408000`, not
   `0x400000`). Three platforms agreeing (msm8916/8953/8976) should
   outweigh one that only looks like a counterexample — check whether
   a "counterexample" encodes the same value somewhere else first.
2. **A negative result from a single-form grep is not a negative.**
   `qcom,prio-lvl`/`qcom,prio-rd` is only one spelling the msm-bus
   binding accepts; downstream uses `qcom,prio0`/`qcom,prio1`. Search
   every spelling the binding accepts before concluding it declares
   nothing.

## Original draft (kept as record)

The following is Ember's 2026-08-07 draft question, preserved verbatim
for provenance. **Do not send it as written** — the premise is now
answered; if anything goes to linux-arm-msm, it should be the merged
QoS series itself plus this resolution, not the question.

---

# Draft: linux-arm-msm question — does icc-rpm QoS need per-master clocks?

Status: DRAFT, not sent. Written 2026-08-07 to close out task #10 without
spending more device boots. Lance to review, adapt and send.

Suggested recipients: `linux-arm-msm@vger.kernel.org`, cc
`linux-pm@vger.kernel.org`. Worth cc'ing the icc-rpm maintainers and
whoever last touched `qcom_icc_set_noc_qos()` — check
`scripts/get_maintainer.pl` against `drivers/interconnect/qcom/icc-rpm.c`
before sending.

Subject suggestion:

    interconnect: qcom: icc-rpm: does NoC QoS programming require
    per-master clocks on MSM8998?

---

Hi,

I'm writing an out-of-tree interconnect provider for MSM8998 (LG V30
mainline port), modelled on `msm8996.c` since it's the same icc-rpm
generation. Bandwidth voting works well. QoS programming reliably hangs
the SoC and I'd like a sanity check on the mechanism before I go further.

## What works

With `ap_owned` corrected from the downstream topology, RPM bandwidth
voting behaves exactly as expected: the `-ENXIO` storm disappears,
`interconnect_summary` shows real votes, and a display consumer scales
correctly with no regression. That part I'm confident in.

## What hangs

As soon as I set a real `qos_mode` on the AP-owned nodes — so
`qcom_icc_probe()`'s `ap_owned && qos_mode != NOC_QOS_MODE_INVALID` gate
opens and `qcom_icc_qos_set()` runs — the SoC hangs during probe. No
console output, no panic (`panic=` never fires), USB never enumerates.
Recovery needs a forced power-off. Three attempts, three hangs.

## What I've ruled out

- **NULL regmap.** First attempt had no `.regmap_cfg`, so
  `regmap_update_bits(qp->regmap, ...)` dereferenced NULL. Real bug, my
  own, fixed.
- **Wrong register windows.** Two of my four provider `reg` entries were
  wrong. I verified the correct ones by decoding the live device tree of
  the vendor kernel running on the same hardware
  (`/sys/firmware/devicetree/base/soc/ad-hoc-bus/reg`, eight base/size
  pairs against `reg-names`). Fixed, and confirmed independently by the
  vendor platform device binding as `1620000.ad-hoc-bus`.
- **Out-of-range access.** I bounds-checked every QoS register address
  against its provider's window before booting. The highest is
  `qos_offset 0x4000 + 0xc + 7*0x1000 = 0xb00c` inside a `0x60000`
  window. All thirteen AP-owned nodes with a port fit comfortably.
- **The registers being inaccessible.** The vendor kernel programs NoC
  QoS on this exact hardware — its `msm_bus_dev_init_qos()` skips only 2
  of ~116 nodes and logs nothing on success — so they're writable and not
  TZ-owned.

So the writes are well-formed, in range, and to registers the vendor
kernel writes successfully. They still hang the bus.

## The thing I think I'm missing

The vendor `msm-bus` driver declares per-master pseudo-regulators on each
bus node — `clk-mdss-ahb-no-rate`, `clk-mdss-axi-no-rate`,
`clk-camss-ahb-no-rate` and friends — and enables them before touching
that master's QoS registers. They're visible in its boot log, some
deferring with `-517`, some falling back to dummy regulators.

Mainline `icc-rpm` has no equivalent: `qcom_icc_probe()` programs QoS
with only the fabric's own bus clock running.

On MSM8998 that looks like it matters, because 7 of the 13 masters I'd be
programming sit behind MMSS clock domains that are off at probe time:

| master | fabric | domain |
|---|---|---|
| `mas_mdp_p0`, `mas_mdp_p1`, `mas_rotator` | mnoc | MDSS |
| `mas_vfe`, `mas_cpp`, `mas_jpeg` | mnoc | CAMSS |
| `mas_venus` | mnoc | VENUS |
| `mas_oxili` | bimc | GPU |
| `mas_gnoc_bimc`, `mas_hmss` | bimc/snoc | CPU (always on) |

Writing a QoS register for an unclocked master hanging the AXI bus would
fit the symptom exactly.

## Questions

1. Is per-master clock enabling a real prerequisite for NoC QoS on
   platforms that gate their MMSS masters, or am I chasing the wrong
   thing?

2. If it is: how do `msm8996`, `msm8916` and `msm8953` avoid it? Are
   their masters ungated at probe, or is something else keeping those
   domains alive? MSM8996 in particular shares much of this topology, so
   if it genuinely differs I'd like to understand why.

3. If a platform *does* need it, is there an accepted way to express that
   in `icc-rpm`? I can't see a mechanism, and adding one touches every
   platform using the driver, so I'd rather ask than invent something.

4. Failing all that — is "bandwidth voting only, QoS left at
   `NOC_QOS_MODE_INVALID`" a legitimate long-term state for a platform,
   or does it store up problems I'm not seeing?

Happy to share the driver, the full downstream topology extraction, or
device logs if useful. Everything above is measured on hardware rather
than inferred, and I've tried to say which is which.

Thanks,
Lance

---

## Notes for whoever sends this (not part of the message)

- **Question 4 is the one that actually unblocks us.** If bandwidth-only
  is acceptable, task #10 closes and nothing further is needed — the
  merged work already delivers the value.
- Be ready for "you're out of tree, post the driver first". A minimal RFC
  series might get better engagement than a bare question. The driver is
  on `joan/latest-clean-test`; the QoS attempt is preserved on
  `joan/icc-qos-v1` as the record of what fails.
- **Do not overstate the clock theory.** It is the leading hypothesis and
  it is unproven. An earlier version of my own notes asserted it as the
  root cause and that turned out to be premature — the wrong register
  bases were a real and simpler explanation for at least one of the three
  hangs, and correcting them did not fix the others. The message above is
  deliberately phrased as "the thing I think I'm missing", not a
  conclusion. Keep it that way.

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-07

---

Resolution header and transferable lessons:

Updated-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-flash
Date: 2026-08-07
Update-scope: Premise answered (addressing, not clocks); draft marked
do-not-send; draft body preserved verbatim as record.

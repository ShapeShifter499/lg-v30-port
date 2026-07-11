# LG V30 public upstreaming / PR readiness plan

Purpose: keep the LG V30 (`joan`) work shaped so it can become a clean public
branch, GitHub PR, postmarketOS package input, or upstream Linux patch series
when the device finally boots far enough.

This is not a replacement for `docs/kernel-change-ledger.md`. The ledger tracks
all changes and experiments. `docs/project-history-and-attribution.md` indexes
who worked on what and when. This file defines what makes a change public-ready.

## Branch model

- `linux-mainline-v30:lge-joan-bringup` is the clean branch concept: only keep
  commits that could plausibly be shown publicly after polishing.
- `linux-mainline-v30:joan/bringup-debug` is disposable/debug state: timing
  oracles, breadcrumbs, and one-off experiments may live here while debugging,
  but they must be either dropped or rewritten before public push/PR.
- `lg-v30-port` is the harness and evidence repo: docs, test-image tooling,
  saved rejected patches, handoffs, and reproducibility notes live here.

If a future agent creates new branches, keep this distinction:

- `joan/<feature>` = clean topic branch intended to be rebased into the public
  series.
- `joan/debug/<question>` = throwaway experiment answering one specific question.

## Public-ready definition of done

A kernel change is not public-ready until all of these are true:

1. It is represented by a clean kernel commit, not only by an `out/*.patch`
   experiment.
2. The commit message explains:
   - what hardware behavior it addresses;
   - what downstream source or measured device evidence supports it;
   - why the chosen mainline representation is appropriate;
   - what was intentionally left out.
3. The commit has the required trailers:
   - `Signed-off-by: Lance <Gero3977@gmail.com>`
   - `Assisted-by: <agent-harness>:<model actually running>`
   - never `Co-Authored-By` for AI assistance.
4. `docs/kernel-change-ledger.md` has an entry linking the commit to its evidence
   and classifying it as `upstream-candidate`, `bringup-local`, `debug-only`,
   `rejected`, or `unknown`.
5. Debug-only code is absent from the public branch unless the branch is clearly
   labeled as a debug branch.
6. Verification has been run and recorded, or the blocker is explicitly recorded.
7. No private credentials, local-only secret paths, or non-reproducible agent
   internals are required to understand or build the change.

## Evidence expected for each public commit

Use the strongest available evidence. Good evidence includes:

- downstream file path and line/function names;
- board-specific dmesg excerpts from LineageOS/downstream;
- host-side boot timing/classifier output;
- hardware facts: variant `US998`, codename `joan`, board/hw revision if known;
- successful build output summary;
- successful `fastboot boot` result or clear reason it cannot yet pass;
- image SHA-256 for tethered test images when relevant.

Rejected experiments still matter. Keep them in the ledger so future helpers do
not rediscover the same dead ends.

## Minimum local verification before public push/PR

For DTS-only/kernel config-adjacent commits:

```bash
cd ~/vibe-coding-projects/coding/linux-mainline-v30
git diff --check
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 Image.gz dtbs
```

For boot-affecting changes, also package and run the tethered RAM-only test while
Lance is present:

```bash
cd ~/vibe-coding-projects/coding/lg-v30-port
./make-testimage.sh
sha256sum out/boot-joan-mainline.img
# then exactly one fastboot client:
# adb reboot bootloader
# sudo -n fastboot boot out/boot-joan-mainline.img
```

Classifier expectations:

- mainline USB/mass-storage diag appears: capture dmesg and mark the fix as a
  strong candidate;
- LineageOS adb returns: classify as reset/failure and record timing;
- fastboot menu/hung download: stop, recover with Lance, and do not infer kernel
  behavior from that run.

If `dtschema`/binding checks are later installed, add the relevant
`make dt_binding_check` / `make CHECK_DTBS=y ...` commands here and record the
package install in the handoff.

## Likely public patch-series shape

The final public series should be split by reviewable topic, for example:

1. `arm64: dts: qcom: add initial LG V30 (joan) device tree`
2. `arm64: dts: qcom: msm8998-lge-joan: reserve LG firmware-owned memory`
3. `arm64: dts: qcom: msm8998-lge-joan: add <confirmed peripheral>`
4. driver or firmware changes only if the final boot fix truly requires mainline
   code outside DTS.

Current debug-only or likely non-public changes:

- ramoops breadcrumb instrumentation in `head.S` / `setup_arch`;
- raw SCM secure-watchdog experiments;
- direct APSS watchdog petter experiments;
- any timing oracle that intentionally resets the phone.

These can be referenced in the ledger or cover letter as investigation history,
but should not be submitted as-is.

## Public cover letter / PR body checklist

When opening a public PR or patch series, include:

- hardware: LG V30 US998 / `joan`, bootloader state, installed fallback OS;
- goal: mainline Linux/postmarketOS bringup without touching installed Android;
- what works now;
- what still does not work;
- exact test method: RAM-only `fastboot boot`, one-client discipline;
- links or references to the public ledger/evidence docs if they are published;
- known rejected approaches, summarized briefly enough to prevent duplicate work.

## Current public-readiness snapshot (2026-07-11)

- Mainline now reaches stable USB userspace, storage, and DRM/fb0 on joan. M1-M3
  are done; M4 display remains in progress. Do not claim visible built-in display
  support yet.
- K030 (`anoc1_smmu` skip-reset) is an important confirmed debug finding: it
  removes a named TrustZone Config/MM-NoC reset class, but it is **not** public-ready
  code as written. It needs a real upstreamable Qualcomm SMMU representation, not
  an `ember,debug-skip-reset` property.
- K041 rejected late-Linux `simple-framebuffer` as an observability path on joan's
  command-mode panel; do not reintroduce simplefb/fbcon as a public patch unless a
  separate early-display mechanism is proven.
- K042 is no longer valid as an SMMU cfg-probe rejection: a later raw-pstore
  partition read showed the K042 image died first in MSM8998 TLMM/GPIO
  registration (`gpiochip_add_data_with_key()` / `msm_gpio_get_direction()`),
  before it could exercise the SMMU cfg-probe hypothesis. Preserve it as
  debug evidence only.
- K050 produced a promising DTS-only candidate: extend joan TLMM
  `gpio-reserved-ranges` from `<0 4>` to `<0 4>, <49 4>, <81 4>`. It survived
  the RAM-only classifier window. Initial source review supports `<81 4>` from
  existing upstream MSM8998 boards; `<49 4>` is pstore/device-proven but needs
  stronger source justification before public use.
- K062's MSM8998 MDSS identity-domain policy is RAM-boot verified and
  upstream-shaped, but it needs wider review of bootloader-active display handoff
  semantics before submission.
- K065 retained the exact public `707f3fc86f6a` 10nm DSI VCO formula correction
  with original author/date preserved. Device evidence confirms the rate fix,
  though it is not sufficient for visible output.
- K067's one-line joan DSI VDD supply correction is source-backed and removed the
  dummy-regulator fallback. The physical K067 screen result is unobserved; the
  remaining RCG/commit-timeout path is still present.
- K068 retested `CLK_OPS_PARENT_ENABLE` after the VCO/VDD corrections. It cleared
  the MMCC RCG-update warnings but caused PLL-lock/clock-balance failures and a
  confirmed black screen. It is rejected debug evidence and must remain off the
  public-shaped kernel branch.
- K069 forced the mode-correct `/2` PLL output divider before lock on top of the
  K068 control. The phone still showed black, PLL lock still failed once, and the
  final live tree returned to `/4`. The hardcoded override is rejected debug
  evidence; instrument the overwrite sequence before designing a generic fix.
- K070 instrumentation proved saved divider state is already correct and isolated
  the early failure to `vco_current_rate=0`. The zero comes from interaction
  between the public-reference VCO formula patch and upstream initial-rate fix
  `8a48e35becb2`. Instrumentation is debug-only; the one-line state assignment
  candidate should be evaluated independently before any public disposition.
- K071 evaluated that one-line recalc side effect and collapsed the final DSI0
  clock tree to 0 Hz, with repeated PLL-lock/vblank failures. It is rejected.
  Any follow-up must keep recalc pure and test an explicit nonzero init-time seed
  rather than copying current-upstream side effects out of their patch context.
- Debug commits and saved experiment patches are valuable evidence but should be
  kept off a clean public PR branch.

## Attribution

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

---

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-08

Consolidated provenance of borrowed / derived material (Lance directive
2026-07-08: track borrowed code + who did the work). Keep this table current
whenever a new external source, downstream file, or mainline template informs a
change.

| Item | Source it's derived from | Author / project | License | Status |
|---|---|---|---|---|
| `msm8998-lge-joan.dts` | `msm8998-oneplus-common.dtsi` (regulator rails, cont-splash approach) + downstream LG `android_kernel_lge_msm8998` DTS (memory map, ramoops, wdt) | Jami Kettunen `<jamipkettunen@gmail.com>` + The Linux Foundation / Qualcomm for the OnePlus common DTS; Qualcomm/LGE for downstream joan data | BSD-3-Clause for joan and OnePlus common DTS; downstream LG kernel material must be treated as GPL-2.0-derived unless independently sourced | in-file header says "based on msm8998-oneplus-common.dtsi" + inline downstream notes present ✓ |
| anoc1 skip-reset (K030, debug) | concept: downstream `msm-arm-smmu-8998.dtsi` `qcom,skip-init`+`qcom,register-save` | Qualcomm/LGE (concept only; **code is original**) | GPL-2.0 | concept credited in-file comment ✓; needs a real upstream binding before it's shippable |
| `joan_imem_oracle.c` (debug, reverted) | IMEM offsets + LGE_RB_MAGIC/reason constants from downstream `lge_handle_panic.c` / `reboot_reason.h` | Qualcomm/LGE | GPL-2.0 | debug-only, not for upstream; constants credited in comments |
| `joan_disp_quiesce.c` (debug, reverted) | DSI/DPU register offsets from mainline `dsi.xml` + `dpu_3_0_msm8998.h` | (same GPL kernel tree — not external) | GPL-2.0 | debug-only |
| `out/aurel-k027-public-bullhead-reboot_reason.h` | public AOSP bullhead msm kernel `reboot_reason.h` (reason-code decode) | Google/Qualcomm/LGE (sourced by Aurel) | GPL-2.0 | reference only |
| K042 SMMU cfg-probe subtraction oracle (debug WIP) | Comparison between mainline `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c::qcom_smmu_cfg_probe()` and downstream `drivers/iommu/arm-smmu.c` / `msm-arm-smmu-8998.dtsi` `qcom,skip-init` policy | Aurel code is original; concept/evidence from upstream Linux + Qualcomm/LGE downstream behavior | GPL-2.0 | saved as `out/aurel-k042-smmu-cfgprobe-wip-2026-07-08.patch` and `out/aurel-k042-smmu-cfgprobe-tested-rejected-2026-07-08.patch` sha256 `e7fe6b0b3f1dd336f5180c92d1ce60da58a91ea1644e2ef5e67ae77c62ed6704`; built image sha256 `bc8099c241dc18865079e4fffce95d13cb9f3885705ae67ac2f570ec3fd85c4f`; device-tested but later superseded by pstore evidence: K042 died in TLMM/GPIO before SMMU; do not publish |
| K050 TLMM GPIO reserved-ranges candidate | pstore-guided TLMM/GPIO abort isolation: K046/K048/K049 showed protected direction reads on GPIO49/50/81; K050 reserves `<49 4>` and `<81 4>` in addition to existing `<0 4>` | Aurel DTS change is original; source basis is upstream MSM8998 pinctrl layout and pstore fault addresses | BSD-3-Clause for DTS if promoted; currently debug/candidate evidence | saved as `out/aurel-k050-clean-candidate-gpio-reserved-ranges-2026-07-08.patch`; RAM-only K050 survivor, source review still required for `<49 4>` |
| MSM8998 MDSS identity-domain client | mainline Qualcomm SMMU identity-domain table and same-class MDSS entries | Aurel/Lance change; Qualcomm mainline policy pattern | GPL-2.0 | local commit `7ff461605`; K062 RAM-boot verified, wider review required |
| 10nm DSI VCO formula | exact public `msm8998-mainline/linux` commit `707f3fc86f6a` | AngeloGioacchino Del Regno `<angelogioacchino.delregno@somainline.org>` | GPL-2.0 | exact patch-id preserved in local commit `5306416d2`; original author/date retained; K065 rate correction verified |
| joan DSI controller VDD supply | mainline `dsi_cfg.c` regulator declaration + downstream `msm8998-mdss.dtsi` PM8998 L1/L2 mapping + public MSM8998 OnePlus DTS | Qualcomm/LGE plus public MSM8998 board reference; Aurel/Lance one-line board mapping | BSD-3-Clause for joan DTS; sources used as hardware mapping evidence | local commit `b549c9f5b`; K067 removed dummy-regulator fallback; physical result unobserved |
| MSM8998 DSI PLL pre-lock output-divider ordering | downstream `drivers/clk/msm/mdss/mdss-dsi-pll-8998.c::dsi_pll_enable()` compared with mainline `drivers/gpu/drm/msm/dsi/phy/dsi_phy_10nm.c::dsi_pll_10nm_vco_prepare()` | Qualcomm/LGE downstream behavior used as diagnostic evidence; no downstream code copied yet | GPL-2.0 | K068 exposed the ordering failure; next experiment must remain debug-only until a generic implementation is justified |
| 10nm DSI initial VCO-rate fix | upstream Linux commit `8a48e35becb214743214f5504e726c3ec131cd6d` by Krzysztof Kozlowski plus current upstream `dsi_phy_10nm.c` | upstream Linux / Krzysztof Kozlowski; reviewed/merged by Dmitry Baryshkov | GPL-2.0 | K070 proves the local VCO formula patch removed state that this upstream initialization path relies on; basis for K071 one-line candidate |
| **PLANNED: `msm8998.c` interconnect provider** | `drivers/interconnect/qcom/sdm660.c` (primary template) + `msm8996.c` + topology/QoS values from downstream `msm8998-bus.dtsi` | **AngeloGioacchino Del Regno** (sdm660, SoMainline/Sony Xperia) + **Yassine Oudjana** (msm8996) + Qualcomm/LGE (values) | GPL-2.0 | not yet written — MUST keep their Copyright lines + SPDX + "based on" note; never present as original |
| initramfs busybox (test harness) | Alpine `busybox-static` package | busybox project / Alpine | GPL-2.0 | test-only, not shipped in kernel |

Rule going forward for any new borrowed code: preserve the origin file's
`Copyright` line(s) and `SPDX-License-Identifier`, add a `based on <file>
by <author>` note in the header, and keep the kernel.org commit trailers
(`Signed-off-by: Lance`, `Assisted-by: <agent-harness>:<model>` using the
actual helper/model, e.g. `Hermes:gpt-5.6-sol` or `Claude-Code:<model>`; never
`Co-Authored-By`). If any prior add above is missing an author I've marked
TBD and you know it, please append it.

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.6-sol
Date: 2026-07-11

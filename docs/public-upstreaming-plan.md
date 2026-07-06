# LG V30 public upstreaming / PR readiness plan

Purpose: keep the LG V30 (`joan`) work shaped so it can become a clean public
branch, GitHub PR, postmarketOS package input, or upstream Linux patch series
when the device finally boots far enough.

This is not a replacement for `docs/kernel-change-ledger.md`. The ledger tracks
all changes and experiments. This file defines what makes a change public-ready.

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

## Current public-readiness snapshot (2026-07-06)

- Clean candidate commits exist for the initial DTS and LG reserved-memory work.
- The reset/watchdog blocker is not solved; do not publish a claim that the phone
  fully boots mainline yet.
- The APSS watchdog node may be useful but remains `unknown` until the reset path
  is understood.
- Debug commits and saved experiment patches are valuable evidence but should be
  kept off a clean public PR branch.

## Attribution

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

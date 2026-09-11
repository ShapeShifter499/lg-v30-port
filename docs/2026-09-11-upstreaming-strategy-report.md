# Report: upstreaming/rebase strategy for the joan kernel stack (2026-09-11)

Investigation: Fulgor (ZCode:zai-coding-plan/GLM-5.3), Explore agent, 2026-09-11.
STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port.

## 0. Premise corrections (verified)

- No `7.2.0-rc2` tag exists; the base is upstream/master itself — merge-base
  = `8cdeaa50eae8` "Linux 7.2-rc2". The branch stacks directly on the rc2
  commit.
- `upstream/master..origin/joan/latest-clean-test` = 465 commits, but only
  401 non-merge and only **157 authored by the porter** — collapsing to
  **140 unique patches** (17 duplicate subjects from cherry-picks across
  topic branches). The other ~244 are upstream fix-tree commits pulled in by
  four merges (net-7.2-rc3, mm-hotfixes-stable, hid-for-linus, ksmbd);
  64 merge commits total. **Stop merging upstream fix trees** — that noise
  will poison future rebases.
- pmaports pinned the tip-3 commit; **bumped to tip `2b6ecf829cd7` same day**
  (pkgrel 13; 0001 verified to apply at the tip; checksums verified).
- `origin/master` (`ab54ef66802c`) is a **parallel curated line, not a
  subset of the tip** — 397 non-merge commits, same fixes at different
  hashes, does not contain the tip. Recommendation: freeze at ab54ef66 and
  retire it; verified fixes should live only on latest-clean-test (Lance's
  call).
- Upstream msm8998 already carries gpu@5000000/adreno_smmu/mdss_mdp dtsi
  nodes, mmcc/gpucc, IPA v3.1, qcom_smbx — the port's gaps are the NEW
  drivers: interconnect (7d9b74b7f0d4, only one in existence), OSM CPU
  clock, CAMSS (4dd87de5e58d, would be first), q6voice.
- Base is ~9 weeks / one merge window behind (7.3-rc2 as of Sep 6; 7.3 final
  late Oct).

## 1. Stack categorization

SoC enablement: msm8998.dtsi (23 commits) + new files (icc msm8998 + dt
bindings, clk-osm-8998.c, q6voice.c). Device: joan dts (52 commits).
Generic fixes: stmfts ×13, hci_qca ×7, qcom-ngd-ctrl ×7, wcd934x ×6,
a5xx_gpu ×4, arm-smmu ×7, qcom_smbx ×5, panel-lg-sw43402 (new driver).
Hacks/TEMP: 11 commits (039d65be K2 earpiece, 29234a4d WIP audio debug,
TEMP-DIAG pairs, fixup, experimental OPPs, pwrkey debounce hack, DPU TE
gate joan-specific for now, IPA scratch-IOVA workaround).

## 2. Roadmap

**Tier 1 — generic fixes, no DT deps, send first:**
1. wcd934x audio (2 patches, Mark Brown): 0f1af12e70f0 (uninit rx_chs/tx_chs
   list heads — "SLIM_RX0 PORT is busy" on every fresh probe, affects all
   wcd934x users) + c2a302cea233 (slim_stream error checks); optionally
   abc48a756b0f (INTR LEVEL init) to MFD.
2. stmfts touchscreen 7-patch series (FTS3670 decode, BTN_TOUCH/pointer,
   slot consistency, release-on-power-down, power-state, runtime-resume
   re-init, drop stopped contacts) — every FTS device benefits.
3. Bluetooth WCN399x (hci_qca quirks + DT BD-address sourcing dedupe).
4. ath10k WCN3990 5845 MHz channel withhold (519646f01702).
5. drm/msm a5xx runtime-suspend robustness (ea1cdd7e234f, 9f3d89120106,
   88dbc4e26623) — every a5xx device.
6. panel-lg-sw43402 new driver (6d7550d4ade8 + squashes) — drm-misc; the
   panel is used beyond joan.
7. soc: qcom small fixes (qmi unmatched messages, apr rx routing at bind).
8. arm-smmu retained-state (7e2dd6769427 + ab2b6869a392 + qcom side) —
   architecturally interesting, expect review.

**Tier 2 — msm8998 SoC enablement (benefits OP5/5T, Mi 6, Pixel 2 XL, Note 8):**
9. Trivial first: pd_mapper msm8998 protection domains (7187fbbb5675, +4);
   gpucc VDD_GFX pair.
10. CAMSS msm8998 (4dd87de5e58d + the dtsi node) — precedents: sm6150,
    QCS8300 series went via linux-media.
11. **Interconnect msm8998** — the flagship: rework 17 cherry-picks into
    6-8 patches (binding 0439cbf10453, driver 7d9b74b7f0d4 + real node data,
    QoS series, min NoC vote, dtsi wiring). Prerequisite for IPA
    GPU/display votes upstream.
12. IPA msm8998 refinements (runtime PM, quiesce, RR weight, modem QMI
    acks) — after interconnect.
13. CPU DVFS OSM — RFC first; upstream will debate OSM clock driver vs
    extending qcom-cpufreq-hw (cpufreq-dt-platdev currently BLOCKS
    qcom,msm8998 upstream). Defer until credibility established.
14. Audio stack in waves (dtsi slimbus+APR, ES9218P codec, TFA9872,
    sdm845 MI2S machine, q6afe/routing, q6voice as its own RFC).
15. Power: PMI8998 fuel gauge (+712) + SMB2 limits.

**Stays downstream forever (until reworked):** TEMP/WIP/DIAG commits, joan
dts until the SoC core lands, the DPU TE gate (until generalized), the IPA
scratch-IOVA workaround (its own comment names the upstreamable fix: correct
ipa_data-v3.1 imem_addr or an sram DT property).

## 3. Rebase strategy

- Textual risk is LOW now (1-2 upstream commits per port path in the whole
  7.2 cycle). Growing later: camss SoC entries will conflict; dtsi churn.
- Verdict: **one rebase to 7.3 final (late Oct) or 7.3-rc3+ soon**; send
  Tier 1 from a 7.3-rc-based send-branch now (patches are base-agnostic).
  Do NOT rebase latest-clean-test until after Tier 1 is out — rebuild once,
  not twice; dropping the four fix-tree merges removes ~240 commits of
  noise for free. Pin tags (joan-7.2-rc2-rN), not raw hashes.

## 4. Single best first PR

**"ASoC: wcd934x: fix SLIMbus port list initialization and error handling"**
— 0f1af12e70f0 + c2a302cea233 to Mark Brown (optionally + abc48a756b0f to
MFD). A real, always-reproducible bug affecting every wcd934x mainline user,
~26 lines, trivially reviewable, no DT dependency — the highest
acceptance-probability entry point before the stmfts/BT series build the
track record for interconnect/CAMSS.

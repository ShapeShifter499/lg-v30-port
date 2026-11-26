# Kernel history rewrite: old doc hashes → current `master`

Several docs cite kernel commit hashes from before the joan line was
reorganised (`joan/<topic>` branches were cherry-picked, rebased or merged into
`joan/latest-clean-test`; the 2026-10-09 mainline v7.3-rc6 merge `dd6f9f84a31f`
came on top). Those old hashes no longer exist in
[`linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan).
The docs commit `de777af` ("docs: follow the kernel branch's rewritten commit
hashes", 2026-09-25) records one earlier rewrite, done to drop chat links from
commit messages. This note records what could be checked for the later one(s).

Checked on 2026-10-27 against kernel `master` = `joan/latest-clean-test` =
`dc9c6692dbfb`. The clone used was shallow (`--shallow-since=2026-05-15`,
blobless), so nothing older than mid-May 2026 was examined.

## How the mapping was made

1. **Exact (trailer).** The re-applied commits keep the original hash in their
   message as `(cherry picked from commit <old>)`. All of `master` since
   2026-06-01 was scanned for that trailer
   (`git log origin/master --no-merges --since=2026-06-01`, body regex
   `cherry picked from commit ([0-9a-f]{7,40})`), and the hits were intersected
   with the hashes that appear in the docs listed below.
2. **By content (subject, date, diffstat), no trailer.** Where no trailer
   exists, a commit is listed only if the doc's own description of the change
   matches the `master` commit's subject and date. These rows say so.
3. **Unchanged.** A hash that still resolves to a commit and is an ancestor of
   `master` needs no mapping.

Docs searched: `README.md`, `docs/joan-hardware-support-matrix.md`, the
2026-08-10 session-close and branch-convention handoffs, the
`docs/handoff-2026-09-2*` and `docs/handoff-2026-10-0*` handoffs, the
2026-09-25 DP handoffs, `docs/session-2026-10-03-ember.md`, and the
2026-10-07 and 2026-10-09 evidence READMEs.

## Verified: exact (cherry-pick trailer)

| Old hash in the docs | Current `master` | Date | Subject |
|---|---|---|---|
| `7732a4cd245a` | `fb289020514a` | 2026-10-07 | arm64: dts: qcom: msm8998: add opp-microwatt to the CPU OPP tables |
| `c77bb2415e75` | `d351a20a06ae` | 2026-10-07 | cpufreq: qcom-cpufreq-osm: register the Energy Model through .register_em |
| `2cdfec0ab5a9` | `85b00b275518` | 2026-10-07 | net: qualcomm: rmnet: set IFF_NOARP on the raw-IP netdevs |

Notes:

- `fb289020514a` is a 53-line insertion in `msm8998.dtsi`, which matches the
  matrix row "opp-microwatt to all 53 CPU OPPs"
  (`docs/joan-hardware-support-matrix.md`, "CPU scheduler (EAS)" row).
- `docs/handoff-2026-10-07-ember-r60.md` (line 44) gives `c77bb2415e75` as the
  tip of branch `joan/cpu-energy-model`, "opp-microwatt for all 53 CPU OPPs …
  + register_em fix". That branch is gone from the remote; its two commits are
  `fb289020514a` then `d351a20a06ae` on `master` (same author, same day,
  10:53 and 12:04 −0700).
- `2cdfec0ab5a9` appears in the docs as the rmnet no-ARP fix
  (`joan/rmnet-noarp` in the matrix's modem row, which gives no hash).

## Verified: range partly mapped

| Doc text | What `master` has | Confidence |
|---|---|---|
| "DisplayPort alt mode … kernel `9d99d011..65405bda`" (matrix, DP row) | The end of the range is unchanged: **`65405bda7cd6`** is on `master` and is the pin used by pmaports `linux-lg-joan` r5 (pmaports `bc28cf7`, `_commit=65405bda7cd6…`). The start `9d99d011` is **not** in `master`'s history and has no cherry-pick trailer. The series that fits the matrix's description (PHY matched to LG's `mdss-dp-pll-8998`, USB3/DP hand-over, `phy_validate` flip report, DP OPPs, `gpio-sbu-mux` AUX, altmode) is the nine commits `21a48b82cd75..65405bda7cd6` below. | End: exact. Start: **uncertain**. |

The nine commits, in `master` order (all 2026-10-10 02:33 −0700, directly
after the speed-bin commits `c342d9cb6854` and `49d0331d4dba`):

```
21a48b82cd75 dt-bindings: phy: qcom,msm8998-qmp-usb3-dp-phy: document the DP port
889eb4747dba dt-bindings: display: msm: qcom,msm8998-mdss: allow the DP controller
5141e7e941f2 dt-bindings: usb: gpio-sbu-mux: add the LG V30 DP AUX switch
2de17bbe0259 phy: qcom-qmp-usbc: match the MSM8998 DP PHY to LG's driver
b03a536f3a68 phy: qcom-qmp-usbc: park the USB3 or DP half instead of failing it
23cd5cd3641b drm/msm/dp: ask the PHY about a flipped plug and map lanes first
408f63b75df4 phy: qcom-qmp-usbc: report a flipped MSM8998 plug through phy_validate()
7097436b59c0 arm64: dts: qcom: msm8998: give the DisplayPort controller its own OPPs
65405bda7cd6 arm64: dts: qcom: msm8998-lg-joan: route DP AUX and finish alt mode
```

Uncertain: whether `9d99d011` was the first of these nine or of the earlier DP
PHY commits (below), and whether the three bindings commits were inside the
range. The matrix text lists no bindings. The DP work as a whole also includes
commits from 2026-09-25 whose hashes were kept as written in the
2026-09-25 handoffs: `f08d8c5f0da9` (add the MSM8998 USB3+DP PHY),
`e6e796df38f4` (mmcc DP link/pixel clocks), `36ba6e40f034`, `5371fb3501ae`,
and the revert `42eff31685a7`.

## Verified: matched by content only

| Old hash in the docs | Current `master` | Basis |
|---|---|---|
| `59d590845da` (`docs/handoff-2026-09-24-usbc-camera-audio-cleanup.md`, "IPA v3.1 system header table") | `640894cb9690` (2026-09-24, "net: ipa: give IPA v3.1 a system header table") | Subject and date match; no cherry-pick trailer, diff not compared. **Uncertain.** |

## Recorded by an earlier docs commit (not re-derived)

| Old hash | Current `master` | Basis |
|---|---|---|
| `5fa00a2` | `42eff31685a7` (DP revert) | Stated in docs commit `de777af`; `master` has the commit with the matching subject. No trailer. **Not independently verified.** |
| `53b45d7` | `e6e796df38f4` (mmcc DP link/pixel clocks) | Same. |

## Hashes checked and still valid (present on `master`)

`47041183b`, `c861d1217`, `3f7fcabf`, `b3dc8621` (full: `b3dc8621470c`),
`621a3778bf10`, `e6e796df38f4`, `42eff31685a7`, `f08d8c5f0da9`,
`5ad311360264` (pmaports `linux-lg-joan` r6 pin), `65405bda7cd6` (r5 pin),
`dc9c6692dbfb` (current head, and the `smgr-iio-build` pin).

## Not resolved

These appear in the searched docs and do **not** resolve in the clone. None
was mapped, and nothing should be inferred from the absence:

- `ab54ef668` ("master" in `handoff-2026-09-24-…`). Pre-rewrite master; no
  trailer points to it.
- `acc4de0f64dd` (`joan/debug-ipa-rx-stall`, "DEBUG instrumentation … Not for
  merging" in `handoff-2026-10-07-ember-r60.md`). Expected to be absent;
  the branch is not on the remote.
- Further 8–12-character hex strings in the 2026-10-03 .. 2026-10-09 handoffs
  that did not resolve (about two dozen). Some are pmaports commits, firmware
  or file checksums rather than kernel commits, and I did not sort them.
  The same applies to hashes older than mid-May 2026 (outside the shallow
  clone).

To re-check any hash yourself against a full clone:

```sh
git log --all --format='%H %s' --grep='cherry picked from commit <old-hash>'
```

Assisted-by: Grok Bot
Date: 2026-10-27
Update-scope: New note; hashes verified against kernel master dc9c6692dbfb.

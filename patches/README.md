# linux-lge-joan package patches — archive

Copies of the patch files carried by the pmaports package
`device/testing/linux-lge-joan` (repo `pmaports-lg-v30-clean`, branch
`joan/readme-build-guide`). Archived here so the kernel-side work is
first-class in this repo, not only inside the pmaports checkout.
sha512 of each archived copy matches the package's sha512sums block.

## Status

| patch | status | content lives in |
|---|---|---|
| `0001-ipa-imem-addr-override.patch` | **LIVE — package is authoritative; this is a mirror** | pmaports commit `d9a12d3cdf` only; no kernel commit carries it |
| `0002-joan-micbias-mbhc-amic4.patch` | RETIRED 2026-09-07 | kernel `622008e1657f` (DTS micbias 2750/2000/2750/2750 mV, ground-jack-type-normally-closed, AMIC4/MIC BIAS4 route) |
| `0003-q6routing-selectable-tx-topology.patch` | RETIRED 2026-09-07 | kernel `fb968169503b` (q6routing `TX COPP Topology` enum, default None; playback untouched) |
| `0004-dpu-first-kickoff-te-gate.patch` | RETIRED 2026-09-07 (same day) | kernel `2f1308c271d8` on `joan/wake-path-v1` = `joan/latest-clean-test` (pushed): gate first kickoff after wake on one TE edge |

## Why 0002/0003 are retired

They were bridge patches: verbatim exports of two kernel commits, applied
on top of the old pin `1b42626b2b448d8fe97d7e2e0a63dec93c3bdaae` so the
package could build the audio work before the pin moved. On 2026-09-07 the
package was re-pinned to `fb968169503b4102340917c15956f533ab40be6c`
(= `joan/mbhc-headset-mic-v2` = `joan/latest-clean-test`, pushed to
github.com/ShapeShifter499/linux-lg-v30-joan), where both changes are
already in the tree — keeping the patches would fail the build on
already-applied hunks.

0001 is different: its `ipa.imem_addr` override exists nowhere else, still
applies clean on the new pin, and is part of the open near-null-IOVA
investigation (docs/2026-08-23-cellular-data-gsi-uplink.md), so it stays
in the package. If it is ever committed to a kernel branch, retire the
package copy the same way and update this table.

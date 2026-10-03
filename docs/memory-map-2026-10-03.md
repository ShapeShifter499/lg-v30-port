# joan reserved-memory map — taken from LG's final builds (2026-10-03)

Written-by: Ember (Claude-Code:claude-opus-5-5)
Kernel commit: linux-lg-v30-joan `4c3d1585c595` ("take the memory map from LG's final builds")

## Reference

The ground truth is the set of DTBs appended to the `boot.img` of LG's **last**
stock release for each variant:

| variant | final build | KDZ sha256 | DZ chunks MD5-verified |
|---|---|---|---|
| US998 (and H930/H932PR family) | `US99830b_00_0902` (Pie, 2019-10-03) | `82af7537bcb720f9aeb3d63ec9d668d62a3b9ecf0c07946549a66edeaa22c1fd` | 147/147 |
| H932 (T-Mobile, differently signed) | `H93230d_00_0902` (Pie, 2019-10-07) | `aa7584f61def75ba8ddfff958cedc807ea9edff079ec77b2a848734afb103c4a` | 144/144 |

LG's own firmware servers (csmgdl.lgmobile.com, tool.lime.gdms.lge.com) no
longer answer; both KDZs came from the AndroidFileHost V30 folder. The sizes
match lgrom/lg-firmwares listings, and every DZ data chunk's MD5 matches its
header (`tools/memmap/dzverify.py`). These are the same Pie builds the
`firmware-lge-joan-blobs` mirror was taken from.

Each `boot.img` carries **ten** DTBs (board-id `0x308`…`0xf08`). All twenty
declare a byte-identical `/reserved-memory`, which also equals a DTB compiled
from the LG-derived 4.4 source (`arch/arm64/boot/dts/lge/msm8998-joan/…nao_us`).
One map therefore serves every joan.

Stock extracted DTBs: skyforge `/data/buildcache/lg-stock-kdz/{us998,h932}/dtbs/`.

## The map

| region | address + size | where LG has it | consumer |
|---|---|---|---|
| hyp/xbl/smem/tz | `0x85800000`–`0x88f00000` | one `removed_regions` | SoC dtsi nodes + `memory@85f00000` plug |
| rmtfs | `0x88f00000 + 0x200000` | dynamic (`qcom,rmtfs_sharedmem` size only) | rmtfs (SoC default, fixed) |
| spss | `0x8ab00000 + 0x600000` | `spss_region` | — (SoC default was 7 MiB) |
| mpss | `0x8b400000 + 0x7700000` | `modem_region` | MSS; image signed for this address |
| adsp | `0x92b00000 + 0x1e00000` | `pil_adsp_region` (joan: 30 MiB) | ADSP |
| venus | `0x94900000 + 0x500000` | `pil_video_region` | Venus (venus.mdt spans 0x4ff020) |
| mba | `0x94e00000 + 0x200000` | `pil_mba_region` | MBA, authenticates modem in place |
| slpi | `0x95000000 + 0xf00000` | `pil_slpi_region` | SLPI (slpi_v2.mdt spans exactly 0xf00000) |
| ipa_fw | `0x95f00000 + 0x10000` | inside `pil_ipa_gpu_region` | IPA (ipa_fws.mdt spans 0x41c0) |
| ipa_gsi | `0x95f10000 + 0x10000` | inside `pil_ipa_gpu_region` | none in this tree; sized to tile the block |
| gpu (zap) | `0x95f20000 + 0xe0000` | inside `pil_ipa_gpu_region` | a540 zap (a540_zap.mdt spans 0x1334) |
| wlan_msa | `0x96000000 + 0x100000` | dynamic (icnss allocates 1 MiB) | WCN3990 |
| splash | `0x9d400000 + 0x2400000` | `splash_region` | bootloader framebuffer |
| ramoops | `0xb0000000 + 0x80000` (+ 0x80000 plug) | `ramoops_region` 1 MiB | pstore, downstream-compatible layout |
| crash_fb | `0xb0100000 + 0x1800000` | `crash_fb_mem` | LG crash handler |

`pil_ipa_gpu_region` has no phandle in the stock DTB — nothing in LG's kernel
references it; IPA firmware and the zap shader are loaded there by PIL.

## What changed and why

- **SLPI** had 2 MiB; the image needs 15 MiB. Sensors could not have booted.
- **gpu_mem** sat at `0x95c00000`, LG's *generic* msm8998 `pil_ipa_gpu` address.
  joan moves that block to `0x95f00000` (`msm8998-joan-common-pm.dtsi`), so
  `0x95d00000`–`0x96000000` was ordinary Linux RAM.
- **Naming**: moved regions kept their SoC node names (`mpss_mem` was
  `memory@8cc00000` at `0x8b400000`, …) — `unit_address_vs_reg` rejects that.
  Moved regions are now `/delete-node/`'d and re-created at their joan address
  (the pattern of `sdm845-lg-common.dtsi` and `msm8998-xiaomi-sagit.dts`);
  `spss_mem` keeps its unit address and takes a label override.

## Verification

- `tools/memmap/cover.py <stock.dtb> <ours.dtb>`: every byte LG reserves is
  reserved here (both variants); extras are rmtfs and wlan_msa only.
- Every `memory-region` consumer resolves to the intended node.
- W=1 build clean, no reserved-memory or unit-address warnings.
- Bench (US998, r41, 2026-10-03): modem + ADSP up, Wi-Fi passing traffic from
  the moved MSA region, both CPU clusters on schedutil. Cellular IPv6 and the
  PipeWire device list were not clean on that boot; kernel-side IPA and audio
  bring-up are line-for-line identical to r39, and a same-boot.img DTB A/B
  (`boot-joan-r41-oldmapdtb.img`) is queued to settle it.

## Tools

- `tools/memmap/splitdtb.py <boot.img> <outdir>` — split appended DTBs
- `tools/memmap/rmem.py <dtb>` — print /reserved-memory sorted by address
- `tools/memmap/cover.py <ref.dtb> <ours.dtb>` — coverage diff
- `tools/memmap/mdtspan.py <*.mdt>` — PT_LOAD span a region must hold
- `tools/memmap/dzverify.py` — MD5-check every chunk of a DZ (stdin: path; needs kdztools)

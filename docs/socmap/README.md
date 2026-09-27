# joan SoC map: what the hardware needs vs what mainline gives it

Built 2026-09-26 so bring-up stops finding missing clocks, rails, bus votes
and carve-outs one probe at a time.

## Sources

- **Downstream:** `joan-downstream-lineage22-live.dtb`, the flattened device
  tree the LineageOS 22 kernel (4.4.302, LineageOS/android_kernel_lge_msm8998)
  booted on the bench US998, pulled from `/sys/firmware/fdt`. `/chosen` is
  removed because it carries boot-time identifiers such as the serial number.
- **Mainline:** `msm8998-lge-joan.dtb` built from `joan/bootlog-fixes`.
- **Names:** clock, power-domain and bus IDs are turned back into names with
  each tree's own dt-bindings headers (downstream `msm-clocks-8998.h`,
  `msm-bus-ids.h`; mainline `qcom,*-msm8998.h`, `interconnect/qcom,msm8998.h`).

Regenerate:

    tools/socmap/joan_socmap.py --ds docs/socmap/joan-downstream-lineage22-live.dtb \
        --ml <build>/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb \
        --ds-tree <android_kernel_lge_msm8998> --ml-tree <linux-lg-v30-joan> \
        --json docs/socmap/joan-soc-map.json --md docs/socmap/joan-soc-map.generated.md

`joan-soc-map.generated.md` has every block. The findings there are
mechanical: a clock or supply listed "downstream only" can simply be named
differently, or be handled by a mainline driver or provider instead of the
consumer node. Treat each one as a lead. The list below is the part that has
been read and judged.

## Bus-bandwidth votes (interconnects)

On Qualcomm SoCs every block that moves data asks the interconnect framework
for bandwidth on its path (its "vote"); NoC and DDR clocks follow the sum. A
block that moves data without a vote depends on some other block keeping the
path up, and a stalled NoC transaction hangs the bus rather than failing.

Mainline providers present: bimc, cnoc, snoc, a1noc, a2noc, mnoc (and gnoc).

| Block | Downstream vote | Mainline | Status |
|---|---|---|---|
| GPU | grp3d, MAS_GRAPHICS_3D -> EBI, up to several GB/s | `gfx-mem` | ✅ |
| Display (MDP) | mdss_mdp, MDP_PORT0/1 -> EBI, ib 6.4 GB/s | `mdp0-mem`, `mdp1-mem` | ✅ |
| UFS | ufs1 | `ufs-ddr`, `cpu-ufs` | ✅ |
| SD card (SDHC2) | sdhc2, up to 400 MB/s ib | yes | ✅ |
| IPA | ipa | yes | ✅ |
| **Camera VFE0/1** | msm_camera_vfe, MAS_VFE -> EBI (DT value is a placeholder; the ISP driver sets it per stream) | **none** | ❌ CAMSS votes nothing. Suspected in the camera reset. |
| **Camera register (AHB) path** | msm-cam `qcom,bus-votes`: 0 / 300 / 640 / 640 MB/s (suspend/SVS/nominal/turbo) | **none** | ❌ |
| **MMSS SMMU** | smmu-bus-client-mmss: MAS_VFE -> EBI and CNOC -> MMSS_SMMU_CFG, 1 MB/s keep-alive while the SMMU is active | **none** | ❌ Page-table walks for camera/display/video go over this path. |
| **USB 3** | usb3, MAS_USB3 -> EBI, 240 MB/s avg / 800 MB/s peak | **none** | ❌ Likely limits USB throughput. |
| Venus video | pil-venus, MAS_VIDEO_P0 -> EBI, 304 MB/s | none (Venus disabled) | ⏳ with the Venus series |
| Crypto engine, TSIF, PCIe, BLSP UARTs, A1/A2NOC SMMUs | small votes | none | low priority |
| CPP, JPEG, FD, rotator | votes | no mainline drivers use them | n/a |

## Reserved memory

Firmware images load at fixed addresses. The joan DT already follows the
downstream layout for most regions (the tables in the generated file show
both sides, sorted by address).

| Finding | Detail |
|---|---|
| SLPI carve-out too small | Downstream `pil_slpi_region` is 15 MiB at 0x95000000; mainline has 2 MiB there, with other regions packed into the rest. Blocks the sensor DSP (Deck #162). |
| IPA/GPU firmware region missing | Downstream `pil_ipa_gpu_region`, 1 MiB at 0x95f00000, has no mainline region. Needed if the GPU zap shader or IPA firmware is ever loaded by the kernel. |
| Dynamic pools | Downstream sizes: CMA 32 MiB, qseecom 24 MiB, secure 92 MiB, ADSP 8 MiB, secure-processor 8 MiB. Mainline uses the kernel's CMA size; check it covers camera and video buffers. |
| Node names | Several joan overrides keep upstream unit addresses while moving `reg` (for example `memory@8cc00000` starts at 0x8b400000). Harmless at runtime but dtc warns; rename. |

## Clocks and supplies worth acting on

- **MMSS NoC interface clocks** (`mnoc_ahb`, `mmssnoc_axi`, `bimc_smmu_ahb/axi`)
  are enabled by every downstream multimedia consumer. In mainline they belong
  to the interconnect provider, the SMMU and porthole's
  `mnoc_ahb` keep-on fix, so they are not per-consumer clocks here. Re-check
  after the camera votes are in.
- **UFS/QUSB/DP use `ln_bb_clk1`** as a reference clock downstream. Worth a
  check against the mainline PHY nodes.
- **DSI panel supplies `lab`/`ibb`** exist only downstream (Deck #166).
- **GPU `vddcx`**: the mainline GPU node logs "supply vddcx not found".

## Next uses

- Camera: add CAMSS interconnects (VFE -> EBI, CPU -> MMSS config), then
  re-run the close/reopen reset tests.
- Wide/front cameras, FM, DP alt mode, Venus, SLPI: start each from this map
  instead of from probe errors.

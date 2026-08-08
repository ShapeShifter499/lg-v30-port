# Handoff: joan modem is up, and the size cliff is gone

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-08

## Headline

**The modem boots.** LG's signed firmware authenticated against our memory
map on the first attempt that got far enough to try:

    remoteproc0: powering up 4080000.remoteproc
    remoteproc0: Booting fw image qcom/msm8998/joan/mba.mbn, size 230056
    qcom-q6v5-mss: MBA booted without debug policy, loading mpss
    remoteproc0: remote processor 4080000.remoteproc is now up
    state: running

The QMI transport came up with it —
`4080000.remoteproc:glink-edge.IPCRTR` is present, and ModemManager is
already in the rootfs. That is layer 1 of 5 complete and layer 2's
transport live. No data, SMS or calls yet.

**And the 55.5 MB size cliff is no longer a constraint.** See below.

## What made the modem work

Three things, in the order they bit.

**1. LG's memory map, proven from the firmware binary.** The generic
msm8998.dtsi layout is not joan's. Rather than trust downstream's DT, I
read `modem.mdt`'s own program headers:

    modem.mdt loadable segments: 0x8b400000 - 0x92b00000  (119 MB)
    LG stock modem_mem:          0x8b400000 + 0x7700000   (119 MB)
    mainline generic mpss_mem:   0x8cc00000 + 0x7000000

Exact match against LG, 24 MB from generic. A 30th segment sits at
0x92b00000 and appears to overrun; its p_flags mark it
QCOM_MDT_TYPE_HASH, which `qcom_mdt_load` routes to the metadata region.

The regions move as a chain — the generic `adsp_mem` at 0x8b200000 lies
*inside* the range LG gives the modem — so mpss, adsp, venus and mba all
shift together. `slpi_mem` is the deliberate exception: LG's full extent
would swallow `ipa_fw_mem`, `ipa_gsi_mem` and `wlan_msa_mem`, which are
at mainline addresses and working (WiFi included). SLPI is not enabled,
so it gets only the 5 MB needed to clear `adsp_mem`.

**2. Everything the modem needs must be built in, not modular.** We
RAM-boot a custom kernel, so `/lib/modules/<release>` on the SD rootfs
never matches. This bit twice: first `CONFIG_QCOM_Q6V5_MSS=m` (caught
before boot), then `CONFIG_QRTR=m` (caught by the boot itself, as
`failed to initialize qmi handle` from `qcom_sysmon.c:672` —
`qmi_handle_init()` opens an AF_QIPCRTR socket).

**3. `auto_boot = false`.** The MSS driver does not start the modem at
probe, so a bad firmware load cannot wedge the boot. Boot, copy firmware,
`echo start > /sys/class/remoteproc/remoteproc0/state`, read the failure
from a live system. Use this — it is much cheaper than the QoS hangs.

Firmware is installed on the persistent SD rootfs at
`/lib/firmware/qcom/msm8998/joan/` — 29 files, 54.5 MB, verified complete
against the mdt program headers (30 headers, 3 with filesz==0, 27 .bXX,
no size mismatches). It survives reboots; you do not need to re-copy it.

## The size cliff: solved, not worked around

Aurel's handoff put the boot chain's uncompressed kernel cap at ~55.5 MB
and it caught my staged image at **55.38 MB — 123 KB of margin**. That
saved a boot.

Moving the whole modem chain to modules bought only **70 KB**. The bulk
was elsewhere:

    .text     21.9 MB
    .rodata   16.3 MB
    .BTF       8.4 MB   <-- BPF type information

`CONFIG_DEBUG_INFO_BTF` was on. Turning it off (with
`DEBUG_INFO_BTF_MODULES`) took the integrated kernel from **55.31 MB to
47.19 MB**. Debug sections like `.debug_info` never reach `Image`, but
`.BTF` does.

That is 8.24 MB of headroom on a tree that now carries *everything*.
The modem chain is back to built-in because we can afford it, which also
removes the release-string matching problem for the part that matters.
BTF only matters for BPF CO-RE and some tracing; if anything ever needs
it, turn it back on and the module strategy is still there as the
fallback.

## The integrated tree

`joan/integration-20260808` @ `d38242fb5`, pushed to `ghfork`.

    ghfork/joan/latest-clean-test   ICC/QoS (PRs #1-3) + mas_ipa (PR #4)
      merged with
    ghfork/joan/battery-fg          PMI8998 FG + charging + WCN3990 (PR #5)
      plus
    b805ab3c0                       modem enable (cherry-picked)

Merged clean, no conflicts, and no duplicate DT node overrides — checked,
since a clean textual merge is exactly where two `&adsp_mem { }` blocks
would hide and the last one would silently win. Aurel's WiFi/BT touches
no memory regions, so it does not collide with the modem carve-outs.

Note the two bases had diverged: PRs #1-4 merged to
`joan/latest-clean-test`, PR #5 merged to `master`. Worth picking one.

Config: modem/QRTR/ICC/battery/charger built in; WiFi/BT modules per
Aurel's strategy. Saved at `docs/integration-20260808.config`.

Verified: build exit 0, zero warnings; overlap scan PASS across 104 MMIO
windows and 22 reserved-memory regions; `mss status = okay`; `mpss_mem`
at LG's base; `wifi@18800000` present.

Staged image: `boot-joan-integration1-rx.img`
sha256 `dfe2f9e95c1a7cb8b5d38a987abc13ba2d84fd9cc473d2cd89013cf64dba9b70`
kernel release `7.2.0-rc2-gd38242fb5c52`. **Not yet booted.**

WiFi/BT modules must be installed for that release string before they
work — `INSTALL_MOD_PATH` tree was being built when this was written;
check `/home/kumo02/.claude/jobs/.../modroot` or rebuild with
`make modules modules_install INSTALL_MOD_PATH=<dir> INSTALL_MOD_STRIP=1`.

## What is next

1. Boot the integrated image. This is the first time all four
   workstreams run together, so it is as much a conflict test as a
   feature test.
2. Install the WiFi/BT modules for `7.2.0-rc2-gd38242fb5c52` and confirm
   Aurel's two walls are where they left them (wlanmdsp.mbn, BT serdev).
3. Layer 2 proper: get ModemManager to see the modem. Per pmaports
   !3531 that needs `ipa`, which upstream msm8998.dtsi has no node for —
   the OnePlus 5/5T support lives in a pmaports kernel patch. That is the
   next real piece of work, and `mas_ipa` QoS (Aurel, PR #4) is already
   in.

## Corrections to my own earlier claims

- I said no in-tree msm8998 device enables the modem. **Wrong** — four
  do: fxtec-pro1, lenovo-miix-630, mtp, clamshell.dtsi. Fxtec is a phone
  and enables it with nothing but `status = "okay"`, no memory
  overrides, because its firmware is signed for the generic layout.
- I said `mas_ipa` was blocked on a missing IPA clock. **Wrong**, twice
  over. It is `RPM_SMD_IPA_CLK` from rpmcc, already in mainline; I only
  ever grepped `gcc-msm8998`. Aurel implemented it and device-tested it
  (17/17 masters, PR #4).

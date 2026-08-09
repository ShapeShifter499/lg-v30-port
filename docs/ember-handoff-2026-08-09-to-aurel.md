# Handoff: Ember -> Aurel, 2026-08-09

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-09

Modem/IPA chain is up, and both of your walls turned out to be firmware
rather than driver gaps. Everything below is device-verified on joan
unless it says otherwise.

## Your two walls, re-characterised

### BT wall #2 is not serdev

`msm_serial` binds fine. `hci0` attaches to `/soc@0/serial@c171000` and
the driver *reads the controller version register* (`0x02140201`), which
requires a working two-way link. The wall was missing firmware. With
`qca/crbtfw21.tlv` and `qca/crnv21.bin` in place:

    QCA Downloading qca/crbtfw21.tlv
    QCA Downloading qca/crnv21.bin
    QCA setup on UART is completed

Your `crnv21.bin` SHA `43f429abcf72...` matched mine exactly, so we
pulled identical files.

### BT is still not finished, and this part is yours

Lance noticed Settings says "off" while quick settings says "on". Both
are correct: `rfkill` sees `hci0` unblocked (quick settings), while
`bluetoothctl show` returns **"No default controller available"**
(Settings). The cause appears immediately after setup:

    Bluetooth: hci0: Frame reassembly failed (-84)    [-EPROTO]

I ruled out the two obvious suspects so you do not have to:

- `max-speed = <3200000>` matches all 19 wcn3990-bt nodes in tree.
- `blsp1_uart3_on` is a proper 4-pin state including CTS.

So it is neither baud rate nor flow-control pins.

### WiFi wall #1 firmware is done, blocker is narrower

`wlanmdsp.mbn` and `bdwlan.bin` -> `board.bin` are installed on the
rootfs. `ath10k_snoc` still binds `18800000.wifi` and stalls **before
issuing any firmware request**, and `qrtr-lookup` never shows wlfw
(service 69). So "needs wlanmdsp.mbn" is no longer the blocker — that
file is present and unused.

Note `wlanmdsp.mbn` is not referenced anywhere in the mainline kernel,
so the modem is expected to load it, and is not doing so.

## New: the modem -> IPA chain works

**`rmtfs` is mandatory, and it needs `CONFIG_QCOM_RMTFS_MEM=y`.**
Without that driver there is no `/dev/qcom_rmtfs_uio*`, rmtfs falls back
to `/dev/mem`, fails to mmap, and the modem comes up with **3 QMI
services instead of 45**. That looks like a modem fault and is not one.
Correct invocation is `rmtfs -P -r -s` (`-r` = read-only; flags taken
from the source's own `getopt(argc, argv, "o:S:Prsv")`).

**IPA works** — `rmnet_ipa0` exists, "IPA driver setup completed
successfully". Two things were needed:

1. A **seventh interconnect provider, `gnoc`**, which did not exist.
   IPA's required config path is
   `<&gnoc MAS_APSS_PROC &cnoc SLV_IPA>`. gnoc is two nodes, carries no
   bus clock (matching downstream's `fab_gnoc`), and its values come
   from downstream's `msm8998-bus.dtsi`. Window `0x17900000/0xe000`
   matches the `gnoc-base` entry in the `ad-hoc-bus` reg list.

2. **`qcom,gsi-loader = "self"` plus `ipa_fws.mdt`** and its five `.b??`
   segments (6 files, 48 KB, from `/vendor/firmware_mnt/image/`).

`"modem"` is the tempting choice since it needs no extracted blob, and
it does get further — the driver initialises and receives the modem
starting and running events — but the handshake never completes.
`ipa_qmi_ready()` gates on `modem_ready` and `uc_ready`, and both are
set by messages the **modem's own IPA driver** sends
(`INDICATION_REGISTER`, `DRIVER_INIT_COMPLETE`). Under
`IPA_LOADER_MODEM` the modem must load GSI firmware and signal over
smp2p before sending either; LG's modem firmware does not. So the AP has
to load it.

## The `=m` trap has now cost boots five times

RAM-booted kernels never match `/lib/modules/<release>`. These must be
`=y`:

    QCOM_Q6V5_MSS       QRTR / QRTR_SMD      QCOM_SYSMON
    QCOM_RMTFS_MEM      QCOM_SPMI_RRADC      QCOM_SPMI_ADC5
    QCOM_SPMI_ADC_TM5   BATTERY_PMI8998_FG   CHARGER_QCOM_SMB2

The battery one deserves calling out: the deferred-probe message names
`usbin_v` and the obvious guess (ADC5) is **wrong** — that channel comes
from **RRADC** (`qcom,pmi8998-rradc`, `adc@4500`). Enabling ADC5 alone
changes nothing. `/sys/kernel/debug/devices_deferred` names the culprit
exactly.

Not needed on joan: `QCOM_SPMI_VADC`, `QCOM_SPMI_IADC` — the only
`qcom,spmi-vadc` reference in `pm8998.dtsi` is a `#include` of the
channel-constants header, not a device node.

## Your size cliff is gone

`CONFIG_DEBUG_INFO_BTF`'s `.BTF` section is 8.4 MB and — unlike the
`.debug_*` sections — **does** land in `Image`. Disabling it (with
`DEBUG_INFO_BTF_MODULES`) took the fully-integrated kernel from
**55.31 MB to 47.19 MB**. Moving the whole modem chain to modules was
worth only 70 KB by comparison.

Your ~55.5 MB cap caught my staged image at 55.38 MB — 123 KB of margin.
That saved a boot; thank you.

## Your mas_ipa work is in

It matched the recipe from my earlier handoff exactly — rpmcc
`RPM_SMD_IPA_CLK`, `"ipa"` first in `intf_clocks`, port 1 landing at
`0x600c`. 17/17 masters.

## Branches

- **Kernel**: `joan/icc-gnoc-and-ipa` @ `9bfc50add`, on top of
  `joan/integration-20260808` (merges ICC + mas_ipa + battery + WiFi/BT +
  modem — clean, no conflicts, no duplicate DT overrides).
- **PR #6** consolidates onto `joan/latest-clean-test`. Worth settling
  that as main: `master` is the upstream mirror (149 commits ahead with
  HID fixes and selftests), and PR #5 landing there is what split the
  tree in the first place.
- **Docs**: `ember/modem-layer1-handoff` —
  `docs/joan-firmware-and-package-requirements.md` (firmware table with
  hashes and a completeness check, package traps, the `=y` table) and
  `docs/integration-20260808.config`.

## Open, in the order I would take them

1. **ModemManager finds no modem.** `rmnet_ipa0` is up, MM logs
   `qrtr devices allowed: yes` and loads 44 plugins across
   tty/net/usbmisc/wwan/rpmsg/qrtr — but there is **no
   `/sys/class/wwan/`**. Mainline IPA registers a plain netdev, not a
   WWAN-class device, so MM's QRTR path has nothing to bind to. Reads as
   userspace/plugin rather than kernel.
2. **WiFi wlfw** — nothing ever requests `wlanmdsp.mbn`.
3. **BT `-EPROTO`** after setup completes.

## One caution

I ran `rmtfs` once **without** `-r`, which gave a mainline modem write
access to NV partitions shared with Android. Lance verified the IMEI is
intact, so no harm done — but use `-r`.

## Device state at handoff

joan is in a pmOS RAM boot running `7.2.0-rc2-g9bfc50addde1`: modem up
with 45 QMI services, `rmnet_ipa0` up, BT `hci0` present, battery 99%.
Nothing is flashed; a reboot returns it to LineageOS. Firmware and the
module tree live on the SD rootfs and persist across reboots.

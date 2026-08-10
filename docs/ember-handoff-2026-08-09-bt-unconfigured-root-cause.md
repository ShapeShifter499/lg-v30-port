# Handoff: Ember -> Aurel/Lance, 2026-08-09 evening — BT root-caused and fixed

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-09

Bluetooth adoption is solved. It was never the UART, the line discipline,
the module load order, or frame framing. It was a regression introduced by
our own BD-address commit, and it is now proven fixed on the running
device without a rebuild or a reboot.

## What was actually wrong

`hci0` was healthy the whole time. The mgmt interface said so exactly:

    READ_INDEX_LIST          count=0  -> (none)
    READ_UNCONF_INDEX_LIST   count=1  -> hci0
    READ_CONFIG_INFO hci0    supported=0x2  missing=0x2  ['PUBLIC_ADDRESS']

The controller was registered, had completed setup, and was parked as
**unconfigured** with exactly one thing missing: a public BD address.
bluetoothd does not expose unconfigured controllers as adapters, hence
"No default controller available". Phosh's indicator lit up because an
mgmt index existed; nothing ever reached D-Bus.

The cause is commit `240de5d2f`, which sets `HCI_QUIRK_USE_BDADDR_PROPERTY`
unconditionally. `hci_dev_setup_sync()` folds that quirk into
`invalid_bdaddr` and only clears it if an address is found in the DT *and*
`set_bdaddr()` succeeds:

    invalid_bdaddr = hci_test_quirk(hdev, HCI_QUIRK_INVALID_BDADDR) ||
                     hci_test_quirk(hdev, HCI_QUIRK_USE_BDADDR_PROPERTY);
    ...
    if (invalid_bdaddr && bacmp(&hdev->public_addr, BDADDR_ANY) &&
        hdev->set_bdaddr) {
            ret = hdev->set_bdaddr(hdev, &hdev->public_addr);
            if (!ret)
                    invalid_bdaddr = false;
    }
    if (hci_test_quirk(hdev, HCI_QUIRK_EXTERNAL_CONFIG) || invalid_bdaddr)
            hci_dev_set_flag(hdev, HCI_UNCONFIGURED);

When the per-device `local-bd-address` came out of the DT (correctly — it
cannot ship), the quirk stayed in with nothing to satisfy it, and every
build since has been guaranteed dead.

Four independent confirmations:

1. The running DTB has no `local-bd-address` (read from `/proc/device-tree`).
2. The core clears `invalid_bdaddr` only on a successful injection.
3. Live mgmt reports `missing=PUBLIC_ADDRESS` and nothing else.
4. `boot-joan-bt-bdaddr.img` — the one image where BT was proven — is the
   **only** image on nym-nest containing the string `local-bd-address`.
   `touch-pwr4`, `gdsc5min` and `stmfts-reinit` all lack it.

## Two corrections to the previous handoffs

- **`-84` is `-EILSEQ`, not `-EPROTO`**, and it is a red herring. The
  controller version read succeeds 150ms after the first one, the full
  two-file firmware download ACKs every chunk, and when I re-triggered
  setup on the live device the same `-84` appeared again while the
  controller came up perfectly. It is a stray byte after a baud change.
- **Mainline never sets this quirk for QCA.** Before `240de5d2f` the only
  QCA quirk was `HCI_QUIRK_BDADDR_PROPERTY_BROKEN` (a byte-order flag).
  So the commit as written would strand every in-tree QCA board that
  carries a usable address in NVM — it was not upstreamable as written.

## There is no factory BT MAC on joan (proven, not assumed)

Worth writing down so nobody hunts it again:

- The NVM's own address TLV is zeroed — `qca/crnv21.bin`, tag `0x0002`,
  length 6, value `00 00 00 00 00 00`.
- LG's vendor tool `btnvtool` (`/system/vendor/bin/btnvtool`) contains the
  strings `/persist/bluetooth`, `.bt_nv.bin` and **`Writing Random
  BD_ADDR`** — the stock stack *generates* a random address on first use
  and persists it.
- That file does not exist. `persist` mounted read-only contains
  `data hvdcp_opti rfs hlos_rfs .twrps bms secnvm vpp sensors lost+found`
  and no `bluetooth` directory.
- `modemst1/2`, `fsg`, `factory`, `sec`, `eksst`, `msadp`, `devinfo`,
  `misc`, `raw_resources`, `persdata` and `sns` carry no address. The only
  MAC-shaped values on the device are the stock WCNSS placeholders
  (`Intf0MacAddress=000AF58989FF` and neighbours) in `drm`.

Conclusion: nothing to recover. Deriving an address is not a workaround
here — it is strictly better than what Android itself does, because ours
is reproducible rather than random.

## The fix, in two halves

**Kernel** (branch `joan/bt-uart-clock-fix`, follow-up commits — PR #7 is
under review, so no force-push):

- `14955ba2e` — gate `HCI_QUIRK_USE_BDADDR_PROPERTY` on the property
  actually being present. Platforms that describe an address opt in;
  everything else keeps mainline behaviour.
- `9314f9acd` — give joan's `bluetooth` node the all-zero placeholder
  `local-bd-address = [ 00 00 00 00 00 00 ];`, as `qcs404-evb.dtsi`
  already does in tree. The core rejects all-zero values, so the
  controller stays honestly unconfigured and userspace supplies the
  address.

Both verified to build: `hci_qca.o` compiles clean, and `fdtget` confirms
the placeholder lands in the DTB.

**Device side** (`device/` in the port repo, not yet installed):

- `usr/local/sbin/joan-bt-address` — derives a locally-administered
  address from the fused SoC serial and applies it with
  `btmgmt --index 0 public-addr`. Waits up to 30s for `hci0`, since the
  controller only appears ~20s into boot.
- `etc/init.d/joan-bt-address` — openrc service, `before bluetooth`.
- Needs `apk add bluez-btmgmt` on the rootfs.

joan's SoC serial is `2695651760` = `0xA0AC61B0`, giving
**`02:00:A0:AC:61:B0`** (unicast, locally administered).

## Proven live, no rebuild and no reboot

Driving `MGMT_OP_SET_PUBLIC_ADDRESS` over a raw mgmt socket on the running
kernel (so nothing was installed on the rootfs):

    BEFORE:  configured=none  unconfigured=hci0
    SET_PUBLIC_ADDRESS 02:00:A0:AC:61:B0 -> status=0
    AFTER:   configured=hci0  unconfigured=none

    READ_INFO hci0: addr=02:00:A0:AC:61:B0 hci_ver=9 manuf=29
                    powered=1 BR/EDR=1 LE=1

    $ bluetoothctl list
    Controller 02:00:A0:AC:61:B0 LG V30 [default]

Class `0x000c020c` matches Aurel's proven session exactly. Full profile
set present (A2DP source/sink, AVRCP, GATT, DIS). A 15-second discovery
returned **15 devices with live RSSI**, including the same ResMed CPAP
(`70:C5:9C:47:AA:0A`) Aurel saw this morning.

This state is live but not persistent — it is gone on the next reboot
until the openrc service is installed.

## Separate finding: a real bug in the touch fix

Not BT, but it fires three times per boot and taints the kernel:

    Unbalanced enable for IRQ 75
    WARNING: kernel/irq/manage.c:774 at __enable_irq+0x4c/0x80
      __enable_irq <- enable_irq <- stmfts_power_on.part.0
      <- stmfts_runtime_resume <- stmfts_input_open <- evdev_open

`stmfts_power_on()` contains a bare `enable_irq()` and expects to be
entered with the interrupt disabled — probe says so in as many words
("stmfts_power_on expects interrupt to be disabled"). The new
`stmfts_runtime_resume()` calls `stmfts_power_on()` directly, so it
bypasses the `sdata->powered` guard that lives in `stmfts_set_power()`
and never updates the flag either. Consequences:

- IRQ enable-depth underflow on every touch open (the warning above).
- A leaked `regulator_bulk_enable()` refcount each time.
- `sdata->powered` desyncs from reality in both directions, so the panel
  path can double-power an already-powered controller, or skip powering
  one that runtime PM has powered off.

That desync is a plausible cause of the very symptom the commit's own
comment is working around ("frozen keypad after wake #2 ... runtime PM
thinks it is active"). Worth fixing before that commit goes near a PR —
either move the guard into `stmfts_power_on()`/`stmfts_power_off()`, or
have `stmfts_runtime_resume()` go through `stmfts_set_power()`.

## Still open

1. **Flash-awake after lock** — untouched this session.
2. **Rainbow on wake** — the 120ms -> 300ms settle test is still queued.
3. **WiFi** — `wlanmdsp.mbn` still unobtainable; nothing new.
4. **pwrkey IRQ freeze** — did not reproduce; not investigated.

## Reproducing the diagnosis

The mgmt probe is the fastest way to tell "kernel BT is broken" from
"userspace won't adopt it", and needs no packages — python3 is on the
rootfs:

    bind AF_BLUETOOTH/SOCK_RAW/BTPROTO_HCI to (HCI_DEV_NONE, HCI_CHANNEL_CONTROL)
    0x0003 READ_INDEX_LIST          -> configured controllers
    0x0036 READ_UNCONF_INDEX_LIST   -> unconfigured controllers
    0x0037 READ_CONFIG_INFO         -> supported/missing options bitmaps
    0x0039 SET_PUBLIC_ADDRESS       -> bdaddr, LSB first

Note the opcodes: `READ_UNCONF_INDEX_LIST` is `0x0036` and
`READ_CONFIG_INFO` is `0x0037`, one lower than a natural guess.

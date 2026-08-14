# Bluetooth on joan: HCI UP and passive discovery working

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-14

Run `CONN-V10-*`, image
`2740a7d03a99edf89ebdd75ff9b65d010e5f0bf8af5efbfde15ef492b5b789c8`.
RAM boot only. No pairing, no connection, no outbound inquiry -- LE passive
discovery only. The address is set at runtime and is not persisted anywhere.

## Result

```
READ_INDEX_LIST:        01 00 00 00        <- one CONFIGURED controller
READ_UNCONF_INDEX_LIST: 00 00
READ_CONFIG_INFO:       missing_options = 00 00 00 00
SET_POWERED:            OK   c1 0a 40 00
READ_INFO:              addr 02:00:5e:10:00:01, ver 8 (BT 5.0), manuf 0x001d
```

and passive discovery returns real devices:

```
DEVICE_FOUND 50:af:cd:15:b4:aa
DEVICE_FOUND 4c:96:ef:0a:f2:db
DEVICE_FOUND 5c:79:49:91:84:23
... 14 events, 8 distinct addresses, in 15 s
```

Against the handoff's acceptance boundary: drivers load (built in), the QCA
controller initialises, firmware loads, a stable local address is adopted,
**HCI is UP**, passive discovery succeeds, and nothing was paired or
connected. That is the lane met.

## What it took

Four separate defects, in the order they surfaced. Each one hid the next.

### 1. Firmware requested before the rootfs exists

QCA setup runs at ~1.8 s; the pmOS rootfs is not mounted until ~10 s. The
firmware request therefore hits the initramfs, gets `-2`, and is never
retried:

```
[1.767799] bluetooth hci0: Direct firmware load for qca/crbtfw21.tlv failed with error -2
```

The file is present at exactly that path on the rootfs. Worked around for
these tests with `CONFIG_EXTRA_FIRMWARE="qca/crbtfw21.tlv qca/crnv21.bin"`.
**The proper fix is the firmware in the pmOS initramfs** -- pmaports
packaging, not a kernel change.

### 2-4. Three commands advertised but not implemented

With firmware loading, HCI init fails on a chain of commands the controller
claims in its supported-commands bitmap and then answers with a malformed
reply or Unknown HCI Command. Each aborts init, leaving the controller in
**neither** index list, so it can never be powered on.

| opcode | command | symptom | fix |
|---|---|---|---|
| `0x204b` | LE Read Transmit Power | `unexpected cc 0x204b length: 1 < 3`, `-38` | `HCI_QUIRK_BROKEN_READ_TRANSMIT_POWER` (existing) |
| `0x2031` | LE Set Default PHY | `Opcode 0x2031 failed: -56` | `HCI_QUIRK_BROKEN_LE_SET_DEFAULT_PHY` (**new**) |
| `0x2041` | LE Set Extended Scan Params | `Opcode 0x2041 failed: -56` | `HCI_QUIRK_BROKEN_EXT_SCAN` (existing) |

`-56` is `-EBADRQC`, HCI status 0x01, Unknown HCI Command.

Commits:

```
f9b6f2841 Bluetooth: hci_qca: mark LE Read Transmit Power broken on WCN399x
7b4062588 Bluetooth: add a quirk for controllers with a broken LE Set Default PHY
31fb4ff27 Bluetooth: hci_qca: mark extended scanning broken on WCN399x
```

The new quirk routes into the branch `hci_le_set_default_phy_sync()` already
takes when the command is absent -- select the 1M PHY -- so it adds no new
behaviour, only a new way to reach existing behaviour.

## Errors of mine along the way

- **I misidentified `0x2031`.** I asserted it was LE Read Resolving List Size
  and built a complete quirk for it -- enum, core gate, driver hook, commit --
  before checking the header. `0x202a` is the resolving list; `0x2031` is LE
  Set Default PHY. The wrong commit was reset out rather than shipped.
- **I blamed the UART.** Three symptoms (frame reassembly errors, a short
  command complete, an unknown-command answer) read like lost bytes, so I
  reverted my own quirk and dropped `max-speed` to 115200. Both halves were
  wrong: the frame errors occur at the *init* speed before any rate change,
  and 115200 cannot push the 177 KB TLV inside the command timeout. Restored.
- **I suspected the re-setup path.** `SET_PUBLIC_ADDRESS` forces a second
  `qca_setup()`, so I tested with the address in `local-bd-address` to make
  init run exactly once. It failed identically, proving the controller and
  not the sequence -- which is what justified the quirks.

## Caveat before upstreaming

All three quirks are keyed on the WCN399x family in `hci_qca`. They are
device-verified on joan only. WCN3990 is used on sdm845 boards where
Bluetooth works today, and `HCI_QUIRK_BROKEN_EXT_SCAN` in particular disables
extended scanning for all of them. **Before submitting, either narrow the key
or test on a second WCN3990 device.** The firmware/NVM pairing differs per
board and may well explain why joan's controller under-delivers against its
own bitmap.

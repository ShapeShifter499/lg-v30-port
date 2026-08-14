# Connectivity round 2: BT init reaches its real bug, Wi-Fi MSA is load-bearing, ADSP sized wrong

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-14

Follows `ember-connectivity-builtin-bringup-2026-08-14.md`. Runs
`CONN-V2-20260814T123143Z`, `CONN-V3-20260814T132011Z`,
`CONN-V4-20260814T140449Z` on nym-nest. RAM boots only; `rmtfs` read-only;
no association, pairing, registration, provisioning write, transmission,
playback or capture. Nothing written outside tmpfs; no partition flashed.

## 1. Harness fix: stage the verification, or lose it

Two boots produced a **zero-byte** result file because one long SSH session was
running when the device reset. Replaced with `stage.sh`, which runs one stage,
has the device write to its own file, fetches it immediately, and on failure
reports `FETCH_FAILED` naming the stage in flight. A reset now costs one stage
instead of the whole run, and the stage that died is identified.

## 2. Bluetooth: firmware timing fixed, then a real controller bug

`CONFIG_EXTRA_FIRMWARE="qca/crbtfw21.tlv qca/crnv21.bin"` (embedded
`crnv21.bin` sha256 `43f429ab...`, matching joan's documented file) makes the
firmware available when QCA setup actually runs:

```
[2.163945] Bluetooth: hci0: QCA Downloading qca/crnv21.bin
[2.207040] Bluetooth: hci0: QCA setup on UART is completed
```

That is at boot, versus the previous failure at 1.77 s and success only on a
manual rebind. The proper long-term fix is the firmware in the pmOS
initramfs -- a pmaports packaging matter, not a kernel one -- but embedding it
is a valid test vehicle and is what these runs used.

### My own error, recorded

The first mgmt attempt failed every command with status `0x11` and I read that
as a device-side problem. **The opcodes in my helper were simply wrong.**
`MGMT_OP_SET_PUBLIC_ADDRESS` is `0x0039`, not `0x0024` (which is
`SET_SCAN_PARAMS`); `READ_UNCONF_INDEX_LIST` is `0x0036` and
`READ_CONFIG_INFO` is `0x0037`. With the right opcodes:

```
READ_VERSION:            OK  01 17 00
READ_INDEX_LIST:         OK  00 00               <- zero configured controllers
READ_UNCONF_INDEX_LIST:  OK  01 00 00 00         <- one unconfigured, index 0
READ_CONFIG_INFO(idx0):  OK  1d 00 02 00 00 00 02 00 00 00
SET_PUBLIC_ADDRESS:      OK
```

`1d 00` is manufacturer 0x001d, Qualcomm. `missing_options` bit 1 is
`MGMT_OPTION_PUBLIC_ADDRESS` -- the controller is missing exactly what joan's
DT comment says it is missing. Supplying an address is accepted and
re-triggers QCA setup, precisely as the DT intends.

### The actual bug

With an address supplied, HCI init proceeds much further and then dies:

```
[249.952882] Bluetooth: hci0: QCA setup on UART is completed
[249.999267] Bluetooth: hci0: unexpected cc 0x204b length: 1 < 3
[249.999758] Bluetooth: hci0: Opcode 0x204b failed: -38
```

`0x204b` is `HCI_OP_LE_READ_TRANSMIT_POWER`. WCN3990 answers with a one byte
command complete where the spec requires three, the event handler rejects it,
the command fails, and HCI initialisation aborts -- leaving the controller in
**neither** index list, so it can never be powered on.

`HCI_QUIRK_BROKEN_READ_TRANSMIT_POWER` exists for exactly this and is used by
`btbcm` and `btusb`, but not by `hci_qca`. Fix: `f9b6f2841`, setting it for the
WCN399x family. checkpatch --strict 0/0/0.

This is only reachable on a board with no factory BD address once an address
has been supplied and init gets as far as LE feature discovery, which is why
it has not surfaced before.

## 3. Wi-Fi: `qcom,msa-fixed-perm` is load-bearing, not a fix (correction)

`10101704e` added `qcom,msa-fixed-perm`, and it does what it claims -- the
`failed to assign msa map permissions: -22` is gone and QMI negotiates
properly:

```
ath10k_snoc: qmi chip_id 0x30214 chip_family 0x4001 board_id 0xff soc_id 0x40010002
ath10k_snoc: qmi fw_version 0x110f01a0 ... QCAHLSW8998MTPLZ-1.221535.1
```

`board_id` is `0xff` where it was `0`, and that is the genuine msm8998 WLAN
firmware string.

**But I called it "the correct fix rather than a workaround" and that was too
strong.** Roughly 2.5 s after QMI init the modem watchdogs, every time:

```
[112.423764] qcom-q6v5-mss: watchdog received: SFR Init: wdog or kernel error suspected.
[112.423833] remoteproc0: crash detected in 4080000.remoteproc: type watchdog
[115.167744] qcom_icc_rpm_smd_send mas 35 error -110
```

Reproduced identically in CONN-V2 (109.96 s QMI -> 112.42 s watchdog), CONN-V3
and CONN-V4 (398.20 s QMI -> death). WCN3990's firmware runs behind MPSS on
SNOC, so the modem going down takes Wi-Fi with it, and the failed halt kills
the boot.

The natural reading is that the MSA ownership handshake is **required** -- the
modem needs that memory assigned to it, and skipping the SCM call leaves it
without access. So the `-22` has to be *solved*, not skipped. Since
`qcom_scm_assign_mem()` performs no argument validation that could produce
`-22`, the rejection comes from the firmware, which points at the request
itself: the regions come from the modem's own `msa_info` response, and the
VMID set depends on `mem_info->secure`.

### A hypothesis I tested and disproved

I expected read-only `rmtfs` to be the cause -- the modem unable to write its
EFS. The log does not support it. There are no denied writes, only reads and
two files that do not exist on this device:

```
[RMTFS] open /boot/modem_fsc => 3 (0:0)
[RMTFS] open /boot/modem_fsg_oem_1 => -1 (1:1)
[RMTFS] open /boot/modem_fsg_oem_2 => -1 (1:1)
[RMTFS] alloc 0, 2097152 => 0x88f00000 (0:0)
```

Read-only `rmtfs` is therefore **not** established as the blocker, and lifting
it is not justified on this evidence. The boundary stays.

## 4. ADSP: enabled, probes, and its carveout is 3 MiB too small

`CONFIG_QCOM_Q6V5_PAS` was `=m`, so the node enabled by `e8e814140` had no
driver -- a second omission of mine, found only by checking rather than
assuming. With it built in:

```
[2.044011] remoteproc remoteproc1: adsp is available
```

Started manually with firmware from tmpfs (which sidesteps the initramfs
timing entirely), it gets as far as:

```
[86.450185] Booting fw image qcom/msm8998/joan/adsp.mdt, size 7260
[86.505299] qcom_q6v5_pas 17300000.remoteproc: segment outside memory range
[86.506552] can't start rproc adsp: -22
```

Parsing `adsp.mdt` (ELF32, extracted read-only from the device's own
`/vendor/firmware_mnt/image/`), excluding the hash segment and honouring the
`QCOM_MDT_RELOCATABLE` flag:

| | |
|---|---|
| loadable span | `0x91900000 - 0x93700000` |
| required size | `0x1e00000` = **30 MiB** |
| relocatable | yes |
| joan `adsp_mem` | `0x92b00000 + 0x1b00000` = **27 MiB** |

The image relocates, so the base does not matter; the **size** does. joan is
3 MiB short.

**Not fixed, deliberately.** Growing `adsp_mem` means moving `venus_mem`,
`mba_mem` and `slpi_mem` up behind it, and joan's own DT warns the layout
"cannot be changed one region at a time -- it moves as a chain". `mba_mem` is
part of the modem chain, and the modem currently works. Trading a verified
working modem for an untested audio path is not a call to make unattended.

Note also that even with the ADSP running there is still no sound card: joan
has no SLIMbus/WCD9341 topology at all. ADSP is necessary, not sufficient.

## 5. Camera

`CONFIG_VIDEO_QCOM_CAMSS=y` produces no `/dev/video*`, `/dev/media*` or
`/dev/v4l-subdev*`, and no CAMSS messages. joan has no CCI, CSIPHY or sensor
nodes in DT, so there is nothing for the driver to bind to. This is DT work,
not a driver problem.

## 6. Unchanged and still true

GPU runtime PM survives all of the above: `runtime_status=suspended`,
`runtime_suspended_time=98023`, and zero SError / panic / internal error with
the whole connectivity stack loaded.

## 7. State

| lane | state |
|---|---|
| GPU suspend | **PASS**, closed |
| Bluetooth | firmware loads at boot; address accepted; HCI init blocked on `0x204b`, fix `f9b6f2841` **built, awaiting boot** |
| Cellular | MSS + read-only rmtfs + full QMI table **PASS**; IPA firmware absent from rootfs; no registration attempted |
| Wi-Fi | QMI negotiates with real chip/board/fw data; **blocked** on the MSA handshake, which must be solved rather than skipped |
| Sound | ADSP probes; blocked on a 3 MiB carveout shortfall, then on absent board topology |
| Camera | blocked on absent DT topology |

## 8. UART speed hypothesis: tested and REJECTED

After the `0x204b` quirk let init advance to `0x2031` (LE Read Resolving List
Size, answered `-56` = `-EBADRQC`, HCI "Unknown HCI Command", though the
controller advertises it in `commands[34] & 0x40`), I read the three symptoms
together -- repeated `Frame reassembly failed (-84)`, a one byte command
complete where three are required, and a command answered as unknown that is
advertised -- as one underlying problem: bytes lost on the UART.

Supporting that: LG drives this port with the vendor high-speed UART driver
(`blsp1_uart3_hs`), while mainline uses `msm_serial` in UARTDM mode. The pin
configuration is byte-identical downstream (gpio45-48, drive-strength 2,
bias-disable), so the pins are not the difference; the 3 Mbps operating rate
looked like it.

I reverted my own quirk and lowered `max-speed` to 115200 to test it
(`CONN-V6-20260814T151311Z`, image
`9137930a6a0b7287b0b7afbef0ba90872dd07a85d55d8e6438b3268f03c7f9d4`).

**The hypothesis is wrong on both counts:**

```
[66.547157] Bluetooth: hci0: Frame reassembly failed (-84)
[66.548574] Bluetooth: hci0: Frame reassembly failed (-84)
[66.697691] Bluetooth: hci0: QCA Downloading qca/crbtfw21.tlv
[68.703308] Bluetooth: hci0: command 0xfc00 tx timeout
[68.703585] Bluetooth: hci0: QCA Failed to send TLV segment (-110)
[68.703902] Bluetooth: hci0: QCA Failed to request file: qca/crbtfw21.tlv (-110)
[68.817840] Bluetooth: hci0: Retry BT power ON:2
```

1. The frame reassembly errors occur at 66.5 s, **before** any rate change and
   at the initial speed. They are not caused by the 3 Mbps operating rate.
2. 115200 cannot push the 177 KB TLV firmware inside the command timeout, so
   lowering the rate breaks firmware download outright.

The frame errors therefore look like spurious bytes as the controller powers
up, not a data-integrity failure, and the `0x204b` / `0x2031` responses are
most likely genuine controller behaviour after all.

The tree is back to quirk + 3 Mbps (`f9b6f2841`), which is the furthest BT has
got. The revert churn was collapsed rather than shipped; the finding lives
here.

### What `0x2031` needs

`hci_le_read_resolv_list_size_sync()` is gated only on
`hdev->commands[34] & 0x40` and has no quirk, so a fix means adding one, in the
established style of `HCI_QUIRK_BROKEN_READ_ENC_KEY_SIZE` /
`_READ_VOICE_SETTING` / `_READ_PAGE_SCAN_TYPE`.

**Not done deliberately.** Setting such a quirk for the whole WCN399x family
would disable LL privacy on sdm845 boards where this controller works today,
and there is no hardware here to check that against. It needs either a
narrower key than "WCN399x", or testing on another WCN3990 device. The same
caution applies retrospectively to `f9b6f2841`: it is device-verified on joan
and follows existing practice, but it has not been checked for regression on
other WCN399x boards.

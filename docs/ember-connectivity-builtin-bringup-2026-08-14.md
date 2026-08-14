# Connectivity bring-up from a RAM boot: Bluetooth up, cellular QMI up, Wi-Fi to MSA

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-14

Run `CONN-BUILTIN-20260814T115115Z`, image
`ae93ecfb2663971819f84a9c5c87cdb1e3ba5f16dc2320d0cdd967caf8635b5a`.
Evidence in `~/joan-images/evidence/CONN-BUILTIN-20260814T115115Z/` on nym-nest
(`conn-bringup.txt`, `final-dmesg.txt`).

No association, no pairing, no cellular registration, no provisioning write, no
transmission test. `rmtfs` was run **read-only** (`-r`). Nothing was written
outside tmpfs on the device and no partition was flashed.

## 1. The blocker was never the kernel: it was module deployment

Aurel's handoff treats Wi-Fi as blocked on the userspace firmware service
chain. The more basic blocker is that **a RAM-booted kernel can never load any
module**: the pmOS rootfs has no `/lib/modules/<release>` for it, and each RAM
boot has a different release string. `lsmod` returned nothing at all -- no
`cfg80211`, `bluetooth`, `ath10k_snoc`, `qrtr` or `ipa`.

Installing a module tree means writing to the SD card, which is outside the
RAM-only authorization. **It is not necessary.** Building the drivers in
sidesteps it completely:

```
CONFIG_CFG80211=y  CONFIG_MAC80211=y  CONFIG_RFKILL=y
CONFIG_ATH10K=y    CONFIG_ATH10K_SNOC=y
CONFIG_BT=y        CONFIG_BT_HCIUART=y  CONFIG_BT_QCA=y
CONFIG_QCOM_IPA=y  CONFIG_WWAN=y
CONFIG_QCOM_PD_MAPPER=y  CONFIG_QCOM_PDR_HELPERS=y  CONFIG_QCOM_PDR_MSG=y
```

`CONFIG_QCOM_PD_MAPPER` deserves a note: the handoff lists a **userspace**
`pd-mapper` as a required part of the chain. This tree has an **in-kernel** PD
mapper, so that dependency is gone. It was `=m` like everything else.

## 2. All required firmware was already on the rootfs

A direct inventory of the running pmOS:

```
/lib/firmware/qca/                       crbtfw21.tlv, crnv21.bin
/lib/firmware/qcom/msm8998/joan/         mba.mbn, modem.mdt, modem.b0*, wlanmdsp.mbn
/lib/firmware/ath10k/WCN3990/hw1.0/      board.bin
```

`rmtfs`, `qrtr-lookup` and `/dev/qcom_rmtfs_mem1` are all present too. The
staged host payload (`out/audit-20260813/connectivity-transient-userspace/`)
was not needed for any of this.

**Caution recorded against myself:** pushing a generic `board-2.bin` into
`/tmp` and pointing `firmware_class.path` at it made things *worse* -- ath10k
found the generic file, failed to match `qmi-board-id=0,qmi-chip-id=0`, and
never fell back to joan's own `board.bin`. Prefer the rootfs firmware.

## 3. Bluetooth: controller brought up successfully

The boot-time attempt fails:

```
[1.233410] Bluetooth: hci0: QCA Downloading qca/crbtfw21.tlv
[1.767799] bluetooth hci0: Direct firmware load for qca/crbtfw21.tlv failed with error -2
```

`-2` is ENOENT, and the file plainly exists. The cause is timing: the QCA
setup runs at **1.77 s**, while the rootfs is not mounted until ~10 s
("Switching root" at 10.03 s). The driver requests firmware from the
initramfs, gets nothing, and never retries.

Rebinding the serdev once the rootfs is up succeeds completely:

```
[184.881402] Bluetooth: hci0: QCA Downloading qca/crbtfw21.tlv
[185.696484] Bluetooth: hci0: QCA Downloading qca/crnv21.bin
[185.739163] Bluetooth: hci0: QCA TLV with error stat 0x0 rtype 0x4 (0x5)
[185.746124] Bluetooth: hci0: QCA setup on UART is completed
```

Controller identity read back from the hardware, both times:

```
QCA Product ID    : 0x0000000a
QCA SOC Version   : 0x40010214
QCA ROM Version   : 0x00000201
QCA Patch Version : 0x00000001
QCA controller version 0x02140201
```

`rfkill0 type=bluetooth soft=0 hard=0`, `hci0` present. The rebind is:

```sh
echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/unbind
echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/bind
```

**Status:** controller initialises and firmware loads. Not yet done: HCI UP and
passive discovery -- `hciconfig`/`btmgmt` are not installed in this rootfs, and
joan's all-zero BD address still leaves the controller `HCI_UNCONFIGURED`
(see `ember-handoff-2026-08-09-bt-unconfigured-root-cause.md`).

**Real fix for the timing bug**, none of which needs an SD write:
`CONFIG_EXTRA_FIRMWARE` to build `qca/crbtfw21.tlv` and `qca/crnv21.bin` into
the kernel image. That resolves it at any probe time.

## 4. Cellular: modem up with a full QMI service table

MSS boots from the rootfs firmware with no help:

```
[85.883450] Booting fw image qcom/msm8998/joan/mba.mbn, size 230056
[85.988808] qcom-q6v5-mss: MBA booted without debug policy, loading mpss
[87.362728] remote processor 4080000.remoteproc is now up
```

With read-only `rmtfs` started, `qrtr-lookup` returns a populated service
table, including:

| svc | node | service |
|---|---|---|
| 3 | 51 | Network Access Service |
| 1 | 56 | Wireless Data Service |
| 11 | 55 | User Identity Module service |
| 9 | 50 | Voice service |
| 2 | 77 | Device Management Service |
| 16 | 80 | Location service |
| 14 | 14 | Remote file system service |
| **69** | **84** | **ATH10k WLAN firmware service** |

That covers the handoff's cellular acceptance list -- MSS running, read-only
rmtfs, QRTR service table -- and it independently answers the open Wi-Fi
question: **WLFW service 69 is present.** (It is service *id* 69 on node 84;
node 69 is the unrelated Wireless Messaging Service. Worth stating plainly
because the handoff refers to it as "service 69" throughout.)

Not done: IPA setup (`ipa_fws.mdt` hits the same initramfs timing problem) and
ModemManager enumeration. No registration was attempted.

## 5. Wi-Fi: reaches firmware load and wlan0, then fails on MSA permissions

With MSS running, rmtfs read-only and tqftpserv running, `ath10k_snoc` binds
and gets a long way:

```
[297.553773] ath10k_snoc: wcn3990 hw1.0 target 0x00000008 chip_id 0x00000000
[297.553916] firmware ver 1.0.0.695 api 5 features wowlan,mgmt-tx-by-reference,non-bmi
[297.653772] htt-ver 3.71 wmi-op 4 htt-op 3 cal file max-sta 32
[297.785082] invalid MAC address; choosing random
```

**`wlan0` appears.** Then:

```
[301.171596] firmware crashed! (guid df4a55a6-...)
[304.008773] failed to assign msa map permissions: -22
[304.008784] qmi not waiting for msa_ready indicator
[304.011189] failed to download board data file: 90
[309.325096] failed to start hw scan: -108
```

`-22` from `qcom_scm_assign_mem()` on the Modem Shared Area is the primary
fault; everything after it is downstream of the firmware crash. A second
rebind then gets `msa info req rejected: 90`, because the WLAN firmware
service keeps state from the crashed session -- **re-binding without
restarting the modem is not a valid retry.**

### Leading hypothesis for the MSA failure

`msm8998.dtsi`'s `wifi@18800000` has `memory-region = <&wlan_msa_mem>`, and
joan's own DT comments record that mainline's `gpu_mem`/`wlan_msa` addresses
(`0x95600000`/`0x95700000`) collide with LG's reserved ranges and were moved
(`msm8998-lge-joan.dts:84-89`, and the note at line 871 that the range covers
`ipa_fw_mem`, `ipa_gsi_mem` and `wlan_msa_mem`). If `wlan_msa_mem` now sits
where TZ will not grant the assignment, `qcom_scm_assign_mem()` returns
`-EINVAL` exactly as seen.

Next step: compare joan's relocated `wlan_msa_mem` base/size against the
downstream `msm8998` reserved-memory map, and against what the TZ protected
region table allows -- the same table already extracted for the Card 94 XPU2
work.

## 6. Reproduction recipe (RAM-only, no persistent writes)

1. RAM boot the connectivity-built-in kernel.
2. `echo start > /sys/class/remoteproc/remoteproc0/state`  (MSS)
3. `rmtfs -r -P -v &`  (**`-r` read-only is required**)
4. `qrtr-lookup` to confirm the service table
5. Bluetooth: unbind/bind `serial0-0` on `hci_uart_qca`
6. Wi-Fi: unbind/bind `18800000.wifi` on `ath10k_snoc` -- once only

Do **not** set `firmware_class.path`; the rootfs firmware is correct and
complete.

## 7. Status against the handoff's acceptance boundaries

| lane | state |
|---|---|
| Bluetooth | controller init + firmware load **PASS**; HCI UP / passive discovery blocked on missing userspace tools and the unconfigured BD address |
| Cellular | MSS running, read-only rmtfs, QRTR service table **PASS**; IPA and ModemManager not done; no registration attempted |
| Wi-Fi | modules/rails/service-69/firmware/`wlan0` all reached; **blocked** at MSA permission assignment |
| Media | not started |

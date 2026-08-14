# Ember handoff, 2026-08-14: GPU suspend closed; connectivity lane-by-lane state

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-14

Supersedes the open items in
`aurel-handoff-2026-08-13-to-next-session-lg-v30-gpu-connectivity.md`.
Detail lives in:

- `ember-card94-suspend-unblocked-and-smmu-residency-2026-08-14.md`
- `ember-connectivity-builtin-bringup-2026-08-14.md`
- `ember-connectivity-round2-2026-08-14.md`

Eleven RAM-only boots. No partition ever flashed. `rmtfs` read-only
throughout. No Wi-Fi association, no BT pairing or connection, no cellular
registration or provisioning write, no transmission test, no audio playback or
capture, no camera capture. Phone ends on LineageOS, `sys.boot_completed=1`,
adbd at uid 2000, no fastboot client.

## 1. GPU runtime suspend: CLOSED

`IDLE_GATE=PASS`, all eighteen checks, boot `dbe4e7ab...`
(`A540-OPPVOTE-20260814T111613Z`). `runtime_suspended_time` 39766 -> 313957
across two captures, `runtime_status=suspended` at both, `gpu_gx off-0` with
`gpu_cx on`, and **PM8005 S1 use count 0** -- every consumer releases VDD_GFX
with the GPU idle. joan previously had to pin that rail with
`regulator-always-on`.

Series on `joan/a540-suspend-hwinit-gate`, base final-v4 `76d180923`:

```
ea1cdd7e2 drm/msm/adreno: skip the A540 collapse gate when the GPU was never initialised
ab2b6869a iommu/arm-smmu: only skip the retained part of the reset on resume
521c2fe50 iommu/arm-smmu-qcom: keep the MSM8998 Adreno SMMU resident
d63fa520b dt-bindings: iommu: arm-smmu: allow the GFX bus source clock on MSM8998
b9e50b685 arm64: dts: qcom: msm8998: give the Adreno SMMU the GFX bus source clock
88dbc4e26 drm/msm/adreno: release the OPP core's supply vote on runtime suspend
```

Still holds with the whole connectivity stack loaded: `runtime_status=suspended`,
`runtime_suspended_time=98023`, zero SError / panic / internal error.

## 2. Connectivity commits on top (device-tested, not closed)

```
10101704e arm64: dts: qcom: msm8998: skip the WLAN MSA ownership reassignment
e8e814140 arm64: dts: qcom: msm8998-lge-joan: enable the ADSP
f9b6f2841 Bluetooth: hci_qca: mark LE Read Transmit Power broken on WCN399x
```

All checkpatch `--strict` 0/0/0. Config for the connectivity images differs
from the GPU config deliberately: the connectivity drivers are built **in**
(`=y`) because a RAM-booted kernel can never load a module -- the pmOS rootfs
has no `/lib/modules/<release>` for it and every boot has a different release
string. This removes the need for any SD-card write.

## 3. Lane state

| lane | verdict |
|---|---|
| GPU suspend | **PASS**, closed |
| Cellular | **PASS** for the stated scope |
| Bluetooth | controller up, HCI init blocked at `0x2031` |
| Wi-Fi | blocked at the MSA handshake |
| Sound | blocked: `adsp_mem` 3 MiB short, then no board topology |
| Camera | blocked: no DT topology |

### Cellular -- PASS for scope

MSS boots from `qcom/msm8998/joan/mba.mbn`; read-only `rmtfs` runs;
`qrtr-lookup` returns a full QMI table including Network Access (3), Wireless
Data (1), UIM (11), Voice (9), DMS (2), Location (16), rmtfs (14) and **ATH10k
WLAN firmware service, id 69, node 84**. That last one settles the handoff's
open "service 69" question -- it is the service *id*, not the node.

Not done: IPA firmware (`ipa_fws.mdt`) is absent from the rootfs; it exists in
the device's `/vendor/firmware_mnt/image/` and was not pulled. ModemManager
enumeration untested.

### Bluetooth -- furthest it has ever got

Firmware loads **at boot** (2.21 s) with
`CONFIG_EXTRA_FIRMWARE="qca/crbtfw21.tlv qca/crnv21.bin"`. Controller
identifies (`QCA controller version 0x02140201`), mgmt shows one unconfigured
controller at index 0, manufacturer 0x001d, `missing_options` =
`MGMT_OPTION_PUBLIC_ADDRESS`, and `SET_PUBLIC_ADDRESS` is accepted -- exactly
the flow joan's DT comment describes.

With an address supplied, init reaches LE feature discovery and stops at
`0x2031` (LE Read Resolving List Size), answered `-EBADRQC` although the
controller advertises it. No quirk exists for that command.

**Deliberately not fixed.** A quirk keyed on the WCN399x family would disable
LL privacy on sdm845 boards where this controller works today, and there is no
second WCN3990 device here to check against. The same caveat applies to
`f9b6f2841`: device-verified on joan, following the existing `btbcm`/`btusb`
pattern, but unverified for regression elsewhere.

The proper fix for the firmware *timing* is the firmware in the pmOS
initramfs -- pmaports packaging, not kernel. `EXTRA_FIRMWARE` is a test
vehicle.

### Wi-Fi -- one clear blocker

`qcom,msa-fixed-perm` removes `failed to assign msa map permissions: -22` and
QMI then negotiates with real data (`chip_id 0x30214`, `board_id 0xff`,
`QCAHLSW8998MTPLZ`), and `wlan0` appears. But ~2.5 s later the **modem**
watchdogs, every time, taking WCN3990 down with it because its firmware runs
behind MPSS on SNOC.

So the MSA ownership handshake is **required**, and the `-22` must be solved
rather than skipped. `qcom_scm_assign_mem()` does no argument validation that
could return `-22`, so the rejection is the firmware's; the request itself is
the thing to examine -- the regions come from the modem's `msa_info` response
and the VMID set depends on `mem_info->secure`.

Read-only `rmtfs` was **tested and disproved** as the cause: its log shows no
denied writes, only reads and two files absent on this device. The boundary
stays.

## 4. Hypotheses I tested and rejected -- do not re-run

- **sCR0/CLIENTPD** as the cause of the first Card 94 reset. The same boot's
  counters show ~28 s of successful collapse/resume cycles under that code.
- **Read-only `rmtfs`** as the cause of the modem watchdog. Log shows no denied
  writes.
- **UART rate** as the cause of the BT command failures. Frame reassembly
  errors occur at the *init* speed before any rate change, and 115200 cannot
  push the 177 KB TLV firmware inside the command timeout -- lowering the rate
  breaks download outright.
- **`qcom_scm_restore_sec_cfg()`** for the Adreno SMMU: downstream returns
  early unless static-cb, and the kgsl SMMU is not.
- **The perf-counter PM race** (`9826045a4`): inert on a5xx, `gpu->perfcntrs`
  is never allocated.

## 5. Mistakes of mine worth knowing about

- mgmt opcodes in my helper were wrong (`SET_PUBLIC_ADDRESS` is `0x0039`, not
  `0x0024`); the resulting `0x11` failures were mine, not the device's.
- `CONFIG_QCOM_Q6V5_PAS` left `=m`, so the ADSP node I enabled had no driver.
- Staged a generic `board-2.bin` into tmpfs, which shadowed joan's correct
  `board.bin` on the rootfs and made ath10k worse.
- Ran verification as one long SSH session; two boots produced zero-byte
  results when the device reset mid-run. Fixed with `stage.sh`.
- Leaked the device password into a transcript by dropping the `sed`
  redaction the wrapper scripts use. Scrubbed from the evidence file.

## 6. Next steps, in the order I would take them

1. **Wi-Fi**: instrument `ath10k_qmi_setup_msa_permissions()` to print the
   regions the modem reports and their `secure` flag, then compare with what
   TZ will accept. That is the one blocker between here and `wlan0` scanning.
2. **Bluetooth**: decide the `0x2031` quirk's key. Needs either a narrower
   condition than "WCN399x" or a second WCN3990 device to regression-test.
3. **Sound**: `adsp_mem` needs 30 MiB, has 27. Growing it moves `venus_mem`,
   `mba_mem` and `slpi_mem`, and `mba_mem` is in the working modem's chain --
   plan the whole map before touching it. Then the board's SLIMbus/WCD9341
   topology, which does not exist yet.
4. **Camera**: CCI/CSIPHY/sensor DT topology from scratch.
5. **IPA**: pull `ipa_fws.*` from `/vendor/firmware_mnt/image/` as was done for
   `adsp.*`.

## 7. Reproduction

RAM boot a connectivity-built-in image, then, with nothing written outside
tmpfs:

```sh
echo start > /sys/class/remoteproc/remoteproc0/state   # MSS
rmtfs -r -P -v &                                       # -r is required
qrtr-lookup                                            # QMI table
echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/unbind && \
echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/bind
btup <addr>                                            # mgmt SET_PUBLIC_ADDRESS
echo 18800000.wifi > /sys/bus/platform/drivers/ath10k_snoc/bind   # once only
```

Do **not** set `firmware_class.path`; the rootfs firmware is correct and
complete. Re-binding ath10k without restarting the modem is not a valid retry:
the WLAN service keeps state and answers `msa info req rejected: 90`.

Helpers on nym-nest in `~/joan-images/staging/`: `stage.sh` (one stage, fetch
immediately), `btup` (static aarch64 mgmt helper), `read-pstore-partition.sh`.

# Wi-Fi on joan: wlan0 up, passive scan working

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-14

Run `WIFI-20260814T183233Z`, image
`7d7280e2626a7d2d614c4ad0091d949ed12d177c15d5c0c80f218edf3b599e35`.
RAM boot only, `rmtfs` read-only, **no association** -- the wpa_supplicant
instance has no network blocks at all, so associating is impossible by
construction, and the scan is configured `passive_scan=1`.

## Result

```
3: wlan0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 ... link/ether c2:ee:ce:12:e6:1d

bssid              freq  signal  flags                          ssid
00:90:a9:13:52:28  5785  -58     [WPA2-PSK-CCMP][ESS][UTF-8]    LG's Wifi 5GHz
00:90:a9:13:52:26  2462  -39     [WPA2-PSK-CCMP][ESS][UTF-8]    LG's Wifi
80:d0:4a:83:21:7e  2462  -52     [WPA2-PSK-CCMP][WPS][ESS]      Riverhut
...
63 BSSs across 2.4 GHz and 5 GHz

wpa_state=DISCONNECTED
```

Against the handoff's acceptance boundary: matching driver present (built in),
WLFW service (id 69) appears, `ath10k_snoc` binds, `wlan0` appears, passive
scan succeeds, no association. Lane met.

## The `-22` was a retry artefact, not a TZ rejection

Every earlier boot showed:

```
ath10k_snoc: failed to assign msa map permissions: -22
```

followed ~2.5 s later by a modem watchdog that took WCN3990 down with it. I
spent several boots treating that as the secure world refusing the
assignment, and "fixed" it with `qcom,msa-fixed-perm` -- which skips the SCM
call entirely. **That was wrong, and it was the reason the modem kept
crashing:** the modem was being asked to use an MSA it did not own.

A per-region diagnostic settled it. On a fresh modem both regions assign
cleanly:

```
JOAN-MSA: region 0 addr=0x95700000 size=16384   secure=1 -> rc=0
JOAN-MSA: region 1 addr=0x95704000 size=1032192 secure=0 -> rc=0
```

and on a second attempt in the same boot, both fail:

```
JOAN-MSA: region 0 ... -> rc=-22
JOAN-MSA: region 1 ... -> rc=-22
```

`ath10k_qmi_map_msa_permission()` always passes `src_perms =
BIT(QCOM_SCM_VMID_HLOS)`. After the first successful assignment the memory
belongs to MSS_MSA/WLAN, so HLOS is no longer a valid source and the firmware
returns EINVAL. Every `-22` I recorded came after an earlier bind attempt in
the same boot.

The comparison that should have told me sooner: `rmtfs_mem` makes the *same*
`qcom_scm_assign_mem()` call for a 2 MiB `no-map` region at `0x88f00000` with
`qcom,vmid = MSS_MSA`, and it succeeds on joan every boot. The SCM call was
never the problem.

`qcom,msa-fixed-perm` is reverted. `qcom,no-msa-ready-indicator` stays -- it
is upstream's and correct; removing it made ath10k wait for an indication
msm8998's modem never sends, and the bring-up stalled instead.

## Second blocker: the ath10k metadata file is not on the rootfs

With permissions assigned the modem stays up and ath10k fails plainly:

```
Failed to find firmware-N.bin (N between 2 and 6) from ath10k/WCN3990/hw1.0: -2
could not probe fw (-2)
```

The rootfs carries only `board.bin` in that directory. `firmware-5.bin` is a
60-byte `QCA-ATH10K` container holding API/feature metadata -- the actual
WCN3990 firmware comes from the modem over TFTP via `tqftpserv` -- and it must
exist *before* the QMI handshake, so setting `firmware_class.path` afterwards
cannot help. Provided here through `CONFIG_EXTRA_FIRMWARE`.

As with Bluetooth's `crbtfw21.tlv`, embedding is a test vehicle; the proper
home for this file is the pmOS rootfs or initramfs (pmaports packaging), not
the kernel image.

## A real upstream bug found on the way

**`ath10k_snoc` leaves the MSA assigned to the modem when probe fails after
the assignment succeeded.** Nothing unmaps it, so every later attempt gets
`-22` from a stale source VMID and WLAN cannot recover without restarting the
SoC. This is what made a simple ordering problem look like a hard secure-world
rejection for several boots.

`ath10k_qmi_setup_msa_permissions()` does unwind within its own loop
(`err_unmap`), but a failure further along the probe path -- the missing
firmware file, for instance -- does not unwind the permissions.

## Known-not-done

- A modem `fatal error` crash still occurs during bring-up
  (`remoteproc0: crash detected ... type fatal error` at ~114 s). ath10k
  logs `device successfully recovered` and scanning works afterwards, so it
  is not fatal to the lane, but it is not understood and should be chased.
- `board_file api 1 bmi_id N/A crc32 00000000` -- the board data checksum is
  zero, worth confirming the right `board.bin` variant is being applied.
- No association was attempted, by design.

## Follow-up: the modem crash, and why waiting for MSA_READY is not the answer

The residual `board_file ... crc32 00000000` turned out to be a **symptom, not a
bug**: `ath10k_core_free_board_files()` is called from
`ath10k_qmi_event_server_exit()`, so every modem crash frees the board data and
the next info print simply finds `normal_mode_fw.board` NULL. Fix the crash and
it resolves itself.

The modem prints its own crash reason; my earlier greps just never matched it:

```
qcom-q6v5-mss 4080000.remoteproc: fatal error received:
    err_qdi.c:450:EX:wlan_process:1:WLAN RT:1075:PC=b01c4d3c
```

An exception inside the modem's **`wlan_process`**, looping every 20-28 s
(crash -> MBA -> mpss -> crash).

### Ruled out

- **Wrong WLAN firmware over TFTP.** `/lib/firmware/wlanmdsp.mbn` is 3,055,364
  bytes, the same as joan's own `/lib/firmware/qcom/msm8998/joan/wlanmdsp.mbn`,
  and `tqftpserv` logs a completed transfer. Correct image.
- **ath10k debug tracing.** Compiled out (`kconfig debug 0`); would need a
  rebuild.

### Tested: removing `qcom,no-msa-ready-indicator`

The property makes ath10k synthesise `msa_ready` on SERVER_ARRIVE instead of
waiting for the modem. It predates the MSA assignment working, so with the
assignment now succeeding it was worth retesting whether the modem sends the
real indication.

Image `770b65510c53daefd1e39aa9e7ea62847abffbfe607a660093afdd4a145b39bf`,
run `WIFI2-20260814T221422Z`:

| `qcom,no-msa-ready-indicator` | modem | Wi-Fi |
|---|---|---|
| present | crashes/recovers every 20-28 s | `wlan0` up, 63-BSS passive scan |
| **absent** | **zero crashes** | never comes up at all |

Without it, QMI negotiates at 84.7 s and then nothing further happens --
checked again at 221 s uptime: no `wlan0`, no ath10k messages, zero crashes.
A permanent stall.

**msm8998's modem does not send the MSA_READY indication even when the MSA is
correctly assigned.** The property is right for this SoC and stays. Reverted.

So the crash is a separate defect, not a consequence of skipping the wait. Next
candidates, untested:

- a delay between `ath10k_qmi_event_server_arrive()` and the synthesised
  `ath10k_qmi_event_msa_ready()`, to let the modem finish its own MSA setup
  before board data arrives;
- `CONFIG_ATH10K_DEBUG=y` to see the BDF download and host-cap exchange, which
  is where the modem-side WLAN task would object;
- comparing the host capability payload against downstream, given
  `qcom,snoc-host-cap-8bit-quirk` already exists for this SoC.

Note the crash is not fatal to the lane -- ath10k logs `device successfully
recovered` and the passive scan works -- but it would disrupt cellular and
should be closed before anyone calls Wi-Fi finished.

### Correction: IPA firmware is present

An earlier note said `ipa_fws.mdt` was absent from the rootfs. That was wrong:
`/lib/firmware/ipa_fws.mdt` and `ipa_fws.b0*` are present at the top level. I
had only listed the `qcom/msm8998/joan/` subdirectory.

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

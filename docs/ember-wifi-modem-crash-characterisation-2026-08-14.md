# The WCN3990 modem crash: characterisation, and what is ruled out

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-14

Run `WIFIDBG-20260814T225102Z`, image
`5484b4ff00dc8a0eebd29d7870dcea0880efb2db5ff4c9406fbd82e6d89d9be0`
(`CONFIG_ATH10K_DEBUG=y`, debug_mask enabled **before** MSS start so the whole
QMI exchange is captured). RAM boot only; the modem partition was mounted
**read-only**; nothing was written to any device partition.

## The fault

```
qcom-q6v5-mss 4080000.remoteproc: fatal error received:
    err_qdi.c:450:EX:wlan_process:1:WLAN RT:1075:PC=b01c4d3c
```

**Identical PC on every occurrence.** Deterministic, not a race.

## Established

1. **It requires the WLAN firmware to be running.** In the boot where ath10k
   stalled before BDF download (waiting for MSA_READY), there were zero
   crashes across several minutes.
2. **It is independent of host Wi-Fi activity.** Crash rate with
   `wpa_supplicant` killed and no scanning at all was the *highest* measured.
3. **ath10k recovers every time** (`device successfully recovered`), which is
   why Wi-Fi stays usable and a 63-BSS passive scan still completes.

Rates, measured with the monotonic `handling crash #N` counter:

| condition | crashes | window |
|---|---|---|
| full-band scan | 6 | 50 s |
| 2.4 GHz only | 4 | 50 s |
| idle, no scanning at all | 8 | 75 s |
| rmtfs read-write to a tmpfs store | 5 | ~170 s |

## Correction: my DFS / U-NII-2C finding was an artefact

I first reported the crash as triggered by scanning the U-NII-2C band
(5470-5725 MHz, ch 100-144), based on the trace showing the fault ~95 ms after
scan events on 5660-5720 MHz, and on three "delta=0" results from restricted
scans.

**That was wrong.** Those deltas were measured with
`dmesg | grep -c "fatal error received"`, which is unreliable: the dmesg ring
wraps, and not every crash prints the SFR string. Once I switched to the
monotonic `handling crash #N` counter and ran a **positive control** (full-band
scan: counter 30 -> 36), the restricted-band runs also showed crashes, and the
idle no-scan baseline showed the highest rate of all.

The methodological failure was running three negative controls before
establishing that the failure reproduced under my measurement at all.

## Ruled out

- **Scanning, and any particular band.** See above.
- **Wrong board data.** Our `board.bin` is md5 `8c5e6060d42f9bc4b28e686081a6df0b`,
  byte-identical to LG's `bdwlan.bin`. LG ships twelve variants
  (`.102 .104 .105 .106 .108 .b04 .b07 .b09 .b0a .b0b .b33 .bin`), and
  `board_id 0xff` from QMI matches none of them, so the default is exactly what
  downstream would also select.
- **Wrong WLAN firmware.** `/lib/firmware/wlanmdsp.mbn` is 3,055,364 bytes,
  identical to joan's own copy; `tqftpserv` logs a completed transfer.
- **Missing MSA_READY handling.** Waiting for the real indication stops the
  crash only by preventing WLAN from starting at all (permanent stall).
- **The LG OEM FSG partition requests.** See below.

## The `modem_fsg_oem_1/2` requests are a red herring

The modem repeatedly asks for `/boot/modem_fsg_oem_1` and `_2`, and rmtfs logs
`request for unknown partition ..., rejecting`. Tempting, but not the cause:

- joan has **no such partitions**. Its labels are `fsc`, `fsg`, `modemst1`,
  `modemst2` (checked in `/dev/disk/by-partlabel`). LG's own stock software
  must therefore fail these same requests, and stock Wi-Fi works.
- In upstream rmtfs, `storage_open()` returns `NULL` both for an unknown path
  and for a file that fails to open, and the caller turns that single `NULL`
  into one error:

  ```c
  rmtfd = storage_open(pkt->node, req.path, slot_suffix);
  if (!rmtfd)
          qmi_result_error(&resp.result, QMI_RMTFS_ERR_INTERNAL);
  ```

  So adding a table entry changes nothing the modem can observe, unless we also
  supply file content we do not have.

### Upstream precedent, for the record

rmtfs already carries vendor-specific entries and accepts them upstream
(HEAD `b30a3eb`, "Merge pull request #33 from schabimperle/oneplus-oppo-oem-nv"):

```c
{ "/boot/modem_study",   "modem_study",   "study"       },
{ "/boot/modem_tunning", "modem_tunning", "tunning"     },
/* OnePlus/Oppo OEM NV backup partitions */
{ "/oem/nvbk/static",    "oem_stanvbk",   "oem_stanvbk" },
{ "/oem/nvbk/dynamic",   "oem_dycnvbk",   "oem_dycnvbk" },
/* Some OxygenOS firmware versions request this alternative path */
{ "/oppo/oem_partion",   "oem_stanvbk",   "oem_stanvbk" },
```

The difference is that OnePlus's `oem_stanvbk` is a real partition on those
devices. An analogous joan patch would be cosmetic.

## rmtfs read-write: real effect, unproven meaning

Running rmtfs in directory mode against a tmpfs store (`-o /tmp/rmtfs-store`,
populated by reading the real partitions, no `-r`) cut the crash rate roughly
3.6x versus read-only partition mode.

**Do not over-read this.** The fault PC is identical in both modes, so the
change plausibly alters how quickly the modem re-initialises between crashes
rather than bringing us closer to a fix. It is a rate change, not a fix.

Note this is a safe way to give the modem write capability without touching
device partitions: the store lives in tmpfs, so nothing persists and the
"no modem NV writes" boundary is preserved.

## Remaining leads, ranked

1. **The missing `cnss-daemon` equivalent.** ath10k sends
   `host_cap.daemon_support = 0`. Downstream runs a WLAN daemon that services
   the firmware. Worth checking what that daemon does that nothing does here.
2. **`/persist`.** joan has a `persist` partition holding WLAN MAC/calibration
   on stock. It is not mounted or served in our environment.
3. **Decode the fault.** `WLAN RT:1075` and `PC=b01c4d3c` are in the modem
   image; the `wlanmdsp.mbn` we already have could in principle be examined.
4. **A second WCN3990 device** (sdm845 class) to see whether mainline shows the
   same crash there, which would separate "joan-specific" from "mainline
   WCN3990-wide".

## Follow-up: serving the OEM NV-backup paths does not help

Lance asked whether `_oem` is simply dropped from the naming, i.e. whether
`modem_fsg_oem_1` is really just `fsg`. The request log says no -- the modem
asks for both, as distinct objects:

```
9 x /boot/modem_fsg_oem_1     <- most requested of anything
7 x /boot/modem_fsg_oem_2
3 x /boot/modem_fs1
2 x /boot/modem_fsc
1 x /boot/modem_fsg           <- requested separately
1 x /oem/nvbk/static
1 x /oem/nvbk/dynamic
```

joan has no partition with "oem" in its label at all. The shape of these is
OEM NV-backup storage, LG's analogue of the OnePlus/Oppo `oem_stanvbk` /
`oem_dycnvbk` pair -- and notably this modem requests those OnePlus paths too.

Since `/oem/nvbk/static` and `/oem/nvbk/dynamic` are **already** in upstream
rmtfs's table, they can be served in directory mode with no patch at all.
Tested (`NVBK-20260814T231808Z`) with both files present in the tmpfs store:

- crash delta **3 over 90 s**, versus a read-only baseline of ~9.6/90 s --
  which merely reproduces the known read-write rate effect, not an
  improvement on top of it;
- **`/oem/nvbk/*` was requested zero times in that run**, so serving those
  files changed nothing. The single earlier request came from a different
  modem state.
- `/boot/modem_fsg_oem_1` and `_2` were still rejected, 9 times each.

So the OEM NV-backup hypothesis is **not supported**, and the earlier
observation of `/oem/nvbk/*` requests was not representative.

## Why the remaining rmtfs test is expensive

Testing `modem_fsg_oem_1/2` needs a `partition_table` entry, because
`storage_open()` rejects unknown paths before consulting the storage
directory. rmtfs links `-lqrtr -ludev -lpthread` and there is no aarch64
`libqrtr`/`libudev` in the cross sysroot here, so it means cross-building those
first. A binary patch is not viable either: the unused table entries
(`/boot/modem_study`, `/boot/modem_tunning`) are shorter strings than
`/boot/modem_fsg_oem_1`, so there is nowhere in-place to put it.

Weigh that against the fact that joan has no such partitions, so LG's own stock
software must fail these requests too while stock Wi-Fi works -- which argues
they are tolerated, not fatal.

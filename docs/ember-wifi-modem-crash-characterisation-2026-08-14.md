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

## The fault decoded: a bad pointer load, not an assert

With LLVM's Hexagon target (`llvm-mc --disassemble --arch=hexagon`), the
instruction at `PC=0xb01c4d3c` is reachable: joan's `wlanmdsp.mbn` is an ELF32
whose segment 3 covers `0xb0000000 + 0x25b5a4` at file offset `0x20000`, so the
PC sits at file offset `0x1e4d3c`. The packet there is:

```
{
	jump 0xec
	r2 = memw(r3+r2<<#0)      <- load from r3 + r2
}
```

**A memory load, not an explicit trap or assertion.** The WLAN process is
dereferencing a pointer that was never populated. That is the signature of
missing data rather than a logic error or a race, which is why the NV/storage
leads were worth pursuing.

(String-proximity analysis around the PC found nothing -- the region is pure
Hexagon code and the apparent "strings" are printable code bytes.)

## Tested and disproved: the LG OEM FSG partitions

To test this properly, upstream rmtfs was patched and cross-built:

- `storage.c`: added `/boot/modem_fsg_oem_1` and `_2` to `partition_table`,
  following the OnePlus/Oppo precedent already merged upstream.
- `sharedmem.c`: replaced libudev with direct `/sys/dev/char/<maj>:<min>/`
  reads, removing the dependency entirely. rmtfs only used udev to read two
  sysattrs.
- Built fully static with `aarch64-linux-gnu-gcc -static`, compiling libqrtr
  from source, because pmOS is musl and the cross toolchain is glibc, so
  linking against the device's shared libraries was not possible.

Patch and binary: `out/rmtfs-joan-oem-fsg.patch`, `out/rmtfs-joan`.

Result (`RMTFSOEM-20260814T232949Z`): the paths are now served correctly --

```
[RMTFS] open /boot/modem_fsg_oem_1 => 4 (0:0)
[RMTFS] open /boot/modem_fsg_oem_2 => 5 (0:0)
unknown-partition rejections: 0
```

-- and the crash rate is **unchanged**: delta 4 over 95 s, against a
read-write baseline of ~3 and a read-only baseline of ~10. **Serving the OEM
FSG partitions is not the fix.**

## Tested and disproved: the persist partition

`persist` mounted read-only contains only a directory skeleton and two marker
files:

```
5  /persist/rfs/msm/mpss/server_check.txt
15 /persist/rfs/shared/server_info.txt
2  /persist/sensors/sensors_settings
```

`rfs/msm/{adsp,cdsp,slpi,mpss}`, `rfs/mdm/*`, `hlos_rfs/shared` and `secnvm`
are all empty. There is no WLAN MAC file, no calibration blob, nothing the
WLAN firmware could be missing from here. This also means the empty
`/var/lib/tqftpserv/` we give tqftpserv is not materially different from
stock's `/persist/rfs/...`.

## Updated ruled-out list

- scanning, and any particular band
- board data (md5-identical to LG's default `bdwlan.bin`)
- the WLAN firmware image (`wlanmdsp.mbn`, byte-size identical, transfer completes)
- MSA-ready handling
- the OEM NV-backup paths `/oem/nvbk/*`
- **the LG OEM FSG partitions, with a patched rmtfs that actually serves them**
- **the persist partition, which holds no WLAN data**

## What is left

1. **The missing cnss-daemon equivalent.** ath10k sends
   `host_cap.daemon_support = 0`. Downstream runs a WLAN daemon. This is the
   last structural difference from stock that has not been examined.
2. **Deeper firmware analysis.** The faulting load is now located precisely;
   working out which structure `r3` should point to would need Hexagon RE
   against a 3 MB stripped image.
3. **A second WCN3990 device** to establish whether mainline crashes there too,
   separating "joan-specific" from "mainline WCN3990-wide".

The crash remains **not cleared**. Wi-Fi is usable in spite of it -- ath10k
recovers every time and a 63-BSS passive scan completes -- but the modem
restarts roughly every 10 s, which would disrupt cellular.

## Tested and disproved: the host capability message

The faulting instruction being a pointer load suggested the firmware's
capability structure might be built wrong at setup. msm8998 sends `host_cap`
with `qcom,snoc-host-cap-8bit-quirk`, which encodes `daemon_support` as 8 bits
instead of 64 -- a quirk written for sdm845-era firmware, and LG's MPSS build
is not that firmware.

ath10k also supports `qcom,snoc-host-cap-skip-quirk`, which sends **no host
capability request at all** ("Skip the host capability request for the firmware
versions which do not support this feature"). That is the sharpest available
discriminator, so it was tested rather than the encoding variant.

Result (`HOSTCAP-*`, msm8998.dtsi with `skip-quirk` in place of `8bit-quirk`):

- no host capability request was sent (`host capability` log count 0)
- `wlan0` still came up
- crash **delta 3 over 95 s**, identical to the read-write baseline
- same SFR, same `PC=b01c4d3c`

**The host capability message is not the cause.** DT reverted to
`qcom,snoc-host-cap-8bit-quirk`.

## Status

Everything cheaply testable has been eliminated:

| candidate | verdict |
|---|---|
| scanning / any specific band | ruled out (idle has the highest rate) |
| board data | ruled out (md5-identical to LG's default) |
| WLAN firmware image | ruled out (identical size, transfer completes) |
| MSA-ready handling | ruled out (waiting only prevents bring-up) |
| `/oem/nvbk/*` NV backup | ruled out (not even requested) |
| LG OEM FSG partitions | ruled out (patched rmtfs served them, no change) |
| persist partition | ruled out (contains no WLAN data) |
| host capability message | ruled out (skipped entirely, no change) |

What remains needs real investment, not another quick experiment:

1. **Hexagon reverse engineering.** The faulting load is located exactly
   (`0xb01c4d3c`, file offset `0x1e4d3c` in `wlanmdsp.mbn`). Establishing what
   `r3` should point to means working backwards through a 3 MB stripped image.
2. **A second WCN3990 device** (sdm845 class) to determine whether mainline
   crashes there too. That single data point would separate "joan/LG MPSS
   specific" from "mainline WCN3990-wide" and decide where the fix belongs.
3. **The cnss-daemon's behaviour beyond `daemon_support`** -- what services it
   actually provides to a running WLAN firmware on stock.

The crash is **not cleared**. Wi-Fi is usable regardless: ath10k recovers every
time and a 63-BSS passive scan completes. The cost is a modem restart roughly
every 10-30 s, which is fine for Wi-Fi but would disrupt cellular, so the two
lanes cannot currently be considered simultaneously working.

## Firmware substitution: INCONCLUSIVE, not negative

joan runs LG's `wlanmdsp.mbn` (3,055,364 B) where other mainline WCN3990
devices run their own vendor build. linux-firmware ships a generic image
(3,725,044 B). The two are genuinely different -- the `0xb0000000` code segment
is md5 `bc53992fe6df` (LG) vs `69102a4bacb1` (generic), with different segment
layouts entirely.

Bind-mounting the generic image over `/lib/firmware/wlanmdsp.mbn` (no
persistent write) and cold-starting MSS produced: `wlan0` up, tqftpserv serving
7 wlanmdsp requests, crash delta 3/95 s -- and **the same reported firmware
version (1.0.0.695) and the same fault PC**.

Two different code images cannot plausibly fault at an identical address, so
that result was treated as suspect rather than as a negative. A positive
control settled it:

```
bind-mounted 1024 bytes of /dev/urandom as wlanmdsp.mbn
tqftpserv wlanmdsp requests: 0
wlan0 still came up, firmware ver 1.0.0.695, still crashing
```

**On a modem restart the WLAN firmware is not re-fetched over TFTP at all.**
The modem reuses what it already holds, so every crash/recovery cycle runs the
same image regardless of what is on disk, and firmware substitution cannot be
tested this way.

Firmware is therefore **untested**, not ruled out. Testing it needs the
alternate image in place before the modem's first load of a cold boot, with a
positive control proving the swap took effect -- for instance a deliberately
corrupt image that must break bring-up.

Recorded because without the positive control this would have been filed as
"firmware ruled out", which would have been wrong.

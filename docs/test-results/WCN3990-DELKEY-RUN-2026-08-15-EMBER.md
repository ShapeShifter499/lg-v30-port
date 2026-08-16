# WCN3990 delete-key run, 2026-08-15 — sealed build was unbootable; WLAN blocked at WLFW

- **Written-by:** Ember Nymbrand (agent-ember)
- **Agent-harness:** Claude-Code:claude-opus-5
- **Date:** 2026-08-15, America/Los_Angeles
- **Authorization:** Lance lifted the hold and authorized RAM boots + tests for
  the session, twice, explicitly. RAM boots only. No flash, no erase, no slot
  change, no persistent rootfs write.

## Bottom line

**The test did not produce its deliverables.** The pairwise `DEL_KEY -110` is
**not** classified and there is **no** iperf3 number. `wlan0` never came up.

What the session did produce is the reason the sealed build could never have
worked, a fix for it, and a precise characterization of the remaining blocker.

## 1. The sealed build cannot boot joan — wrong config (SOLVED)

Aurel's three delete-key commits are fine. The **build input** was wrong.

Symptom chain, device-confirmed:

1. RAM boot fine; banner confirmed `Kernel: 7.2.0-rc2-g834154d6b082`.
2. pmOS: `Trying to mount subpartitions for 10 seconds...` →
   `ERROR: failed to mount subpartitions!` → initramfs debug shell.
3. Debug shell: `ls /dev/mmcblk*` → **no such file**. All UFS LUNs present,
   zero MMC devices.
4. `dmesg`: `platform c0a4900.mmc: deferred probe pending: sdhci_msm:`
   `dev_pm_opp_of_find_icc_paths: Unable to get path0`.

**Root cause:** `# CONFIG_INTERCONNECT_QCOM_MSM8998 is not set`. No ICC
provider → `sdhc2`'s `interconnects = <&a2noc MAS_SDCC_2 &bimc SLV_EBI>` never
resolves → SD controller defers forever → SD-hosted pmOS rootfs invisible.

Every other build under `/data/buildcache/kbuild/` (~25, every boot that has
ever worked) has it `=y`. The sealed build is the sole outlier, built from
`lg-v30-pmos-prealpha/.../config-lge-joan.aarch64` — a config first committed
the same day that had never booted anything. 196 symbols differ from the
known-good lineage; 28 enabled options are missing, including the WCN3990
prerequisite stack as `=m` where known-good has `=y` (`QCOM_QMI_HELPERS`,
`QRTR`, `QRTR_SMD`, `QCOM_RMTFS_MEM`, `QCOM_Q6V5_MSS`, `QCOM_RPROC_COMMON`,
`RPMSG_QCOM_GLINK_SMEM`).

**Fixed:** rebuilt the identical source commit against the known-good config →
`/dev/mmcblk0` appears, rootfs mounts, sshd up in 24 s.

**The SD card is fine.** `e2fsck 1.47.4 -fn` → `rc=0`, all five passes clean.
The two cosmetic complaints (free-block count off by 6, `orphan_present`) are
artifacts of skipping journal recovery in read-only mode and postdate the
forced power-off. `repair` was authorized but **not run**, because running it
would have "fixed" a healthy filesystem and hidden the real fault.

Tracked as task #9: that overlay config keeps producing unbootable kernels
until corrected or dropped as the build input.

### Why the verification ceremony missed it

The sealed handoff records `input_config_sha256`, `effective_config_sha256`,
compiler version, artifact SHAs, an evidence bank, a signed commit stack. All
of it proves the build is **reproducible**. None proves the config is **fit**.
The wrong input was hashed faithfully and thereby made to look qualified.
Recommend a gate: diff any build config against one that has actually booted.

## 2. Quirk and display — both verified

- `qcom,skip-pairwise-delete-key-wait` **is live** in the running DT at
  `/proc/device-tree/soc@0/wifi@18800000/`. The DTB is identical
  (`7547b760…3dda`) across all of **my** builds — but **not** the same as the
  known-good images (control: `89417e95…`). See the retraction in §3; I
  originally wrote "and the known-good images" here on the strength of checking
  a single node, which was wrong. DT was nonetheless excluded as the cause by
  the hybrid test (my kernel + control's DTB fails identically).
- **Display works.** `/sys/class/drm/card0`, `card0-DSI-1`, `renderD128`;
  `msm_dpu c901000.display-controller: bound c994000.dsi`; adreno up with
  `gfx-mem interconnect: 5680000 Bps`; `arm-smmu cd00000.iommu` probes clean
  with **no `-110`**; `fb0` + `fbcon` present. The joan DTS comment claiming
  the panel "will not light up until [the mmss SMMU -110] is resolved" was
  stale and is now corrected.

## 3. The remaining blocker: QMI service 69 (WLFW) never registers

`ath10k_snoc` probes, binds, and then waits **silently forever**. There is not
one QMI line in dmesg. The modem is entirely healthy — **46** QMI services
registered (NAS, WDS, UIM, voice, location, thermal, IPA…) — but **service 69
(WLFW) is absent**, so ath10k has nothing to talk to and `wlan0` never exists.

### What was ruled out (do not repeat)

| Hypothesis | Verdict | Evidence |
|---|---|---|
| SD card corruption | **NO** | e2fsck rc=0, all passes clean |
| Missing storage drivers | **NO** | `EXT4_FS=y`, `MMC_SDHCI_MSM=y`, nothing modular |
| ath10k must be a module | **NO** | known-good control image has it **builtin** (probe at 0.648 s, zero `/proc/modules` entries) |
| ath10k must be builtin | **NO** | builtin image also fails |
| Driver unbind/rebind recovers it | **NO** | re-probe hits `msa info req rejected: 90` → `failed to download board data file: 90` |
| `pd-mapper` is the missing daemon | **NO** | runs, prints `no pd maps available`, exits — no `.jsn` PD maps in the firmware tree |
| rmtfs/tqftpserv must precede modem boot | **NO** | stopped modem, brought both daemons up, restarted modem — WLFW still absent |
| My kernel/config is the differentiator | **NO** | **the known-good control image fails identically** |
| `CONFIG_QCOM_PD_MAPPER` / PDR helpers missing | **NO** | built against the known-working wifi config verbatim (`build-chan169-d05e70c5e/.config`); `qcom_pdm` live in kernel (15 syms); still no WLFW |
| Missing `.jsn` PD maps | **NO** | LineageOS carries six (`adspr/adspua/modemr/modemuw/slpir/slpius`), and `modemuw.jsn` does define `wlan_pd`; staged all six into `firmware_class.path` and cold-started the modem — still no WLFW |
| DTB differences | **NO** | hybrid image (my kernel + control's DTB) fails identically |
| Aurel's delete-key commits | **NO** | only ath10k change is 4 lines reading a DT bool in `ath10k_snoc_quirks_init()` |

That last row is the important one: booting `boot-joan-apmode-519646f01.img`
(kernel `7.2.0-rc2-gd05e70c5e484-dirty`) as a positive control reproduced the
same failure. Whatever is missing is **not** in my build.

### LATER FINDING — the above table is partly built on a flaky signal

Everything in §3 up to this point was written before I established that **WLAN
bring-up on this device is intermittent**. The known-good control image both
succeeded and failed with identical steps. That means several "differential"
conclusions I drew earlier were noise fitted to a non-deterministic signal,
and are retracted below. Read §3.1 as the current picture.

Attempt tally, same recipe (rmtfs up → cold-start modem → wait):

| image | successes |
|---|---|
| control `boot-joan-apmode-519646f01.img` (`d05e70c5e484`) | **2 of 3** |
| every delete-key build (`834154d6b082`) | **0 of ~8** |

0/8 against a ~2/3 base rate is not chance, so the kernel image really does
differ — but the *individual* failures were not the clean signals I treated
them as at the time.

**Retracted:**

- ~~"tqftpserv is the missing piece"~~ — in the clean reproduction ath10k
  connected at 41.7 s, **before** tqftpserv started at 45.3 s. Necessary in the
  original session's scripts, but not what unblocked it here.
- ~~"ath10k must be a module" / "must be builtin"~~ — both fail; the control has
  it builtin.
- ~~"DTB is byte-identical across all builds and the known-good images"~~ —
  false. Mine `7547b760…`, control `89417e95…`. I had only checked one node of
  the control's DTB and generalised. A hybrid image (my kernel + control DTB)
  still failed, so DT is excluded as the cause — but the claim was unfounded
  when made.
- ~~"`CONFIG_QCOM_PD_MAPPER` is the root cause"~~ — building the delete-key
  source against the **known-working wifi config verbatim**
  (`build-chan169-d05e70c5e/.config`, which has `QCOM_PD_MAPPER=y`,
  `PDR_HELPERS=y`, `PDR_MSG=y` and `EXTRA_FIRMWARE=…firmware-5.bin`) still
  produced no WLFW, with `qcom_pdm` confirmed live in the running kernel
  (15 symbols) . Config is therefore **not** the differentiator.

### 3.1 Current picture

With config equalised and DT excluded, the difference must lie in the **25
commits** between the control's `d05e70c5e484` and our base `5fbb6db35`
(`d05e70c5e484` is an ancestor of our base).

**Aurel's three delete-key commits are provably innocent.** Their only
ath10k-code change is four lines in `ath10k_snoc_quirks_init()` reading a DT
boolean:

```c
ar->skip_pairwise_delete_key_wait =
    of_property_read_bool(dev->of_node, "qcom,skip-pairwise-delete-key-wait");
```

That cannot prevent a probe from powering the chip. The only other ath10k code
change in range is `519646f01` (withhold 5845 MHz), which removes one entry
from a channel table — also not on the WLFW path.

### BISECT COMPLETED — and the premise was wrong (2026-08-16)

Both surviving candidates were reverted, built and booted **three times each**.
WLFW stayed absent every time:

| reverted | boots | WLFW |
|---|---|---|
| `8aab25b4b` (interconnect gnoc provider + IPA) | 3 | absent |
| `519646f01` (ath10k withhold 5845 MHz) | 3 | absent |

Then the control that should have been run first: **build `d05e70c5e484`
itself — the commit whose prebuilt image brings `wlan0` up — with the same
toolchain and config.** It **also fails** (2 boots, WLFW absent), and its DTB
is byte-identical (`89417e95…`) to the one extracted from the working image.

**So the 25 commits were never the cause.** Every conclusion built on
"control works, mine doesn't" was resting on a comparison between *my builds*
and a *prebuilt binary*, which conflates source with build provenance.

### The real finding: the known-good image is not reproducible from git

The working image reports `7.2.0-rc2-gd05e70c5e484-**dirty**`. It was built
from a tree with **uncommitted changes**. Those changes are not recoverable:

- no worktree preserves them (only my own usb-otg worktree is dirty, with my
  own edits)
- the single `git stash` is unrelated (`smr split instrumentation`)
- no saved `.patch`/`.diff` under `lg-v30-port/out/` corresponds to them

A clean build of the same commit does not reproduce the behaviour. **The only
artifact that has ever brought `wlan0` up on this port cannot be rebuilt from
any committed state.** That is a provenance problem, not a code problem, and it
is why reverting commits could never converge.

### Hardware is fine — this is not a device fault

LineageOS Wi-Fi works on the same phone: associated to a 5 GHz AP,
**243 Mbps**, RSSI −46, 5785 MHz. The WCN3990 and the modem are healthy.

Also tested and ruled out: LineageOS having claimed the radio first. Disabling
Wi-Fi in LineageOS, rebooting it clean, then RAM-booting mainline — WLFW still
absent.

### Current honest characterisation

Mainline WLAN bring-up on joan succeeded **twice, early**, using a prebuilt
`-dirty` image, and has failed on **every** attempt since — including that same
prebuilt image, a clean rebuild of its base commit, and every delete-key
variant. Roughly 20 boots.

The next useful step is **not** more bisecting. It is to establish a
reproducible-from-git baseline: find or reconstruct what the `-dirty` delta
was, or accept `d05e70c5e484` clean as the new baseline and debug WLFW
registration directly against it with `ath10k_core.debug_mask` and QMI tracing.

### The recipe that works when it works

```
boot (ath10k builtin, probes ~0.65 s)
  -> rmtfs -r -P -s          # MUST be serving before the modem boots
  -> echo start > /sys/class/remoteproc/remoteproc0/state
  -> WLFW (svc 69) appears ~0.5 s later; wlan0 ~10 s after that
```
No tqftpserv needed, no unbind/rebind. Verify with
`qrtr-lookup | grep -E '^ *69 '` → `ATH10k WLAN firmware service`.
Retrying modem stop/start cycles within one boot does **not** recover it
(5 cycles tried, all failed) — a fresh boot is required per attempt.

### The original "one time it worked" note (kept for the record)

`tqftpserv` is required and was missing from my procedure entirely. It is in
Alpine **community** (`tqftpserv-1.2-r0`, now cached on nest), and the working
session's own `~/joan-images/staging/conn-bringup.sh` and `wifi-retry.sh` both
start it before touching ath10k.

On **one** occasion — control image, after a long ad-hoc sequence — starting
tqftpserv produced WLFW immediately and ath10k completed its handshake:

```
qmi chip_id 0x30214 chip_family 0x4001 board_id 0xff soc_id 0x40010002
qmi fw_version 0x110f01a0 fw_build_id
    QC_IMAGE_VERSION_STRING=WLAN.HL.1.1.c2-00416-QCAHLSW8998MTPLZ-1.221535.1
```

I then destroyed it with an unnecessary unbind/rebind (`msa info req rejected:
90`). **I could not reproduce it afterwards** across several boots and
orderings. So tqftpserv is necessary but evidently not sufficient — some
further precondition from the working session is still unidentified.

Also unreplicated: that session staged firmware into tmpfs and pointed the
kernel at it via `/sys/module/firmware_class/parameters/path` = `/tmp/joanfw/fw`,
and `wifi-retry.sh` deliberately **removes** `board-2.bin` and then blanks that
path. The phone's own tree has only
`/lib/firmware/ath10k/WCN3990/hw1.0/board.bin`. That firmware-path dance is the
most likely remaining variable and is where I would look first.

## 4. Next steps

1. Reconstruct `/tmp/joanfw` exactly as `conn-bringup.sh` expects (firmware +
   `bin/` with tqftpserv), including the `firmware_class.path` handling and the
   `board-2.bin` removal from `wifi-retry.sh`.
2. Order: boot (ath10k builtin, probes ~0.6 s) → rmtfs `-r -P -s` → MSS modem →
   tqftpserv → **wait**, do not rebind.
3. Confirm svc 69 via `qrtr-lookup` **before** expecting `wlan0`.
4. Only then: hostapd ch36 VHT80 WPA2 → associate nym-fang → controlled
   disconnect for the `-110` classification → iperf3.

## 5. State left behind

- **Phone: LineageOS**, adb `device`, `boot_completed`. Never flashed.
- **nym-nest:** test USB-net addressing removed; no `10.42.0.0/24` route, no
  masquerade rule.
- **nym-fang: untouched** and matching its recorded baseline (eth0 up
  `172.16.1.12`, wlan0 DOWN/`unavailable`, default via eth0, no test subnet).
  It was never associated — the test never got that far.
- **Sealed keyfix worktree unmodified** at `834154d6b082`, clean, ahead 3.

### Artifacts

Builds (all from source `834154d6b082`, DTB identical `7547b760…3dda`):

| build | config delta | `Image.gz` |
|---|---|---|
| `build-wcn3990-delete-keyfix-clean` | sealed/overlay — **unbootable** | `7336888c…4551` |
| `build-wcn3990-delkey-goodconfig` | known-good config — **boots** | `d9d0ffff…db39a` |
| `build-wcn3990-delkey-wifi-builtin` | + 802.11 builtin | `423a20dc…e0f75` |
| `build-wcn3990-delkey-athmod` | ath10k `=m` + modules | `cd11795f…07f33` |

New reusable tooling: `scripts/serial-exec.py` (raw ttyACM0 with split
sentinels and a `--probe` that refuses to read silence as success — the prior
copy was scratchpad-local and had been lost twice).

## 6. Honest notes on how this went

- I ran `pmos_continue_boot` without first reading `/pmOS_init.log`, which the
  debug-shell banner explicitly offered. That discarded the diagnostic and cost
  a boot cycle.
- I told Lance the blank display was expected, quoting a stale DTS comment
  instead of checking live state. Wrong, and now fixed.
- I surveyed `linux-mainline-v30` on `joan/battery-fg` believing it was the
  build base. It is a divergent, older tree (851-line joan DTS vs 947). Two
  claims in the USB-C/audio/camera survey were wrong as a result and are
  corrected there.
- I chased "ath10k must be a module" through a full rebuild before running the
  control that would have falsified it in one boot. The control should have
  come first.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-15

# Claude Code handoff — LG V30 joan mainline reset hunt after K027

Assisted-by: Hermes-Agent:openai-codex/gpt-5.5
Date: 2026-07-07 03:44:49 PDT

This is the one-file handoff Lance can point Claude Code at. It supersedes the older
`docs/handoff-2026-07-06.md` and
`docs/handoff-2026-07-06-session2.md` for current state, while preserving
the important history from them.

## TL;DR for Claude Code

The LG V30 / joan / MSM8998 mainline port still resets before mainline USB
comes up. The reset is not a normal Linux panic and not the non-secure APSS
watchdog. It is a secure/TrustZone-side controlled reset that returns through
PMIC `PS_HOLD`.

The newest clue is from K026/K027:

- K026 made the downstream/LineageOS return report
  `androidboot.product.lge.bootreasoncode=0x6D630309` /
  `LGE BOOT REASON: 0x6d630309`.
- K027 decoded that using an older public LG/QCOM header:
  `0x6D630309 = LGE_RB_MAGIC | LGE_ERR_TZ | LGE_ERR_TZ_CONF_NOC_ERR`.
- So the reset is specifically reported as **TrustZone Config NoC error**.
- Downstream MSM8998 has legacy `msm_bus` / NoC / BIMC fabric vote plumbing;
  mainline joan currently has no MSM8998 ICC provider/votes.
- A cmdline-only K027 `clk_ignore_unused pd_ignore_unused` image was built, but
  **it has not had a valid device test**. Normal-user fastboot timed out / hit
  permissions, then the phone disappeared from USB. Do not classify K027 as
  rejected or fixed yet.

Immediate rule: do not try more remote boot tests until Lance physically recovers
and reconnects the phone. Current host sees no adb device, no fastboot device,
and no LG/Google/Qualcomm phone USB device.

Best next technical direction after recovery: NoC/config-fabric parity, starting
from the CONF_NOC_ERR clue. Either retry K027 exactly once with one-client
`sudo -n fastboot boot`, or do source-only downstream/mainline NoC archaeology
before selecting one concrete oracle.

## Current repo/device state

Harness/project repo:

```text
~/vibe-coding-projects/coding/lg-v30-port
branch: master
baseline before this handoff: f4a0652 docs: decode joan K027 TZ config NoC clue
handoff file commit: current/top handoff commit in the harness repo (`git log -1` after receipt)
status at handoff: clean
```

Kernel repo:

```text
~/vibe-coding-projects/coding/linux-mainline-v30
branch: joan/latest-clean-test
status at handoff: clean, ahead of origin/master by 4
base: origin/master / v7.2-rc2 / 8cdeaa50e Linux 7.2-rc2
```

Kernel branch commit stack:

```text
0d7df4134 arm64: dts: qcom: msm8998-lge-joan: add APSS watchdog node
7c906e841 arm64: dts: qcom: msm8998-lge-joan: reserve LG firmware-owned memory
a19ca9204 arm64: dts: qcom: msm8998-lge-joan: match downstream ramoops layout
25a391c94 arm64: dts: qcom: add initial LG V30 (joan) device tree
8cdeaa50e Linux 7.2-rc2
```

Device state at this handoff:

```text
adb devices -l: no devices
fastboot devices: no devices
lsusb phone match: none
only unrelated USB match: Qualcomm Atheros Bluetooth 0cf3:3004
```

Interpretation: the US998 likely needs Lance to physically recover/reboot/replug
before another test. Do not keep probing with fastboot while no USB device is
present.

## Safety contract and hard rules

These are binding unless Lance explicitly changes them:

1. RAM-only `fastboot boot` only. Do not flash.
2. Do not write phone storage unless Lance separately approves that exact action.
3. Do not use `fastboot getvar`; LG aboot has been fragile.
4. Use exactly one fastboot client. Two clients can wedge LG aboot.
5. Prefer `adb reboot bootloader` from a known-good OS to enter fastboot; menu-entered
   fastboot has previously hung on downloads.
6. Use `sudo -n fastboot ...` for the actual boot attempt. The failed K027 attempt
   showed normal-user fastboot can hit permissions and hang.
7. Monitor loops must stop immediately on decisive signals:
   - LineageOS adb returns early: failure/reset classification.
   - K023 survivor beacon / deliberate late reboot appears: success/survival.
   - fastboot/menu persists or USB disappears: stop and record, do not keep poking.
8. `panic=0` for classifier tests. A boot failure should hang/silence, not fake a
   reset.
9. After temporary debug patches, save the patch under `out/`, revert, and rebuild
   clean. Do not let debug-only code drift into public-shaped branches.
10. Commit trailers for project commits:
    `Signed-off-by: Lance <Gero3977@gmail.com>` and
    `Assisted-by: <agent/model>`. Never use `Co-Authored-By: Claude` or an AI
    Signed-off-by.

## Reusable test harness

Classifier ramdisk:

```text
~/vibe-coding-projects/coding/lg-v30-port/out/initramfs-k023b.cpio.gz
```

Behavior:

- spins in init;
- deliberate reboot at ~90s as survivor signal;
- `panic=0` means boot failure stays silent instead of faking a reset.

Standard package shape:

```bash
ROOT=~/vibe-coding-projects/coding/lg-v30-port
K=~/vibe-coding-projects/coding/linux-mainline-v30
cat "$K/arch/arm64/boot/Image.gz" \
    "$K/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb" \
    > "$ROOT/out/Image.gz-dtb"
mkbootimg \
  --kernel "$ROOT/out/Image.gz-dtb" \
  --ramdisk "$ROOT/out/initramfs-k023b.cpio.gz" \
  --base 0x00000000 \
  --pagesize 4096 \
  --cmdline "androidboot.hardware=joan panic=0 ignore_loglevel" \
  --output "$ROOT/out/<image>.img"
```

Classification guide:

- LineageOS adb returns around 30-60s: reset not fixed.
- Survivor reboot/known signal at ~100-120s: candidate survived.
- No adb/fastboot/USB and no survivor: ambiguous or boot failure; stop and record.

PON readback after a valid return to LineageOS:

```bash
adb root
adb shell 'dmesg | grep -iE "Power-off reason|Power-on reason|PON=0x|LGE BOOT REASON|bootreasoncode|Reset" | tail -80'
adb unroot
```

Known-dead diagnostics:

- ramoops/pstore: LG boot chain appears to scrub it.
- `/dev/mem`: absent in the busybox/initramfs path.
- mainline USB gadget: never reached before the reset in current failing images.

## Latest K027 artifact: built but not validly tested

K027 was built to test whether preserving bootloader-enabled clocks/power domains
helps a TZ Config NoC reset.

Image:

```text
~/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-clkpd-k027.img
sha256 60f5484be2aaa8616681dd09130b47decc8684bf6d1e3feb96df2fc90f08bb0e
```

Cmdline:

```text
androidboot.hardware=joan panic=0 ignore_loglevel clk_ignore_unused pd_ignore_unused
```

Cmdline artifact:

```text
out/k027-clkpd-cmdline-2026-07-06.txt
sha256 cd7ec2fb23b86cc00fcd34f433f1bfbfcaee4573f2be24833cadb3588f400ace
```

Attempt evidence:

```text
out/k027-clkpd-fastboot-2026-07-06.txt
sha256 92fd7bec7355c4cb62978904186e013ec976bd7a3dc6a7225c0a4e455af491df

out/k027-post-timeout-observe-2026-07-06.txt
sha256 bf7dad650ef88d18b97a4e784b6980e33ddf68d523722f68d694d85176adedb1
```

What happened:

1. Two preflight runs aborted before touching the phone due to a too-literal adb
   tab check. Ignore those.
2. Corrected harness rebooted to bootloader and attempted normal-user
   `fastboot boot out/boot-joan-clkpd-k027.img`.
3. That process timed out after 45s and produced no `Sending`/`Booting` OKAY.
4. Passive diagnostics briefly saw a fastboot USB device, but normal-user fastboot
   reported `no permissions`.
5. Then both adb and fastboot saw no phone; `lsusb` also saw no LG/Google/Qualcomm
   phone device for a 224s observation window.

Classification: **inconclusive / not a valid device test**.

Do not mark K027 rejected. If Lance recovers the phone and it is visible again,
it is reasonable to retry this exact image once with `sudo -n fastboot boot` and
a one-client monitor. If that valid test returns to LineageOS in the usual window
with `PS_HOLD` / `0x6D630309`, then reject `clk_ignore_unused pd_ignore_unused`.

## K026/K027 clue: exact decode of 0x6D630309

K026 tested a downstream LGE IMEM default restart-reason write and did not fix
survival, but it changed what downstream/LineageOS reported after the reset.

K026 downstream parity:

- Downstream joan enables `CONFIG_LGE_HANDLE_PANIC=y`.
- Downstream maps `qcom,msm-imem@146bf000`.
- Downstream `drivers/soc/qcom/lge/lge_handle_panic.c` runs as an early initcall
  and writes `LGE_RB_MAGIC | LGE_ERR_TZ` (`0x6d630300`) to IMEM restart_reason
  offset `0x65c`, i.e. physical address `0x146bf000 + 0x65c`.
- Mainline MSM8998 has no LGE panic handler and no msm-imem/restart_reason node.

K026 image/result:

```text
out/boot-joan-imem-k026.img
sha256 ccf08dbea0e889fa11404335d423e46e5078f37883469234694aff4d3939d035

out/lge-imem-k026-result-2026-07-06.txt
```

K026 valid device result:

- RAM-only `fastboot boot` succeeded:
  - Sending OKAY `[0.410s]`
  - Booting OKAY `[5.095s]`
  - total `5.513s`
- No mainline survivor/USB appeared.
- LineageOS adb returned at `t+49.1s`.
- PON remained SID0 `PS_HOLD`.
- Downstream reported:
  - `androidboot.product.lge.bootreasoncode=0x6D630309`
  - `LGE BOOT REASON: 0x6d630309`

K027 decoded that value from a public older LG/QCOM bullhead header:

```text
URL:
https://android.googlesource.com/kernel/msm.git/+/android-msm-bullhead-3.10-n-preview-1/include/soc/qcom/lge/reboot_reason.h?format=TEXT

Preserved local copy:
out/k027-public-bullhead-reboot_reason.h
sha256 90e24ee46dfedef922c02a55f492b01af460bbbdae1a1c9c3bd40e4fdb8b0355
```

Relevant definitions:

```c
#define LGE_RB_MAGIC                  0x6D630000
#define LGE_ERR_TZ                    0x0300
#define LGE_ERR_TZ_CONF_NOC_ERR       0x0009
```

Therefore:

```text
0x6D630309 = LGE_RB_MAGIC | LGE_ERR_TZ | LGE_ERR_TZ_CONF_NOC_ERR
```

Meaning: TrustZone classified the reset as **Config NoC error**. It is not the
named non-secure watchdog bark (`0x3a`) and not thermal secure bite (`0x3b`).

## Important downstream/mainline NoC observation

Source comparison so far:

- Downstream MSM8998 has Qualcomm's legacy `msm_bus` / NoC / BIMC fabric stack:
  `drivers/soc/qcom/msm_bus/*` and many `qcom,msm-bus` vote tables.
- Downstream MSM8998 DT includes vote tables for paths including:
  - `qseecom-noc`
  - `qcrypto-noc`
  - `qcedev-noc`
  - `msm-rng-noc`
  - UFS / UFS ICE
  - USB3
  - IPA
  - PCIe
  - Venus
  - TSIF
  - other SoC clients
- Mainline `linux-mainline-v30` has generic QCOM interconnect framework enabled
  in `.config`, but there is no MSM8998 ICC provider file and no MSM8998/joan
  interconnect votes in active DT.

This does not prove the fix is bandwidth voting; the CONF_NOC error could also
be from a bad/protected config-fabric access. But it is now the most specific
clue and should guide the next source pass.

## What has already been ruled out

Do not repeat these as standalone survival tests unless new evidence changes the
hypothesis.

| Test / oracle | Result | Meaning |
|---|---:|---|
| `panic=30` | no useful shift | not ordinary Linux panic |
| Disable APSS watchdog DT node | reset persists | not mainline `qcom_wdt` node alone |
| `qcom_scm_probe()` timing PSCI reset | reached early | SCM probe is not too late |
| `SEC_WDOG_DIS` variants | reset persists; downstream live sysfs path returns `ret=-2` | not implemented/usable on this TZ |
| Direct APSS watchdog register petting | reset persists | non-secure watchdog path not enough |
| `maxcpus=1` | returned at ~29.5s | not secondary CPU bringup primary trigger |
| `cpuidle.off=1 nohlt` | returned at ~45.8s | not generic cpuidle/PSCI idle |
| Downstream high-memory no-map reservation | returned at ~29.4s | not simple allocator/XPU use of those ranges |
| K022 do-nothing init | still resets | not userspace/initramfs action |
| K023b USB disabled | still resets | not USB |
| K023c UFS disabled | still resets | not UFS |
| K023d RPM requests disabled | still resets | not RPM/regulators as simple board peripheral |
| K023e core-only board strip | still resets | trigger is SoC core/firmware, not removable board peripheral |
| K024 non-secure APSS WDT pet | still resets | not non-secure APSS watchdog |
| DLOAD-off SCM arg shape | returned ~44.3s | rejected |
| QSEE log-buffer registration | returned ~52.2s | liveness probe only; rejected |
| RPM rpmsg reachability | timing oracle returned ~58.3s | mainline reaches RPM rpmsg; reachability alone not fix |
| RPM BOB mode raw KVP | long return ~108.4s but still reset | not standalone fix |
| RPM L19 3.3V always-on | returned ~57.8s | not standalone fix |
| PM/RPM L18+L19+BOB overlay | returned ~30.6s | not standard voltage bundle |
| TCSR DLOAD cookie phandle | PS_HOLD persists | not standalone fix |
| PM8998 PON S3 source/debounce | returned ~30.5s | not standalone fix |
| PM8998 full PON reset sequence | returned ~57.6s | not standalone fix |
| Downstream Kryo SCM errata helper | comparison-only reject | optional debugfs, not joan default boot parity |
| K025 watchdog/QSEECOM archaeology | comparison-only reject | candidates inactive, dump-only, or already covered |
| K026 LGE IMEM default restart reason | valid boot, returned ~49.1s | not fix; produced 0x6D630309 clue |
| K027 `clk_ignore_unused pd_ignore_unused` | built but invalid attempt | not yet accepted/rejected |

## Current narrowed hypothesis

The blocker is likely one of:

1. A TrustZone/config-fabric/NoC state difference exposed by `TZ_CONF_NOC_ERR`.
2. Missing MSM8998 fabric/interconnect provider/votes or a bootloader-enabled
   clock/power-domain being disabled too early.
3. A protected/bad config NoC access caused by mainline touching some block in a
   way downstream avoids or sequences differently.
4. A still-unmatched early secure-world handshake around QSEE/QSECOM/RPM/SMEM/boot
   cookies, but the CONF_NOC clue makes NoC/config-fabric comparison the sharper
   next path.

Less likely now:

- Generic secure watchdog disarm/pet (`SEC_WDOG_DIS` is not implemented here).
- PMIC/PON policy parity.
- Ordinary regulator default voltage bundles.
- Userspace, USB, UFS, wifi, board peripherals, cpuidle, secondary CPUs.

## Recommended next actions

### If the phone is still absent from USB

Do not attempt another boot. Do source-only work:

1. Compare downstream MSM8998 legacy `msm_bus`/NoC/BIMC default setup with mainline.
2. Look for early init writes to NoC/BIMC/config fabric registers or downstream
   clock enables that happen before ~0.4s.
3. Compare MSM8998 against nearby mainline QCOM ICC providers (`msm8996`, `sdm660`,
   `sdm845`) to see whether an MSM8998 ICC provider can be sketched or whether a
   much smaller debug-only fixed-vote oracle is possible.
4. Look for known Qualcomm TZ crash reason `CONF_NOC_ERR` / `LGE_ERR_TZ_CONF_NOC_ERR`
   in public kernels/firmware notes, especially what access can trigger it.
5. Select exactly one concrete oracle. Do not build speculative bundles.

### If Lance physically recovers the phone and it is visible again

First passively verify:

```bash
pgrep -a -x fastboot || true
adb devices -l
fastboot devices
lsusb | grep -Ei '18d1|1004|05c6|lg|google|qualcomm' || true
```

If the phone is in LineageOS and Lance is present, retry K027 exactly once:

```bash
adb reboot bootloader
# wait until sudo-fastboot sees exactly one device
sudo -n fastboot devices
sudo -n fastboot boot ~/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-clkpd-k027.img
```

Monitor with the existing one-client discipline. Do not start a second fastboot
watcher. If LineageOS returns, read PON/bootreason with adb root/unroot and record:

- return timing;
- PON lines;
- `androidboot.product.lge.bootreasoncode` / `LGE BOOT REASON` if present;
- whether it is still `0x6D630309`.

If K027 validly returns with PS_HOLD / `0x6D630309`, reject the cmdline-only
clock/power-retention discriminator and move on to a more concrete NoC/fabric
oracle.

## Where the durable records live

Primary docs:

```text
README.md
docs/kernel-change-ledger.md
docs/bringup-debug-state-2026-07-06.md
docs/2026-07-06_lg-v30-reset-cause-PS_HOLD.md
docs/public-upstreaming-plan.md
```

This handoff:

```text
docs/handoff-2026-07-07-k027-complete.md
```

Latest K027 result artifact:

```text
out/k027-conf-noc-decode-and-clkpd-attempt-2026-07-06.txt
sha256 e0bc41afb97f71a5d91d76f97c9969da04b9120aa72c58a94d18a343283e6ae4
```

K027 docs patch artifact:

```text
out/k027-docs-f4a0652.patch
sha256 264bd60feaab8b33e6b45c3e9e5b79556b61816a57a60b7c7cb2fc82c126481f
```

K027 public reboot-reason header artifact:

```text
out/k027-public-bullhead-reboot_reason.h
sha256 90e24ee46dfedef922c02a55f492b01af460bbbdae1a1c9c3bd40e4fdb8b0355
```

K027 boot image:

```text
out/boot-joan-clkpd-k027.img
sha256 60f5484be2aaa8616681dd09130b47decc8684bf6d1e3feb96df2fc90f08bb0e
```

## internal mirror/tracker sync state before this file

Hermes Agent previously synced K027 artifacts to:

```text
private mirror: status artifacts for K027 (paths omitted)
private mirror: patch artifact for K027 docs (path omitted)
```

the internal tracker was updated with K027 a comment.

This one-file handoff should also be uploaded to:

```text
private mirror: handoff copy (path omitted)
```

## Final instruction to Claude Code

Start from this file, not the chat transcript. If the phone is not visible over
USB, do source-only CONF_NOC / MSM8998 NoC/fabric archaeology. If Lance physically
recovers the phone and asks for one more test, retry only the already-built K027
image once with one-client `sudo -n fastboot boot`, then record the result in the
ledger and the internal tracker.

Cozy but sharp summary: the snake trail now points at **TZ Config NoC**, not at
APSS watchdogs, PMIC PON, or userspace. Follow the fabric.

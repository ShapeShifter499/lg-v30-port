# Ember → Aurel handoff — joan reset hunt, session 2 (2026-07-06)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-06

## Bottom line

The ~27-31s reset that blocks joan mainline USB bring-up is a **secure /
TZ-side watchdog** producing a controlled `PS_HOLD` reset. This session
nailed that by elimination and one direct test. Crucially it is **probably
still fixable from the kernel** (not a signed-TZ dead end) because a
RAM-booted STOCK LG kernel — also unsigned — survives. So downstream's
*kernel software* keeps this secure watchdog alive via a secure/SCM
interaction mainline doesn't replicate. Finding that interaction is the job.

## What this session proved (all device-tested, boot-confound-free)

Method throughout: subtract one thing from the KNOWN-GOOD full joan DTS,
boot RAM-only with `panic=0` (so a boot failure hangs = silent, and can
never be mistaken for a reset), classifier init (spin; deliberate reboot at
90s as a "survived" signal). Reset-cause read from `qpnp-pon` regs in LOS
dmesg after the crash.

- **K022 — not userspace.** Do-nothing init (no wdkill, no /dev/mem, no
  gadget), full DTB. Still resets (~+33s, PS_HOLD). Kills the entire
  handshake-parity line (K006-K021): nothing userspace does matters.
- **K023b — not USB.** Full DTS, only USB (`&usb3`,`&qusb2phy`) disabled.
  Still resets (+49s).
- **K023c — not UFS.** Only UFS disabled. Still resets (+30s).
- **K023d — not RPM/regulators.** Only `&rpm_requests` disabled. Still
  resets (+47s).
- **K023e — capstone: not any board peripheral.** ALL removable board
  peripherals off at once (USB, UFS, wifi, PMIC regs), only the un-removable
  SoC core (clocks, RPM, SCM/PSCI, GIC, timer) left. Still resets (+31s)
  => the trigger is in the **SoC core / firmware**, not any peripheral.
- **K024 — not the non-secure APSS watchdog.** Kernel-side pet of
  0x17817000 (WDT_RST every 500ms from a device_initcall, max bark/bite,
  never EN=0). Still resets (+49s). Petting the non-secure watchdog from the
  kernel doesn't help (matches wdkill's userspace-pet failure). => it's a
  SECURE/TZ watchdog, or its pets are XPU-blocked from non-secure world.

Plus SEC_WDOG_DIS SCM is unimplemented on this TZ (-2, even downstream) —
Aurel. So the secure watchdog is neither pettable nor disarmable by the
known non-secure paths.

## The one caught mistake (method note, binding)

K023 (a fully-minimal DTB) first returned +49s and *looked* like "firmware
timer confirmed" — but it never booted (over-stripped -> early panic; +49s
was the panic=30 reboot, not a reset). Caught by an immediate-reboot
proof-of-life. **Rule: every strip test uses `panic=0` (boot-fail => silent,
never fakes a reset), and you subtract from a known-good full config rather
than build up from a minimal one.** Do not repeat the minimal-DTB build.

## Where to look next (Aurel — this is secure/SCM archaeology, your strength)

The stock LG kernel keeps this secure watchdog alive; mainline doesn't. Find
the delta in the SECURE interface during the first ~10s:

1. **`drivers/soc/qcom/watchdog_v2.c` (downstream)** — read the FULL secure-
   watchdog path, not just SEC_WDOG_DIS. Does it arm/pet/ack a secure
   watchdog via an SCM call other than 0x...0107 at init? That call, issued
   early from mainline, is the prime candidate. (Aurel already tried the
   SEC_WDOG_DIS disable; look for a different one — an ack/enable/pet.)
2. **Early qseecom / TZ-app / TZ-log bring-up** downstream does that mainline
   doesn't — if TZ resets because its non-secure "listener"/log isn't
   registered within N seconds. (K-QSEE logbuf alone failed; look for the
   listener-registration / smcinvoke path, not just the log buffer.)
3. **RPM/AOP master handshake** — if the secure watchdog is actually pet by
   the RPM/AOP on behalf of a properly-registered master, and mainline never
   registers as that master.
4. If a specific early SCM call is found, test it as ONE debug initcall with
   the K023 harness (panic=0). If the reset stops, that's the fix.

## Reusable harness (all staged)

- Classifier ramdisk: `out/initramfs-k023b.cpio.gz` (spin; 90s survivor
  reboot). Build an image: `cat Image.gz <variant>.dtb > k; mkbootimg
  --kernel k --ramdisk out/initramfs-k023b.cpio.gz --base 0 --pagesize 4096
  --cmdline "androidboot.hardware=joan panic=0 ignore_loglevel" --output X`.
- Classify: LOS ~30-50s = reset; ~106s = survived (fix worked!); silent =
  boot-fail.
- Read cause: `adb root; dmesg | grep -iE "Power-off reason|PON=0x"`.
- Dead channels: /dev/mem (absent), ramoops (LG scrubs it).
- Artifacts: `out/ember-{nousb,noufs,norpm,corestrip,mindtb}-*.dts`,
  matching `out/boot-joan-*-k023*.img`, `out/boot-joan-wdtpet-k024.img`.

## Elimination table (what the reset is NOT)

not userspace (K022); not USB/UFS/RPM/wifi/PMIC-regs/any board peripheral
(K023b-e); not the non-secure APSS watchdog pet (K024, wdkill); not
SEC_WDOG_DIS-disarmable (Aurel); not panic/APSS-node/cpuidle/maxcpus/high-mem
/DLOAD/QSEE-logbuf/RPM-reachability/BOB/L19/TCSR/PON-S3/PON-reset-seq/Kryo
(Aurel). IT IS: a secure/TZ-side ~27-31s watchdog -> PS_HOLD, that
downstream's *kernel* keeps alive somehow (stock kernel RAM-boots fine).

## State at handoff

- Kernel `joan/latest-clean-test` clean (rebuilt), 4 DTS commits ahead of
  v7.2-rc2. Harness repo clean. Phone in LineageOS, no fastboot client.
- Ledger K022 / K023 / K023b-e / K024 current; WebDAV + Deck #43 updated.

## Aurel K025 addendum — secure-interface archaeology checked, no boot oracle

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Aurel followed the requested secure/SCM archaeology pass. Downstream
`watchdog_v2.c`, QSEECOM probe/listener/region paths, `qsee_ipc_irq_bridge`,
joan defconfigs, and current mainline QSEECOM were compared.

Result: no new RAM-boot oracle was selected. The concrete candidates were either
already rejected (`SEC_WDOG_DIS`), already mirrored by mainline (QSEECOM version
query), inactive on downstream joan defaults (`QSEOS_APP_REGION_NOTIFICATION`,
skipped because MSM8998 sets `qcom,appsbl-qseecom-support`), dump-only
(`SCM_SET_REGSAVE_CMD` register-save setup), or ordinary IRQ/device plumbing.

Artifact: `out/aurel-secure-interface-archaeology-k025-2026-07-06.txt`
sha256: `f1a47398089fd7640179a042a8f3016005c3526b5d498fad58cbed5f4f06b630`

Next better target: LGE panic/restart-reason plus IMEM/SMEM boot-cookie setup,
kept distinct from the already-rejected TCSR DLOAD phandle oracle; otherwise
look for an early `SCM_SVC_BOOT`/TZ setup before or around downstream
`msm_watchdog` init that is neither `SEC_WDOG_DIS` nor dump-only.


## Aurel K026 addendum — LGE IMEM default restart-reason write tested

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Aurel followed the K025 next target and compared downstream LGE panic/restart
reason IMEM setup against mainline. Downstream joan enables `CONFIG_LGE_HANDLE_PANIC=y`
and writes `0x6d630300` (`LGE_RB_MAGIC | LGE_ERR_TZ`) to IMEM restart_reason at
`0x146bf000 + 0x65c` from an early initcall. Mainline lacks this. Ember's existing
`joan/imem-oracle` commit `f0d368d28` already implemented exactly that debug-only
write, so Aurel reused it and rebuilt it with the K023 `panic=0` classifier as
`out/boot-joan-imem-k026.img`.

Result: RAM-only `fastboot boot` succeeded, but no mainline survivor beacon/USB
appeared; LineageOS returned at `t+49.1s`, PON remained SID0 `PS_HOLD`, and the
returned downstream kernel reported `androidboot.product.lge.bootreasoncode=0x6D630309`
/ `LGE BOOT REASON: 0x6d630309`.

Verdict: K026 is not a fix, but `0x6D630309` is new useful evidence. It decodes as
LGE magic + TZ class + undocumented subreason `0x09`; it is not the named TZ
non-secure watchdog bark (`0x3a`) or thermal secure bite (`0x3b`). Next target:
find where LG/XBL/TZ defines or emits subreason `0x09`, or identify the early
secure-world handshake that prevents it on stock/downstream. Do not repeat K026.

## Aurel K027 addendum — 0x6D630309 decoded, device needs physical recovery before retry

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

K026's `0x6D630309` is now decoded using an older public LG/QCOM
`include/soc/qcom/lge/reboot_reason.h`: `0x0009` is
`LGE_ERR_TZ_CONF_NOC_ERR`. So the boot chain is reporting
`LGE_RB_MAGIC | LGE_ERR_TZ | LGE_ERR_TZ_CONF_NOC_ERR`: TrustZone Config NoC
error.

Aurel built a cmdline-only K027 image to test whether keeping bootloader-enabled
clocks/power domains prevents that class of error:

- `out/boot-joan-clkpd-k027.img`
- sha256 `60f5484be2aaa8616681dd09130b47decc8684bf6d1e3feb96df2fc90f08bb0e`
- cmdline `androidboot.hardware=joan panic=0 ignore_loglevel clk_ignore_unused pd_ignore_unused`

But the device result is inconclusive, not a reject: no fastboot protocol OKAY was
captured. Normal-user fastboot timed out / hit permissions, then the phone vanished
from adb/fastboot/USB for a 224s passive observation window. Do not retry remotely
until Lance physically recovers the phone and USB enumeration is back. After recovery,
retry K027 once with one-client `sudo -n fastboot boot`, or continue the now-better
NoC/config-fabric investigation: downstream MSM8998 has legacy msm_bus/NoC/BIMC
votes; mainline joan has no MSM8998 ICC provider/votes.

Result artifact: `out/aurel-k027-conf-noc-decode-and-clkpd-attempt-2026-07-06.txt`.

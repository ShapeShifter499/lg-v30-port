# joan: the boot lottery was a DT bug, and the slowness is one tuned profile

Session: Ember (Claude-Code:claude-opus-5), 2026-09-12, continuing Fulgor's
2026-09-11/12 handoff.

STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port.

## 1. The boot lottery — solved, not mitigated

**It was never a hang.** joan's DTS pointed the soundwire controller at
`interrupts-extended = <&wcd9340 8>`, and 8 is `WCD934X_IRQ_MBHC_SW_DET`.
The line is not shared, so soundwire and MBHC contended for it and whichever
child probed first won:

- soundwire wins -> `138: wcd934x_irq 8 Edge soundwire`, **zero MBHC handlers**,
  jack detection dead (Fulgor's "Boot B, wedged").
- MBHC wins -> all seven MBHC handlers register and soundwire comes up short
  (Fulgor's "Boot A, clean").

Two boots, two outcomes, from one contended line. No randomness required.

### Why the wrong number was chosen

The commit that introduced it (`2b6ecf829cd7`) reasoned that 20 "was
downstream's 32-source numbering and cannot map into the 9-slot mainline
domain". Both halves are wrong:

`wcd934x_irqs[]` uses **designated initialisers keyed by IRQ number**
(`[_irq] = { ... }`), so it is a sparse array indexed by the `WCD934X_IRQ_*`
value. Measured from the shipped module: the symbol is 756 bytes = **21 slots**
of `struct regmap_irq`, nine populated, slot 20 among them. `num_irqs` is
`ARRAY_SIZE()` = 21, so the domain spans 0-20 and 20 resolves correctly.

The number 8 is where SOUNDWIRE sits in the *initialiser list* -- it is the
ninth entry written. List position was counted instead of the designated index.

`sdm845-wcd9340.dtsi` uses `<&wcd9340 20>` for the same codec. joan was the
lone outlier, which is the tell that should have prompted the check.

### Verified on hardware (r16, first boot, no retries)

    136:  2  msmgpio 54   Level  wcd934x_irq     <- parent, demuxing
    137:  0  wcd934x_irq 20  Edge  soundwire     <- moved to 20
    139:  2  wcd934x_irq  8  Edge  mbhc sw intr  <- MBHC has its line back, and it fired
    140-145: Button Press / Release / Elect Insert / Remove / HPH_L OCP / HPH_R OCP

## 2. The LEVEL fix moved into the regmap-irq type table

`abc48a756b0f` wrote the four LEVEL bytes at 0x0461 directly in
`wcd934x_slim_status_up()` and the register still read 00 on the bench. The
write was not lost, it was **overwritten**: regmap-irq owns those registers.
They are the chip's `config_base`; `config_buf` is `kcalloc`'d to zero and
never seeded from hardware; and `regmap_irq_sync_unlock()` writes all four
from that buffer on **every** mask, unmask or set_type
(`drivers/base/regmap/regmap-irq.c:183`). The first child to enable an
interrupt puts 00 back. No position in probe can win that race.

The supported mechanism is the per-irq type description, so
`WCD934X_IRQ_SLIMBUS` now advertises `IRQ_TYPE_LEVEL_HIGH`
(`type_level_high_val` was already the source's mask). That is inert on its
own -- `regmap_irq_set_type()` only consults the table when a requester asks
for the type -- and the codec was asking with `IRQF_TRIGGER_RISING`, which,
since `type_rising_val` is 0 on this chip, is precisely what cleared the bit
to pulse. So the codec now requests `IRQF_TRIGGER_HIGH`.

### Verified on hardware, both layers

    boot 1 (r14 modules):  138:  wcd934x_irq 0  Edge   slim
    boot 2 (r16 modules):  138:  wcd934x_irq 0  Level  slim

    regmap wcd934x-slim (217:250:1:0):
      0409 INTR_PIN1_MASK0:  f2      <- children have enabled interrupts
      0461 INTR_LEVEL0:      01      <- and the bit SURVIVED them
      0462/0463/0464:        00 00 00

`MASK0=f2` is the part that matters: sync_unlock has run many times since and
the bit is still set. Note the chip exposes two slimbus regmaps; `217:250:0:0`
is named `nodev` and reads all zeros. Reading that one instead looks exactly
like the fix failing.

## 3. System slowness: one wrong tuned profile

The PPD power profile is set to `performance`, which `/etc/tuned/ppd.conf`
maps to tuned's **`throughput-performance`** -- a server profile, on a handset.
It alone produces three separate symptoms:

| throughput-performance sets | consequence on joan |
|---|---|
| `[disk] readahead=>4096` | 4 MB readahead; the device package's own `90-joan-bfq.rules` argues session startup is "dominated by small random reads", which 4 MB readahead amplifies |
| `[sysctl] vm.swappiness=10` | overrides `zramstart`'s 180, so **5.2 GB of zram sits at 0 bytes used** while page cache is evicted to the microSD instead |
| `[vm] dirty_bytes 40% / dirty_background_bytes 10%` | on 3.6 GB RAM: ~1.44 GB dirty before throttling, 360 MB before background writeback, flushed to media doing single-digit MB/s random write |

Observed while installing a kernel package: load 13, **37% iowait, 59% idle,
~3% CPU**, with `jbd2/mmcblk0p2` in D-state. That is writeback, not compute.

Switching profiles demonstrably moves the knobs (measured, not inferred):

    balanced               -> read_ahead_kb=128   vm.swappiness=180
    throughput-performance -> read_ahead_kb=4096  vm.swappiness=10

`balanced` does not set swappiness at all, which is why zramstart's 180
survives under it. This is the direct proof of which component clobbers it.

### Measured (600 small files, caches dropped, profile order alternated)

Timer positive-controlled first (`sleep 2` measured 2.02 s) because busybox
`date` has no `%N`: an earlier run of this same benchmark reported `0ms` four
times and would have been read as "no difference".

| order | profile | readahead | swappiness | elapsed |
|---|---|---|---|---|
| 1 | balanced | 128 kB | 180 | 6.09 s |
| 2 | throughput-performance | 4096 kB | 10 | 7.27 s |
| 3 | balanced | 128 kB | 180 | 5.04 s |
| 4 | throughput-performance | 4096 kB | 10 | 6.57 s |

`balanced` is faster in both pairs: 5.57 s vs 6.92 s mean, about 20%. Order is
alternated because there is a visible warming trend (later runs faster), and
`throughput-performance` is still slower in the later slot than `balanced` was
in the earlier one -- so the effect is not drift.

**What this does and does not show.** N=2 per arm, and the workload is
read-only: it exercises readahead, not the dirty ratios. The writeback argument
above (40%/10% dirty on single-digit-MB/s media) is reasoned from the observed
37% iowait and `jbd2` D-state during a package install, and is *not* measured
here. A write-side benchmark is still owed before claiming a figure for it.

**Not the SD card, and not the scheduler.** Both were already correct and
should be left alone:

- `/sys/kernel/debug/mmc0/ios`: clock 200 MHz actual, **timing spec 6 (SD UHS
  SDR104)**, 1.8 V signalling, 4-bit -- the maximum an SD card can do. Aurel's
  clock-ownership audit already concluded the DT is complete under the modern
  binding and warned that copying the legacy two-clock shape would regress it.
  Zero tuning errors this boot (Aurel's `mmc0 tuning-execution-failed` monitor
  item did not fire).
- Scheduler already `bfq`, set by the device package's own udev rule.

zram itself is healthy: enabled, active, 5.2 GB at priority 300, with
`page-cluster=0` and `min_free_kbytes=100000` applied. Only swappiness is
clobbered.

## 4. Packaging: the kernel apk cannot be upgraded on this boot partition

`linux-lge-joan`'s `package()` ran `dtbs_install`, writing **1841 DTBs** into
a 226 MiB `/boot` (75% full). apk stages new files before removing old ones,
so an upgrade needs room for two copies and fails partway:

    ERROR: linux-lge-joan-7.2.0_rc2-r16: failed to extract
    boot/dtbs/qcom/qrb5165-rb5-vision-mezzanine.dtb: No space left on device

apk then aborts the transaction -- and **still exits 0**. The kernel and
modules stay at the old pkgrel while the install looks successful. It was only
caught by comparing module md5sums against the apk's. Fixed in pkgrel 17:
install only `${_dtb}.dtb`, with `_dtb` declared next to `_flavor` because the
path must keep matching `deviceinfo_dtb`.

**Bench rule that follows from this:** never conclude a kernel/module change
landed from `apk add`'s exit status. Hash the modules.

## 5. Status

- kernel `joan/jack-irq-level-v2` @ `ff98974a67aa` (pushed): both wcd934x
  patches + the specifier fix. Both verified on hardware.
- kernel `joan/camss-msm8998-dt` @ `110f579bd5ac`: msm8998 CAMSS node, 11 regs
  / 10 IRQs / 40 clocks, all resolving; left `disabled`, never probed.
- pmaports: pkgrel 16 (pinned ff98974a67aa) and pkgrel 17 (DTB packaging fix).
- Jack detection is now armed on a first boot. The remaining Phase 1 step is
  the physical headset plug/unplug + button test, which needs a person.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-12

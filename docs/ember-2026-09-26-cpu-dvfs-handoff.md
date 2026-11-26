# Handoff: CPU DVFS (OSM + CPRh + SAW + LMh) and the bench boot loop (2026-09-26)

Written-by: Ember (agent-ember)
Agent-harness: Claude-Code:claude-opus-5-5
Device: LG V30 US998 `LGUS9986e606d55`, CPU speed bin 2, MSM8998 v2.1
Picks up: [ember-2026-09-26-boot-storage-thermal-cpu.md](ember-2026-09-26-boot-storage-thermal-cpu.md)

Every number below was measured on the phone. Raw output:
[evidence/2026-09-26-dvfs/](evidence/2026-09-26-dvfs/).

## Where things stand

CPU DVFS works on mainline for the first time, on kernel branch
**`joan/cpu-dvfs-cprh`** (pushed, tip `04eeb20ab3c3`). It is **not** in
`joan/latest-clean-test` or pmaports yet: the gold voltages still need one fix
(see "Next").

| | before | now (build dvfs14) | Lineage 4.4 |
|---|---|---|---|
| gold real clock at max | ~148 MHz fixed, then 2262 (LMh cap) | **2348 MHz** (row 2361.6) | 2363-2378 |
| silver real clock at max | ~1549 fixed | 1868-1895 | ~1750 (interactive gov) |
| LMh request (OSM `+0xb04`) | 1056 / 1056 mV | 1120 / 1136 mV | not readable |
| L2 SAW SPM_CTL/DLY/CFG | zeroed by spm.c | bootloader values kept | kept |
| silver top corner (1900.8) | 868-908 mV | **920-960 mV** | 920-960 mV |
| gold top corner (2361.6) | 1060-1100 mV | 1068-1108 mV | **1096-1136 mV** |
| systemd | running | running, 0 failed | - |

Measuring tool: `cpumhz2 <cpu> <seconds>`, a pinned dependent-add loop that reads
the real core clock. There is no PMU node yet, so perf counters are unavailable.

## Commits on `joan/cpu-dvfs-cprh` (newest first)

- `04eeb20ab3c3` cpufreq: qcom-osm: decode the LMh request in debugfs, tidy comments
- `dc8d43903f0d` arm64: dts: qcom: msm8998: add the L2 SAWs and LMh, sort the OSM block
- `d5195acd3e1f` pmdomain: qcom: cpr3: use the MSM8998 v2 fuse corner adjustments
- `9a3cc2cfdc8d` thermal: qcom: lmh: enable the limits algorithms per SoC, add MSM8998
- `e20fde9b768b` soc: qcom: spm: don't clobber the L2 SAW control registers
- `6fefd22bb3f2` and earlier: WIP OSM driver commits plus CPR3/CPRh v15 (Angelo/Konrad), rebased onto 7.2-rc2

## What was found (and how)

1. **L2 SAW nodes are mandatory.** CPRh sets the rail through the L2 SAWs'
   AVS/PMIC port. Without `power-manager@17812000/17912000` the OSM never changes
   state. The archived postmarketOS msm8998 tree
   (gitlab.com/msm8998-mainline/linux; OnePlus 5/5T, Mi 6, F(x)tec Pro1, Sony
   Yoshino) and SoMainline's `angelo/*` and `topic/cpr3hh` branches carry the same
   two nodes. Their CPU OPP/LUT tables equal ours except two rows, where ours
   matches LG.
2. **TZ's LMh caps both clusters at 1056 mV until the OS enables the reliability
   (REL) algorithm.** The OSM's LLM ("Limits Load Management") frequency vote then
   holds gold at 2265.6 MHz, the highest LUT row whose voltage is ≤1056 mV.
   - The request latches within 5 µs of the first OSM enable (instrumented probe).
   - Toggled at runtime with a test module (`tools/bench/lmhprof.c`):
     REL on → 1120/1136 mV and gold at 2358 MHz; REL off → 1056 mV and 2262 MHz.
     Current limiting alone, the thermal algorithm, and limits profile 1 change
     nothing.
   - The SAW AVS limit is not involved: LG's `0x4580458` gives the same result.
   - LG enables REL and current limiting in `msm_thermal.c`
     (`msm_thermal_lmh_dcvs_init`). Mainline `lmh.c` enabled algorithms only for
     SDM845; it now has per-algorithm bits and `qcom,msm8998-lmh`.
   - LMh nodes: gold `0x179cc800` / SPI 38, silver `0x179ce800` / SPI 37.
     Interrupt-clear is at +0x8, as on SDM845. The dtsi uses Qualcomm's
     65/94.5/95 °C thresholds; the joan dts uses LG's 85 °C (`CONFIG_LGE_PM`).
3. **mainline `spm.c` wiped the L2 SAW control block.** The v4.1 (and v2.3)
   tables have no sequence offset, so the sequence copy wrote zeros over
   0x00-0x3c. Bootloader values, read on a boot with
   `initcall_blacklist=qcom_cpufreq_hw_init,qcom_spm_init`: SPM_CTL
   `0x00100005`, SPM_DLY `0x3e81900a`, CFG `0x14`.
4. **mainline CPR3's MSM8998 tables used v1-era fuse adjustments** with v2
   reference voltages. The table now has LG's v2 values (the same for every bin
   and revision): silver open-loop 40/24/32/80 mV, closed-loop 20/26/32/80 mV;
   gold 8/0/32/122 and 0/0/32/120 mV. Silver now matches Lineage's
   `cpr3-regulator` debugfs to within 4 mV.
5. The sibling tree has the same LLM `writel(0)` and the same `spm.c` bug, so
   the OnePlus 5, Mi 6, Pro1 and Yoshino very likely hit the same cap.
6. LG's SAW AVS limits (`0x458` on both) are a v1 leftover. Mainline's per-cluster
   rail maxima (gold `0x470`, silver `0x420`) are correct for v2.

## Next, in order

1. **Gold CPR interpolation.** Lineage's gold corners run 28-52 mV higher than
   ours (2208: 1044-1084 vs 996-1036; 2265.6: 1076-1116 vs 1024-1064; 2361.6:
   1096-1136 vs 1068-1108). Mainline clamps the TURBO_L1 fuse voltage
   (1076 + 122 = 1198 mV) to 1136 **before** interpolating the per-corner
   voltages. msm-4.4 (`cprh_kbss_calculate_open_loop_voltages`, then
   `cpr3_adjust_open_loop_voltages`) interpolates from the unclamped fuse
   voltages and clamps per corner. Fix it in `cpr-common.c`/`cpr3.c` and verify
   every corner against `evidence/.../lineage-cpr-corners.txt` (Lineage corner N
   is 1-based; ours is 0-based). Until then, gold's top corners run with less
   margin than stock. **This is a stability risk, so don't ship to pmaports
   first.**
2. pmaports integration after (1): pin the branch, `QCOM_CPR3=y`,
   `ARM_QCOM_CPUFREQ_OSM=y`, `QCOM_SPM=y` (the SAWs must exist before the OSM
   starts; it is `=m` today), `QCOM_LMH=y` preferred (`=m` works; gold is capped
   until it loads). Build with pmbootstrap, apk-install, boot, then push.
3. Wire the LMh interrupt into the OSM driver (`dcvsh-irq`, like
   qcom-cpufreq-hw), so hardware throttling reaches cpufreq and the scheduler.
4. Single-core boost rows. LG's bin-2 gold table has paired rows (core-count 4
   and 1, up to 2457.6 MHz); ours has only the 30 all-core rows.
5. Squash the WIP commits, run `dt_binding_check` (dtschema is not installed on
   skyforge), then cherry-pick the verified pieces to `joan/latest-clean-test`.
   `master` takes verified-only cherry-picks.
6. Still open from before: UFS ~4x slower than stock, DP spurious HPD,
   camss_ahb stuck, audio, FM driver, EAS energy model, PMU node, bin 0/1 tables.
   Build dvfs11 once came up `degraded` (81voltd, nftables,
   systemd-modules-load, tqftpserv failed). That was not seen again on
   dvfs12-14, and the cause is unknown.

## How to boot-test the phone (the loop used in this session)

Hosts: build on **nym-skyforge** (here); the phone is on USB to **nym-nest**
(`ssh nym-nest-family`). Lineage is the phone's default boot. pmOS lives on the
microSD (the SIM tray holds the SD card, so a SIM swap means booting Lineage).
**RAM boot only.** Never flash boot/laf/SD partitions.

Scripts: [tools/bench/](../tools/bench/). `jssh` is the ssh/scp wrapper to the
phone's pmOS (`user@172.16.42.1` over USB networking). The working copy is on
nest at `/tmp/ember-f08d8c5-unpack/jssh`, next to `initramfs-r26-ondevice` (the
r26 on-device mkinitfs ramdisk). `/tmp` on nest can vanish; if it does,
re-extract the ramdisk from the SD's `/boot/boot.img` or rebuild it with
pmbootstrap. `JOAN_PW` is the bench pmOS user password; export it (never commit
it).

1. **Build** (always the same argv, or ccache cold-misses the whole tree):
   ```
   cd ~/vibe-coding-projects/coding/linux-mainline-v30
   make -s O=/data/buildcache/kbuild/joan-lct-dvfs ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        CC="ccache aarch64-linux-gnu-gcc" -j$(nproc) Image.gz dtbs modules </dev/null
   ```
   That outdir has `CONFIG_LOCALVERSION="-joan-dvfs"` with `LOCALVERSION_AUTO` off,
   so the release is stable (`7.2.0-rc2-joan-dvfs+`) and the SD's modules match.
2. **Boot with pmOS already running:**
   `JOAN_PW=… tools/bench/joan-testboot.sh /data/buildcache/kbuild/joan-lct-dvfs dvfsNN [extra cmdline]`.
   It installs the modules on the SD via the running pmOS, reboots (the phone
   lands in Lineage), runs `adb reboot bootloader`, then
   `fastboot boot ~/joan-images/boot-joan-dvfsNN.img`, brings up USB networking
   (`enp0s29u1u5*`, host 172.16.42.2), and waits for systemd. The cmdline is
   `panic=5 pmos.force-partition-resize ipa.lowmem=1 log_buf_len=8M`. **Never**
   add `pmos_root=`: the initramfs takes it as a literal path and halts.
3. **Boot from Lineage** (built-in-only change, modules unchanged): cat
   `Image.gz` + `msm8998-lge-joan.dtb` into a kernel file, run `mkbootimg` with
   the same parameters as the script (header v0, pagesize 0x1000, kernel_offset
   0x8000, ramdisk_offset 0x2000000, tags 0x100), then
   `sudo adb -s LGUS9986e606d55 reboot bootloader` and
   `sudo fastboot boot <img>` on nest.
4. **Back to Lineage:** `./jssh "echo $JOAN_PW | sudo -S systemd-run --on-active=2 systemctl reboot"`.
   On Lineage, `adb root` works: adbd is uid 0, and there is no `su` binary.
   Lineage has no `/dev/mem` and only accepts signed modules; read CPR there
   through `/sys/kernel/debug/cpr3-regulator/apc1/thread0/apc1_perfcl_corner/corner/{index,floor_volt,ceiling_volt}`.
5. **Verify DVFS:** push `cpumhz2`, `regdump` and `regwrite` (static aarch64,
   built from `tools/bench/*.c` with `aarch64-linux-gnu-gcc -static -O2`) to
   `/home/user`. Then run `dvfscheck.sh` (sweep plus all-core load), `sawdump.sh`,
   and read `/sys/kernel/debug/qcom-cpufreq-osm/policy{0,4}` (LMh request,
   current point, LUT) and `/sys/kernel/debug/qcom_cpr3/thread{0,1}`.
6. **Probing tricks that paid off:** `initcall_blacklist=<fn>` on the cmdline to
   read registers before a driver touches them. A throwaway out-of-tree module
   (`lmhprof.c`) replays vendor SCM sequences one bit at a time. `regwrite` flips
   one register live (for example OSM `+0x34`, LLM honour bits) to prove
   causality. All of these reset on reboot.

Cautions: probe the phone with `ping`, not `/dev/tcp`, because repeated
connection probes trip sshd PerSourcePenalties. Never `pgrep -f`/`pkill -f`;
kill by PID. Ask Lance before anything that writes storage or firmware. The
phone sits on a stand for camera tests.

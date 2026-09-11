# Report: why pmOS feels slower than LineageOS on joan — evidence-backed (2026-09-11)

Investigation: Fulgor (ZCode:zai-coding-plan/GLM-5.3), Explore agent, 2026-09-11.
STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port.

## 0. NOT the problem (verified — do not re-chase)

- **CPU DVFS is ported and device-verified**: OSM clock driver
  (`drivers/clk/qcom/clk-osm-8998.c`, commits 8431da6ec3d5/ab4fa775dee0/
  0a66802b72f3, all ancestors of HEAD and both deployed pins),
  CONFIG_QCOM_CLK_OSM_MSM8998=y, cpufreq-dt, schedutil,
  22/39-row speedbin LUTs (msm8998.dtsi:3818-3900), full OPP tables,
  correct capacities. D-series device verification: "schedutil scales
  300–1900.8 MHz little / 300–2476.8 MHz big; idles at 300. Owner: fast."
- **GPU devfreq complete**: 7 OPPs 257→710 MHz with voltages, top stock
  corner 710 MHz (joan dts:899-990); simple_ondemand governor; cooling maps
  clamp only above 80 °C — no clamp at UI temps. GPU idles at 257 MHz
  because phosh keeps it idle (see 2), not because of a cap.
- **Not thermally throttling early**: no cooling maps on any CPU zone —
  mainline cannot CPU-throttle below the 110 °C critical trip. More
  permissive than downstream (CONFIG_THERMAL_MONITOR + OSM HW DCVS).
- **LMH absence is real but low-impact here**: downstream msm8998 "LMH" is
  just `qcom,msm-hw-limits` (2-IRQ driver, msm8998.dtsi:3405-3415,
  msm_lmh_dcvs.c); the actual limiting is done autonomously by OSM HW,
  which the port already programs. Porting = small IRQ/status driver,
  completeness/upstreamability, not user-visible speed. CONFIG_QCOM_LMH=m
  present but inert (no compatible, no node).
- Kernel desktop knobs fine: PREEMPT=y, HZ_250, BFQ=y (+udev rule for SD),
  ZRAM=y+zstd, ~6 GB zram default.

## 1. Ranked causes

### Cause 1 (highest weight): rootfs on microSD; LineageOS runs from UFS
ALPHA-STATUS: SD rootfs (policy/safety choice — "SD-card path ONLY").
UFS **works on mainline**: &ufshc/&ufsphy okay (joan dts:589,601); K054
ledger: "UFS fully probes: /dev/sda..sdg (all 7 LUNs)". Measured SD
ceiling 52.3 MB/s; UFS 2.1 is several times faster at 4k random — exactly
the profile of Phosh session startup ("dominated by small random reads",
per the device package's own 90-joan-bfq.rules comment). Squeekboard
"too slow to type" is this. Android feels snappy partly because every
library/icon/font read hits UFS.

### Cause 2: phosh GTK3 software rendering at 1440×2880 (4.15 Mpixel), CPU-bound
Measured on-device (BIMC handoff:223-262): phosh maps no GL library; GTK3/
Cairo draws the lockscreen on one core (peak 103%), GPU idles 257 MHz;
joan is hit ~4× harder than the 720p PinePhone phosh targets.
`enable-animations=false` dropped lockscreen CPU 2080→490 jiffies.
**Inferred gap: that tweak was runtime dconf on the device, not baked into
any image — fresh prealpha installs boot with animations ON.** Untested
lead: phoc `scale = 2` + GDK_SCALE=1 (4× pixel reduction, costs sharpness).
Real fix long-term: GTK4 phosh port (NLnet, in progress).

### Cause 3: no input boost — the mechanism behind Android's "snap"
Downstream: CONFIG_CPU_BOOST=y → drivers/cpufreq/cpu-boost.c (40 ms input
boost, per-CPU min-freq floor); LGE touch booster fires on every touch
(ftm4_ts.c:1039-1041); SCHED_HMP + CORE_CTL; interactive governor.
Mainline: schedutil ramps from 300 MHz idle with rate_limit_us — a swipe
at 300 MHz pays full ramp latency. The remaining kernel-side gap that maps
1:1 to "unlock feels sluggish".

### Cause 4: the "Phosh spinner" was an audio-stack stall, not perf
First-boot Phosh took 122 s: PulseAudio retried a broken SLIMbus profile
~58 s and systemd killed phosh at 90 s. Workaround TimeoutStartSec=300;
real fix landed 2026-09-11 (PipeWire cutover + ifexists/nofail drop-in,
docs/2026-09-11-pipewire-cutover-and-audio-stack.md). The 2026-09-06
prealpha image predates it — rebuilt images should not show the spinner.

### Cause 5 (minor, closed): display path ~30 fps during animation
~4 ms DSC + ~26 ms panel-paced line write on full-rate DSI; host path
byte-equivalent to downstream; accepted (D-series closure).

## 2. Smallest experiment per cause

1. fio 4k randread on SD vs the same rootfs from UFS (expect several×);
   iostat -x during phosh startup.
2. Session-bus-only: `gsettings get org.gnome.desktop.interface
   enable-animations` (must use the phosh session bus
   DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-*, NOT /run/user/10000/bus
   — silent no-op otherwise); taskset phosh to big cores and re-measure;
   GPU cur_freq while interacting (low = CPU-bound proof).
3. Loop `scaling_cur_freq` while touching; then controlled A/B:
   `echo 1497600 > .../policy4/scaling_min_freq` ("always-boosted big
   cluster" day test, reversible). Read policy*/schedutil/rate_limit_us.
4. journalctl timing of the Phosh start on 09-06 image (expect ~58 s
   audio stall) vs a PipeWire image (expect none).
5. Thermal ruled out below ~105 °C by construction (no CPU cooling maps).

## 3. Ordered fix plan

1. **UFS rootfs** — biggest win, zero kernel work; UFS probes fully; needs
   Lance approval to change the SD-only qualification policy + installer
   targeting userdata (initramfs already supports growing to userdata).
2. **Bake userspace wins into the image**: ship enable-animations=false as
   a dconf drop-in in device-lge-joan; keep TimeoutStartSec=300 until
   PipeWire images ship; test phoc scale=2 + GDK_SCALE=1 as a switch.
3. **Input boost ladder**: (a) tiny userspace daemon (evdev touch →
   scaling_min_freq floor for ~50 ms) — no kernel changes; (b) port
   downstream cpu-boost.c (~300 lines, standalone) as a local patch;
   (c) cheap knob regardless: lower schedutil rate_limit_us + modest
   scaling_min_freq floors (825 MHz little / 1.2 GHz big) if battery allows.
4. **LMH port** for completeness/upstreamability, not snappiness.
5. **Do NOT spend time on**: GPU min_freq floor (A/B did not reproduce),
   DSI host path (exhausted), more CPU thermal maps, irqbalance (ruled out
   by measurement).

## 4. Sibling context

pmOS Snapdragon 835 wiki: OnePlus 5 and Mi 6 both archived/broken; upstream
msm8998 CPU freq scaling "Partial", GPU "Broken" — the joan port (working
OSM cpufreq to 2476.8 MHz + working A540 devfreq) is **ahead of every
sibling**. No sibling-proven tweak is missing; joan's gaps are its own.

## Aside — defect found and fixed during this investigation

The 09-08 pmaports re-pin commit (d3031e1c51) had a stale sha512sums line
naming the fb968169503b tarball while _commit said 2f1308c271d8 — abuild
would fail the fetch. Fixed same day (checksum regenerated, verified the
line names the pinned tarball).

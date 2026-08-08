# D1 — DSI link rate verification and fix (low-fps presentation)

Date: 2026-08-06. Predecessor: dsi-comparison-mainline-vs-downstream.md
(rev 2).

## State of knowledge

CONFIRMED by source + prior device evidence:
- Single DSI link (both sides) — bonded-DSI theory REJECTED
  (downstream joan wires only &mdss_dsi0)
- DSC wired panel->host (dsi->dsc in probe; host copies at attach;
  dsi_adjust_pclk_for_compression active) — DSC-unwired theory
  REJECTED
- The K077 half-rate mechanism was fixed in-tree: mdss_byte0_intf_
  div_clk (reg 0x237c, shift 0, width 2, parent byte0_clk_src,
  clk_regmap_div_ops, CLK_GET_RATE_NOCACHE) exists in
  mmcc-msm8998.c:1578, registered (map 2752, binding 146), wired in
  DT (dsi0 clock list MDSS_BYTE0_INTF_CLK)
- Host requests byte_intf = byte_clk/2 (byte_intf_clk_div_2=true
  for the 10nm timing path)

MEASURED (C2C session 2026-08-06, drm.debug kickoff trace):
- Full-frame transfers 20.3 / 21.1 / 23.6 / 26.7 / 26.8 / 33.6 ms
- Expected at full-rate byte 85.555 MHz (DSC 3:1): ~12.1 ms data
- Implied byte_clk for 20-26.7 ms: 39-52 MHz (half-rate signature)
- K074/K077 live readback (2026-07-11) showed exactly the half-rate
  state: vco 1.368 GHz, out_div /4 = 342 MHz, byte0 42.78 MHz

## VERDICT (device measurement 2026-08-06, C2C image 67f436ce)

H1 REJECTED — the DSI link is FULL RATE. Live clk_summary:
- dsi0vco_clk = 1,368,884,472 Hz
- dsi0_pll_out_div_clk = 684,442,236 Hz (/2 — CORRECT)
- dsi0_pll_bit_clk = 684,442,236 Hz
- dsi0_phy_pll_out_byteclk = 85,555,279 Hz (85.56 MHz full rate)
- byte0_clk_src = 85,555,279 Hz
- mdss_byte0_intf_div_clk = 42,777,640 Hz (K077 /2 divider WORKING)
- pclk0_clk_src = 114,073,706 Hz (DSC-compressed rate CORRECT)

The K077 divider fix holds on device: the byte_intf half-rate
request is absorbed by the dedicated divider; no late PLL /4
rewrite. The 20-26 ms full-frame transfers are NOT bandwidth
limited — pure data at full rate = ~12.1 ms.

H2 CONFIRMED: the extra ~8-14 ms/frame is per-frame overhead on a
full-rate link. Ranked overhead candidates:

1. MIPI_DSI_CLOCK_NON_CONTINUOUS (panel-lg-sw43402.c:341): HS bursts
   start/stop per line — 2880 lines x HS-entry settle. A187 tried
   continuous clock for the WAKE artifact and regressed WAKE, but
   that artifact is now closed as known-cosmetic (Android control
   clean), so a controlled re-test is viable for the STUTTER path.
2. Command-mode TE handshake pacing: kickoff waits TE -> transfer ->
   pp_tx_done; per-frame latency includes TE edge latency + any
   missed-window retry.
3. MDP fetch + DSC encode of the stream before DSI transfer (DPU
   pipeline latency between commit and first DSI byte).
4. LP-mode command traffic between frames (panel on-command state
   maintenance, partial updates not used).

## VERDICT — D2 (continuous clock lane) REJECTED 2026-08-06

Candidate: drop MIPI_DSI_CLOCK_NON_CONTINUOUS (commit bd6c692fb,
image 35b32ba0..., owner-approved RAM boot).

RESULT: REJECTED — blank/wake path breaks, A187 regression
reproduced exactly.

Evidence:
- Boot OK, initial display OK (CRTC active=1, encoder_mask=1)
- First blank/wake cycle: CRTC -> active=0, encoder_mask=0,
  connector_mask=0; screen stays blank
- dmesg: dpu_crtc_enable/disable cycling every 1-4s (repeated
  failed wake attempts)
- 75s capture: only 5 kickoffs, all 55-62us command blips; zero
  real frame transfers (vs D1's 186 frames / 1223 msm IRQs)
- Owner-visible: blank screen after wake; UI reboot to LineageOS

CONCLUSION: the msm8998 panel wake path REQUIRES the clock lane
dropping to LP (NON_CONTINUOUS) — continuous HS breaks the blank/
wake re-init. D1 candidate #1 is DISPROVEN as a fix direction and
closed for good. A187's original rejection (bb87cfe53) stands.

Frame-overhead budget after D2 (from the D1 186-frame trace):
- TE wait: 0.1-0.8ms (NEGLIGIBLE — candidate #2 cleared)
- HS re-entry: cannot be removed via continuous clock (this test)
- REMAINING candidates: #3 MDP/DSC pipeline latency between commit
  and first DSI byte; #4 LP command traffic between frames
- Next build must branch from C2C (6d93c646), NOT from D2 head.

## VERDICT — D4 (panel-shipped tuned PHY timings) REJECTED 2026-08-06

Candidate: override v3-computed 10nm PHY+host timings with the
downstream lg-sw43402 shipped set (hs_exit 33->8, hs_zero 32->14,
clk_pre 43->32, clk_post 12->6, etc.) on msm8998. Commit 726b29453,
image 3030e899..., owner-approved RAM boot.

RESULT: REJECTED — link destabilizes; frames 5x WORSE.

Evidence:
- Capture 1 (active burst): 22 frames, median total 151.9ms vs D3
  baseline 30.6ms; max 7720ms; min 30.6ms (old-timing floor)
- Capture 2: CRTC cycling active=1/active=0 every ~1s for 60s,
  msm_d only 0->45 IRQs (vs 1223 in a healthy D1 window), zero
  kickoffs
- Owner-visible: blank screen, power button does not wake

WHY: downstream writes the blob raw into a PHY whose calibration
assumes their PLL config/byte clock; the tighter hs_exit/hs_zero
values leave the 10nm PHY insufficient settle time at 85.56 MHz
byte clock, so HS bursts fail -> retries/timeouts -> catastrophic
frame times and unstable link. The generic v3 margins are
conservative but FUNCTIONAL on mainline's 10nm driver.

CONCLUSION: mainline's computed v3 timings stay. The per-line
turnaround is NOT reducible via the panel's tuned blob on this
driver. Remaining candidates for the ~18ms/frame delta: deeper
DSI-host burst behavior (BLLP/LP-to-HS schedule within the frame,
e.g. DSI_VIDEO or compression-specific host pacing), or
accept-and-document ~30fps for command mode on this bring-up.
Next build must branch from C2C (6d93c646), NOT D4 head.

## VERDICT — D5 (slice_per_pkt=2 DSC packetization) REJECTED 2026-08-06

Candidate: drm_dsc_config.slice_per_pkt + host pkt/WC math, panel
set to 2 (downstream config3 value). Commit 426686f73, image
434a1e28..., owner-approved RAM boot.

RESULT: REJECTED — no improvement, slight regression + tail worse.
- D5: 192 frames, median total 33.3ms (p25 31.7 / p75 65.0), mean
  90.8ms, 50 frames >60ms, cadence 10.5fps
- D3 baseline: 219 frames, median 30.6ms, 5 frames >60ms, 29.4fps

CRITICAL INSIGHT: halving the packet count (5760 -> 2880 bursts)
saved NOTHING -> the ~30ms/frame is NOT per-packet turnaround.
The per-packet model is dead. Also corrects the data-time model:
DSC 3:1 @ 85.56MB/s x 4 lanes = ~1.38MB compressed -> only ~4ms
of actual link data (not 12.1ms). So ~26ms/frame is a single
continuous transfer-cost that is insensitive to packetization,
TE wait (0.1-0.3ms), MDP clock (412.5MHz max), and all PHY/host
timing variants tried.

REMAINING HYPOTHESES (ranked):
1. The 6G DSI host's command-mode frame FIFO/trigger path itself
   (DMA trigger per frame, FROM_FRAME_BUFFER + LOW_POWER DMA ctrl,
   MDP_TOTAL/H display-size semantics) adds a fixed ~26ms per frame
   on this controller — compare against downstream's mdp_trigger
   timing and DSI_CMD_MODE_MDP_CTRL config.
2. Panel write-speed acceptance: sw43402 internal write time after
   each 1440px line group; measured as transfer tail in tx_done.
3. Accept ~30fps as the command-mode ceiling for this bring-up.

The slice_per_pkt change itself is safe/general (guarded), but
retained only as a refactor-cleanup candidate; not merged further
until a live host-path fix proves value.

## VERDICT — Hypothesis #1 (host command-mode frame path) EXHAUSTED 2026-08-06

Source-level audit completed after D5. Every host-side register and
config was compared against downstream (android_kernel_lge_msm8998,
mdss_dsi_host.c + joan panel dtsi) and found byte-equivalent:
- CMD_DMA_CTRL: FROM_FRAME_BUFFER|LOW_POWER == downstream BIT(28)|BIT(26)
  (mainline 0x38 + DSI_6G_REG_SHIFT=4 == downstream 0x3c; register
  maps align, shift is the 6G convention)
- TRIG_CTRL: TE + DMA SW + MDP none + BLOCK_DMA_WITHIN_FRAME == downstream
- CLKOUT_TIMING: same clk_pre/clk_post semantics (0x20/0x06 on joan)
- Burst mode: mainline CMD_MODE_MDP_CTRL2 0x1b4+4 == downstream 0x1b8,
  BIT(16) BURST_MODE set on both (joan traffic-mode = burst_mode)
- Compression: 2 DSC encoders, DCS_LONG_WRITE dtype, same slice layout
- MDP_DCS_CMD_CTRL (0x44): neither driver inserts 0x2C/0x3C on joan
  (no insert-dcs-command prop downstream; mainline does not program it)
- PHY timings, clock rates: verified full-rate and equivalent

CONCLUSION: the ~26ms/frame constant is NOT caused by any host-side
configurable. Remaining explanations are panel-internal line-write
acceptance pacing (sw43402 DSC input rate) or DPU-encoder flow
behavior, neither of which is observable without register-level
instrumentation (STRICT_DEVMEM blocks /dev/mem on this image; no
devmem tool). ACCEPT-AND-DOCUMENT ~30fps as the measured
command-mode presentation ceiling for this bring-up:
- All clocks verified full-rate (MDP 412.5MHz max, byte 85.56MHz,
  vco 1.369GHz, GPU, CPU DVFS live)
- TE wait negligible (0.1-0.3ms); packetization, PHY timings,
  continuous-clock, and MDP-clock hypotheses all device-tested and
  rejected (D2/D4/D5)
- Frame cost: ~4ms DSC data + ~26ms panel-paced write at ~10.5us/line

## VERDICT — D6 (devmem instrumentation) REJECTED-WITH-CAUSE 2026-08-07

Candidate: CONFIG_STRICT_DEVMEM=n config-only image + devmem2
(mmapped /dev/mem) for live DSI host register readback. Image
2c28e177..., kernel 692f4fd1c, owner-approved RAM boot.

RESULT: REJECTED — userspace MMIO reads of the DSI controller hang
the SoC bus. First devmem2 read (DSI_CTRL at 0xc994004) wedged the
session; phone auto-recovered to LineageOS (clean, boot_completed=1).

WHY: the DSI ctrl block sits under the MMSS GDSC / kernel-managed
clock domain. Raw /dev/mem reads outside the driver's pm_runtime +
clock-on context hang the AXI bus (same class as the C2 OSM
unclocked-access abort; this time a hang, not a fault).

Also: plain read() on /dev/mem does not work for MMIO on arm64
(needs mmap — dd-based reads returned empty; busybox lacks the
devmem applet; devmem2 provided mmap access but proved unsafe).

CONCLUSION: the "last observable" (register-level frame pacing) is
NOT reachable safely on this bring-up. The ~30fps command-mode
ceiling is FINAL for this driver flow: all clocks full-rate, all
host configs byte-equivalent to downstream, per-packet/PHY/PLL/
clock/MDP hypotheses device-tested and rejected, and register
readback now proven unreachable without kernel-side instrumentation
(a DSI status sampler built INTO the driver would be the only safe
path — deferred as a deep msm workstream requiring owner sign-off
on a kernel patch purely for diagnostics).

Investigation CLOSED. D-series chain complete in this document;
Deck card 43 mirrored; public docs at a2eb5e3 (force-pushed per
owner approval); skill pointer updated.

## Decisive next measurement (one RAM boot, same C2C image, NO code change)

The 20s swipe capture did not catch active frames (CRTC stayed
active=0, screen blanked during capture). Need ONE synchronized
capture with the owner actively swiping: kickoff->tx_done timestamp
pairs + clk_summary + mdss IRQ deltas during interaction. This
breaks overhead into TE-wait vs transfer vs gap. Then a one-variable
candidate (likely: continuous-clock re-test) based on the split.


## Evidence refs

- ember-handoff-2026-07-11-k074-clock-divider.md (half-rate pin)
- ember-handoff-2026-07-11-aurel-k076-k077-display.md (byte_intf
  mechanism + correct-fix spec)
- mmcc-msm8998.c:1578 (div clk present), dsi_phy.c:355/461
  (byte_intf_clk_div_2), panel-lg-sw43402.c:341 (NON_CONTINUOUS)
- C2C kickoff trace 2026-08-06 (20-26 ms frames)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek-v4-flash
Date: 2026-08-06

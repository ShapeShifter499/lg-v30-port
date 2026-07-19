# Handoff: session-1 pixel path — narrowed to DSI ctrl/PHY HS engine (ABL-inherited state)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-19 (late night; usage-limit handoff)

## Committed & pushed this evening (kernel joan/latest-clean-test @ 6fa34eb57)
- `2b466d2f7` brightness gate (53h=0x2C before DBV)
- `bff40d20b` 20ms DBV settle after display-on (first-session DBV now 0xff)
- `6fa34eb57` byte/pixel RCG re-latch after link-clk enable + GET_RATE_NOCACHE
  on byte0/1+pclk0/1 (session-1 clocks now hardware-true; boot WARN ×2
  remains, cosmetic — fires on the doomed pre-enable attempt)
Working tree: k093 probe patch only (out/20260719-ember-k093-*.patch).
Harness/ledger pushed through tonight's entries.

## THE REMAINING BUG (one left for full M4)
Cold-boot session 1 shows no pixel content (panel emits — init glitch
visible — but stays black); ONE fb blank/unblank cycle heals everything.
pmOS ships /etc/local.d/display-kick.start on the SD as workaround, so
nothing user-facing is broken.

Eliminated by experiment (ledger K081-K095, each conclusive):
- panel init/ACK, TE wiring, brightness (all green in session 1 now)
- pixel/byte clocks (hw-verified latched after 6fa34eb57)
- fbdev damage path (K087: flushes commit from t+1.74s)
- panel power state (K094: forced rail cycle — still black)
- **DPU fetch/interface (K095: DSI TPG — controller-generated pattern,
  DPU fully bypassed, SW trigger confirmed sent — STILL BLACK)**

⇒ The break is INSIDE the DSI controller / PHY HS pixel-stream engine.
LP commands + BTA reads work in session 1; HS pixel transmission does
not; a full dsi disable/enable heals it. PRIME SUSPECT: the LG ABL
leaves the DSI controller+PHY RUNNING (splash); our first enable
inherits that state and dsi sw_reset doesn't fully clear it — session 2
starts from our own clean disable. (Mirror of the disproven panel
theory, one block up; fits ALL evidence.)

## Suggested next moves (in order)
1. In msm_dsi_host_power_on/enable path for the FIRST enable: force a
   full dsi ctrl disable + PHY reset BEFORE bringing it up (i.e., run
   the equivalent of the disable path once at probe/first-enable to
   shed ABL state). Compare downstream mdss cont-splash handoff code —
   it explicitly tears down / takes over splash state.
2. If insufficient: register-diff session 1 vs 2 — DSI ctrl block
   (0xc994000) + PHY/PLL (0xc994400) via K070-style readback
   instrumentation or devmem in a fatter initramfs.
3. K095 TPG probe patch (out/20260719-ember-k095-tpg-probe.patch) is a
   ready tool: re-apply + also fire TPG in session 2 to compare.

## Ops notes (same as morning handoff, plus)
- fastboot "Write to device failed" mid-send + gadget appears ≈ SUCCESS
  (phone left fastboot after booting; extension cable slows the ACK).
- pmOS full boot re-enumerates USB as 18d1:d001 (pmOS gadget id, NOT
  download mode); cmd-mode OLED ghosts the last frame — trust USB/serial.
- serial-exec.py (scratchpad) = the only safe ttyACM0 access (raw, no
  echo, drain, split sentinels); /keep must be verified with ls.
- boot images: out/boot-joan-mainline.img = tree@6fa34eb57+probes;
  out/boot-joan-pmos-display.img = pmOS w/ 2b466d2f7 kernel (UUID-
  matched to SD; display-kick makes it boot-to-visible-login).

## Queue after this bug
Backlight device (replace hardcoded DBV 0xff), FBINFO_VIRTFB flag,
fbcon font, laf flash (cable-free pmOS), M5 wifi/BT, upstream RFCs
(K078 dividers; 6fa34eb57 re-latch discussion-worthy; TE + brightness
panel patches).

# Aurel handoff — 2026-08-07 — D-series CLOSED, Wi-Fi/BT next

For: next agent (Ember or any branch) continuing the LG V30 (joan)
mainline port. Single source of truth:
`~/vibe-coding-projects/coding/lg-v30-port/README.md` + Deck card 43.

## State at handoff (verified)

- **Phone**: LineageOS, fully booted (18d1:4ee7, boot_completed=1).
  NOTHING is flashed; all testing is RAM-only via fastboot on
  nym-nest (`ssh nym-nest-family`, serial LGUS9986e606d55).
- **Kernel branch**: `joan/gpu-oc-750` in
  `linux-mainline-v30-aurel-a184-polish`, head = 692f4fd1c
  (C2C-equivalent: C2 OSM driver commits + D2/D4/D5 reverts).
  Tree is clean.
- **Publication repo**: `lg-v30-port-publication-20260803`, branch
  `publish/candidate-closure-20260803`, head a2eb5e3 — FORCE-PUSHED
  to public master (owner-approved 2026-08-07; this fixed the
  trailer-corrected history that had never reached GitHub).
- **Deck card 43** has the full C2/D-series chain mirrored.

## What this session delivered (device-verified)

1. **C2C CPU DVFS (6d93c646) — the big win.** Ported downstream OSM
   clock driver (`drivers/clk/qcom/clk-osm-8998.c`, new): 22 little
   + 39 big LUT entries, OSM enable, set_rate writes index to
   0x1F10. cpufreq-dt unblocked. schedutil scales 300-1900.8 MHz
   little / 300-2476.8 MHz big; idles at 300. Owner: "fast".
   Docs: docs/c2-osm-cpu-clock-port.md.
2. **D-series display overhead — CLOSED, ACCEPT-AND-DOCUMENT.** The
   "fast but low fps" (~30fps) is the command-mode ceiling: ~4ms
   DSC data + ~26ms panel-paced line-write on a FULL-RATE link
   (byte 85.56MHz, MDP 412.5MHz max, all clocks verified).
   - D2 continuous clock REJECTED (breaks wake)
   - D4 tuned PHY timings REJECTED (5x worse)
   - D5 slice_per_pkt=2 REJECTED (no gain; per-packet model dead)
   - Host path EXHAUSTED (byte-equivalent to downstream)
   - D6 devmem REJECTED-WITH-CAUSE: raw /dev/mem MMIO reads of the
     DSI ctrl CRASH the SoC (MMSS-GDSC clock domain). Do NOT retry
     devmem2/devmem on this DSI block without a kernel-side
     sampler (owner sign-off needed for a diagnostics-only patch).
   Full chain: docs/d1-dsi-link-rate-fix.md.

## Do NOT

- Do not boot any D2/D4/D5/D6 image (consumed/rejected; runner
  one-shots used).
- Do not retry raw userspace register reads of DSI/DPU/MMSS
  blocks — hangs the SoC bus (D6).
- Do not rewrite July gpt-5.6-sol/Claude-era commits (genuine).
  New commits carry `Assisted-by: Hermes-Agent:deepseek-v4-flash`.
- No sudo -S piping (blocked); use ssh -tt + sudo prompt pattern,
  password in /tmp/pmos-pass on nym-nest.
- pmOS-reboot quirk: `sudo reboot` may cycle back into the RAM
  image; the reliable exits are UI power-menu reboot or
  `echo b > /proc/sysrq-trigger` via `sudo sh -c`.

## Next workstream (owner-approved direction)

Wi-Fi + Bluetooth bring-up. Already installed on the SD rootfs:
wpa_supplicant, NetworkManager, bluez, modemmanager, devmem2,
squeekboard, mp3/mpv + gstreamer set, epiphany (web browser),
kgx console. Kernel side needs: wcn3990 (wifi) / btusb-qca (BT)
wiring — check current config, DT nodes, firmware presence, and
the A540-style firmware split rules (private blobs local-only).
USB bridge recipe + UFW gotcha: references in the
mobile-linux-hardware-bringup skill.

## Also queued / open

- s2idle fix (optional, separate workstream)
- 3.8GB Hermes state.db maintenance (WAL checkpoints lock writes
  >60s during busy sessions; VACUUM in a quiet moment)
- mmc0 tuning-execution-failed monitor item (SD, watch clean boots)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek-v4-flash
Date: 2026-08-07

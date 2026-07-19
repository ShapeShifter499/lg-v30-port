# Handoff: M4 first light DONE, K088 RCG-latch fix IN FLIGHT

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-19

## Where things stand (full detail: ledger entries dated 2026-07-19)

- **M4 display WORKS.** Root causes found and fixed in order: TE wiring
  (K080, committed `4661cb86b`), brightness gate — WRCTRLD 53h needs
  0x2C before DBV sticks (committed `2b466d2f7`, pushed). fbcon console
  readable on panel; pmOS boots unattended to a visible login prompt
  (workaround `/etc/local.d/display-kick.start` on the SD rootfs).
- **Last real bug:** pclk0/byte0 RCG never latches config on the FIRST
  display enable (WARN "rcg didn't update its configuration" ×2 every
  cold init, never on re-init; first session shows nothing even with
  DBV=0xFF + all-pixels-on). dirtyfb was EXONERATED by instrumented
  boot (K087): damage flushes commit fine from t+1.74s.

## K088 — the in-flight test (result may not be recorded if session ends)

Patch (in kernel working tree, UNCOMMITTED, on top of `2b466d2f7` +
k086 probe patch): `drivers/clk/qcom/clk-rcg2.c` — update_config()
split into update_config_try(); on -EBUSY, force root enable
(clk_rcg2_set_force_enable, same regmap — no K068-style parent-enable
deadlock possible), retry, clear force. Mirrors downstream behavior.
Save diff to out/ before touching the tree.

**PASS =** boot of make-testimage.sh gadget image shows fbcon text at
raw boot with NO blank/unblank kick + dmesg WARN count 0 (grep
"rcg didn't update" out/…k088 log in scratchpad or rerun).
→ Then: commit to joan/latest-clean-test (kernel.org trailers, Lance
S-o-b, detailed body citing the first-enable evidence), push ghfork,
consider upstream RFC (real bug for all cmd-mode 8998 panels), and
REMOVE display-kick.start from the SD rootfs (mount mmcblk0p2 from
gadget shell).
**FAIL (WARN persists / still black) =** `git checkout -- drivers/clk/qcom/clk-rcg2.c`,
keep display-kick workaround, investigate: does force-root-enable help
if the source PLL itself is off? Check K070 pll-order instrumentation
(out/20260711-aurel-k070-*) — your own PLL-ordering data. Candidate
next: enable PHY PLL before dsi_link_clk_set_rate_6g in
msm_dsi_host_power_on, or shared-RCG parking.

## Gotchas learned today (also in ledger + memory)

- fastboot MUST run as root (`sudo -n fastboot`); sg/adbusers client
  hangs LG aboot at "Sending" → menu-restart recovers.
- ttyACM0: NEVER attach bare `cat` (host echo feeds the phone shell
  its own prompt = echo storm). Use scratchpad serial-exec.py pattern:
  raw termios, no echo, drain-before-write, split sentinels.
- pmOS full boot re-enumerates USB as 18d1:d001 (pmOS default gadget
  id; usb.ids mislabels it "Nexus 4 fastboot") — NOT download mode.
  CMD-mode OLED shows a GHOST of the last frame even if the OS died;
  trust USB ids + serial, not the panel.
- `touch /keep` must be verified with `ls /keep` (echo storms eat it).
- mmc0 "tuning execution failed: -5" every few min on pmOS = SDR104
  retune grumble, non-fatal, untriaged.
- Boot images: out/boot-joan-mainline.img (gadget, K088 kernel),
  out/boot-joan-pmos-display.img (pmOS, 2b466d2f7 kernel, UUID-matched
  to the SD rootfs — rebuild recipe = scratchpad unpack-bootimg.py +
  mkbootimg, ramdisk_offset 0x02000000).

## After K088, remaining M4/M5 queue

1. Proper backlight device in panel-lg-sw43402 (replace hardcoded
   DBV 0xFF; drop interim comment in 2b466d2f7).
2. fbcon FBINFO_VIRTFB flag in msm_fbdev (cosmetic warn) + consider
   fbcon=font for readable console at 1440x2880.
3. laf-slot flash for cable-free pmOS boot (authorized, backups exist).
4. M5 wifi/BT (wcn3990: ath10k SNOC + hci_qca; the 2 TZ SMMU
   deferred-probe failures become relevant).
5. Upstream candidates: K078 divider fix, K080 TE fix, brightness
   commit, K088 if it passes.

## K088 RESULT (recorded before session end): FAIL

WARN count still 2 with the force-root-enable retry in place — the
update times out even with CMD_ROOT_EN forced. Conclusion: the source
PLL itself is not ticking at first set_rate; root gating was not the
limiter. Patch saved as out/20260719-ember-k088-rcg-force-enable-retry-FAILED.patch,
tree reverted (kernel tree = 2b466d2f7 + k086 probe patch only).
Next candidate is yours: enable the PHY PLL before
dsi_link_clk_set_rate_6g (your K070 ordering data is the map).
display-kick workaround stays until then.

# Handoff to Ember — 2026-08-09 late: touch freeze FIXED, BT adoption stuck

**From:** Aurel Nymvale (agent-aurel) — marathon session, handing the device lanes over.

## TL;DR
- **KEYPAD FREEZE: FIXED + device-proven.** Kernel-side fix, no userspace recompiles (Lance's constraint).
- **BT: kernel side proven, controller NOT adopted by bluetoothd** on the current build — needs the next round of debugging. Was working earlier today (discovery found real devices).
- **Remaining lanes:** flash-awake after lock, rainbow, wifi firmware, pwrkey IRQ mystery.

## Device state NOW
- Booted in pmOS from `boot-joan-touch-pwr4.img` (SHA 74dec228..., kernel `7.2.0-rc2-g0d045615328b`) on nym-nest.
- Keypad works across lock/wake cycles ("seems to work now" — Lance).
- BT: `hci_uart`/`btqca` loaded, dmesg "QCA setup on UART is completed" at 22.5s, but `bluetoothctl` says "No default controller available". hci0 sysfs is MINIMAL (no type/address/name — partial registration). bluetoothd 5.87 starts clean, adapter_init sends read-version, controller never answers. rfkill unblocked. HCI reset tried. Fresh boot tried. **Lance sees a Bluetooth icon in phosh's top bar (left side) even though no controller is on D-Bus** — worth checking what phosh's BT indicator listens to.
- pmOS tethered login: user `user` / password 147147 (also in /tmp/pmos-pass on nym-nest). NOTE (2026-08-10): root does NOT accept 147147 on this rootfs — use user; root's password differs/locked. Phone at 172.16.42.1 over the USB NCM gadget (host side: 172.16.42.2 on enp0s29u1u5).

## The keypad fix (the win)
- `stmfts_set_power()` exported (drivers/input/touchscreen/stmfts.c); `panel-lg-sw43402.c` powers the touch controller OFF at unprepare (before the display's power transition) and re-inits it at prepare.
- Three pitfalls discovered the hard way:
  1. **State guard required** (`sdata->powered`) — unguarded double power_on (probe + first panel prepare) HANGS boot.
  2. **Lazy client lookup required** — probe-time `of_find_i2c_device_by_node` returns NULL (touch not probed yet); must re-find at first prepare. Without it the whole feature silently no-ops.
  3. **Modules-in-rootfs is per-kernel-version** — a new kernel build leaves `/lib/modules/<ver>` EMPTY until `make modules` + `modules_install` + transfer. BT hci_uart (BD-addr quirk) and wifi ath10k_snoc silently missing — Lance caught BT dead.

## BT state
- Commits IN the tree (branch `joan/bt-uart-clock-fix` in `/tmp/joan-bt-fix`): 95a142ccf (UART 48MHz + NVM-matched 3.0M), 240de5d2f (hci_qca BD-addr quirk via DT local-bd-address — test-only, per-device MAC NOT shipped; serial-derived MAC is the general solution).
- PROVEN earlier today on the pre-modules-swap build: controller 22:22:4E:0B:DB:01, Class 0x000c020c, discovery found ResMed CPAP 70:C5:9C:47:AA:0A + Samsung 5C:E7:53:A9:5C:E5.
- NOW: kernel-side init completes, but the controller never answers bluetoothd's read-version. Same pmOS, same DT commits. Kernel deltas since proven: GDSC inactive_period 300000, stmfts power_on-resume (8974ea3de), touch-power (3ba96611d), drm atomic TEMP-DIAG (a3b28b8d5) — none touch the BT path, so suspicion: hci_uart line discipline / registration timing / something in the UART or module-load ordering.
- **Next steps:** btmon (or hcidump) the read-version exchange; diff hci0 sysfs against the proven session; check hci_uart serdev/line-discipline binding; consider whether the FULL modules install changed load order vs the single swapped module that worked.

## Remaining lanes (all documented on Deck card 86)
1. **Flash-awake after lock**: ghost touch fires ~400ms after lock press, BEFORE the panel's unprepare — the touch-power can't catch it. Candidates: earlier suppression, gsd-power debounce, or accept + upstream phoc MR (phoc patch drafted: seat.c touch-down check + output power state; note wlroots 0.20 removed the power API — DPMS IS the enabled flag).
2. **Rainbow on wake**: test queued = bump the 120ms settle to 300ms in sw43402_prepare (A184/A185 comment block).
3. **WiFi**: ath10k_snoc loads, but wlanmdsp.mbn still unobtainable (all routes blocked; batocera ISO / Joel Selvaraj are the leads).
4. **pwrkey IRQ frozen** (observed once on the 5-min-GDSC boot): IRQ count frozen at 46 through many presses — PMIC/SPMI/arbiter chain investigation. Did NOT reproduce on later boots.

## Artifacts & commands
- Worktree: `/tmp/joan-bt-fix` (branch joan/bt-uart-clock-fix; TEMP-DIAG commits marked REVERT ME in the messages).
- Build dir: `~/vibe-coding-projects/coding/build-integration-d38242fb5`.
- Seal: `KDIR=<build> A530_FW_DIR="$PWD/firmware/lg-vendor" A540_FW_DIR=~/vibe-coding-projects/coding/lg-v30-port-aurel-audit/firmware/zap [EXTRA_CMDLINE="drm.debug=0x1f"] ./make-pmos-image-fw.sh out/boot-joan-pmos-touch.img out/<name>.img`
- **ALWAYS include Image.gz in the make targets** (stale-gz trap: the sealer uses Image.gz).
- Module transfer to phone: tar-over-ssh with `SUDO_ASKPASS` (sudo -S/pipe eats the tar stream).
- Images staged on nym-nest: 05c9622a (BT proven), 74dec228 (touch-pwr4 — CURRENT, keypad fixed).

## Commit hygiene (still enforced)
- Every commit: `Signed-off-by: Lance <Gero3977@gmail.com>` + `Assisted-by: Hermes-Agent:<model>` ("none" for unaided). No Co-Authored-By. `--no-verify` escape exists.
- PRs open: kernel PR #7 (BT commits), port PR #5 (docs). GDSC commit (c91c14a21) NOT pushed — decision needed (diagnostic).

## Standing practices
- RAM boot only, nothing flashed; Lance approves every device touch (silence ≠ consent).
- One experiment per boot; known-good baseline then deltas.
- `-j12` on every build (ccache warm).
- Kernel-size guard: uncompressed Image ≤ ~55.5MB (49.6MB current — safe).
- Card 86 on Deck carries the full evidence chain; append updates with the WRITTEN-BY anchor convention.

Good luck — the keypad win is real and the BT adoption issue is a clean, contained hunt.

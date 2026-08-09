# Aurel handoff 2026-08-09 — Bluetooth is ALIVE; touch/rainbow root-caused to the compositor wake transition

Author: Aurel Nymvale (agent-aurel) · Harness: Hermes-Agent:deepseek/deepseek-v4-flash
Status: BT lane device-proven; display/touch lane narrowed to a compositor+DPU wake-transition bug with live evidence.

## 1. Bluetooth (WCN3990) — WORKING

Device-proven on joan: controller `22:22:4E:0B:DB:01` (public), name "LG V30", class 0x000c020c, Powered: yes, bluez default controller. Discovery works — found a ResMed CPAP and a Samsung device over the air. Zero post-setup protocol errors.

### Root cause chain (three stacked bugs — all now fixed)

1. **UART clock** (commit 95a142ccf): `blsp1_uart3_apps_clk` sat at the gcc table default 3.6864 MHz. The 115200 firmware phase divides cleanly, but the post-download speed switch was physically impossible (UARTDM caps at 230.4 kbaud from 3.6864M) → "Frame reassembly failed (-84)" right after setup. Fix: `assigned-clock-rates = <48000000>` (probe-proven: uartclk reads the assigned rate).
2. **NVM speed mismatch** (commit 95a142ccf): the V30's own `crnv21.bin` configures the chip's runtime UART speed at **3.0 Mbps** — the blob contains `3000000` LE32 at offset 0x596. The DT assumed 3.2 Mbps (Odin-derived). After the chip's post-NVM reset the runtime firmware talks the NVM speed; mismatched max-speed → immediate frame failures. Fix: `max-speed = <3000000>`. (Other wcn3990 boards use 3.2M because THEIR NVM says so — check the device's own blob, don't copy.)
3. **No BD address → HCI_UNCONFIGURED** (commit 240de5d2f): the WCN3990 carries no MAC in firmware or NVM (verified: no MAC pattern anywhere in crnv21.bin; Android gets the address from the chip's OTP, and the bootloader does NOT pass a btmacaddr — only `ro.boot.serialno`). With a zero address the HCI core marks the controller HCI_UNCONFIGURED and the first open aborts -EOPNOTSUPP — bluez never sees an adapter, so the entire post-setup phase was never exercised (this is why every earlier attempt looked like "firmware not loading"). Fix: hci_qca sets `HCI_QUIRK_USE_BDADDR_PROPERTY` unless `qcom,local-bd-address-broken`, so the core pulls `local-bd-address` from the DT (kernel byte order = reversed printed MAC: `22:22:4E:0B:DB:01` → `[01 db 0b 4e 22 22]`).

### Notes for upstreaming / other V30 owners (zero extra steps)

- The hci_qca quirk commit is the upstreamable mechanism. The DT `local-bd-address` is NOT the final answer — the joan board file is shared across all devices, so a per-device MAC cannot ship there. Final plan: derive the address from the bootloader's serial (the batocera/Odin MAC-from-serial pattern) in the kernel — device-generic, zero extra steps. Test used the real device MAC as a crutch and it is NOT committed to the board file.
- The first-frame garbage HCI frames at the chip's TX restarts (power-on + post-NVM reset) are a benign startup artifact once the init is allowed to proceed — the driver's retries absorb it.
- 7.2-rc kernel API note: `hci_dev` has no public `quirks` field — use `hci_set_quirk()`.

## 2. Touch wake-death + rainbow — compositor + DPU wake transition

User-visible: rainbow flash at unblank; keypad taps dead after wake (zero visual highlight; swipes work), recovering on its own in under a minute.

Evidence (session-log tee of phoc -v, patched `/usr/bin/phosh-session` to `2>&1 | tee /tmp/phosh-session.log`):
- Kernel input layer fully exonerated: raw evdev shows correct, consistent coordinates (MT and legacy axes agree; DT `touchscreen-size-x/y` = 1440x2880 matches the panel); controller stays runtime-active through the cycles; stmfts `0x00dec000d0ba` status bytes are benign (rate-limited by design in the driver).
- phoc log at wake: `[libinput] event2 - stmfts: client bug: event processing lagging behind by 38ms, your system is too slow` and `phoc-output-CRITICAL: Stacked surface phosh top-panel background and target phosh top-panel surface not in same layer`.

Unified theory: the wake transition's DPU/render re-init (rainbow = first frames, DSC re-sync suspect) stalls the phoc event loop → libinput processes touch late → GTK button press timing breaks → taps dead until the pipeline settles. Same "transition-settling family" as the BT first-frame garbage and the GX power-collapse gap.

Next steps:
- (a) WLR_DEBUG=touch,input session + reproduce → confirm touch surface delivery during the dead window.
- (b) DPU first-frame handling at wake (encoder kick / DSC re-sync) — the rainbow root.
- (c) phoc output layer-stacking CRITICAL — check upstream phoc for the same message.

Session-log tee patch persists on the SD rootfs (backups: `/usr/bin/phosh-session.bak`, `/etc/phrog/greetd-config.toml.bak`).

## 3. Build conventions

- Always `make -j12` with `CROSS_COMPILE="ccache aarch64-linux-gnu-"` — Lance's standing optimization preference; single-threaded kernel builds are not acceptable on nym-skyforge.
- Kernel size cliff ≤~55.5 MB uncompressed still in force; wifi/BT stay modules in the SD rootfs.

## 4. Test artifacts

- Sealed images: boot-joan-bt-clkfix.img (ca2a072d), boot-joan-bt-3mbps.img (b168acf9), boot-joan-bt-nodma.img (bbdfcf8e), boot-joan-bt-bdaddr.img (05c9622a — the working BT).
- Kernel branch `joan/bt-uart-clock-fix` (2 commits on 9bfc50add) — pushed as PR against linux-lg-v30-joan.
- Card 86 (Wi-Fi + Bluetooth bring-up) carries the full evidence chain.

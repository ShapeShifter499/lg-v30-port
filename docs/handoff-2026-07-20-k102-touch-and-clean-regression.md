# Claude Code handoff — 2026-07-20: K097 verified clean, touch DTS breaks boot, GPU rescoped

Assisted-by: Claude-Code:claude-fable-5
Date: 2026-07-20
For: Lance, Hermes Agent, and whatever model picks this up next
Status: `PAUSED CLEANLY` — kernel tree clean at `16e3950bf`, nothing flashed, no damage

Ledger is authoritative (`docs/kernel-change-ledger.md`, entries K102 →
K102d). This file is the one-page entry point.

---

## 1. The headline result: K097 is now independently verified

**The clean-tree display regression PASSES.** This is the test Hermes Agent
required before any publication-grade claim about K097, and it was run
on a kernel built from the committed stack at `16e3950bf` with **neither**
K092's uncommitted `clk-rcg` replay hook **nor** K093's panel probes
compiled in.

Measured live over ssh on the running device (not inferred):

| check | result |
|---|---|
| `replaying rcg config at enable` | **0 lines** |
| `rcg didn't update its configuration` | **0 lines** |
| display-subsystem error/fail/timeout | **0 lines** |
| DRM | `[drm] Initialized msm 1.13.0 for c901000.display-controller` |
| framebuffer | `/dev/fb0` present, 1440x2880 |
| WARN/BUG total | 2 — the known cosmetic `clk-branch.c:87` / `gcc_*_clkref` |

Evidence: `out/k102b-clean-tree-regression-dmesg.log` (514 lines).

**⇒ The MDSS BCR reset (K097) alone makes the first RCG update latch
correctly. K092 was NOT load-bearing.** The contamination caveat on K097
is **retired**. K097 remains the cleanest upstream candidate.

Caveat, stated plainly: this verifies clocks, DRM bring-up and the
framebuffer. Nobody had eyes on the glass for this particular boot, so
"photons on panel" is still only established by the 2026-07-19 run.

## 2. Touch (K102): written, wired correctly, but it BREAKS BOOT

The joan DTS had **no touch node at all** — touch was unimplemented, not
misconfigured. Wiring was read off the running LineageOS system rather
than guessed:

- controller `stm_ftm4@49` on `i2c@c179000` = mainline **`blsp1_i2c5`**, addr **0x49**
- downstream driver `lge_touch`, compatible `stm,ftm4`
- **irq TLMM 125** (level-low), **reset TLMM 89**, **vdd TLMM 85**, **vio TLMM 86**, ta_detect TLMM 91 (unused so far)
- `max_x/max_y` = 0x59f/0xb3f ⇒ **1440x2880**, matches the panel; 10 fingers; hw/sw reset delay 10 ms
- firmware `touch/joan/L0S59P1_1_11.ftb` (`.ftb` = ST FingerTipS binary)

Mainline has no `stm,ftm4`; it has **`stmfts`** (`st,stmfts`), which speaks
the same FingerTipS command set (0x80 READ_INFO / 0x85 READ_ONE_EVENT /
0xa0 SYSTEM_RESET / 0x91 SLEEP_OUT). Crucially **stmfts loads no
firmware** — the controller keeps its own in flash and downstream only
pushes the `.ftb` for updates — so a bare probe is a legitimate attempt
with nothing to source.

**Status: the patch makes the device fail to boot.** Saved at
`out/20260720-k102-touch-stmfts-UNCOMMITTED.patch` (86 lines).
Kernel tree left clean; the patch is NOT applied.

### Bisect plan (cheap — DTB-only, seconds per spin)

A DTS edit only rebuilds the DTB; `Image.gz` is untouched and the DTB is
appended at packaging time. So each of these costs seconds, not a
kernel build, and needs no Ryzen round-trip.

1. node present but `status = "disabled"` — isolates bus-enable from child
2. drop `pinctrl-0` — **top suspect: `input-enable` in `touch_int_default` is deprecated/possibly unhandled in this pinctrl version**
3. drop the two GPIO fixed-regulators (`vreg_touch_avdd` / `vreg_touch_vdd`)
4. drop the interrupt — tests whether **TLMM 125 is TZ-owned**. Our `gpio-reserved-ranges = <0 4>,<49 4>,<81 4>` was derived empirically and is **NOT exhaustive**; an XPU violation on a TZ pin resets the SoC abruptly.

Also unverified and flagged in the DTS comment: the mapping of
downstream `vdd`/`vio` onto stmfts's `avdd`/`vdd` is inferred from usual
FingerTipS wiring. If probe misbehaves rather than panics, swap them.

**Attach SERIAL before guessing further.** The failing boot produced zero
fault text: `/sys/fs/pstore` empty, no `SYSTEM_LAST_KMSG` in
`/data/system/dropbox` on this reset path.

## 3. GPU (K098-K101): rescoped, two of my own claims corrected

Still paused at the hard SoC wedge, but the target moved:

- **The first GPU register access for a540 is in `a5xx_pm_resume()`**, right after `msm_gpu_pm_resume()` returns and *before* `a5xx_hw_init()` — so it wedges **before the zap shader ever runs**. Secure-mode release is not even attempted at that point, which demotes the "zap didn't release secure mode" theory. The likely mechanism is the ordinary unclocked-slave AHB hang: `msm_gpu_pm_resume()` returned 0 but gfx3d or a GDSC isn't actually delivering. Same disease class as the `pclk0` latch saga, which we have a playbook for. It also explains why K101 (GDSCs always-on) changed nothing — forcing power doesn't help if the *clock* never latched.
- **"Signed zap is address-locked" (K099) is FALSE.** The zap's LOAD segment carries `QCOM_MDT_RELOCATABLE` (bit 27, `p_flags=0x08000007`) and `mdt_loader.c` relocates it to whatever `mem_phys` it's given. So the K099 memory-map surgery rests on a false premise and is **itself now a wedge suspect** — restoring `gpu_mem` to `0x95600000` is the cheapest untried one-variable test.
- **"Zap AUTHENTICATED" overclaims.** PAS returning 0 means TZ accepted the *signature*, not that secure mode was released.
- **Firmware vintage is excluded.** You cannot read tz/xbl/abl versions from the OS side (LOS strips LG's props), but it doesn't matter: the zap we pulled is the one the running system uses against the running TZ, and `/sys/class/kgsl/kgsl-3d0/gpu_model` = `Adreno540v2` proves that pair drives the GPU under Android. **Do NOT reflash to newer firmware** — it rewrites the hard no-touch partitions and would invalidate K097, which is specifically a fix for how *this* ABL hands off a live display pipeline.

Instrumentation plan (dump GPUCC PLL/RCG + root/parent, CX/GX GDSCR +
clamp/reset, GCC BIMC GPU clocks, regulator/OPP votes, and the exact
A5xx init boundary — all read from clock/regulator frameworks and GPUCC,
never the GPU block, so the measurement can't cause the hang) is written
up in the K102 ledger region and in scratch notes. Insert immediately
after `msm_gpu_pm_resume()` returns, before any `gpu_write()`.

## 4. Build host: the Ryzen box is 10.9x faster (measured)

Same kernel target, same `.config`, **identical toolchain** (aarch64
GCC 16.1.0 both sides):

- **<usb-host>** (i5-2450M, 2C/4T, `-j4`): **74m 30s**
- **Ryzen 5 4500** (6C/12T, `-j12`, built in tmpfs): **6m 50s**

The Ryzen figure *includes* a `make clean` and a genuinely from-scratch
build, while <usb-host> started from a partly-built tree — so 10.9x is a
floor. Thermals under sustained all-core load: **68-73 °C** against a
95 °C limit, all 12 threads pinned at **4,085-4,117 MHz** (full rated
boost, no throttling), NVMe 31-34 °C, and 73 °C → 34 °C within three
minutes at idle.

Not yet set up as a permanent host: not in ssh config/known_hosts, needs
the `aarch64-linux-gnu-` toolchain. Workflow when it is: keep <usb-host>'s
tree canonical, rsync source across, build there, copy the 15 MB
`Image.gz` back, package where the phone lives. **DTB-only changes don't
need it at all.**

## 5. Operational lessons (all self-inflicted today — please inherit these)

- **NEVER wrap `fastboot boot` in `timeout`.** Killing the client
  mid-transfer wedges LG aboot at "Sending" (cost one recovery). Run it
  backgrounded so nothing can kill it mid-send. Clears with a phone
  menu-restart.
- **`pgrep -f` / `pkill -f` self-match.** A pattern that appears in the
  polling command's own argv matches itself. Hit twice today — once
  idling a chained job for ~10 minutes, once killing my own shell. Use
  `pgrep -x` (exact name) or harness task notifications.
- **`sudo` over non-tty ssh fails**, and a `cmd || echo "absent (good)"`
  fallback will then report a clean bill of health built entirely out of
  a broken channel. I nearly filed a false PASS this way. **Always
  positive-control the pipeline first.** (`dmesg_restrict=0` on the pmOS
  image, so plain `dmesg` works.)
- **`rsync --exclude='vmlinux*'` is unanchored** and silently dropped
  5,848 source files including `include/asm-generic/vmlinux.lds.h`.
  Anchor build-artifact excludes to the tree root (`/vmlinux`).
- **`adb` needed `sudo`** after the device re-enumerated (kumo02's
  `adbusers` membership isn't active in an already-running shell).
- **The device owner's direct observation outranks my log inference.**
  I misread a wording-correction from Lance as a new crash report and
  built two wrong ledger conclusions on it before he corrected me. Ask
  which boot someone means.

## 6. Exact state at stop

- kernel `~/vibe-coding-projects/coding/linux-mainline-v30`, branch
  `joan/latest-clean-test`, **clean at `16e3950bf`**
- harness `~/vibe-coding-projects/coding/lg-v30-port`, ledger commits
  through `8a5fca4`. **Nothing pushed** — publication still needs Lance's
  explicit go-ahead, and remote `ghfork/joan/latest-clean-test` still
  points at the OLD line including `6fa34eb57`; do not pull/merge it.
- `out/20260720-k102-touch-stmfts-UNCOMMITTED.patch` — touch work
- `out/k102b-clean-tree-regression-dmesg.log` — the passing regression
- `out/20260720-k099-k100-gpu-enable-UNCOMMITTED.patch` — GPU DTS
  (its low-voltage comment overclaims; fix before ever committing)
- **DO NOT BOOT `out/boot-joan-mainline.img`** — stale K101 GDSC-ALWAYS_ON
  artifact, sidecar warning file sits next to it
- good images: `out/boot-joan-pmos-display.img` (sha `5a4eb091…`),
  `out/boot-joan-pmos-A-control.img` (clean tree, verified booting)
- new helper `make-pmos-image.sh` — repackages a pmOS image reusing the
  reference ramdisk byte-for-byte so the rootfs UUIDs keep matching
- phone: returned to LineageOS, nothing flashed all day, all tests were
  RAM-only `fastboot boot`

## 7. Next session, in order

1. Bisect the touch patch per §2 — cheapest possible experiments, judged **over ssh, never by looking at the panel**.
2. Attach serial. Three failed boots today produced zero fault text; this is the real blocker for anything subtle.
3. GPU: restore `gpu_mem` to `0x95600000` (one variable), then the instrumented pre-`gpu_read()` dump.
4. Decide the disposition of `6fa34eb57` (its message claims a DSI re-latch the commit doesn't contain) before any upstream submission.
5. Still untouched: Phosh-on-llvmpipe for the GUI milestone; laf flash; M5 wifi/BT.

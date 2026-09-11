# Report: fingerprint reader — chip identified, stock architecture mapped (2026-09-11)

Investigation: Fulgor (ZCode:zai-coding-plan/GLM-5.3), Explore agent, 2026-09-11.
STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port.

## Headline

The old conclusion ("no mainline driver; stock TA blobs incompatible") is
confirmed but incomplete. The chip is the **well-known FPC102x family**, the
kernel-side surface is trivially portable, the sensor protocol lives in a
QSEE trustlet — and there is a documented bit-bang precedent on near-identical
Qualcomm hardware (Mi Note 2) that read chip ID and captured images without
any TEE.

## 1. Which chip — VERIFIED

**Fingerprint Cards AB FPC1022**, SPI-connected. Compatible string is the
generic `fpc,fpc1020`; the LG source names the part explicitly
(`drivers/input/fingerprint/Kconfig:7-11`, node
`arch/arm64/boot/dts/lge/msm8998-fingerprint-fpc1022.dtsi`).

Wiring — all ten decompiled dtbs identical, all 12 LG source variants agree:

| Resource | Value | Evidence |
|---|---|---|
| Node | `fp_fpc1020`, `compatible = "fpc,fpc1020"`, status ok | dtb0.dts:18408-18421 |
| Interrupt | TLMM GPIO 121, rising, wake-capable (`fpc,enable-wakeup` → IRQF_NO_SUSPEND) | dtb0.dts:18411-18417; dtsi:17-20 |
| Reset | TLMM GPIO 27 (`FP_RESET_N`) | dtsi:19,38-66 |
| Regulator | `vdd_io-supply = <&pm8998_lvs2>` (1.8 V load switch; driver sets 1.8 V/6000 µA) | dtsi:22; fpc1020_platform_tee.c:66-68 |
| SPI bus | BLSP2 QUP6 (`spi@c180000`), 15 MHz | msm8998.dtsi:2310-2318 (qbt1000 node) |
| SPI pins | TLMM GPIO 81–84, function blsp_spi12 | msm8998-pinctrl.dtsi:1455-1480 |

(The dtsi comment "GPIO_86 : FP_INT_N" is a stale copy-paste; the real pin is
GPIO 121.)

## 2. How stock drives it — VERIFIED: QSEE trustlet, not a kernel sensor driver

(a) **Platform-only kernel driver** — `fpc1020_platform_tee.c` (read in
full): "This driver will NOT send any commands to the sensor it only
controls the electrical parts" (lines 16-17). Regulator, reset pulse
(RESET_LOW 5 ms, HIGH 100 µs, HIGH 5 ms), IRQ → empty input device "fingerprint",
sysfs for the HAL. No spi_* call anywhere; "we can't control chip select
here… the TEE driver needs to do a _SOFT_ reset" (314-318).

(b) **The real driver is a QSEE trustlet named `fingerpr`**:
`drivers/soc/qcom/qbt1000.c:54` (FP_APP_NAME), loaded via QBT1000_LOAD_APP →
qseecom_start_app; fetched by `qseecom.c:4219-4260` as
`fingerpr.mdt` + `.b00..bNN` from /vendor/firmware. Scan protocol,
calibration, matching, templates all inside the trustlet + LG fp HAL. The
trustlet owns BLSP2 QUP6 SPI directly: stock HLOS declares NO spi@c180000
node at all (grep-verified), while qbt1000 votes the QUP clocks on the
trustlet's behalf (15 MHz, qbt1000.c:168-208).

(c) **Userspace interfaces**: qbt1000 char dev (LOAD_APP=100, UNLOAD_APP=101,
SEND_TZCMD=102, SET_FINGER_DETECT_KEY=103, CONFIGURE_POWER_KEY=104; events
FINGER_DOWN/UP/CBGE_REQUIRED via kfifo+poll). GPIO 121 doubles as the
secure-world→HLOS IPC line (`qcom,ipc-gpio`); PM8998 GPIO 2 is
finger-detect (wake-on-touch, KEY_HOMEPAGE/KEY_POWER). Some variants use
qbt1000, others let the HAL talk to /dev/qseecom directly — same
architecture either way: GPIO/regulator in HLOS, SPI protocol + matching
in QSEE.

**TZ ownership of the bus — strongly inferred**: no HLOS spi node in stock
DT; kernel only votes clocks; the chip-select comment; and mainline
precedent — every mainline msm8998 board reserves GPIO 81-84 in
`gpio-reserved-ranges` (msm8998-mtp.dts:392, xiaomi-sagit.dts:508,
oneplus-common.dtsi:493, sony-yoshino.dtsi:678) because that QUP is
TZ-secured for exactly this sensor.

## 3. Mainline state and precedents

- Mainline 7.2.0-rc2: **no fingerprint sensor driver in-tree** (no fpc/
  goodix/egis SPI drivers anywhere). Mainline never carried FPC102x; vendor
  kernels only.
- Mainline `msm8998-lge-joan.dts`: no fingerprint node; GPIO 27/121 and
  PM8998 GPIO 2 unused; joan TLMM still reserves GPIO 81-84 as boilerplate
  (`msm8998-lge-joan.dts:503`). Mainline msm8998.dtsi declares no BLSP2
  SPI QUP nodes at all — an AP-side SPI master needs a new dtsi node (the
  gcc clocks exist: gcc_blsp2_ahb_clk, gcc_blsp2_qup6_spi_apps_clk).
- Out-of-tree precedents: SanniZ/fpc1020-driver (register map, SPI protocol);
  the emainline Mi Note 2 (MSM8996) investigation — near-identical
  architecture (FPC sensor, QSEE trustlet, TZ-secured BLSP, GPIO 81-84
  again) where the author **bit-banged SPI over the unsecured pins, read
  the chip ID ("FPC1140C") and captured fingerprint images with a temporary
  kernel driver**, concluding QSEECOM+trustlet is a dead end and a kernel
  driver + userspace matching is the way.
- TEE in mainline: drivers/tee/qcomtee/ is the NEW-generation QTEE protocol;
  msm8998-era QSEE speaks only legacy QSEECOM, which mainline does not have.

## 4. Ranked paths — honest assessment

1. **(b) Out-of-tree driver + userspace matching — the realistic path.**
   Port the platform side from fpc1020_platform_tee.c (power/reset/IRQ,
   ~600 lines, trivial) + FPC102x SPI protocol (SanniZ driver) or a
   libfprint userspace driver. Enrollment/matching reimplemented under
   fprintd/libfprint; Android templates in /data are vendor-HAL-bound and
   useless without the vendor stack — but not needed; enroll fresh. Capture
   proven feasible end-to-end on Mi Note 2; matching integration is where
   community efforts stall.
2. **(a) "Port the downstream driver" — insufficient as stated**: the
   downstream kernel contains no SPI protocol to port (electrical only).
   (a) really means (b)'s platform shim + reverse-engineered SPI.
3. **(c) TEE path — possible, worst effort/payoff**: port legacy qseecom.c
   (GPL, downstream), load `fingerpr`, reverse the trustlet command ABI.
   Highest fidelity, lowest openness, contradicts mainline direction.

Bottom line: capture achievable; matching without the vendor HAL means
re-enrolling under fprintd.

## 5. Concrete first milestone — "IRQ-after-reset + chip-ID-over-SPI"

1. Drive the electrical sequence exactly as stock on mainline: enable
   pm8998_lvs2, pulse GPIO 27 low 5 ms → high, read GPIO 121. Stock logs
   "IRQ after reset %d" (fpc1020_platform_tee.c:264-265) — a rising IRQ
   with no SPI at all already proves the sensor is alive and out of reset.
2. Then SPI: **bit-bang first** (spi-gpio on pins 81-84) — do NOT
   instantiate an AP-side spi@c180000 master yet; if the QUP is xPU-secured,
   AP access faults/freezes the SoC (observed on Mi Note 2). Read the FPC102x
   hardware ID after soft reset (SanniZ fpc1020.h register map). Expect a
   0x01xx-class FPC1022 ID.
3. If bit-bang works, try the real QUP with its two gcc clocks at 15 MHz;
   if that freezes, pins/QUP are TZ-locked → path (b) bit-bang or a TZ
   handoff is the only bus owner.

Evidence gaps: whether joan's GPIO 81-84 (vs the QUP itself) are
TZ-secured; the trustlet command ABI; dtb-variant ↔ retail-unit mapping
(immaterial — all ten agree on fingerprint wiring).

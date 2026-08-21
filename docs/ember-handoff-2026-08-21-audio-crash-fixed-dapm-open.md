# V30 audio — handoff (2026-08-21, Ember → next session)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-21

## Headline

**The SoC-reset crash is FIXED and pushed.** PCM playback runs end to end.
Sound is **not yet audible**, and the remaining question is a hardware-topology
one, not a crash.

## Part 1 — the crash (DONE, verified, pushed)

Root cause: `q6asmdai` had no `iommus`. `q6asm_dai_probe()` reads it to recover
the audio stream ID and puts it in bits [63:32] of the buffer address it hands
the DSP (`q6asm-dai.c:452`). msm8998.dtsi omitted the property deliberately
("no apps_smmu") — but the SoC has `lpass_q6_smmu` @0x5100000, which was
`disabled` and referenced by nothing. So `sid = -1`, the buffer was allocated
against a device attached to no IOMMU, and the DSP got a bare physical address.
`ASM_CMD_SHARED_MEM_MAP_REGIONS` still succeeded (the ADSP only records the
address); the fault landed on the first `ASM_DATA_CMD_WRITE_V2`. **A Q6
translation fault on msm8998 is a silent SoC reset handled below the kernel** —
which is why ~25 boots found no panic, no RCU stall, no "crash detected in adsp".

Fix (kernel `ab99261d5`):
```dts
q6asmdai { iommus = <&lpass_q6_smmu 1>; };   /* msm8998.dtsi */
&lpass_q6_smmu { status = "okay"; };         /* joan dts     */
```
SID 1 confirmed twice: sdm845 `apps_smmu 0x1821` (`& 0xF` == 1), and downstream
`msm-audio.dtsi:448` `qcom,msm-audio-ion iommus = <&lpass_q6_smmu 1>`.

Boot 23a: `aplay rc=0` twice, 156 `ASM_DATA_EVENT_WRITE_DONE_V2`, six wall
seconds per five-second clip (real time ⇒ the port clocks at 48 kHz), clean
`SHARED_MEM_UNMAP` + `ADM_CMD_DEVICE_CLOSE_V5`, phone alive. Also retires the
separate teardown-crash suspect open since 2026-08-17.

## Part 2 — the codec DAPM lane (boot 24a + live iteration)

Boot 24a survived, so most of this was done **live over ssh without reboots**.
That is the big workflow win: the phone now stays up, so the codec can be
poked interactively.

### Fixed

**Stereo.** Setting `SLIM RX1 MUX` = AIF1_PB in addition to RX0 changed the AFE
port config from `ch 1 map 144/0/0/0` to **`ch 2 map 144/145/0/0`**.

**My own gain bug — read this before re-testing.**
`SOC_SINGLE_S8_TLV("RXn Digital Volume", …, -84, 40, digital_gain)` means the
**control value is an offset from −84 dB**, not dB. Setting it to `0` is
**−84 dB**, i.e. silence. 0 dB is control value **84**. I spent a listening pass
at −84 dB. Verified by register readback: control 94 → `0b59: 0a` (+10 dB).

### Proven working (measured, not assumed)

Dumped from `/sys/kernel/debug/asoc/LG-V30/wcd934x-codec.0.auto/dapm/` **while a
tone was playing** (dumping it idle shows everything Off and proves nothing):

```
AIF1 PB: On in 1 out 3          RX INT1 MIX3: On in 1 out 1
SLIM RX0: On in 1 out 2         RX INT1 DEM MUX: On in 1 out 1
RX INT1_1 MIX1 INP0: On         RX INT1 DAC: On in 1 out 1
RX INT1_1 MIX1: On              HPHL PA: On in 1 out 1
RX INT1_1 INTERP: On            HPHL: On in 1 out 1
RX INT1 SEC MIX: On             RX_BIAS: On   MCLK: On
RX INT1 MIX2: On
```

Codec registers while playing (regmap `217:250:1:0`):

| reg | value | meaning |
|---|---|---|
| 0x601 `ANA_BIAS` | 0x80 | analog bias enabled |
| 0x608 `ANA_RX_SUPPLIES` | 0xc1 | RX supplies + RX bias on |
| 0x609 `ANA_HPH` | 0xf0 | HPHL PA + HPHR PA + INT1 DAC + INT2 DAC all enabled |
| 0x60a `ANA_EAR` | 0xa0 | EAR PA enabled |
| 0x0b41 / 0x0b55 `RX0/RX1_RX_PATH_CTL` | 0x24 | path enabled, PGA **unmuted**, rate 4 = 48 kHz |

SLIMbus stream really is established — from netconsole, per playback:
`mc=0x2d` CONNECT_SINK ×2, `mc=0x21` DEF_ACT_CHAN, `mc=0x24` RECONFIG_NOW,
`mc=0x2e` DISCONNECT_PORT ×2 on teardown. No bus errors.

So: **the digital path is complete and the WCD9340's analog output stages are
enabled and unmuted.** Everything the codec can do, it is doing.

### Still silent — and the open question

After correcting the gain bug I ran a −20/−10/0/+10 dB sweep and then a
two-minute loop. **Neither was confirmed by ear** (first sweep was missed, the
second run hit my own command timeout before a verdict). So the corrected-gain
configuration has **never actually been listened to**. That is the very first
thing to do next session, and it may simply work.

If it is still silent, the live hypothesis is topological:

> joan may not connect the WCD9340's analog outputs to any transducer at all.

Evidence for that reading:
- Headphone jack goes through the **ES9218P** ("Quad DAC") on i2c_1 @0x48.
- Loudspeaker goes through a **TFA98xx** on i2c_7 @0x34, fed by **quaternary
  MI2S**; the ES9218P is fed by **tertiary MI2S** (downstream
  `msm8998-joan-common-sound.dtsi`).
- Downstream's `qcom,audio-routing` for joan lists **only microphone paths** —
  no speaker, earpiece or headphone routes off the codec at all.
- Nothing in joan's downstream DT references the codec's EAR/HPH/LINEOUT.

If that is right, audible sound needs MI2S + one of those two chips, and the
WCD9340 is a mic/SLIMbus-control part on this board.

### ES9218P Low Power Bypass — how to get the WCD to the jack (if it is wired)

From LG's `es9218p.c` header:
```
reset=H && hifi_mode2=L  -> HiFi mode
reset=L && hifi_mode2=H  -> Low Power Bypass   <- WCD analog passes through
reset=L && hifi_mode2=L  -> Standby / shutdown
reset=H && hifi_mode2=H  -> LowFi mode
```
Pins (1-based, matching downstream directly — `pinctrl-spmi-gpio`'s `of_xlate`
subtracts `PMIC_GPIO_PHYSICAL_OFFSET`, so DT `<10>` really is PMIC GPIO_10):
- power → `&pm8998_gpios 10`, drive **high**
- hifi_mode2 → `&pm8998_gpios 12`, drive **high**
- reset → `&pmi8998_gpios 2`, drive **low**

### Open bug: the DT gpio-hogs silently do nothing

I added `gpio-hog` nodes for those three pins. They are present in the live DT
(`/proc/device-tree/soc@0/spmi@800f000/pmic@0/gpio@c000/es9218p_power_hog` etc.)
and **the pins stayed inputs**, with nothing logged in dmesg. Cause not yet
found; `pinctrl-spmi-gpio` looks like it should support hogs. **Do not trust
the hogs** until this is understood — verify with `/sys/kernel/debug/gpio`.

Workaround that works: `gpiohold`, a small static aarch64 tool in
`docs/tools/gpiohold.c`, requests lines via GPIO_CDEV and holds them for N
seconds (the phone has `CONFIG_GPIO_CDEV=y`, no `GPIO_SYSFS`, and no libgpiod).
```
/tmp/gpiohold "pmic@0" 200 9=1 11=1 &     # offsets are 0-based: GPIO_10, GPIO_12
/tmp/gpiohold "pmic@2" 200 1=0 &          # GPIO_2
```

## Next session, in order

1. **Listen to the corrected-gain configuration.** It has never been heard.
   Recipe is `docs/tools/joan-codec-dapm-setup.sh`; digital volume **84**, not 0.
2. If silent, settle the topology question: does the V30 earpiece hang off WCD
   `EAR`, or is every output behind ES9218P / TFA98xx? A teardown photo, an LG
   service manual, or the vendor `mixer_paths_*.xml` from a stock V30 system
   image would answer it directly and cheaply.
3. Depending on (2): either finish the WCD analog path, or open the MI2S lane
   (tertiary → ES9218P, quaternary → TFA98xx). Mainline has `snd-soc-tfa989x`
   for some TFA parts — check whether joan's is covered.
4. Fix the gpio-hog no-op, or bind the pins from the ES9218P driver instead.
5. ES9218P driver (`dbd7d8f4d`, local, Lance-approved RE work): never probed,
   `CONFIG_SND_SOC_ES9218P` not enabled. Bringing it up is the proper home for
   the mode pins and for HiFi mode.

## Rig notes

- **netconsole had never worked** in this campaign: `netpoll: netconsole: usb0
  doesn't exist, aborting` at 3.05 s — the cmdline initcall runs long before the
  USB gadget. Configure via configfs after usb0 is up, with nest's **live** MAC
  (pmOS randomises the CDC host MAC every boot), and positive-control it with a
  marker through `/dev/kmsg` before spending a run.
- Dump ASoC DAPM **while audio is playing**; idle dumps show everything Off.
- Widgets live at
  `/sys/kernel/debug/asoc/LG-V30/wcd934x-codec.0.auto/dapm/<widget>`.
- Codec regmap is `/sys/kernel/debug/regmap/217:250:1:0/registers`.
- debugfs is not mounted by default on this rootfs: `mount -t debugfs none
  /sys/kernel/debug`.
- Boot-test must wait for `sys.boot_completed` before `dumpsys battery`; if the
  phone is left in pmOS, reboot it to Android first (fastboot is only reachable
  from there).

# Card 94 Test A — the overclock is NOT the cause

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-12
State: DEVICE RESULT; hypothesis refuted; no fix promoted

## Hypothesis tested

joan's GPU OPP table carries three experimental corners above the stock top
(750 MHz at 964 mV, 800 at 1000 mV, 850 at 1036 mV), and `msm_gpu.c`
`enable_clk()` programs `gpu->fast_rate` -- the highest OPP -- on every resume.
The DT's own comments state this twice, and record 900 MHz being dropped because
`gpupll0` could not lock. So the proposal was that every resume onto a
just-collapsed GX rail was landing on an out-of-envelope 850 MHz corner, and
that this was the Card 94 reset.

## Result: refuted

Image `boot-joan-resume-stock-5c568a736.img`,
SHA-256 `84e32644e7d3feafa89c3bc2971932e93dabddc23d7c0a6dd085e73b936c2763`,
kernel `7.2.0-rc2-g5c568a736374`, branched from the gate0 source `93cc2be54`
with only the three overclock corners removed. Packaged against the gate0 image
itself, so ramdisk and cmdline are byte-identical and the OPP table is the only
variable. Verified post-pack: ramdisk sha matches, kernel sha matches the staged
`Image.gz-dtb`, cmdline preserved, and the packaged image's own GPU table
contains zero of the 750/800/850 corners.

| run | top corner / fast_rate | last coherent ts |
|---|---|---|
| gate0 | 850 MHz | 17.122 s |
| stock | 710 MHz | **18.565 s** |

Both reset at the same milestone, immediately after
`EXT4-fs (mmcblk0p1): mounted filesystem`, which is where pmOS starts services
and greetd opens the GPU. The 1.4 s difference sits inside the 17.1-19.9 s
spread of earlier runs and carries no signal.

**The resume fault occurs at the stock Qualcomm 710 MHz corner.** The local
overclock is exonerated as a cause. It remains a bad idea to leave in a
diagnostic image, but it is not this bug.

Capture: `~/joan-images/pstore/pstore-stockcorner-2026-08-12T*.bin`. As before,
a `[204.5]` fragment appears far below the last coherent line; it is stale
non-monotonic ring data from an earlier boot, not evidence of survival.

## What survives, and why it is still the best lead

The entry-corner asymmetry is independent of the overclock:

- downstream `msm8998-gpu.dtsi` sets `qcom,initial-pwrlevel = <4>`, so the GPU
  powers up at 251 MHz -- the second-lowest of seven levels -- and reaches
  level 0 only under load;
- downstream's CRC power sequence separately sets "a safe frequency" during GX
  transitions;
- mainline `enable_clk()` programs `fast_rate`, the *maximum*, on every resume.

Removing the overclock changed which maximum, not the fact that resume enters at
maximum. Test B reduces the table to the single 257 MHz corner so `fast_rate`
approximates downstream's power-up level, which discriminates "entry corner is
the fault" from "corner is irrelevant".

If Test B survives, the proper fix is a driver change -- enter resume low and let
devfreq ramp -- and it would plausibly affect every mainline msm8998 device, not
only joan.

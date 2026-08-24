# LG V30 earpiece: WCD934x Class-H K2 negative test — Aurel → Ember

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:gpt-5.6-terra
Date: 2026-08-24

## Purpose

Lance asked to hand this lane to Ember after one tightly bounded live test of
the only concrete remaining WCD934x initialization mismatch found against LG's
downstream driver. The physical earpiece remains silent.

This record separates the tested fact from the remaining hypotheses. It is not
an upstream-ready patch recommendation.

## Result at a glance

**Rejected as a sufficient fix:** initializing WCD934x Class-H K2 to LG's
`0x0060` value did not make the earpiece audible.

The variable genuinely changed in the live codec register bank:

```text
stock before test:     0x0c0b = 0x80
LG downstream target:  0x0c0b = 0x60
temporary test module: 0x0c0b = 0x60 (read back after probe)
post-playback readback:0x0c0b = 0x60
physical verdict:      Lance: "no"
```

The control-path test itself completed: all seven required mixer stages read
back as configured, RX0 digital volume was 84 (0 dB), EAR PA volume was 4
(+6 dB), and the full 26-second 48 kHz tone returned `aplay exit=0`.

## Exact source delta

Kernel test worktree:

```text
/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-wcd934x-init
branch: joan/wcd934x-common-init-test
base live source revision: 5f6732fb6
commit: 0ee6f8a57db100bda3da0aca7085bcbfc1eccf75
```

Commit `0ee6f8a57` adds only this initialization in
`wcd934x_hw_init()`:

```c
regmap_update_bits(rm, WCD934X_CDC_CLSH_K2_MSB, 0x0f, 0x00);
regmap_update_bits(rm, WCD934X_CDC_CLSH_K2_LSB, 0xff, 0x60);
```

Primary downstream basis:

```text
android_kernel_lge_msm8998/
sound/soc/codecs/wcd934x/wcd934x.c:8668-8669
  {WCD934X_CDC_CLSH_K2_MSB, 0x0F, 0x00},
  {WCD934X_CDC_CLSH_K2_LSB, 0xFF, 0x60},
```

Test-branch insertion:

```text
linux-mainline-v30-wcd934x-init/
sound/soc/codecs/wcd934x.c:2219-2224
```

The delta was intentionally limited to K2; do not infer that it reproduces
LG's complete codec-init table.

## Module construction and safety checks

Phone kernel at test time:

```text
7.2.0-rc2-g5f6732fb6cb8
```

The test module was built with a matching `LOCALVERSION` and had exact
vermagic:

```text
7.2.0-rc2-g5f6732fb6cb8 SMP preempt mod_unload aarch64
```

The module SHA-256 was:

```text
a25923b1d776c4cade55a53b1757dd2e7deb94b64d36943c79a6d5c9d64917be
```

This test worktree did not have a linked `vmlinux.o`, so Kbuild's normal
modpost dependency check could not use its symbol table. The module was
therefore produced with `KBUILD_MODPOST_WARN=1`; that is a build caveat, not
something to hide. Before load, all 90 unique undefined symbols from the
module were compared against a root-read `/proc/kallsyms` capture on the live
phone: **90/90 resolved**. The live kernel also confirmed:

```text
CONFIG_MODULE_UNLOAD=y
# CONFIG_MODVERSIONS is not set
# CONFIG_MODULE_SIG is not set
```

The module then successfully loaded in the real live kernel, rebound the
machine card, and programmed/read back K2. Thus the physical negative result
is valid for this one-variable runtime test despite the modpost caveat.

No rootfs or boot image was written.

## Live procedure and observations

### 1. Temporary module hot-swap — succeeded

The phone-side script temporarily:

1. stopped active user sound daemons;
2. unloaded `snd_soc_sdm845`;
3. unloaded packaged `snd_soc_wcd934x`;
4. `insmod`ed the test module;
5. rebound `snd_soc_sdm845`;
6. read back the ALSA card and `0x0c0b` through WCD regmap debugfs.

Observed result:

```text
0 [LGV30]: sdm845 - LG-V30
0c0b: 60
```

### 2. Earpiece listening test #13 — transport/route succeeded, audibility failed

The script set and verified:

```text
SLIMBUS_0_RX Audio Mixer MultiMedia1 = [on]
SLIM RX0 MUX = AIF1_PB
RX INT0_1 MIX1 INP0 = RX0
RX INT0_1 INTERP = RX INT0_1 MIX1
RX INT0_2 MUX = RX0
RX INT0_2 INTERP = RX INT0_2 MUX
RX INT0 DEM MUX = CLSH_DSM_OUT
RX0 Digital Volume = 84 (0 dB)
EAR PA Volume = 4 (+6 dB)
```

`/tmp/ear-tone48.wav` was a 2,496,044-byte, 48 kHz mono 26-second tone.
Playback completed with `aplay exit=0`. Lance listened during the announced
window and reported **"no"** — no earpiece audio.

After the script's cleanup, independent readback still showed:

```text
0c0b: 60
LG-V30 card present
snd_soc_sdm845, snd_soc_wcd934x, snd_soc_wcd_classh loaded
```

### 3. Return to packaged module — completed, but does not reset codec hardware

The packaged runtime module was restored successfully:

```text
/lib/modules/7.2.0-rc2-g5f6732fb6cb8/kernel/sound/soc/codecs/snd-soc-wcd934x.ko.zst
LG-V30 card rebound successfully
```

Important residual-state caveat: the component-module reload does **not**
hardware-reset the powered WCD934x register bank. Consequently K2 remained
`0x60` after packaged-module restoration. This is expected from the observed
runtime behavior, not evidence that the packaged mainline module initializes
K2 to `0x60`.

A normal phone reboot is required to return the codec's reset value (`0x80`,
observed before the test). Do not claim the current live phone is a clean
stock-register baseline merely because the packaged module has been reloaded.
No reboot was performed after the test.

## Durable helper scripts

These are committed alongside this handoff:

```text
docs/tools/reload-wcd934x-k2.sh
  SHA-256 227380aafca16b4c61ee47ec723357d3f89cde52544db45ff7394942315e0e27

docs/tools/ear-test-v13-k2.sh
  SHA-256 a0c3b229f273bdd94fe7c0f2721aacb401e68031c4528f171b12e35844be7a35

docs/tools/restore-wcd934x-stock.sh
  SHA-256 2e51d78c4b0b1b048ada88e7c925bd50f8eee63b71c61d757664867932205229
```

They require the existing nest hop `/tmp/joan` → `user@172.16.42.1`, a
phone-side `SUDO_ASKPASS` helper, and a staged test module. They contain no
credential values. The regmap reader deliberately uses a full sequential
`cat .../registers | grep` because direct `grep` did not reliably force this
debugfs implementation to emit the desired register.

## What this closes

- General PCM/ADSP transport is not the failure: independent loudspeaker
  playback was audibly confirmed via TERT_MI2S and the external TFA path.
- The complete known WCD INT0 earpiece mixer path can be configured and
  read back; PCM playback completes without codec/ADSP fault evidence.
- The gain-offset trap is avoided here: RX0 control 84 is 0 dB, not control 0.
- WCD934x K2 reset-default versus LG's `0x60` init mismatch is **not enough**
  to restore earpiece audibility. Do not repeat this exact K2-only test.

## Remaining boundary for Ember

The live receiver failure remains beyond the proven WCD digital route and
this one Class-H initialization coefficient. Rank follow-up work by evidence:

1. **Establish actual receiver topology/wiring.** Obtain a stock V30 vendor
   mixer-path file, service/schematic evidence, or a teardown trace that
   identifies what drives the physical earpiece. Do not assume the WCD `EAR`
   pin reaches it merely because DAPM calls it `EAR`.
2. **Diff the full downstream WCD934x init and EAR power/event sequencing**
   against mainline, but make each next live experiment one causal variable.
   K2 is now an explicit rejected isolate, not a reason to bulk-copy an init
   table.
3. **Check board-specific power/enable paths or receiver hardware** only after
   topology evidence identifies them. The downstream machine driver has
   `CONFIG_SND_SABRE_EAR_AMP`-guarded generic code, but the available
   downstream config search did not establish it is enabled or wired for joan;
   do not elevate that conditional code into a joan fact.
4. Do not use current headphone testing as a shortcut: no headphones are
   attached, and Lance reports jack detection is unwired. The historical
   ES9218P headphone path is not current earpiece evidence.

## Sources / provenance

- LG downstream source: `/home/kumo02/vibe-coding-projects/coding/android_kernel_lge_msm8998/`
- Mainline test source: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-wcd934x-init/`
- Prior audio topology/crash handoff:
  `docs/ember-handoff-2026-08-21-audio-crash-fixed-dapm-open.md`
- This session's live phone observations were captured through
  `nym-nest-family` and the USB-network target `user@172.16.42.1`.

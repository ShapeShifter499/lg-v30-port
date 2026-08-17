# Boots M/N (qmidbg9m/n): audio-routing added — playback crashes the kernel

Date: 2026-08-17
Kernel: 7187fbbb5675 + q6core.skip_versions gate + v9 stack + joan DT
        audio-routing. Image sha256 (final N): d179136689d8e40c72ca1cc237a1bb75027081571fab1200ab13bbe7ae87cbcc

## Boot M (first attempt): card failed to register

Added db845c's audio-routing to the joan sound node. The card never
registered. The breadcrumb caught it:

    JOAN-DBG: dapm route 'SPK1 OUT' -> 'SpkrLeft IN': lookup failed (sink=MISSING)
    ASoC: Failed to add route SPK1 OUT -> SpkrLeft IN

"SpkrLeft IN" is the WSA881x amp's widget on db845c (db845c has WSA
speaker amps; joan does not). The failed of_dapm_route add makes
snd_soc_dapm_new_widgets() fail -> the whole card instantiation fails
(not a defer, a hard error). Lesson: audio-routing pairs must resolve
on THIS machine's widget set.

## Boot N (fix): card up, tone plays, kernel crashes mid-playback

Fix: "Left Spk", "SPK1 OUT" (the machine's own pin). Card registers,
zero route failures. Mixer sequence + aplay of a 6s 1kHz tone:

    SLIMBUS_0_RX Audio Mixer MultiMedia1 = on
    SLIM RX0 MUX = AIF1_PB
    RX INT0_1 MIX1 INP0 = RX0
    RX INT0 DEM MUX = CLSH_DSM_OUT (control missing -> amixer error)

aplay started ("Playing WAVE ... Stereo") and the phone crashed to the
bootloader mid-play. The dmesg stream was written to /tmp (tmpfs) and
died with the reboot. The crash is in the playback data path itself
(Boot L's post-play crash was likely the same thing with different
timing).

## Boot O (next): netconsole for panic capture

- CONFIG_NETCONSOLE=y + DYNAMIC (added; the config episode forced a
  near-full rebuild).
- cmdline: netconsole=6665@172.16.42.1/usb0,6666@172.16.42.2/92:e9:43:17:eb:60
  (nest enp0s29u1u5 MAC).
- Nest listener: /tmp/netconsole-listen.sh 6666
  /tmp/joanrun/netconsole-qmidbg10o.txt
- Test: /tmp/joan-scripts/booto-audio-test.sh (also writes dmesg to
  /home/user/joan-bootm-dmesg.txt — EMMC, survives reboot modulo the
  page-cache window).

## Notes for the crash hunt

- Boot L: aplay /dev/zero (3s) completed, crash seconds later (looked
  like teardown). Boot N: crash DURING a 6s tone. Same path, likely the
  same root cause.
- Candidates: q6asm-dai buffer/event handling during playback, the
  SLIM data transfer, the wcd934x SLIM IRQ handler, or the mclk (LN_BB)
  RPM clock. Netconsole will say which.

## Earpiece / mock stereo (Lance)

V30 has a main speaker + an earpiece receiver. Main speaker = codec
SPK1 (class-H DSM). Earpiece wiring not yet identified — likely SPK2
or a receiver output; candidate for mock stereo (earpiece = right
channel) after the main speaker plays.

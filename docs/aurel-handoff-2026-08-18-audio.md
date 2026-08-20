# V30 audio bring-up — handoff (2026-08-18, Aurel → next session)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-18

## Goal state

Sound does NOT play yet on the LG V30 (joan) with mainline + pmOS.
The remaining failure is ONE mechanism, now tightly characterized:
a silent SoC reset (no panic, no RCU stall, no "crash detected in adsp"
print) ~0.3-1.3 s after the stream reaches the AFE port config, racing
ahead of the PCM trigger. Everything up to that point works.

## What works (verified by boots 19y-20i)

1. SLIMbus NGD controller + QMI (svc 0x0301) come up; satellite handshake
   (REPORT_SATELLITE) completes.
2. WCD934x codec + IFD enumerate (LA 0xcf / 0xce), both regmaps work
   (elemental REQUEST_VALUE 0x60 / CHANGE_VALUE 0x68 traffic).
3. Mixer routing is CORRECT: with "SLIMBUS_0_RX Audio Mixer MultiMedia1"
   = on and "SLIM RX0 MUX" = AIF1_PB, the FE MultiMedia1 links its BE
   (the "no backend DAEs" error is only daemon-opens-before-mixer
   ordering, not a topology bug).
4. Stream setup completes: q6slim_hw_params, q6afe_dai_prepare, AFE slim
   port 16384 config, APR acks.
5. PGD laddr discovery works: ctrl->get_laddr() directly (downstream
   style) — the ADSP answers pgdla = 0xc4. All 12 USR pipe connects
   (SRC+SINK, pn 0..5) post with ZERO bus errors.

## The killer (evidence)

- Boot 20d: dump_stack proved app-side writel to PGD_PORT_CFGn (0x14000)
  hangs the CPU mid-ADSP-activity. REMOVED (f173f0394 / master
  80cd7f61e). The ADSP owns the PGD block; app-side PGD register writes
  are retired for good (also explains Boots R/S/T).
- Boots 20e-20i: with the PGD writes gone, the death is a silent SoC
  reset shortly after stream setup — with zero pipe connects (20e) and
  with twelve clean ones (20h/20i), so the connects are not the missing
  piece either.
- Ruled out: autosuspend (r4 died without a suspend cycle; the sysfs
  autosuspend_delay_ms file errors EIO on this device), unanswered QMI
  indications (20i breadcrumb in qmi_invoke_handler: ZERO unmatched
  messages — the IPCRTR len-48 messages are handled responses).
- The last event before every death: a SECOND bus power_up (wake) while
  the ADSP is mid-stream-setup, or the APR ack stream — then silence.

## Remaining leads (next session, in order)

1. Downstream's SPS/BAM pipe setup: downstream slim-msm.c
   msm_slim_connect_pipe_port() configures the SPS/BAM pipes AND the PGD
   ports when the stream's connects go out (slim-msm-ngd.c intercepts
   them in xfer_msg). Mainline has the USR-connect remap but no SPS/BAM
   setup. If the ADSP's wedge is the apps' BAM pipes being unconfigured,
   porting the SPS part (WITHOUT the PGD register writes, which hang) is
   the fix.
2. The codec-side SLIM PGD port interrupt enables: wcd934x
   enable_slim / wcd934x.c:4090ish writes the codec's SLIM_PGD_PORT_INT
   registers via the if_regmap (the 0xce traffic at stream setup). The
   values/semantics vs downstream tavil deserve a diff.
3. Capture the ADSP's own state: the reset is silent (hardware watchdog,
   not the remoteproc recovery path), so the ramdump never lands. Worth
   one attempt at netconsole-with-pstore or the TZ/XPU angle on why the
   ADSP's activity wedges the apps bus.
4. The wake power_up's early-return path (NGD_STATUS LADDR bit) skips
   the capability exchange on wakes — verify that matches downstream's
   wake behavior (downstream msm_slim_ngd_power_up equivalent).

## Evidence rig (reusable, works)

Phone-side, USB-death-proof, survives the SoC reset:
- remount,rw,sync / (ext4 sync mount: every write commits; the default
  mode loses ~seconds to journal rollback after a crash)
- incremental logger: dmesg -c >> /var/log/joan-aplay.log every 0.2 s
  (full-buffer dumps are too slow to reach the crash point)
- detached audio sequence: setsid sh /tmp/joan-audio-seq.sh (mixer set +
  two aplay bursts, logs to /var/log/joan-mixer2.txt)
- readback: adb reboot bootloader -> fastboot boot <image> -> ssh
  user@172.16.42.1 -> cat the logs (world-readable)

Gotchas:
- ssh -tt WITHOUT -n when piping the sudo password ( -n eats stdin and
  sudo hangs forever; the password dots "\b\b\b" = delivered).
- Heredoc'd remote bash scripts eat their own stdin via nested ssh —
  write readback scripts as files on nest, never heredocs.
- repack script REFUSES on release-string mismatch: pass the current
  `strings Image | grep "Linux version"` value.

## Tooling locations

- Kernel: ~/vibe-coding-projects/coding/linux-mainline-v30-usb-otg
  branch joan/usb3-otg-bringup (HEAD 0d00bab2b, includes the qmi
  breadcrumb).
  Build: make ARCH=arm64 O=/data/buildcache/kbuild/build-adsp-only
  CROSS_COMPILE="ccache aarch64-linux-gnu-" -j12 Image.gz dtbs.
- GitHub ShapeShifter499/linux-lg-v30-joan: joan/latest-clean-test =
  0d00bab2b (full history, incl. qmi breadcrumb); master = proven fixes
  (6fc576542).
- nest: ~/joan-images/staging/qmidbg20i/{repack,boot-test,seq} +
  /tmp/readback-20i.sh; latest image boot-joan-qmidbg20i.img
  (cf8dbfb1...).
- Evidence: lg-v30-port/docs/evidence/2026-08-18-persistent-log/ and
  docs/NEXT-SESSION.md.
- Deck: card 99 "LG V30 joan — audio bring-up: SLIMbus/ADSP sound
  (2026-08-18)" in Active.
- Phone: back in LineageOS at ~100% battery.

## Budget note

Lance flagged ~$5 remaining on deepseek credits before this last run;
the goal command is queued for clearing. Next session should re-check
budget before resuming boot cycles.

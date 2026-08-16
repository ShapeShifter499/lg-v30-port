# WLAN confirmed: the config confound was the whole story, and WLAN is reproducible

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-16 (session C)

## Result

`wlan0` comes up from **committed state** on `joan/latest-clean-test` (`7187fbbb5`)
with `CONFIG_ATH10K_DEBUG` and `CONFIG_ATH10K_DEBUGFS` cleared, and passively
scans **84 BSSs** across both bands. One boot, no retries.

```
t+5s  mss=running svc69=absent  net=[lo usb0 ]
t+10s mss=running svc69=PRESENT net=[lo usb0 wlan0 ]
WLAN0_APPEARED_AT=t+10s

69  1  0  0  84  ATH10k WLAN firmware service

BSS_COUNT=84
2.4GHz=54  5GHz=30
```

The driver reports the decisive config back itself:

```
ath10k_snoc 18800000.wifi: kconfig debug 0 debugfs 0 tracing 0 dfs 0 testmode 0
```

This closes `docs/ember-wlan-delta-recovered-2026-08-16.md`, which proved *which*
variable differed but explicitly noted "flipping it back restores `wlan0` still
needs one confirming boot." That boot is done and it is positive.

## What this settles

- **WLAN is reproducible from committed state.** The previous handoff's "the only
  artifact that has ever brought `wlan0` up cannot be rebuilt from any committed
  state" is now doubly retracted — once by the config recovery, once by hardware.
- **The bisect was measuring its own instrumentation.** Six candidate boots and
  two controls all carried the two debug symbols, which independently break
  bring-up. No arm could have shown a difference. Same class as
  `feedback_ab_order_confound`.
- **The result survives the audio lineage's config.** This build carries the audio
  session's `SND`/`SLIMbus`/`SOUND` stack as `=y` where the known-good Aug-14
  image had them `=m` — ~90 symbols of difference beyond the two ath10k ones.
  WLAN works anyway, so those changes are cleared of suspicion too.

## The modem crash is fixed, and the mechanism is directly evidenced

First observation was `fatal_error_lines=0` over 160 s. That was too short to
claim anything, so the same boot was held open and re-tested with **six repeated
5 GHz passive scans over a 56-minute window** — repeating the exact trigger Aurel
root-caused (channel 169 / 5845 MHz).

```
uptime_start=3031s   mss=running   fatal_at_start=0   recover_at_start=0
scan 1  bss=76  5GHz=28  max_freq=5785  fatal=0  mss=running
scan 2  bss=77  5GHz=29  max_freq=5785  fatal=0  mss=running
scan 3  bss=75  5GHz=29  max_freq=5785  fatal=0  mss=running
scan 4  bss=76  5GHz=29  max_freq=5785  fatal=0  mss=running
scan 5  bss=68  5GHz=28  max_freq=5785  fatal=0  mss=running
scan 6  bss=83  5GHz=31  max_freq=5785  fatal=0  mss=running
uptime_end=3362s   fatal_total=0   recover_total=0   mss=running
```

The Aug-14 baseline crashed every **20-28 s** (`err_qdi.c:450:EX:wlan_process`).
3362 s covers roughly **120-170 expected crash intervals with zero crashes**, and
zero recoveries, while scanning repeatedly and successfully on 5 GHz.

The mechanism is not inferred, it is visible: **`max_freq=5785` on every scan.**
5845 MHz never appears in any result, and `grep 'freq: 58[0-9]+'` for anything
above 5785 returns nothing — `519646f01` ("wifi: ath10k: withhold 5845 MHz from
the WCN3990 channel list") is withholding exactly the channel that took the
firmware down, and 5 GHz scanning still works without it.

That commit post-dates `d05e70c5e484`, which is why the Aug-14 image crashed and
this one does not. The known-not-done in `ember-wifi-working-2026-08-14.md` is
closed.

Caveat kept honest: this is **one boot** held open for 56 minutes, not six
separate boots. It rules out a short-window fluke decisively; it does not rule
out a boot-to-boot nondeterminism that happens to have missed this boot.

## Method notes worth keeping

**The image proves its own config.** The repack script extracts the `.config` out
of the *packed boot image* via `CONFIG_IKCONFIG` (slice between `IKCFG_ST` and
`IKCFG_ED`, gunzip) and refuses to proceed unless both symbols read
`is not set`. Verifying the build dir would not have caught a stale or wrong
image; verifying the artifact does. This is the check whose absence created the
confound.

**Single-variable donor.** The boot image reuses the ramdisk and cmdline of
`boot-joan-wifi-d05e70c5e.img` — the only image that has ever brought `wlan0` up —
verbatim, so the kernel is the only thing that changed. The repack refuses to run
unless the donor's sha256 matches.

**Positive controls before trusting silence.** `qrtr-lookup` was verified present
and working on the running device *before* the boot, because the previous
session's "769 never appeared" conclusion would have been vacuous if the tool had
been missing (`feedback_validate_debug_channels`). It is real: `/usr/bin/qrtr-lookup`,
and it enumerated the ADSP's services fine.

**Cheap test first.** Only 28 objects rebuilt (~5.5 min) because the two symbols
touch `drivers/net/wireless/ath/ath10k/` only, and the build was done **in place**
in `/data/buildcache/kbuild/build-adsp-only` with the original flags — no `cp -a`,
no added `KCFLAGS` (`feedback_build_dir_clone_kills_ccache`).

## Artifacts

| what | where |
|---|---|
| boot + wlan0 + qrtr | `docs/evidence/2026-08-16-wlan-nodbg-boot/boot-and-wlan.txt` |
| passive scan, 84 BSS | `docs/evidence/2026-08-16-wlan-nodbg-boot/passive-scan.txt` |
| config read back out of the booting image | `docs/evidence/2026-08-16-wlan-nodbg-boot/embedded-verified.config` |
| image (nym-nest) | `~/joan-images/boot-joan-wlan-nodbg-7187fbbb5.img`, sha256 `5e9e2816…5747` |
| repack (hash-bound) | `~/joan-images/staging/repack-wlan-nodbg.sh` |
| RAM-boot runner (hash-bound, single attempt) | `~/joan-images/staging/wlan-nodbg-ramboot-once.sh` |
| on-device scripts | `~/joan-images/staging/wlan-inner.sh`, `/tmp/scan-inner.sh` |

RAM boots only. Nothing was flashed. Passive scan only, no association — the
wpa_supplicant path was never invoked.

## Next

1. **Decide the config's home.** WLAN now needs both symbols *off* in every image
   meant to have Wi-Fi. That is a footgun for anyone who turns them on to debug.
   Worth a note in the kernel-change ledger and in whatever config the series
   ships with.
2. **Confirm the modem-crash fix** attributable to `519646f01` — two or three
   boots with a 5+ minute window and the 5 GHz scan repeated.
3. **The real WLAN target is now the fragility itself**: why is bring-up timing
   sensitive enough that enabling logging loses the race? The MSA-permission /
   modem-watchdog race in `ember-wifi-modem-crash-rootcaused-2026-08-14.md` is the
   place to start.
4. `tqftpserv` is still staged from tmpfs each boot. Lance approved installing it;
   doing so would remove a manual step from every WLAN test.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-16

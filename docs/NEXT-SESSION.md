# LG V30 (joan) — next session start here

**2026-08-17 evening (Aurel) — READ FIRST: Lane B root cause FOUND, sound card UP.**
Five boots (E–I) took Lane B from "QMI wedge mystery" to a registered
`LG-V30` ALSA card. The wall was: mainline's q6afe/q6asm probes send
q6core FWK_VERSION/SVC_VERSION APR commands — mainline-only, sdm845-era
messages the msm8998 firmware mishandles — which wedges the ADSP's
QMI/glink transport ~2 s later. Symptoms followed: select-instance
unanswered, no RX_DONE, the 30-intent pool draining (the 2-4 min
"wedge" = exactly 30 AP->ADSP messages with zero returns).
Fix (debug-gated): `q6core.skip_versions=1` (or `apr.skip_devices=1`).
With it: ADSP alive indefinitely, SLIM SAT completes, WCD9340 enumerates
(chip 0x108), `LG-V30` card + MM1/MM2 PCMs register.
Full story: `docs/aurel-2026-08-17-qmi-death-window.md`; evidence in
`docs/evidence/2026-08-17-qmi-boots/` (boots E–I); ledger K175–K181.
Patches v1–v5 in `out/` (gitignored; sha256s in ledger). Kernel tree is
DIRTY with the v5 debug stack (breadcrumbs + gates); restore canonical
when the upstream-shaped fix lands (DT-gate the version commands).
**Next: playback path** — SLIM Playback/Capture dai-links are dropped
("codec dai not found" despite wcd934x dais registered; codec is in the
card as aux only) and aplay on MM1/MM2 fails silently EINVAL. Start at
sdm845_snd_parse_of codec-dai resolution + probe order vs the mfd child.
Also queued: upstream-shaped q6core fix; WLAN re-confirmation boots;
cellular lane (IPA data / SMS / native-IMS research per Lance 2026-08-17).

The original Ember handoff follows, preserved below.

- **From:** Ember Nymbrand (agent-ember) · Claude-Code:claude-opus-5 · 2026-08-16 (session C)
- **Full detail:** `docs/ember-handoff-2026-08-16b-pd-mapper-fixed-qmi-is-next.md`
- **WLAN detail:** `docs/ember-wlan-delta-recovered-2026-08-16.md` →
  **CONFIRMED ON HARDWARE:** `docs/ember-wlan-confound-confirmed-2026-08-16.md`

## State

Everything is banked and pushed.

| | |
|---|---|
| `ghfork/joan/latest-clean-test` | `7187fbbb5` (full history) |
| `ghfork/master` | `63a15f526` (device-verified only; history amended 2026-08-16) |
| kernel tree | `~/vibe-coding-projects/coding/linux-mainline-v30-usb-otg`, branch `joan/usb3-otg-bringup`, clean |
| build dir | `/data/buildcache/kbuild/build-adsp-only` — build **in place**, no `cp -a` |
| test image | `~/joan-images/boot-joan-snd-pdm.img` on nym-nest |
| Deck | Shared Tasks board 4, card **98** |

Phone: LG V30 `LGUS9986e606d55` on nym-nest. **RAM boots only — never flashed.**
Recover with `adb reboot` or a 10 s power hold.

## Do this first

### Lane A — WLAN — ✅ DONE 2026-08-16, positive

`wlan0` comes up from committed state (`7187fbbb5`) with both symbols cleared,
and passively scans **84 BSSs** (54× 2.4 GHz, 30× 5 GHz). QMI service 69 present
at t+10 s. Full writeup: `docs/ember-wlan-confound-confirmed-2026-08-16.md`.

The driver confirms the config itself:
`kconfig debug 0 debugfs 0 tracing 0 dfs 0 testmode 0`.

Modem crash **closed**: 0 fatal errors over a 56-min window with 6 repeated 5 GHz
scans (`max_freq=5785` every time). `519646f01` (withhold 5845 MHz) confirmed —
the Aug-14 baseline crashed every 20-28 s; 3362 s covers ~120-170 intervals.

**Remaining WLAN work** — the lane is reopened, not finished:
1. Re-confirm the modem fix across *separate boots* (this was one 56-min boot;
   it kills the fluke reading but not boot-to-boot nondeterminism).
2. The real target is the fragility: why is bring-up timing-sensitive enough that
   enabling logging loses the race? Start from
   `docs/ember-wifi-modem-crash-rootcaused-2026-08-14.md` (MSA permission vs
   modem watchdog, ~2.5 s).
3. Both symbols must stay **off** in any image meant to have Wi-Fi. That is a
   footgun for the next person who turns them on to debug — worth a ledger note.
4. `tqftpserv` is staged from tmpfs every boot; Lance approved installing it.

### Lane B — audio, and the wall moved (STILL OPEN — start here)

The PD lookup fix landed and is **verified on device**: `avs/audio` now resolves
and the audio PD reports `SERVREG_SERVICE_STATE_UP`. Still no ALSA card. The
blocker is now **below SLIMbus**:

```
qcom,slim-ngd-ctrl 171c0000.slim-ngd: QMI wait timeout
PDR: msm/adsp/audio_pd register listener txn wait failed: -110
```

The ADSP never registers **QMI service 769 (SLIMbus control service)** — checked
with `qrtr-lookup` across three boots. APR over the same GLINK edge works fine
(all four Q6 services register), so this is specific to QMI/QRTR.

Investigate the QMI layer to the ADSP. **Not** the sound node, **not** SLIMbus.
Open questions: why QMI transactions time out at `-110` while APR is healthy;
whether the ADSP needs something before it starts its SLIMbus service; whether
a `tms/pdr_enabled` equivalent is wanted (joan's `modemr.jsn` advertises it,
`mpss_root_pd` does not carry it).

Worth trying alongside: now that PD maps work, add
`qcom,protection-domain = "msm/adsp/audio_pd"` to the Q6 service nodes, as
sdm845 does. It was omitted on a false premise.

## Resolved: the false PD-maps claim is fixed

`719e34de5` claimed *"msm8998 does not run the audio PD split -- its firmware
carries no PD maps."* False; joan ships six. Lance approved amending, so master
was rewritten: `719e34de5` → `a72f66c1d`, and `ghfork/master` is now
`63a15f526`. Verified message-only — both old and new histories resolve to tree
`f16de7d1a`. The corrected body says the property is dropped because the
*kernel's* msm8998 PD table had no ADSP domains, cites `adspua.jsn`, and points
at revisiting `qcom,protection-domain`.

⚠️ **`joan/latest-clean-test` still carries the original `c43b281a5` with the
wrong body.** It was not rewritten — that would force-push six commits of the
shared full-history branch. Fix it when preparing the series for upstream, or
ask Lance.

## Bring-up sequence on device

```sh
# after every phone reboot the USB net link must be rebuilt by hand:
sudo ip link set enp0s29u1u5 up
sudo ip addr add 172.16.42.2/24 dev enp0s29u1u5

# then, from nym-nest (sshpass -f /tmp/pmos-pass, sudo needs -tt):
scp ~/joan-images/staging/adspfw/* user@172.16.42.1:/tmp/adspfw/
echo /tmp/fwpath > /sys/module/firmware_class/parameters/path
echo start > /sys/class/remoteproc/remoteproc1/state
```

`~/joan-images/staging/fastboot-adsp.sh`-style orchestration exists at
`/tmp/fastboot-adsp.sh` on nym-nest — it does Android → RAM boot → net → ADSP in
one shot, ADSP started at 33 s.

## Don'ts — each of these cost real time

- **Don't `cp -a` a build dir and add `KCFLAGS`.** Read `.<obj>.cmd` first to see
  what the dir was actually built with. Adding `-ffile-prefix-map` changed every
  argv and cold-missed ccache: 2200 objects / 20+ min vs 5 objects / 7m40s in
  place.
- **Don't use `deferred_probe_timeout=0`.** It makes
  `driver_deferred_probe_check_state()` return `-ETIMEDOUT` for genpd and iommu
  lookups (`drivers/base/dd.c:292`). Use a large value — `300` worked. But the
  default `10` *will* drop the sound card before a hand-started ADSP exists.
- **Don't judge audio from an ADSP restart.** `echo stop` times out waiting for
  shutdown and the PD listener then fails; only fresh boots are meaningful.
- **Don't trust `grep -c "[p]attern"` for "is anything using this".** Your own
  shell command line matches. Bit me again this session.
- **Don't assume a `-dirty`-looking image is the one you think.** Check the
  version string in the actual file; several neighbours were `-dirty` and the
  working one was not.

## Unrelated but settled

`build-snd-pdm` deleted (5.6 GB) with Lance's approval.

The monthly `duperemove` pass was running for the whole session (started
2026-08-15 07:12; `/home` ~9 h, `/data` still going at 29.5 h) and made all disk
timings noisy — **check `systemctl is-active duperemove.service` before blaming a
build.** It is doing real work, not spinning: `/data/buildcache/kbuild` is
**661 GB logical across 85 build trees**, while the whole `/data` filesystem
occupies only 457 GB — so sharing has already reclaimed 200 GB+, and `/data`
used fell 486 → 457 GB over ~5 h of this session.

**Done 2026-08-16:** `-q` added to `/usr/local/sbin/duperemove-run.sh` with
Lance's approval (backup at `duperemove-run.sh.bak-20260816`). Without it the
pass logged **3.1 M journal lines** (1.5 GB of journal) to the same disk it was
deduping. Takes effect next monthly run; the in-flight pass keeps its old argv.

**Still open, needs Lance:** 85 kernel build trees in `/data/buildcache/kbuild`
is the actual driver of runtime. Pruning dead ones would shorten every future
pass. Not urgent for space — dedup is already reclaiming it.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-16

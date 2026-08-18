# LG V30 (joan) — next session start here

**2026-08-18 (Aurel, seventh shift) — PGD-write kill PROVEN and removed; stream links; crash persists at trigger (20e evidence in flight).**
- Boot 20c/20d used the PHONE-SIDE persistent SD-root dmesg logger (sync-per-
  line). Evidence: docs/evidence/2026-08-18-persistent-log/.
- Boot 20d dump_stack proved the kill chain: aplay trigger ->
  slim_stream_prepare (first USR CONNECT) -> joan pipe bring-up ->
  ADDR_QUERY (fine) -> FIRST app-side writel to PGD_PORT_CFGn (0x14000)
  HANGS the CPU while the ADSP's audio machinery is live. Silent, no panic,
  SoC reset to Android. ADSP owns the PGD block; app-side PGD register
  writes are RETIRED for good (also explains Boots R/S/T).
- Boot 20e (f173f0394): removed the PGD writes; keep pgdla discovery +
  USR CONNECT_SRC/SINK posts. The stream now LINKS (mixer set => BE found;
  q6slim_hw_params + q6afe_dai_prepare fire) — the "no backend DAEs" error
  is only daemon-opens-before-mixer ordering, NOT a topology bug.
- 20e still dies during aplay1 (no "aplay1 rc=" in joan-mixer2.txt);
  first two 20e evidence pulls were eaten by ext4 journal rollback after
  the crash. 20e-r3 uses mount -o sync + INCREMENTAL dmesg -c logger
  (full-buffer dumps were too slow to reach the crash point).
- Fixed recipe for phone-side evidence: remount,rw,sync; rm logs; detached
  seq script (setsid) + dmesg -c loop to /var/log/joan-aplay.log.
- Tooling: nest ~/joan-images/staging/qmidbg20e/{repack-qmidbg20e.sh,
  boot-test-20e.sh, joan-audio-seq.sh}; image boot-joan-qmidbg20e.img
  (sha256 93f755d2d0055d2688d16cded2033673fd16b549d8958729a9d652106a349726).
- Next: analyze 20e-r3 crash point; likely walls after the PGD fix: the
  USR pipe-connect handling on the ADSP side (connect w/o app-side port
  programming), or the ADSP watchdog on the same stream path.

**2026-08-18 (Aurel, sixth shift) — Boot X ran: core blocks hang on READ; controller is V2 NGD; pivot to message path.**
- Boot X (qmidbg19x, STRICT_DEVMEM=n, pgd_enable=0): userspace read-probe before
  ADSP start. 0x171c0004 (COMP_CFG_V2) reads OK = 0x0; 0x171c0200 (MGR_CFG)
  read wedges the system permanently (SIGKILL can't recover; USB died; no
  netconsole output). Control run: garbage unmapped reads hang cores only
  transiently (recover after SIGKILL) => the 0x200 wedge is register-specific.
- Downstream register map (android_kernel_lge_msm8998/drivers/slimbus/slim-msm.h):
  V1 vs V2 offset layouts via CFG_PORT(). All observed behaviors match V2
  (COMP_CFG=4, TRUST=0x3000, PGD_CFG=0x800, OWN=0x300C, PGD_PORT_CFGn=0x14000).
- The component-init sequence (Boots R-W) came from slim-msm-ctrl.c — the
  NON-NGD manager driver. msm8998.dtsi binds qcom,slim-ngd for slim@171c0000,
  and downstream slim-msm-ngd.c never writes COMP_CFG/MGR_CFG. The core is
  ADSP-owned; app-CPU MMIO to 0x200+ hangs BY DESIGN. Boots R-W direction REJECTED.
- NEXT (Boot Y/Z): code study DONE — mainline never reads the ADSP's QMI
  requests (svc 0x0301 rx side missing; downstream drains them and programs
  pipe ports on request). Port downstream's QMI recv path (kworker +
  QMI_RECV_MSG + rx handlers) + pipe-port connect (PGD_PORT_CFGn/BLKn/TRANn,
  port_b rewrite, pgdla get_laddr) into qcom-ngd-ctrl.c. Reconfigure-range
  drop is CORRECT NGD behavior — reconf_passthrough retired as dead end.
  See docs/evidence/2026-08-17-qmi-boots/boot-Y-codestudy-qmi-rx-gap.md.
- Evidence: docs/evidence/2026-08-17-qmi-boots/boot-X-readprobe.md.
- Tooling staged on nest: ~/joan-images/staging/qmidbg19x/{devprobe,probe-x.sh,
  nest-bootx.sh,repack-qmidbg19x.sh}; image boot-joan-qmidbg19x.img
  (sha256 f2fd7f28...).

**2026-08-17 night (Aurel, fourth shift) — PGD writes HANG; next: downstream init-sequence port.**
Boots Q/R/S/T mapped the CONNECT_SINK wall to the missing PGD programming:
- Q: port-level PGD_PORT_CFGn writes are IGNORED (cfg reads back 0); connect
  stalls; ADSP watchdogs 1.3s later ("crash detected in adsp: type watchdog") = the kill.
- R/S/T: the PGD_CFG (0x800) + PGD_OWN_EEn (0x300C+4*ee, 0x3F<<17) enable/ownership
  writes HANG the controller (write never completes, no soundcard, progressive wedge).
  Downstream does them inside a full init sequence (framer→MGR→INTF→PGD→COMP enables)
  that mainline's qcom_slim_ngd_setup lacks.
- Boot U (qmidbg16u): pgd_enable param default OFF (stable); experiments cmdline-driven.
- Stats: apps-ch-pipes 0x1f80 (bus ports 7-12, port_b identity for 0-5); PGD stat shows
  pipes 7-12 auto-assigned; params live at /sys/module/slim_qcom_ngd_ctrl/parameters/.
- Next: code-study the downstream init order (slim-msm-ctrl.c enable path vs mainline
  setup/power_up), find the prerequisite write, one-boot A/B with netconsole.
- Also watch: no-playback wedge appeared on R/S/T but not Q (correlates with the PGD
  writes — confirm gated-off on U).
Details: `docs/evidence/2026-08-17-qmi-boots/boot-RST-pgd-writes-hang.md` +
`boot-Q-adsp-watchdog-pgd-ownership.md` + `boot-P-slim-connect-stall-analysis.md`.

**2026-08-17 late night (Aurel, third shift) — CRASH EVIDENCE CAPTURED: SLIM CONNECT_SINK stall.**
Boot O hung at the logo: the MODULES=n olddefconfig sweep (632 m->y flips)
regressed early boot. Fixed by rebuilding from the Aug 16 config backup
(.config.bak-20260816-adsp-athdbg) + netconsole only = Boot P (qmidbg11p).
Boot P boots, ADSP comes up, and the first netconsole-captured crash shows:
playback start stalls the SLIMbus NGD TX on the CONNECT_SINK user message
(MC 0x2d, mt 2, LA 0xcf = codec) -> silent death (no panic reached
netconsole; dmesg stream lost to missing local dir).
Two candidates + Boot Q plan: `docs/evidence/2026-08-17-qmi-boots/boot-P-slim-connect-stall-analysis.md`.
Evidence: `.../boot-P-netconsole-crash.txt`.
Key facts: nest listener `nc -u -l -p 6666 >> /tmp/joanrun/netconsole-qmidbg11p.txt`;
phone ssh = `sshpass -f /tmp/pmos-pass ssh user@172.16.42.1` (sudo via SUDO_ASKPASS=/tmp/askpass.sh);
nest iface = `ip addr add 172.16.42.2/24 dev enp0s29u1u5 && ip link set up`.
**Next: Boot Q breadcrumbs + candidate toggles (reconf_passthrough, portb_rewrite) + timeout unwedge + pstore.**

**2026-08-17 night (Aurel, second shift) — PLAYBACK PATH OPENED.**
Boots J–L took the playback lane from EINVAL to a completed aplay:
- The "no backend DAIs enabled" wall was the DAPM mixer gates: the
  intercon routes exist (routing comp = every link's platform), but the
  FE walk stops because mixer input paths start disconnected. Enable
  `SLIMBUS_0_RX Audio Mixer MultiMedia1` (amixer) and the FE opens.
  A UCM profile automates this on real systems.
- The AFE port start error 0x9 needed TWO fixes: kernel sets
  `slimbus_dev_id = AFE_SLIMBUS_DEVICE_1` in q6afe_slim_port_prepare
  (v9 patch; mainline left it 0), and `SLIM RX0 MUX` = `AIF1_PB` so the
  codec exposes its SLIM channels to the machine driver (else the CPU
  dai channel map stays empty and the firmware rejects the port).
- With all three: `aplay hw:0,0 48k stereo` completes. The phone then
  crashed (fell to the bootloader) — teardown path suspect (BE shutdown /
  port stop / slimbus teardown), evidence lost with the RAM boot.
- Still missing for AUDIBLE sound: joan DT has no `audio-routing`
  (db845c has it) and the codec-side mixer sequence (RX INT0_1 MIX1 INP0
  = RX0, RX INT0 DEM MUX = CLSH_DSM_OUT, SPK PA) — see Boot L notes.
- DAC (ES9218P): headphone-path-only, mainline has es9218p.c; separate
  lane later, not part of any current wall.
Details: `docs/evidence/2026-08-17-qmi-boots/boot-L-playback-opened.md`;
patches v6–v9 in out/ (v9 sha256 2b19d41f...); ledger K182+ to be
appended. Kernel tree DIRTY with the v9 debug stack (breadcrumbs + gates
+ dev-id fix).
**Next: teardown-crash hunt + codec-side DAPM for first audible sound.**
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

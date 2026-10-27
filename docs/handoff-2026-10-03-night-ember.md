# LG V30 (joan) pmOS port — handoff 2026-10-03 night → next agent

Written-by: Ember (Claude-Code:claude-opus-5-5)
Supersedes the "next steps" of `handoff-2026-10-03-boot-and-open-issues.md` (Fulgor); read that
one for the boot knowledge base (RAM-boot flow, netconsole, SD fsck, repo map), this one for
what changed today and what is blocked.

## 0. Read first

- **Code lives on nym-skyforge** (`ssh nym-skyforge-family`, `~/vibe-coding-projects/coding/`).
  Phone is on USB to **nym-nest**; images in nest `~/joan-images/`.
- Session detail: `docs/session-2026-10-03-ember.md` (bench results, decisions, bench queue).
- Journal: nest `~/.hermes/journal/joan-pmos-mainline-2026-10-03.md` (dated, append-only;
  note its 19:50 entry is corrected at 20:30).
- Memory notes worth reading: `joan_bench_ramboot_gotchas.md` (Claude memory dir).
- Push approvals from Lance (2026-10-03): full-history pushes to kernel `joan/latest-clean-test`,
  **verified-only** cherry-picks to kernel `master`, pushes to the pmaports fork and the
  packages repo. Naming is **`lg-joan`** (not `lge`). Everything else still asks.
- Commit trailers: `Signed-off-by: Lance <Gero3977@gmail.com>` + `Assisted-by: <harness>:<model>`
  (a commit-msg hook enforces both). Never Co-Authored-By.

## 1. BLOCKER — the bench cannot RAM-boot since 09:52

Last successful RAM boot: **r41 at 09:47** (`boot-joan-r41-lg.img`, sha256 `8f65871a…`).
Since then every `fastboot boot` fails. Diagnosis (details in `docs/lg-aboot-fastboot-download-2026-10-03.md`):

- Decompiled stock US99830b ABL (Ghidra; skyforge `/data/buildcache/abl-re`, `all.c` = every
  function). `CmdDownload` (0x38214) answers *"Requested download size is more than max allowed"*
  for size > 512 MB **or size parsed as 0**. The image (31 MB) is not too big; it is identical to
  the one that booted at 09:47.
- A clean first `download:` **is accepted** (`DATA01e9f000`), but the 31 MB bulk OUT transfer
  never completes (no `OKAY`); earlier attempts showed replies out of step and bulk timeouts.
  → **USB data path** problem (nest EHCI rate-matching hub, port `1-1.5`), not a bootloader setting.
- Ruled out: microSD, battery (100 %), lock state (`verifiedbootstate=orange`), PMIC PON spare
  (`0x88f = 0`), cold vs warm entry, image size/header (identical across all of today's images).
- Every confused fastboot session ends at LG's **"any key to shutdown"** screen and needs a
  physical power-hold from Lance.

**Next step (needs Lance):** move the phone to nest's **Renesas xHCI** ports (buses 3/4, empty)
and/or a new cable, *or* test after nest's reboot (20:30 tonight; Lance was going to try the
image by hand). Then one clean attempt: `adb reboot bootloader` → wait 5 s → `fastboot boot <img>`
as the **first** command, full output (never `| tail -1`).

Rules: don't fire `getvar` probes before the send (they desynced aboot tonight), never
`fastboot reboot`/`reboot-bootloader`/`continue` from a confused session, bound every send.
`tools/bench/ramboot.sh` enforces this. Raw-USB tools (log every reply, 16 KiB writes with
progress): nest `~/.ember/workspace/joan-r37-bench-2026-10-03/tools/{fbboot,fbdrain,fbpeek}.py`
(need a venv with `pyusb`).

## 2. State of the repos

| repo / branch | state |
|---|---|
| kernel `joan/latest-clean-test` (origin) | **`a4c931d8c550`** — pushed, see §3 |
| kernel `master` (origin) | `1492105184d6` — + tfa989x set_fmt, sdm845 ENOTSUPP (bench-verified r37) |
| kernel `joan/gold-boost` (local) | `8f45281b82ea` — not booted |
| kernel `joan/charge-thermal` (local) | `3b46281a1663` — not booted |
| kernel `joan/bench-r45` (local) | `12c78319ca0d` = canonical + both above |
| kernel `joan/slpi-enable` (local) | `d1cdbea80ebd` — not booted |
| kernel `joan/venus-porthole-canonical` (local) | `f351e7aa910a` — porthole's 24 patches + TEST-ONLY enable |
| pmaports fork `joan/readme-build-guide` | pushed **`d601b0f73c`** (rename to lg-joan, kernel pin `74dc95f`) |
| pmaports local, **not pushed** | `6c961a4fa2` r41 pin · `261858941e` bootmac · `e95cc41e8c` PCI off · `55f0ecb734` r44 pin |
| packages repo `master` | pushed `260ecfd` (rename + resync from pmaports) |
| docs `claude/lucid-dijkstra-bxx3r9` | pushed `9e7e59d` |

Untracked in lg-v30-port (Fulgor's / earlier, **not mine — leave them**): `docs/cpu-gpu-audit-2026-10-02.md`,
`docs/hardware-gap-sweep-2026-10-02.md`, `docs/hi553-port-2026-10-02.md`, `docs/evidence/2026-10-02-hi553/`, `fw/`, logs.

Fork default branch is still `device-lge-joan` (2026-09-06 pre-alpha, 134 behind) — Lance's call.

## 3. What changed today (kernel, all on latest-clean-test unless noted)

Bench-verified (RAM boot):
- es9218p mute-register cache seed (`df9cb24`) — r38/r39: 0 ASoC errors.
- Venus firmware name `venus.mdt` (`b05c269`) + **Venus kept disabled** (`3334adb`): a full probe
  resets the phone (proven by a blacklist boot).
- OSM ACD programmed on its own cluster (`36be1fd`) — fixes intermittent silver `-110` (no policy0).
  2 clean boots; keep off master until more.
- Rename `msm8998-lg-joan.dts`, compatible `lg,joan` (`74dc95f`).
- **Memory map from LG's final builds** (`4c3d158`): all 20 DTBs of US99830b + H93230d identical;
  SLPI now 15 MiB, pil_ipa_gpu block at 0x95f00000, wlan_msa at 0x96000000. r41 booted with it.
  Open: cellular IPv6 got no replies and PipeWire listed no device on that boot — kernel logs
  identical to r39; confounded by an accidental pipewire 1.6.9 upgrade. A/B image staged.

Built, compile-checked, **never booted**:
- SX9320 SAR node disabled (`f184bc3`) — absent from all stock DTBs, NACKs.
- bu24235 lens registered as a media entity with devnode (`f0efba5`).
- pop_mem thermal rule (`233f7e5`) — LG SS-POPMEM: gold throttled at 85 C.
- **FCC register bug fix (`a4c931d`)** — qcom_smbx wrote the charge current to CHGR+0x40 (the
  step-charge threshold) since 2026-08-07; FCC is CHGR+0x61, 25 mA steps. Bug is on `master` too:
  cherry-pick to master after one bench read of the register.
- Gold single-core boost to 2457.6 MHz (`joan/gold-boost`) — design + traps in
  `docs/cpu-gold-boost-design-2026-10-03.md` (cpufreq table now sorted with LUT row in
  driver_data; gold cooling states +3).
- LG charge throttling (`joan/charge-thermal`) — FCC cooling device, 2.6/1.5/0.8/0.6 A at
  10/40/42/45 C skin.
- pmaports: PCI off (−63 modules, package 51 → 44 MB), bootmac (stable MACs).

## 4. Bench queue (in order, once a send works) — artifacts on nest `~/joan-images/`

1. **r41 A/B**: `boot-joan-r41-lg.img` (new map) vs `boot-joan-r41-oldmapdtb.img` (same image,
   pre-map DTB), order new → old → new; `tools/bench/validate.sh <tag>`, cellular IPv6 over
   `qmapmux0.0`, `wpctl status`, `journalctl --user -u wireplumber -b`.
2. `device-lg-joan-1-r21.apk` (bootmac): same `02:00:…` wlan0 MAC across two reboots.
3. `boot-joan-r41-slpi.img`: expect remoteproc slpi up; any reset → add stock's `aggre2` NoC vote.
4. `linux-lg-joan-7.2.0_rc2-r44.apk` (PCI off, SAR off, bu24235) via `tools/bench/joan-pkgboot.sh`.
5. `linux-lg-joan-7.2.0_rc2-r45.apk` (r44 + FCC fix + boost + charge throttling): check
   `scaling_available_frequencies`/`boost`, debugfs `qcom-cpufreq-osm/policy4` LUT dump,
   skin cooling states still map to 1958.4/1728/1056/729.6 MHz, FCC register value,
   `pmi8998-charger-fcc` cooling device.
6. Venus: `linux-lg-joan-7.2.0_rc2-r42.apk` (TEST ONLY), cmdline
   `modprobe.blacklist=venus_core,venus_dec,venus_enc`, then `modprobe venus_core stop_at=6`
   (reboot between rounds; never rmmod). `stop_at=N` runs checkpoints **< N**.
7. After each success: push the matching pmaports commit; promote verified fixes to `master`
   by cherry-pick (FCC fix first).

## 5. Open decisions for Lance

- **Wi-Fi calibration**: US998 runs the H930 board file (no `qcom,calibration-variant`).
  Proper fix = per-model DTS + an `lg-joan-us998` pmbootstrap device (Deck #86).
- Fork default branch `device-lge-joan` move/rename.
- Cleanup candidate (not deleted): skyforge `/data/buildcache/lg-stock-kdz/us998/slices` (5.1 GB
  real, every stock partition) — keep `dtbs/`, `abl.image`, `boot.image`.

## 6. Hard facts (don't re-derive)

- No FM transmitter on joan (WCN3990 Helium is RX-only; LG builds only `SND_FM_RX_MI2S`).
- GPU 710 MHz and silver 1900.8 MHz already equal stock maxima; only gold 1-core boost was missing.
- No packaged NFC GUI (GNFC repo returns 404) or V4L2 FM tuner app exists to ship as defaults.
- Final stock builds: US99830b_00_0902 (sha256 `82af7537…`), H93230d_00_0902 (`aa7584f6…`), on
  skyforge `/data/buildcache/lg-stock-kdz/`; all DZ chunk MD5s verified.
- `apk` pins file-installed packages in `/etc/apk/world`; a local test repo needs a `noarch`
  symlink; `apk add -u` drags in distro upgrades (use `apk upgrade <names>`).
- systemd 262: `systemctl reboot --reboot-argument=bootloader`.

## 7. Deck

#179 (handoff tracker), #180 (Blocked: phone/USB), #86 (Wi-Fi calibration decision), #162 (SLPI),
#178 (boot-log error counts).

# 2026-10-07 — gold DVFS dropout, boot-log pass, charge throttling, IPA SSR BUG (Ember)

Claude-Code:claude-opus-5-5. Bench: US998, RAM boots (`fastboot boot`, armed send),
rootfs on the SD. Kernel tree: `linux-lg-v30-joan` `joan/latest-clean-test`.

## Pushed / pinned

- Kernel `joan/latest-clean-test` 01fd102a → **b3dc8621** (fast-forward, 24 commits,
  all of 2026-10-06 plus the ones below).
- pmaports `joan/readme-build-guide`: the 57 local commits of 10-03..10-06 (mostly
  "debug pin cycle" commits) were rebuilt as 9 clean commits on the published tip;
  the tree is identical to the old local tip apart from the kernel pin, which is
  now **linux-lg-joan r55 → b3dc8621**. Old local history: tag
  `ember/pre-squash-20261007` (skyforge clone only).

## Findings and fixes

### Gold cluster without cpufreq on one boot (fixed, 1c6b4ecf)
The r49 boot that had been up for 14 h had **no policy4**:
`ACD auto-transfer timed out on CPU4: autoxfer_sts=0x1` → `Cannot setup the OSM for
CPU4: -110` → three `WARNING: drivers/opp/core.c:2563 dev_pm_opp_set_config` and
`Could not attach to pm_domain: -16` for CPU5-7. Gold ran at its boot clock.
- The status read back as done right after the timeout: the transfer was late, not
  lost. Our poll slept (1 µs sleep, 3 µs budget); LG's `clock-osm.c` busy-waits
  (`ndelay`, 500 ns/register). Now `readl_poll_timeout_atomic`, 100 µs.
- The ACD step ran after the LUT. Programming the LUT attaches the CPRh domain
  (devm on a CPU device, never released) and fills the OPP table the four gold
  CPUs share, so the cpufreq core's retry from CPU5 hit a populated table → -EBUSY.
  ACD now runs first; a failure leaves nothing behind.
- No `->online/->offline` meant a cluster hotplug re-ran `->init()` on a live OSM.
  Empty callbacks added. Bench: offline/online CPU4-7 keeps policy4, 2457.6 MHz.
- Reliability: 8 RAM boots of b3dc8621, policies=2 and osm_err=0 every time.

### Boot-log pass (r53: err+warn 64 → 32..45 per boot, rest triaged)
- `debugfs: 'pfp'/'me'/'meq'/'roq'/'reset' already exists` — adreno_load_gpu() ran
  the a5xx debugfs_init for the primary AND render minor, but all minors share one
  directory now. Called once (1f1ac5f1). Upstream candidate.
- `spmi spmi-0: cleanup_irq apid=58 sid=0x2 per=0x40 irq=7` + bad_chained_irq dump:
  BATT_SOC bit 7 is **msoc-full** (LG `msm-pmi8998.dtsi` names: soc-update,
  soc-ready, bsoc-delta, msoc-delta, msoc-low, msoc-empty, msoc-high, msoc-full),
  left enabled by the bootloader. Masked at probe (c70c6206), then mapped and
  handled (power_supply_changed) because an event latched before boot is still
  pending in the arbiter (b641fd48 binding, df05b214 dtsi, b3dc8621 driver). The
  binding example used bit 4 (msoc-low) for soc-delta; fixed. dt_binding_check and
  CHECK_DTBS on the joan DTB clean.
- `qcom,slim-ngd-ctrl: QMI wait timeout` ×2 — the normal path (new_server re-runs
  the worker); now dev_dbg (67d14598).
- Triaged, unchanged (cosmetic or bootloader): kernel image misaligned (ABL), ITS,
  UFS ICE, adreno vddcx dummy, wifi vdd-3.3-ch1 dummy (LG wires ch0 only), tfa989x
  vddd dummy, wcd934x-gpio DMA mask, ath10k board-2 miss (per-variant board.bin
  fallback works; per-model DTB decision pending), `Handover signaled, but it
  already happened`, ext4 "unchecked fs" on /boot (bench hard resets), BT frame
  reassembly -84 during firmware download, WCN3990 three read faults at IOVA 0
  (SID 0x1900) at firmware boot — LG maps WLAN IOVAs from 0xa0000000, so IOVA 0 is
  unmapped there too; Wi-Fi works.
- DP: `PHY is configured for USB, can not enable DP` / `phy init failed -16` /
  `phy_power_on was called before phy_init`. The DP controller initialises the
  usbc PHY while it is in USB mode. LG wires DP over USB-C (mdss_dp_ctrl AUX OE/SEL
  + CC GPIOs, USB_PD_POLICY); our DT has the 0xff01 altmode on the PMI8998
  connector. Needs a DP sink on the bench.

### Charge throttling (LG CHG_MONITOR) — now in the tree (41f97fc7)
The 10-03 `joan/charge-thermal` commit had never been booted. Bench (r52/r53):
`cooling_device0 pmi8998-charger-fcc`, bound to skin-thermal trips 9-12, state 1
(2.6 A) at 31 °C skin, as LG. (A NULL second argument looked like a bug; it is
`cdev_id` in 7.2 and the helper uses dev->of_node. Not changed.) Not yet measured:
battery current at each state (battery was full).

### IPA: kernel BUG after a modem restart (fixed locally, ef74a2f4, NOT yet booted)
Restarting the modem remoteproc (I meant the ADSP: remoteproc numbering changes
between boots — select by `name`), then ModemManager re-opening the netdev:
`GSI command 2 for channel 8 timed out` → `error -11 attempting to stop endpoint 16`
→ `kernel BUG at net/core/dev.c:7659` (napi_enable_locked) in `ipa_open` under
`rtnl_setlink`. RTNL stayed held; sshd stopped answering; the phone needs a power
cycle. gsi_channel_stop() returned before napi_disable() on failure while the
endpoint was marked disabled anyway. Fix: always disable IEOB + NAPI. Same code in
mainline → upstream candidate once bench-verified (modem SSR, then data back).

### ADSP QRTR silent on 1 of 8 boots (open)
First boot of r53: ADSP up, APR services present, IPCRTR rpmsg channel present, but
**no node-5 QRTR services** → no SLIMbus QMI (769) → `msm-snd-sdm845: SLIM Playback:
codec dai not found` → no sound card. The next 7 boots were fine (6 services on
node 5). Not reproduced since. Next: on a failing boot, capture whether qrtr_smd
bound the ADSP IPCRTR device and whether the ADSP sent HELLO (qrtr tracepoints);
then decide between a root-cause fix and an ADSP restart when 769 never appears.
`tools: ~/joan scratch probe.sh` records adsp_qrtr_svcs/card/policies per boot.

## Bench notes
- boot.img from on-device mkinitfs is 31,932,416 B; aboot's limit is 32,108,544 B
  (176 KB headroom). Watch kernel/initramfs growth.
- `systemctl reboot -ff --reboot-argument=bootloader` did not get through after the
  RTNL-held oops (sshd was already unresponsive).

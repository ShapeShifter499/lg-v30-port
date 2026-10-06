# LG V30 (joan) pmOS port — handoff 2026-10-05 (Fulgor, night) → next agent

Written-by: Fulgor Nymvale (agent-fulgor-zcode, ZCode:GLM-5.3-Flash)
Continues: handoff-2026-10-03-night-ember.md + handoff-2026-10-03-boot-and-open-issues.md
(read both first — boot KB still applies, with the USB update below).

## 0. THE HEADLINE — RAM boot SOLVED

Lance found it: **aboot's download session times out**. The host must run
`fastboot boot <img>` FIRST (parked at "waiting for device"), then trigger the
reboot into the bootloader (adb reboot bootloader, or from pmOS
`systemctl reboot --reboot-argument=bootloader`). The send fires at
enumeration, inside aboot's window. r41 and r46 both RAM-boot this way.
- The 2026-10-03 "no RAM boot" outage was this race (not hub/cable/phone).
- usbcore.quirks=18d1:d00d:k (NO_LPM) on nest stays required for full-speed
  bulk-OUT (persisted in nest's systemd-boot entries, both arch*.conf).
- Truncated pulls fail "remote: BootImage is Incomplete" — verify pulls.
- ramboot.sh rewritten (lg-v30-port d125aa2): armed-send pattern + .done check.
- Cable swaps / xHCI port: no longer needed for this issue.

## 1. r46 is BUILT and RUNNING (base for everything next)

linux-lg-joan-7.2.0_rc2-r46, kernel pin chain: a4c931d (r41+FCC) → 2f744cab
(brightness) → venus fold-in (68ba44d0) → DT fixes (9e36b2f5, f125b7c0,
01fd102a) → debug prints (9566dcc8..HEAD). Phone runs #47-lg-joan, system
running. Validated 2026-10-04: cellular LTE 94% + IPv6 works, PipeWire sees
TFA9872, GPU up, dmesg clean of program-critical errors, memtester 2GB×2 clean.
New in r46 vs r41: **brightness blmap curve** (2f744cab — LG's joan table
resampled to [6..255]; mid-slider ~65% DBV), **Venus DT enabled + porthole
series**, FCC register fix, SX9320-off, BU24235, pop_mem, bootmac.

## 2. VENUS — exactly one clock short (next session: build + verify)

The porthole fold-in hit a chain of fixes, each verified on the bench:
1. -EEXIST before venus_probe → NOT genpd: it was the driver core's
   dev_pm_domain_attach vs the driver's own multi-domain attach. FIX (DT,
   committed 9e36b2f5): &venus lists THREE power-domains
   (VIDEO_TOP_GDSC, VIDEO_SUBCORE0/1_GDSC) + power-domain-names
   "venus","vcodec0","vcodec1" → genpd skips single-attach for multi-PD
   devices and the driver's devm_pm_domain_attach_list("venus","vcodec0",
   "vcodec1") attaches cleanly (verified: vcodec_domains = 3).
2. -ENOENT in core_get → the msm8998_res clks list (5+ clocks) needs DT
   entries. mnoc_ahb fixed (f125b7c0). **NEXT CLOCK, applied-but-UNBUILT
   (01fd102a): "noc_axi" = <&gcc GCC_MMSS_SYS_NOC_AXI_CLK>** — just build.
3. After clocks: the probe proceeds toward firmware boot; VENUSDBG prints
   (core.c/firmware.c/pm_helpers.c) are still in the tree to trace it —
   strip them once Venus probes clean, then cherry-pick the icc-optional
   fix (e84d90c0 + 9b69e05e) to master. Interconnect on msm8998 is
   absent mainline (mmss_noc exists at 1740000 as an icc device and
   claims video_axi — a future real icc provider candidate).

Deploy loop (proven, ~10 min): pmbootstrap build → scp apk to phone →
sudo apk add --allow-untrusted → boot-deploy regenerates /boot/boot.img →
scp back → armed fastboot boot. Debug builds: **pmbootstrap builds the
STAGED DISTFILE, not the working tree** — every source edit needs
git commit → git archive --prefix=linux-lg-v30-joan-<sha>/ → stage into
cache_distfiles AND chroot_native/var/cache/distfiles → update the
APKBUILD _commit + sha512 (the build-cycle.sh pattern on nest /tmp).

## 3. Other open items (Deck)

- #182 DSI-1 atomic EBUSY: display enable HANGS on laf-entry boots
  (connector Off, commits EBUSY forever); on fastboot-entry boots the
  connector is On but EBUSY flood persists (~2/s). Entry path changes the
  panel handoff, not the commit bug. drm.debug boot is the next probe.
- #183 SMMU context faults (wlan msa, SID 0x1900): benign, decoded.
- phy -16 (DP alt-mode qmp contention): untouched. DisplayPort over
  USB-C remains a feature goal (needs the qmp/typec serialization).
- DT2W: pinned #181 (stmfts gesture mode; ~1 bench session).
- Brightness: Lance should feel the r46 slider ramp (blmap curve).

## 4. Repo state (push where Lance approved: kernel canonical + docs)

- kernel joan/latest-clean-test-merged HEAD 01fd102a (local; canonical was
  pushed at 68ba44d0 — push again after stripping debug prints). DEBUG
  commits (prints) sit on top: strip + revert before promoting anything.
- pmaports joan/readme-build-guide: pin 01fd102a pkgrel 46 + DEBUG commits,
  NOT pushed (debug); the r46-release pin was 68ba44d0 pkgrel 46.
- Deck: #181 DT2W (Someday), #182 DSI-1 EBUSY, #183 SMMU, #184 DONE r46,
  #185 RAM-boot procedure, #186 venus -EEXIST pre-probe finding.
- Honcho + memory: RAM-boot procedure + laf deploy path saved.

## 5. Bench ops quick reference (all proven tonight)

- pmOS USB-net: 172.16.42.1, jssh wrapper /tmp/ember-f08d8c5-unpack/jssh
  (recreate from lg-v30-port/tools/bench/jssh), JOAN_PW=~/.config/joan-bench-pw.
  Link bounces: `ip link set enp0s29u1u1 down/up` + re-add 172.16.42.2/24.
- Deploy new kernel: scp apk → phone /home/user → `sudo apk add
  --allow-untrusted` → boot-deploy auto → md5 /boot/boot.img → scp to nest →
  arm `fastboot boot` → pmOS `reboot --reboot-argument=bootloader`.
- H932: no fastboot at all — laf + Vol+ path only; stock laf restorable from
  skyforge ~/h932-laf-backups/. H932 DPU crash (frame_done timeout) still
  open; fastboot-entry boots light the panel on the US998 — compare.
- US998 hardware: RAM clean (memtester), abl stock (673263a7), flash chain
  healthy. Bench phone: US998 with its own SD (pmOS rootfs mmcblk0p2,
  boot p1 on that card; UFS = sda in LineageOS).

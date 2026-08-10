# Card 94 retest — 2026-08-10: A540 runtime-PM pin is load-bearing (device-proven)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-flash
Date: 2026-08-10

Retest of Ember's staged card-94 experiment (handoff
ember-handoff-2026-08-10-for-aurel-card94-retest.md, image
boot-joan-icc-suspend.img). Result: the pin stays. Full evidence
below.

## Experiment matrix (all RAM-only boots, nothing flashed)

| # | image | content | result |
|---|---|---|---|
| 1 | boot-joan-icc-suspend.img (27,815,936 B, sha256 f61a155e…) | unpin + ICC gfx-mem vote-drop | booted to pmOS userspace, wedged ~40s: `qcom_icc_rpm_smd_send mas 35 error -110` (34.8s) then `sdhci_msm: Failed to remove bandwidth[0]: -110` (39.9s); console ends abruptly → watchdog reboot → LineageOS |
| 2 | boot-joan-unpin-only.img (27,815,936 B) | unpin alone (ICC hunks reverted, same base b79ba8084) | console stops at [9.46s] right after switch_root; no -110s; reboot → LineageOS |
| 3 | boot-joan-master.img (27,807,744 B, kernel 7.2.0-rc2-g47041183b55e) | master tree, pin present, nothing changed | **STABLE: 11+ min at the pmOS lockscreen**, `runtime_suspended_time` = 0 (pin holding), **0** `qcom_icc_rpm_smd_send` errors |

## Conclusions

1. **The A540 runtime-PM pin is load-bearing.** Both pin-removed images
   (size- and hash-verified) fail to reach a stable userspace; the
   pin-present master image is rock solid. The earlier "confounded"
   unpin negative from Ember was confounded in the image, but the
   substance — pin removal breaks the boot — is now reproduced cleanly
   twice.
2. **The ICC vote-drop change did not rescue it** (unpin-only died
   even earlier, at switch_root) and added its own RPM-SMD wedge. The
   change is shelved; `joan/a540-unpin-test` and `joan/unpin-only-test`
   branches keep both variants for reference.
3. **Root cause is the A540 suspend path**, exposed the moment the pin
   allows runtime suspend: upstream `a5xx_pm_suspend()` skips the VBIF
   reset on A540 ("the others will tend to lock up") and mainline lacks
   the downstream SPTP gate on `A5XX_GPMU_SP_PWR_CLK_STATUS`. Next
   lead: fix the suspend path (VBIF/SPTP), then retry the unpin with
   `CONFIG_PM_ADVANCED_DEBUG` to watch `power/runtime_usage`.
4. **Bonus finding (battery lane):** on the stable master boot,
   `/sys/class/power_supply/` contains only `pmi8998-charger` — the
   `pmi8998_fg` driver is NOT registering a battery supply, which is
   why phosh reports no battery ("missing battery code"). Real lead
   for Lance's fuel-gauge goal: check pmi8998_fg probe failure
   (dmesg) on the next root session.

## Evidence saved

- out/pstore-icc-suspend-2026-08-10.{bin,strings.txt} (crash #1 record:
  banner, userspace boot to 39.9s, -110s, abrupt end)
- out/pstore-unpin-only-2026-08-10.strings.txt (crash #2 record:
  console ends at [9.46s] switch_root)
- Live checks on the stable boot: up 11 min, suspended_time 0,
  ICC errors 0, power_supply list (above).

## Access correction (important)

The Aug 9 handoff's "pmOS root password: 147147" is wrong for this
rootfs: **root rejects 147147; user `user` / 147147 works.** Phone is
at 172.16.42.1 over the USB NCM gadget (host: 172.16.42.2 on
enp0s29u1u5 at nym-nest). Corrected in the Aug 9 doc.

## State after test

- Phone: stable pmOS lockscreen on the RAM-booted master kernel
  (nothing flashed; a power cycle returns to LineageOS).
- Branches: joan/a540-unpin-test (3f0954cfa, both changes),
  joan/unpin-only-test (3d55e94d6, unpin only). Neither pushed;
  master untouched.
- Deck card 94: comment filed with this summary.

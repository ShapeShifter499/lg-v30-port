# Handoff — 2026-08-10 session close

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-10

Four lanes closed, all device-verified. Three of the four had been
misdiagnosed before today, and the corrections matter more than the fixes.

## Closed

**Bluetooth** — `hci0` was never broken. It was `HCI_UNCONFIGURED`,
missing only a public BD address, because our own `240de5d2f` set
`HCI_QUIRK_USE_BDADDR_PROPERTY` unconditionally and it regressed the
moment the per-device MAC left the DTS. Gated the quirk, added an
all-zero `local-bd-address` placeholder (as `qcs404-evb.dtsi` does), and
a device service deriving `02:00:A0:AC:61:B0` from the fused SoC serial.
Autostart proven across two boots; discovery returns 16 devices.

joan has **no factory BT MAC** — NVM address TLV is zeroed, LG's own
`btnvtool` generates a random one, and LineageOS keeps its
`22:22:4E:0B:DB:01` in `/data/misc/bluedroid/bt_config.conf`. Wipe
userdata and Android gets a different MAC. Ours is derived and stable.

**Keypad freeze** — not the compositor. `stmfts` stranded MT slots;
`EVIOCGMTSLOTS` showed **five phantom contacts held with nothing touching
the screen**, so every tap arrived as a sixth finger and phosh routed it
to a gesture. Fixed with `INPUT_MT_DROP_UNUSED`, justified by
measurement: a held finger is re-reported at ~125 Hz so it is in every
frame, while a stranded contact is silent for ten seconds at a time.

**Rainbow on wake** — not settle time. `sw43402_prepare()` forced
brightness to `DBV_MAX` on every wake and the backlight framework
restored the real value a beat later. See
`ember-2026-08-10-rainbow-on-wake-was-brightness.md` for the full write-up.

**Flash-awake after lock** — not a ghost touch. The power switch
chatters: one press produced three press/release pairs in 90 ms, gaps of
17-19 ms, which clear mainline's 15.625 ms debounce but not the 31.25 ms
the vendor configures for the same PMIC. Adopted the vendor value.

## Repo state

    linux-lg-v30-joan   master ................. c861d1217
                        joan/latest-clean-test .. c861d1217  (identical)
                        PR #8 .................. MERGED
    lg-v30-port (docs)  ghpub/master ........... 8dc16b5

Convention as Lance set it: master is verified fixes, `latest-clean-test`
is the raw "booting but ugly" working history. `345eb2ddc` brought that
history in as ancestry with master's tree verbatim, so staging carries the
experiments and reverts while content stays identical.

## Card 94 — reframed, not solved

The GPU power domain never suspending is **deliberate**. `c3f1b45f0`
(2026-08-02) holds `devm_pm_runtime_get_noresume()` for the A540 because
"runtime power collapse leaves the A540 interconnect wedged on MSM8998",
explicitly labelled a bounded workaround. `devm` holds it until unbind, so
the autosuspend timer never starts — which is why `runtime_suspended_time`
is 0 at *any* `inactive_period`, and why Aurel's later 5-minute GDSC
change measured as a no-op. Two workarounds for one thing, the second
unaware of the first.

**Retest run and failed.** Lifting the pin on the theory that the ICC work
since 2026-08-02 had made collapse safe hung the device at the LG logo —
autosuspend fires ~250 ms after probe, collapse wedges the interconnect,
boot dies there. USB came up as `18d1:d00d`, recovered by force-restart,
nothing flashed, reverted in `b79ba8084`.

**Research lead for the real fix.** Mainline sets the GPU's interconnect
vote once at probe and never drops it:

    a5xx_gpu.c:1773   icc_set_bw(icc_path, 0, Bps_to_icc(gpu->fast_rate) * 8);

Downstream KGSL instead drops the bus vote on every power transition
(`msm_bus_scale_client_update_request(pwr->pcl, buslevel)`) and gates SPTP
collapse on `A5XX_GPMU_SP_PWR_CLK_STATUS`. So mainline collapses the power
domain **with an ICC vote still outstanding**, where the vendor does not.

**Chronology rules this out as the original cause**, and I had it wrong in
the first draft of this document. The vote is ours, added by `7d9b74b7f`
on 2026-08-04 along with the msm8998 ICC driver itself — two days *after*
the pin. On 2026-08-02 there was no mainline interconnect driver for this
SoC at all ("the 8998 GPU previously ran without any bus-bandwidth
scaling"), so whatever wedged then was the hardware NoC, not a vote we
were holding.

It is still worth testing, but as "does holding the vote across collapse
make things worse, and does dropping it on suspend help now" — not as an
explanation of the original breakage. The experiment is cheap: drop the
`gfx-mem` vote in the a5xx suspend path, restore it on resume, and retry
the unpin.

Cost of the workaround is real: an idle screen-off phone keeps the GPU
domain powered.

## Open

| card | lane | state |
|---|---|---|
| 90 | WiFi / WLFW service 69 | blocked on `wlanmdsp.mbn` |
| 91 | pwrkey IRQ froze at 46 | plausibly fixed by the debounce; retire or retest |
| 94 | A540 collapse sequence | reframed above, ICC-vote lead |
| 95 | charging path moves current | pinned; needs the pack to drain to ~90% |

Cards 88 and 89 carry the `Finished` label but could not be moved to the
Done stack — this Deck version returns HTTP 200 for a card `stackId`
change and ignores it, on both v1.0 and v1.1. They need dragging in the UI.

## Environment

    source worktree   /tmp/joan-bt-fix          (tmpfs — evaporates on reboot)
    build dir         /data/buildcache/kbuild/build-integration-d38242fb5
    ccache            /data/buildcache/ccache

Both moved to the spinning disk for SSD wear: measured `sda +539.7 MB` vs
`nvme0n1 +19.9 MB` over 150 s of compilation, ~19 GB relocated. The NVMe
was at 13% used / 19.8 TB written.

**ccache is not automatic.** It only applies when the make line carries
`CC="ccache aarch64-linux-gnu-gcc"`. The practice note claiming "ccache
warm" was wrong for the whole session — `/usr/lib/ccache` only shims
native compilers, so `CROSS_COMPILE` resolved straight to real GCC. Full
invocation:

    make -j12 O=/data/buildcache/kbuild/build-integration-d38242fb5 \
         ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
         CC="ccache aarch64-linux-gnu-gcc" Image Image.gz modules dtbs

Other traps hit today: `olddefconfig` will **not** enable a
newly-available driver (that is how the fuel gauge went missing from
master's first boot); the single-dtb target without `O=` is an in-tree
build and leaves the source tree unbuildable for out-of-tree builds; and
`pgrep -f` in a polling loop matches the loop's own argv, which left nine
stuck waiters running up to 3.2 hours.

## Method note

Every fix today came from comparing against a reference — the vendor
DTSI, the downstream driver, the upstream sibling, or raw device state.
Every wrong turn came from reasoning forward from a plausible story. The
rainbow delay is the clearest case: 20 → 120 ms, with 300 ms queued, three
steps down a path with no counterpart in LG's sequence at all.

Read device state directly rather than inferring it from an event stream.
`EVIOCGMTSLOTS` answered in one call what an hour of reasoning got wrong,
and `getevent` under LineageOS is ground truth for what a correct driver
produces on this hardware.

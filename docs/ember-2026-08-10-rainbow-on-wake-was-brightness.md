# The rainbow on wake was never a settle-time problem

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-10

joan showed transient rainbow garbage on the panel every time the screen
woke. It had been chased for weeks as a display timing problem. It was
the panel driver slamming brightness to maximum on every wake.

## What it actually was

`sw43402_prepare()` ended with:

    mipi_dsi_msleep(&dsi_ctx, 120);
    sw43402_write_wrctrld(&dsi_ctx, ctx->link);
    mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_DISPLAY_BRIGHTNESS,
                                 SW43402_DBV_MAX);
    sw43402_bc_dim_init(&dsi_ctx, ctx->link);
    mipi_dsi_msleep(&dsi_ctx, 20);
    mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_DISPLAY_BRIGHTNESS,
                                 SW43402_DBV_MAX);

`DBV_MAX` is 255. `prepare()` runs on every wake, so the panel came up at
full brightness regardless of what the user had set, and the backlight
framework then restored the real level a moment later. What that looks
like is a flash across a panel that is still mid-transition — which reads
as garbage, because during that window the panel genuinely is unsettled.

It was also **redundant**. The backlight device is registered on the
drm_panel:

    ctx->base.backlight = devm_backlight_device_register(...)

so `drm_panel_enable()` calls `backlight_enable()`, which runs
`backlight_update_status()` and applies the stored brightness through
`sw43402_backlight_update_status()`. The framework was always going to
restore the correct value. `prepare()` was overriding it first, for
nothing.

## Three references, and we were the outlier

None of this was ambiguous once we looked:

| source | brightness after display-on |
|---|---|
| LG downstream DV3.1 DTSI | nothing at all |
| upstream `panel-lg-sw43408.c` | nothing — only in `backlight_update_status` |
| our `panel-lg-sw43402.c` | `DBV_MAX`, twice |

Downstream's whole post-panel-on command is:

    39 01 00 00 3C 00 03  B0 A5 00     B0 A5 00, wait 0x3C = 60 ms
    05 01 00 00 00 00 01  29           display-on, wait 0x00 = NOTHING

Our 60 ms *before* display-on matched the vendor exactly. Everything
after it was ours. LG sets `51 03` — near-dark — during init and never
touches brightness again; the framework ramps it afterwards.

`sw43408` is the closest in-tree sibling (same LG SW434xx family, DSC
1.1) and the driver our own header says we adapted from. It writes
brightness in exactly one place: its `backlight_update_status` handler.

## How the wrong answer survived so long

The git history tells the story:

    2b466d2f7  enable brightness control after display-on
    bff40d20b  let the panel settle before latching brightness
    28801f2cc  restore full byte brightness range
    519c7bf17  settle longer after display-on on wake

Each step was reasonable on its own. Together they produced a hardcoded
max-brightness write plus a settle delay that grew 20 ms -> 120 ms, with
a proposal on the table to try 300 ms.

The delay *appeared* to help each time it was increased, which is what
kept the theory alive. It almost certainly did help, but not for the
stated reason: a longer wait meant more of the brightness flash happened
while the panel was still dark, so less of it was visible. The delay was
partially hiding a different bug, and every increase bought a little more
concealment at the cost of wake latency.

That is the trap worth naming. **A change that reduces a symptom is not
evidence that the mechanism you had in mind is the right one.** Three
successive "it got better" results built a confident, wrong model.

## The fix

Commit `7955237ff` — drop both `DBV_MAX` writes and let the backlight
framework own brightness. `WRCTRLD` and the dimming init stay; those are
panel control state, not brightness.

Verified on device (`g0dc0bb9eb8ca`), brightness set to 22, two lock/wake
cycles:

    t=27s  brightness=22  bl_power=0    set low
    t=33s  brightness=22  bl_power=4    lock
    t=36s  brightness=22  bl_power=0    wake — held, no jump to 255
    t=45s  brightness=22  bl_power=4    lock
    t=48s  brightness=22  bl_power=0    wake — still 22

Owner report: *"brightness held and the rainbow is gone"*.

## And then the delay came out too

With the real cause fixed, the 120 ms settle had no remaining
justification — the vendor waits nothing there. Commit `d7206ebe0`
removes it.

Verified over 8-10 lock/wake cycles (`g42fa5a3e4d5a`): no rainbow,
brightness held at 56 across the transitions the trace caught. Owner
report: *"no rainbow. lockscreen seems a little snappier actually"* —
that is 120 ms returned on every unlock.

The panel sequence now matches LG's on both sides. No invented delays,
no invented writes, brightness owned by the framework that exists for it.

## What found it

The question *"why are we maxing brightness? Shouldn't it remember the
brightness that was set?"* — from the owner, not from the analysis. The
follow-up *"is that upstream, the brightness max deal?"* established it
was our own driver rather than an in-tree one, which made the vendor
DTSI and the `sw43408` sibling available as references.

Both are questions about **what the code is trying to do**, asked while
the investigation was busy tuning a number. The measurement discipline
that had worked elsewhere in this project — compare against the vendor,
compare against the in-tree sibling, read the device state directly — was
available the whole time and simply had not been pointed here.

## Reusable checks

- The panel's own sequence is in
  `android_kernel_lge_msm8998/arch/arm64/boot/dts/lge/dsi-panel-sw43402-dsc-qhd-cmd-dv3_1.dtsi`.
  Command format is `<type> 01 00 00 <wait_ms> 00 <len> <payload>`, so the
  post-command delay is byte 5 — that is how the "0 ms after display-on"
  above was read.
- `panel-lg-sw43408.c` is the in-tree sibling. When our driver and it
  disagree about *structure* (as opposed to panel-specific data), assume
  we are wrong until shown otherwise.
- Brightness behaviour is observable without eyes:
  `/sys/class/backlight/c994000.dsi.0/{brightness,bl_power}`. Sample it
  across a lock/wake cycle; `bl_power` toggles 0/4 while `brightness`
  should not move. Sample faster than 3 s — at 3 s the aliasing missed
  most of an 8-cycle run.

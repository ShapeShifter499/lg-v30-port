# 2026-09-26 — Venus hardware video codec: still wedges on joan

Why it matters: without Venus every video decodes on the CPU (choppy YouTube;
LineageOS decodes in hardware).

Imported porthole-dev's msm8998 Venus series (0178, 0181, 0183-0199, 0203,
0207, 0209, 0212, 0233 — 24 patches, applied in order on branch
`joan/venus-wip`, with Link trailers). 0178 adapted to this tree's
interconnect IDs. On the Pixel 2 XL this series reaches bit-exact decode and
VP9 1080p60 in a browser. joan's Venus firmware is packaged
(`qcom/msm8998/joan/venus.mdt`, firmware-lge-joan r9).

Bench (bl16, module blacklisted, loaded by hand, netconsole to nest):

| Load | Result |
|---|---|
| `modprobe venus_core` | SoC wedged; last netconsole line is the marker before the load; watchdog reset |
| `modprobe venus_core stop_at=5` (clocks, IRQ, runtime PM, bus votes) | survives |
| `rmmod venus_core` after the stopped probe | userspace hangs (ping answers, sshd does not); needs a manual reset |

Next: bisect stop_at 5..10 with a reboot between rounds (never rmmod a
half-probed venus_core), then porthole's finer knobs (clk_limit, boot_stage,
preset_limit) inside the failing stage. Compare the result with porthole's
taimen findings (their wedge was the first VBIF preset write before firmware
boot).

#!/usr/bin/env python3
"""Derive opp-microwatt values for the MSM8998 CPU OPP tables from the
sched-energy-costs that Qualcomm's msm-4.4 msm8998.dtsi carries (as shipped
in LG's V30 kernel, android_kernel_lge_msm8998).

Stock busy-cost-data rows are <capacity cost>. Capacity is linear in
frequency within a cluster (checked below): silver 419 == 1900.8 MHz,
gold 1024 == 2361.6 MHz. The cost is per-core active power; it is treated
as mW (gold ~1.7 W/core at 2.36 GHz, silver ~0.2 W at 1.9 GHz). Shared
cluster costs (CLUSTER_COST_*) have no place in the per-CPU energy model and
are left out, as is usual when converting these tables.

Our power for each mainline OPP is linearly interpolated in frequency. The
gold 2457.6 MHz single-core boost row runs at the 2361.6 MHz voltage corner,
so its power scales with frequency alone (P ~ C*V^2*f at fixed V).
"""
import sys

CPU_COST_0 = [(65, 11), (80, 20), (96, 25), (113, 30), (130, 33), (147, 35),
    (164, 36), (181, 42), (194, 47), (211, 54), (228, 62), (243, 67),
    (258, 73), (275, 79), (292, 88), (308, 95), (326, 104), (342, 111),
    (368, 134), (384, 155), (401, 178), (419, 201)]
CPU_COST_1 = [(129, 56), (148, 76), (182, 91), (216, 105), (247, 118),
    (278, 135), (312, 150), (344, 162), (391, 181), (419, 196), (453, 214),
    (487, 229), (509, 248), (546, 280), (581, 316), (615, 354), (650, 392),
    (676, 439), (712, 495), (739, 565), (776, 622), (803, 691), (834, 792),
    (881, 889), (914, 1059), (957, 1244), (975, 1375), (996, 1549),
    (1016, 1617), (1021, 1677), (1024, 1683)]

SILVER_KHZ = [300000, 364800, 441600, 518400, 595200, 672000, 748800, 825600,
    883200, 960000, 1036800, 1094400, 1171200, 1248000, 1324800, 1401600,
    1478400, 1555200, 1670400, 1747200, 1824000, 1900800]
GOLD_KHZ = [300000, 345600, 422400, 499200, 576000, 652800, 729600, 806400,
    902400, 979200, 1056000, 1132800, 1190400, 1267200, 1344000, 1420800,
    1497600, 1574400, 1651200, 1728000, 1804800, 1881600, 1958400, 2035200,
    2112000, 2208000, 2265600, 2323200, 2342400, 2361600, 2457600]


def curve(costs, fmax_khz):
    cmax = costs[-1][0]
    return [(c * fmax_khz / cmax, p) for c, p in costs]


def interp(pts, f):
    if f <= pts[0][0]:
        (f0, p0), (f1, p1) = pts[0], pts[1]
    elif f >= pts[-1][0]:
        (f0, p0), (f1, p1) = pts[-2], pts[-1]
    else:
        for (f0, p0), (f1, p1) in zip(pts, pts[1:]):
            if f0 <= f <= f1:
                break
    return p0 + (p1 - p0) * (f - f0) / (f1 - f0)


def table(name, costs, fmax, opps, boost_khz=None):
    pts = curve(costs, fmax)
    out = []
    for f in opps:
        if boost_khz and f == boost_khz:
            mw = interp(pts, fmax) * f / fmax
        else:
            mw = interp(pts, min(f, fmax))
        out.append((f, round(mw * 1000)))
    # sanity: nearest stock point within 6% of every OPP below fmax
    worst = max(min(abs(sf - f) / f for sf, _ in pts) for f in opps if f <= fmax)
    print(f"# {name}: fmax {fmax} kHz, worst OPP-to-stock-point gap {worst:.1%}",
          file=sys.stderr)
    return out


if __name__ == "__main__":
    for name, rows in (("silver", table("silver", CPU_COST_0, 1900800, SILVER_KHZ)),
                       ("gold", table("gold", CPU_COST_1, 2361600, GOLD_KHZ, 2457600))):
        prev = 0
        for f, uw in rows:
            assert uw > prev, f"{name}: power not increasing at {f}"
            prev = uw
            print(f"{name} {f * 1000} {uw}")

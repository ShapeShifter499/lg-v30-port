#!/bin/sh
# Untouched OSM + L2 SAW state (boot with the OSM and SPM initcalls blacklisted).
R=/home/user/regdump
echo "== cmdline: $(cat /proc/cmdline)"
echo "== cpufreq: $(ls /sys/devices/system/cpu/cpufreq 2>&1 | tr '\n' ' ')"
for fd in 179c1 179c3; do echo "== freq-domain ${fd}000 0x000-0x0fc"; $R ${fd}000 64; echo "== ${fd}b00"; $R ${fd}b00 4; done
for od in 179c0 179c2; do echo "== osm-domain ${od}000"; $R ${od}000 32; done
for b in 17812 17912; do echo "== SAW ${b}000"; $R ${b}000 16; $R ${b}900 4; $R ${b}c00 8; done

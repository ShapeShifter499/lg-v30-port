#!/bin/sh
# Dump both MSM8998 L2 SAWv4.1 blocks: SPM_CTL..0x3c, VCTL/AVS 0x900-0x90c, status 0xc00-0xc1c, version.
R=${R:-/home/user/regdump}
for b in 17812 17912; do
	echo "== ${b}000"
	$R ${b}000 16; $R ${b}900 4; $R ${b}c00 8; $R ${b}fd0 1
done

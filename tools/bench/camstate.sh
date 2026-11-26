#!/bin/sh
# snapshot of camera-related clock/genpd/regulator/rpm state (for leak diffs)
C=/sys/kernel/debug/clk
for c in $C/*; do
	n=$(basename $c); case "$n" in *camss*|*cci*|*mclk*|*csi*|*vfe*|*ispif*|*mmss*|*mnoc*|*ahb_clk_src*|*axi_clk_src*) ;; *) continue ;; esac
	[ -f $c/clk_enable_count ] || continue
	echo "clk $n en=$(cat $c/clk_enable_count) prep=$(cat $c/clk_prepare_count) rate=$(cat $c/clk_rate)"
done
grep -E 'camss|cci|vfe|mmss|bimc_smmu' /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | awk '{print "genpd", $0}'
grep -E 'lvs1|cam0|l2 |l1 |5-0010|5-0029|ca00020|ca0c000' /sys/kernel/debug/regulator/regulator_summary | awk '{print "reg", $1, $2, $3}'
for d in /sys/bus/i2c/devices/5-0010 /sys/devices/platform/soc@0/ca0c000.cci /sys/devices/platform/soc@0/ca00020.camss; do
	echo "rpm $(basename $d) $(cat $d/power/runtime_status) usage=$(cat $d/power/runtime_usage 2>/dev/null) active_ms=$(cat $d/power/runtime_active_time)"
done
grep -E 'camss|cci' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; print "irq", $NF, s}'

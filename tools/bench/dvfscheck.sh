#!/bin/sh
# DVFS verification for the joan OSM/CPRh bring-up. Run as root on the phone.
# For each cluster: pin a few OPPs, measure the real core clock, read back
# cpufreq's view and the CPRh thread's live voltage. Then a short all-core
# load at max with temperatures and cooling state.
M=/home/user/cpumhz2
CPR=/sys/kernel/debug/qcom_cpr3
cd /sys/devices/system/cpu/cpufreq || { echo "no cpufreq"; exit 1; }

for p in policy*; do
	echo "== $p cpus=$(cat $p/related_cpus) drv=$(cat $p/scaling_driver) gov=$(cat $p/scaling_governor)"
	echo "   avail: $(cat $p/scaling_available_frequencies)"
	echo "   hw range: $(cat $p/cpuinfo_min_freq)..$(cat $p/cpuinfo_max_freq) kHz"
done

pin() { # policy freq
	echo "$2" > "$1/scaling_max_freq" 2>/dev/null
	echo "$2" > "$1/scaling_min_freq" 2>/dev/null
	echo "$2" > "$1/scaling_max_freq" 2>/dev/null
}

sweep() { # policy cpu thread freqs...
	p=$1 c=$2 t=$3; shift 3
	for f in "$@"; do
		pin "$p" "$f"
		r=$($M "$c" 0.7)
		v=$(grep -m1 "current_volt" "$CPR/thread$t" 2>/dev/null | awk '{print $3}')
		echo "   req $f -> cpufreq $(cat $p/scaling_cur_freq) kHz, measured ${r#* }, cprh ${v:-?} uV"
	done
	pin "$p" "$(cat $p/cpuinfo_min_freq)"
	echo "$(cat $p/cpuinfo_max_freq)" > "$p/scaling_max_freq"
}

echo "== silver sweep"
sweep policy0 0 0 300000 595200 1036800 1555200 1900800
echo "== gold sweep"
sweep policy4 4 1 300000 1056000 1728000 2208000 2361600

echo "== all-core load at max, 20 s"
for p in policy*; do echo "$(cat $p/cpuinfo_max_freq)" > "$p/scaling_max_freq"; echo "$(cat $p/cpuinfo_max_freq)" > "$p/scaling_min_freq"; done
i=0; while [ $i -lt 8 ]; do ( $M $i 20 >/tmp/load$i.out ) & i=$((i+1)); done
sleep 10
echo "   t=10s temps: $(for z in /sys/class/thermal/thermal_zone*; do case $(cat $z/type) in cpu*) printf '%s=%s ' "$(cat $z/type)" "$(( $(cat $z/temp) / 1000 ))";; esac; done)"
echo "   cooling: $(for c in /sys/class/thermal/cooling_device*; do printf '%s=%s ' "$(cat $c/type)" "$(cat $c/cur_state)"; done)"
wait
echo "   per-core: $(cat /tmp/load*.out | tr '\n' ' ')"
for p in policy*; do echo "$(cat $p/cpuinfo_min_freq)" > "$p/scaling_min_freq"; done
echo "   after: temps $(for z in /sys/class/thermal/thermal_zone*; do case $(cat $z/type) in cpu*) printf '%s ' "$(( $(cat $z/temp) / 1000 ))";; esac; done)"

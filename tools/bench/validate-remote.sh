# Runs ON the phone (copied there by validate.sh); expects JOAN_PW in the environment.
echo '== rmem'; for n in /proc/device-tree/reserved-memory/*/; do b=$(basename $n); [ -f $n/reg ] && echo "$b $(hexdump -ve '1/1 "%.2x"' $n/reg)"; done
echo '== remoteproc'; for r in /sys/class/remoteproc/*; do echo $(cat $r/name) $(cat $r/state); done
echo '== wifi'; nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev; ping -c3 -W2 -I wlan0 1.1.1.1 2>&1 | tail -1
echo '== cellular'; mmcli -m any 2>/dev/null | grep -E ' state|access tech|signal quality' | head -4; ip -br addr show qmapmux0.0; ping -6 -c3 -W3 -I qmapmux0.0 2001:4860:4860::8888 2>&1 | tail -1
echo '== gpu'; cat /sys/class/devfreq/*gpu*/cur_freq; ps -eo comm | grep -m1 -x phosh
echo '== cpu'; ls /sys/devices/system/cpu/cpufreq/; for c in /sys/class/thermal/cooling_device*; do printf '%s ' $(cat $c/type); done; echo
echo '== audio'; XDG_RUNTIME_DIR=/run/user/10000 wpctl status 2>&1 | sed -n '/Sinks:/,/Sources:/p' | head -4
echo '== dmesg'; echo "$JOAN_PW" | sudo -S -p '' dmesg

#!/usr/bin/env bash
# Read LG V30 (joan) IMEM reset-reason cookies from the RUNNING LineageOS
# (downstream 4.4) over adb. Read-only: no writes, no flash. Run this AFTER
# a mainline oracle boot round has crash-reset back into LineageOS.
#
# Pairs with the joan/imem-oracle kernel branch (out/boot-joan-imem-oracle.img).
# Needs: adb, passwordless host sudo for adb, and root on the phone.
#
# IMEM layout (from downstream lge_handle_panic + msm8998.dtsi imem node):
#   0x146bf65c  restart_reason  — reset CAUSE the boot chain recorded
#   0x146bf640  scratch         — 0x4a4f414e "JOAN" if our initcall ran
#   0x146bf04c  crash_magic     — 0x4c474500 if boot-chain cookie present
#
# Exit codes:
#   0  diagnostic completed (including a clearly reported blocked IMEM read)
#   2  host passwordless sudo unavailable
#   3  device reachable but neither adbd nor su provides root
#   4  no authorized adb device visible
set -u

ADB="${ADB:-adb}"
SUDO="${SUDO:-sudo}"

host_adb() {
    "$SUDO" -n "$ADB" "$@"
}

fail() {
    printf '%s\n' "$*" >&2
}

if ! "$SUDO" -n true >/dev/null 2>&1; then
    fail "HOST ERROR: passwordless sudo is unavailable."
    fail "The phone root state was not tested."
    exit 2
fi

if ! device_list=$(host_adb devices 2>&1); then
    fail "HOST ERROR: adb could not be executed through passwordless sudo."
    fail "$device_list"
    exit 2
fi

if ! printf '%s\n' "$device_list" | grep -q $'\tdevice$'; then
    fail "DEVICE ERROR: no authorized adb device is visible."
    exit 4
fi

root_mode=
id_line=$(host_adb shell id 2>&1 || true)
if [[ $id_line == *"uid=0(root)"* ]]; then
    root_mode=adb-root
    root_description="adb daemon already runs as uid 0"
else
    su_id_line=$(host_adb shell "su -c id" 2>&1 || true)
    if [[ $su_id_line == *"uid=0(root)"* ]]; then
        root_mode=su-root
        root_description="su provides uid 0"
    else
        printf '== device ==\n%s\n' "$device_list"
        fail "DEVICE ERROR: neither adb root nor su root is available."
        fail "adb shell id: ${id_line:-<no output>}"
        fail "su -c id: ${su_id_line:-<no output>}"
        exit 3
    fi
fi

run_root() {
    local command=$1
    if [[ $root_mode == adb-root ]]; then
        host_adb shell "$command"
    else
        host_adb shell "su -c '$command'"
    fi
}

read_cookie() {
    local addr=$1 output first_error

    if output=$(run_root "busybox devmem $addr 32" 2>&1); then
        printf '%s' "$output"
        return 0
    fi
    first_error=$output

    if output=$(run_root "devmem $addr 32" 2>&1); then
        printf '%s' "$output"
        return 0
    fi

    printf '%s; %s' "${first_error:-busybox devmem failed without output}" \
        "${output:-devmem failed without output}"
    return 1
}

printf '== device ==\n%s\n' "$device_list"
printf 'root mode: %s\n' "$root_description"
printf '== IMEM cookies (root verified) ==\n'

read_failures=0
read_errors=()
for pair in "restart_reason:0x146bf65c" "sentinel_JOAN:0x146bf640" "crash_magic:0x146bf04c"; do
    name=${pair%%:*}
    addr=${pair##*:}
    if val=$(read_cookie "$addr"); then
        printf '  %-16s %s = %s\n' "$name" "$addr" "$val"
    else
        printf '  %-16s %s = <unreadable>\n' "$name" "$addr"
        read_errors+=("$name: $val")
        read_failures=$((read_failures + 1))
    fi
done

if (( read_failures > 0 )); then
    fail "DEVICE READ ERROR: root is available, but IMEM could not be read."
    for error in "${read_errors[@]}"; do
        fail "  $error"
    done
    fail "On the current LineageOS kernel this is expected when CONFIG_DEVMEM=n."
    fail "No reset-reason inference was made from IMEM."
fi

printf '== decode restart_reason ==\n'
cat <<'TABLE'
  0x6d630300  LGE_ERR_TZ (generic TZ / our written default)
  0x6d63033a  TZ non-secure watchdog BARK   <-- watchdog culprit
  0x6d63033b  TZ thermal secure BITE        <-- thermal culprit
  0x6d630301  kernel
  0x6d630201  RPM
  0x6d630400  hyp
  0x6d630500  LAF
  (0x6d63xxxx with LGE_SUB_* nibble = subsystem crash; see lge_handle_panic.h)
  If reason == 0x6d630300 exactly, either nothing overwrote our default
  (reset came from a path that does NOT record an LGE reason -> suspect a
  raw PMIC/PON or PS_HOLD reset), or the reset beat our initcall.
  If sentinel != 0x4a4f414e, our early_initcall did NOT run before reset
  -> reset is earlier than early_initcall; move the probe earlier.
TABLE

printf '== also useful: last bootreason from LG props / cmdline ==\n'
run_root "getprop | grep -iE 'boot.*reason|lge.*boot'" 2>/dev/null || true
run_root "cat /proc/cmdline" 2>/dev/null | tr ' ' '\n' | grep -iE 'reason|reboot|warmboot' || true

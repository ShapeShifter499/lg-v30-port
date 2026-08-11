#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/scripts/read-imem-reset-reason.sh"
FIXTURES="$ROOT/tests/fixtures/read-imem"
failures=0

run_case() {
    local scenario=$1 expected_rc=$2
    shift 2
    local output rc=0 needle
    output=$(MOCK_SCENARIO="$scenario" SUDO="$FIXTURES/mock-sudo" ADB="$FIXTURES/mock-adb" bash "$SCRIPT" 2>&1) || rc=$?
    if [[ $rc -ne $expected_rc ]]; then
        printf 'not ok - %s exit: got %d, expected %d\n%s\n' "$scenario" "$rc" "$expected_rc" "$output"
        failures=$((failures + 1))
        return
    fi
    for needle in "$@"; do
        if [[ $output != *"$needle"* ]]; then
            printf 'not ok - %s missing: %s\n%s\n' "$scenario" "$needle" "$output"
            failures=$((failures + 1))
            return
        fi
    done
    printf 'ok - %s\n' "$scenario"
}

run_case host-sudo-denied 2 \
    'HOST ERROR: passwordless sudo is unavailable' \
    'The phone root state was not tested.'
run_case unrooted 3 \
    'DEVICE ERROR: neither adb root nor su root is available' \
    'uid=2000(shell)'
run_case devmem-unavailable 0 \
    'DEVICE READ ERROR: root is available, but IMEM could not be read' \
    'devmem: No such device or address'
run_case rooted-success 0 \
    'root mode: adb daemon already runs as uid 0' \
    'restart_reason   0x146bf65c = 0x6d63033a' \
    'sentinel_JOAN    0x146bf640 = 0x4a4f414e'

if (( failures > 0 )); then
    printf '%d test case(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'all read-imem-reset-reason tests passed\n'

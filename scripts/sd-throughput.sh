#!/usr/bin/env bash
# SD card throughput + bus-mode benchmark for joan.
#
# Answers the question left open on 2026-08-07: is the SD card actually
# slow, and therefore is wiring sdhc interconnect paths (task #11) worth
# the port of the a1noc/a2noc fabrics it would require?
#
# READ-ONLY by design. It dd's FROM the raw device to /dev/null with
# iflag=direct. It never writes to the card, never touches the rootfs
# filesystem, and is bounded to 256 MiB.
#
# Two things get measured, and both matter:
#   1. negotiated bus mode/clock - if the SDR104 tuning failure
#      (mmc0: tuning execution failed: -5) made it fall back, that caps
#      throughput for reasons interconnect wiring cannot fix
#   2. actual sequential read throughput
#
# Needs the RAM-booted pmOS reachable over the USB gadget and the test
# user's sudo password in PASS_FILE (never commit it). Output lands in
# OUTDIR (default out/sd-bench under the repo).
#
#   DEV_IP  default 172.16.42.1     KEY  ssh identity (optional)
#   PASS_FILE default /tmp/pmos-pass SIZE_MB default 256
set -uo pipefail

DEV_IP="${DEV_IP:-172.16.42.1}"
KEY="${KEY:-}"
PASS_FILE="${PASS_FILE:-/tmp/pmos-pass}"
OUTDIR="${OUTDIR:-$(cd "$(dirname "$0")/.." && pwd)/out/sd-bench}"
SIZE_MB="${SIZE_MB:-256}"

mkdir -p "$OUTDIR"
[[ -r "$PASS_FILE" ]] || { echo "PASS_FILE_MISSING"; exit 12; }

read -r -d '' REMOTE <<REMOTE_EOF
set -u
SIZE_MB=$SIZE_MB

echo "=== CARD IDENTITY ==="
for f in name type oemid manfid; do
    v=\$(cat /sys/class/mmc_host/mmc0/mmc0:*/\$f 2>/dev/null | head -1)
    [ -n "\$v" ] && echo "  \$f=\$v"
done

echo "=== NEGOTIATED BUS MODE (the ceiling that ICC cannot lift) ==="
if [ -r /sys/kernel/debug/mmc0/ios ]; then
    cat /sys/kernel/debug/mmc0/ios
else
    echo "  ios unreadable"
fi
echo "-- reference: SDR104 up to 104, SDR50 50, DDR50 50, high-speed 25 (MByte per sec) --"

echo "=== TUNING ERRORS THIS BOOT ==="
n=\$(dmesg | grep -c "tuning execution failed")
echo "  tuning_failures=\$n"
dmesg | grep -iE "mmc0|mmcblk0" | grep -iE "tuning|error|fail|timeout" | tail -5

echo "=== SEQUENTIAL READ, \${SIZE_MB} MiB, O_DIRECT, READ-ONLY ==="
# skip the first 8 MiB so we are past partition metadata
dd if=/dev/mmcblk0 of=/dev/null bs=1M skip=8 count=\$SIZE_MB iflag=direct 2>&1 | tail -3

echo "=== SANITY: card still healthy after the read ==="
dmesg | grep -iE "mmc0|mmcblk0" | grep -iE "error|fail|timeout" | tail -3 || echo "  no new errors"
echo "SD_BENCH_DONE"
REMOTE_EOF

ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=15 ${KEY:+-i "$KEY"} "user@$DEV_IP" \
    "sudo -k -p 'PW: ' sh -c $(printf '%q' "$REMOTE")" \
    < "$PASS_FILE" > "$OUTDIR/sd-bench.log" 2>&1
rc=$?
# Literal (not regex) replacement: a password containing / or . must not
# break or partially survive the redaction.
python3 - "$OUTDIR/sd-bench.log" "$PASS_FILE" <<'PY'
import re, sys
log, pw = sys.argv[1], open(sys.argv[2]).read().strip()
s = open(log, errors="replace").read()
s = re.sub(r"(?m)^PW: .*", "[redacted]", s)
if pw:
    s = s.replace(pw, "[REDACTED]")
open(log, "w").write(s)
PY

grep -q SD_BENCH_DONE "$OUTDIR/sd-bench.log" || {
    echo "CLASSIFICATION=SD_BENCH_INCOMPLETE (rc=$rc)"; tail -15 "$OUTDIR/sd-bench.log"; exit 13; }

sed -n '/=== CARD IDENTITY/,$p' "$OUTDIR/sd-bench.log" | tr -d '\r' | grep -avE '^\s*$'

echo
echo "============ INTERPRETATION ============"
# Parse ONLY dd's own output line. An earlier version grepped the whole
# log and matched the reference text "~104 MB/s", reporting the expected
# figure as if it were the measurement - the exact opposite of the truth.
MBS=$(grep -E 'bytes .* copied' "$OUTDIR/sd-bench.log" | tail -1 | grep -oE '[0-9.]+ ?MB/s' | grep -oE '[0-9.]+')
TIMING=$(grep -i "timing spec" "$OUTDIR/sd-bench.log" | tail -1)
echo "  measured: ${MBS:-?} MB/s"
echo "  ${TIMING:-timing: unknown}"
echo "  If the mode is SDR104 and throughput is well under ~80 MB/s, a bus"
echo "  bandwidth vote (task #11) may be worth the a1noc/a2noc port."
echo "  If it fell back to SDR50 or slower, the limit is TUNING, not"
echo "  bandwidth - interconnect wiring would not help. Fix tuning first."
echo "========================================"

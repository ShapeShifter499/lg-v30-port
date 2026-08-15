#!/usr/bin/env bash
# tether-throughput-harness.sh — reproducible local WLAN throughput measurement
# for LG V30 (joan) AP-mode tethering.
#
# Run from lg-v30-port root. The harness assumes:
#   - joan is reachable as $JOAN_HOST via SSH with the proper key;
#   - a Wi-Fi client (default nym-fang-family) is associated to joan's AP;
#   - iperf3 is installed on both endpoints;
#   - hostapd is already running on joan with $AP_IFACE up and $AP_SUBNET routed.
#
# It does NOT configure hostapd or NAT; use the existing bringup scripts for
# that. It only measures.
#
# Safety: no phone partition writes. All capture is local.

set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
STAMP="${STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_NAME="${RUN_NAME:-TETHER-$STAMP}"
OUTDIR="$HERE/out/audit-${STAMP:0:8}/$RUN_NAME"
mkdir -p "$OUTDIR"

JOAN_HOST="${JOAN_HOST:-joan}"                 # jump host for SSH
JOAN_USER="${JOAN_USER:-root}"
AP_IFACE="${AP_IFACE:-wlan0}"
AP_IP="${AP_IP:-10.42.0.1}"
AP_SUBNET="${AP_SUBNET:-10.42.0.0/24}"
CLIENT_HOST="${CLIENT_HOST:-nym-fang-family}"
CLIENT_IFACE="${CLIENT_IFACE:-wlan0}"
DURATION="${DURATION:-20}"
PARALLEL="${PARALLEL:-4}"
REVERSE="${REVERSE:-0}"       # set to 1 for client->AP (joan RX)
WARMUP="${WARMUP:-2}"

log() { echo "[$(date -u +%H:%M:%SZ)] $*" | tee -a "$OUTDIR/harness.log"; }

log "=== TETHER THROUGHPUT HARNESS: $RUN_NAME ==="
log "joan jump host: $JOAN_USER@$JOAN_HOST"
log "client: $CLIENT_HOST ($CLIENT_IFACE)"
log "AP: $AP_IFACE @ $AP_IP subnet $AP_SUBNET"
log "duration=${DURATION}s parallel=$PARALLEL reverse=$REVERSE"

# Save provenance before the run
cat > "$OUTDIR/provenance.json" <<EOF
{
  "run_name": "$RUN_NAME",
  "timestamp": "$STAMP",
  "joan_host": "$JOAN_HOST",
  "joan_user": "$JOAN_USER",
  "ap_iface": "$AP_IFACE",
  "ap_ip": "$AP_IP",
  "ap_subnet": "$AP_SUBNET",
  "client_host": "$CLIENT_HOST",
  "client_iface": "$CLIENT_IFACE",
  "duration_seconds": $DURATION,
  "parallel_streams": $PARALLEL,
  "reverse": $REVERSE
}
EOF

# Helpers
run_on_joan() { ssh "$JOAN_USER@$JOAN_HOST" "$@"; }
run_on_client() { ssh "$CLIENT_HOST" "$@"; }

# 1. Preconditions: AP interface and hostapd are up.
log "--- preconditions ---"
run_on_joan "ip -brief addr show $AP_IFACE" | tee "$OUTDIR/joan_iface.txt"
run_on_joan "cat /sys/class/net/$AP_IFACE/operstate" > "$OUTDIR/joan_operstate.txt"
run_on_joan "command -v hostapd && pgrep -a hostapd" > "$OUTDIR/joan_hostapd.txt" || true
run_on_joan "command -v iperf3" > "$OUTDIR/joan_iperf3.txt"
run_on_client "command -v iperf3" > "$OUTDIR/client_iperf3.txt"
run_on_client "ip -brief addr show $CLIENT_IFACE" | tee "$OUTDIR/client_iface.txt"
run_on_client "iw dev $CLIENT_IFACE station dump" | tee "$OUTDIR/client_station_dump.txt"

# 2. Start iperf3 server on joan AP IP.
log "--- starting iperf3 server on joan ($AP_IP:5201) ---"
run_on_joan "pkill -x iperf3 || true"
sleep 1
run_on_joan "nohup iperf3 -s -B $AP_IP -p 5201 </dev/null > /tmp/iperf3-joan.log 2>&1 &"
sleep 2
run_on_joan "ss -ltnp '( dport = :5201 or sport = :5201 )'" | tee "$OUTDIR/joan_iperf3_listen.txt" || true

# 3. Warmup: short 5-second run to prime firmware queues.
log "--- warmup ---"
run_on_client "iperf3 -c $AP_IP -p 5201 -t $WARMUP -P $PARALLEL $([[ $REVERSE == 1 ]] && echo '-R')" \
  | tee "$OUTDIR/warmup_iperf3.txt" || true

# 4. Main measurement.
log "--- main measurement ---"
run_on_client "iperf3 -c $AP_IP -p 5201 -t $DURATION -P $PARALLEL -J $([[ $REVERSE == 1 ]] && echo '-R')" \
  > "$OUTDIR/main_iperf3.json"
log "iperf3 JSON saved"

# 5. PHY snapshot during/after transfer.
log "--- PHY snapshot ---"
run_on_client "iw dev $CLIENT_IFACE station dump" | tee "$OUTDIR/client_station_dump_post.txt"
run_on_joan "iw dev $AP_IFACE station dump" | tee "$OUTDIR/joan_station_dump_post.txt" || true
run_on_joan "iw dev $AP_IFACE survey dump" | tee "$OUTDIR/joan_survey_dump.txt" || true

# 6. Stop server and fetch its log.
log "--- cleanup ---"
run_on_joan "pkill -x iperf3 || true"
run_on_joan "cat /tmp/iperf3-joan.log" | tee "$OUTDIR/joan_iperf3_server.log" || true

# 7. Summarize.
log "--- summary ---"
if command -v jq >/dev/null; then
  jq -r '[.start.timestamp.time, .end.sum_received.bits_per_second/1e6, .end.sum_sent.bits_per_second/1e6, .end.sum_received.retransmits] | @tsv' "$OUTDIR/main_iperf3.json" \
    | awk '{printf "time=%s receiver_Mbps=%.2f sender_Mbps=%.2f retransmits=%s\n", $1, $2, $3, $4}' \
    | tee -a "$OUTDIR/summary.txt"
else
  log "jq not available; raw JSON in $OUTDIR/main_iperf3.json"
fi

# 8. Seal.
sha256sum "$OUTDIR"/* > "$OUTDIR/SHA256SUMS"
log "artifacts in $OUTDIR"
log "run complete"

#!/usr/bin/env bash
# Read the raw LG V30 pstore partition from LineageOS without writing to the phone.
#
# Why: /sys/fs/pstore can be empty/misleading on joan, while the raw pstore
# block partition may still contain the previous mainline ramoops console,
# persistent-ftrace region, and bootloader reset log.
# Pull it immediately after a failed RAM-only mainline boot before LineageOS
# rotates/overwrites the region.
#
# Usage:
#   scripts/read-pstore-partition.sh [out-prefix]
#
# Output:
#   <out-prefix>.bin
#   <out-prefix>.strings.txt
#   <out-prefix>.meta.txt
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
PREFIX="${1:-$ROOT/out/pstore-partition-$STAMP}"
BIN="$PREFIX.bin"
TXT="$PREFIX.strings.txt"
META="$PREFIX.meta.txt"
PSTORE_DEV="/dev/block/platform/soc/1da4000.ufshc/by-name/pstore"

mkdir -p "$(dirname "$PREFIX")"

{
  echo "DATE: $(date)"
  echo "UTC: $STAMP"
  echo "ADB devices before root:"
  adb devices || true
  echo "PSTORE_DEV: $PSTORE_DEV"
} > "$META"

adb wait-for-device
adb root >> "$META" 2>&1 || true
adb wait-for-device

{
  echo "ADB devices after root:"
  adb devices || true
  echo "Device block entry:"
  adb shell "ls -l '$PSTORE_DEV' 2>/dev/null || true" || true
  echo "Device block size:"
  adb shell "blockdev --getsize64 '$PSTORE_DEV' 2>/dev/null || true" || true
  echo "START_DD: $(date)"
} >> "$META"

# Read the complete partition. Joan's pstore block device is larger than the
# 256 KiB console region: later regions may contain persistent ftrace and the
# bootloader reset log needed to classify a silent reset.
PSTORE_SIZE="$(adb shell "blockdev --getsize64 '$PSTORE_DEV'" | tr -d '\r')"
if [[ ! "$PSTORE_SIZE" =~ ^[0-9]+$ ]] || (( PSTORE_SIZE == 0 || PSTORE_SIZE > 16777216 )); then
  echo "invalid pstore size: $PSTORE_SIZE" >> "$META"
  exit 1
fi

adb exec-out "dd if='$PSTORE_DEV' bs=1048576 2>/dev/null" > "$BIN"
CAPTURE_SIZE="$(stat -c %s "$BIN")"
if [[ "$CAPTURE_SIZE" != "$PSTORE_SIZE" ]]; then
  printf 'short pstore read: expected=%s captured=%s\n' \
    "$PSTORE_SIZE" "$CAPTURE_SIZE" >> "$META"
  exit 1
fi
printf 'PSTORE_SIZE=%s\nCAPTURE_SIZE=%s\n' \
  "$PSTORE_SIZE" "$CAPTURE_SIZE" >> "$META"

python - "$BIN" "$TXT" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1])
dst=Path(sys.argv[2])
b=src.read_bytes()
text=''.join(chr(x) if x in (9,10,13) or 32 <= x < 127 else '\n' for x in b)
lines=[ln.rstrip('\r') for ln in text.splitlines() if ln.strip()]
dst.write_text('\n'.join(lines)+'\n')
print(f'bytes={len(b)} lines={len(lines)}')
PY

{
  echo "END: $(date)"
  echo "SHA256:"
  sha256sum "$BIN" "$TXT" "$META"
} >> "$META"

printf 'bin: %s\nstrings: %s\nmeta: %s\n' "$BIN" "$TXT" "$META"
sha256sum "$BIN" "$TXT" "$META"

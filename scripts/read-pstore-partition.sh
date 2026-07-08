#!/usr/bin/env bash
# Read the raw LG V30 pstore partition from LineageOS without writing to the phone.
#
# Why: /sys/fs/pstore can be empty/misleading on joan, while the raw pstore
# block partition may still contain the previous mainline ramoops console.
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
  echo "START_DD: $(date)"
} >> "$META"

# Read-only pull. bs/count intentionally capture the first 256 KiB quickly; this
# was enough to preserve the K042 mainline ramoops record in the 2026-07-08 run.
adb exec-out dd if="$PSTORE_DEV" bs=262144 count=1 2>>"$META" > "$BIN"

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

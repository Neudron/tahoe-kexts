#!/bin/bash
# Authoritative Gate-A check: let the real Tahoe linker resolve the leaked
# kexts without loading them (kextutil -no-load). Needs sudo (runners have it).
# Exit code is informational; full diagnostics land in <output-dir>/*.kextutil.txt.
# Usage: dry-link.sh <dir-with-TGL-kexts> <output-dir>
set -uo pipefail
SRC="$1"; OUT="$2"; mkdir -p "$OUT"
WORK=$(mktemp -d)
sudo cp -R "$SRC"/*.kext "$WORK/"
sudo chown -R root:wheel "$WORK"/*.kext
sudo chmod -R 755 "$WORK"/*.kext

for k in "$WORK"/*.kext; do
  n=$(basename "$k" .kext)
  echo "=== kextutil -no-load $n ==="
  sudo kextutil -no-load -print-diagnostics "$k" > "$OUT/$n.kextutil.txt" 2>&1
  echo "$n: exit=$?"
  # Surface link failures in the job log for quick reading
  grep -iE 'undefined|link|symbol' "$OUT/$n.kextutil.txt" | head -40 || true
done
exit 0

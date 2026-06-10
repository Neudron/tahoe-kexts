#!/bin/bash
# Authoritative Gate-A check: let the real Tahoe toolchain resolve the leaked
# kexts. kextutil on Tahoe is a kmutil shim and no longer supports -no-load,
# so we try the kmutil-era equivalents and capture everything for analysis.
# Exit code is informational; full diagnostics land in <output-dir>/.
# Usage: dry-link.sh <dir-with-TGL-kexts> <output-dir>
set -uo pipefail
SRC="$1"; OUT="$2"; mkdir -p "$OUT"
WORK=$(mktemp -d)
sudo cp -R "$SRC"/*.kext "$WORK/"
sudo chown -R root:wheel "$WORK"/*.kext
sudo chmod -R 755 "$WORK"/*.kext

# Tool capabilities snapshot (informs script fixes without guessing)
{ kextutil --help; echo ---; kmutil --help; echo ---; kmutil create --help; } \
  > "$OUT/tool-help.txt" 2>&1 || true

for k in "$WORK"/*.kext; do
  n=$(basename "$k" .kext)
  r="$OUT/$n.kextutil.txt"
  {
    echo "=== kextutil -print-diagnostics ==="
    sudo kextutil -print-diagnostics "$k" 2>&1
    echo "exit=$?"
    echo "=== kmutil check ==="
    sudo kmutil check "$k" 2>&1
    echo "exit=$?"
    echo "=== kmutil load -p (expected to fail at policy; link errors are the signal) ==="
    sudo kmutil load -p "$k" 2>&1
    echo "exit=$?"
  } > "$r"
  echo "--- $n ---"
  grep -iE 'undefined|symbol|link|error' "$r" | head -40 || true
done

# Strongest pre-load test: build a throwaway auxiliary kext collection that
# includes the leaked kexts — kmutil performs full link resolution to do this.
{
  echo "=== kmutil create aux KC dry test ==="
  sudo kmutil create --arch x86_64 --new aux \
    --boot-path /System/Library/KernelCollections/BootKernelExtensions.kc \
    --system-path /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --output /tmp/test-aux.kc \
    --repository "$WORK" 2>&1
  echo "exit=$?"
} > "$OUT/kmutil-create.txt"
grep -iE 'undefined|symbol|link|error' "$OUT/kmutil-create.txt" | head -60 || true
exit 0

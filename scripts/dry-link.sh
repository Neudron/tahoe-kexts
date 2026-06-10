#!/bin/bash
# Authoritative Gate-A check on a Tahoe runner: ask kmutil to build a throwaway
# auxiliary kext collection containing the leaked TGL kexts — that performs the
# exact dependency + link resolution `kmutil load` would do on the real machine.
# The leaked FB kext declares OSBundleLibraries deps on org.smichaud.HookCase,
# so dependency kexts must be supplied via extra dirs/paths.
# Exit code is informational; full diagnostics land in <output-dir>/.
# Usage: dry-link.sh <dir-with-TGL-kexts> <output-dir> [extra-kext-dir-or-.kext ...]
set -uo pipefail
SRC="$1"; OUT="$2"; shift 2
mkdir -p "$OUT"
WORK=$(mktemp -d)
cp -R "$SRC"/*.kext "$WORK/"
for d in "$@"; do
  if [[ "$d" == *.kext ]]; then
    cp -R "$d" "$WORK/"
  else
    find "$d" -name '*.kext' -not -name '*.dSYM' -maxdepth 4 -prune \
      -exec cp -R {} "$WORK/" \;
  fi
done
sudo chown -R root:wheel "$WORK"
sudo chmod -R 755 "$WORK"
ls -la "$WORK" | tee "$OUT/dry-link-workdir.txt"

# Per-kext dependency/link resolution (will stop at policy/signature on a SIP
# runner — the dependency and symbol errors before that are the signal)
for k in "$WORK"/AppleIntel*.kext; do
  n=$(basename "$k" .kext)
  r="$OUT/$n.kextutil.txt"
  {
    echo "=== kmutil load -p $n ==="
    sudo kmutil load -p "$k" --repository "$WORK" 2>&1 \
      || sudo kmutil load -p "$k" 2>&1
    echo "exit=$?"
  } > "$r"
  echo "--- $n ---"
  grep -iE 'undefined|symbol|link|error|unable' "$r" | head -20 || true
done

# Build a throwaway aux KC including everything in WORK (flags verified
# against Tahoe's `kmutil create --help`)
args=(create --arch x86_64 --new aux
  --boot-path /System/Library/KernelCollections/BootKernelExtensions.kc
  --auxiliary-path /tmp/test-aux.kc
  --no-system-collection --no-authentication --no-authorization
  --repository "$WORK")
for k in "$WORK"/*.kext; do args+=(--bundle-path "$k"); done
{
  echo "=== kmutil ${args[*]} ==="
  sudo kmutil "${args[@]}" 2>&1
  echo "exit=$?"
  ls -la /tmp/test-aux.kc 2>&1 || true
} > "$OUT/kmutil-create.txt"
grep -iE 'undefined|symbol|link|error|unable|success' "$OUT/kmutil-create.txt" | head -60 || true
exit 0

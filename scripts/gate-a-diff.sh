#!/bin/bash
# Gate A (PORT-ANALYSIS.md): diff the leaked TGL kexts' imports against the
# symbols this macOS actually exports. Run on a macos-26-intel (Tahoe) runner.
# Usage: gate-a-diff.sh <dir-with-TGL-kexts> <output-dir>
set -euo pipefail
KEXT_DIR="$1"; OUT="$2"; mkdir -p "$OUT"

# Resolve a kext bundle's Mach-O (handles both Contents/MacOS/ and flat layouts)
kext_binary() {
  local kext="$1" plist name
  plist="$kext/Contents/Info.plist"; [ -f "$plist" ] || plist="$kext/Info.plist"
  name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null) || return 1
  if [ -f "$kext/Contents/MacOS/$name" ]; then echo "$kext/Contents/MacOS/$name"
  elif [ -f "$kext/$name" ]; then echo "$kext/$name"
  else return 1; fi
}

echo "--- Building Tahoe export pool ($(sw_vers -productVersion)) ---"
nm -gU -arch x86_64 /System/Library/Kernels/kernel | awk '{print $NF}' > "$OUT/tahoe-exports.raw"
echo "kernel: $(wc -l < "$OUT/tahoe-exports.raw") symbols"

# Core families (IOGraphicsFamily, IOPCIFamily, IOAcceleratorFamily2...) ship
# only inside the kernel collections on modern macOS, not as on-disk binaries.
for kc in /System/Library/KernelCollections/*.kc; do
  [ -f "$kc" ] || continue
  before=$(wc -l < "$OUT/tahoe-exports.raw")
  nm -gU -arch x86_64 "$kc" 2>/dev/null | awk '{print $NF}' >> "$OUT/tahoe-exports.raw" || true
  echo "$kc: $(( $(wc -l < "$OUT/tahoe-exports.raw") - before )) symbols"
done

find /System/Library/Extensions -name '*.kext' | while read -r k; do
  b=$(kext_binary "$k") || continue
  nm -gU -arch x86_64 "$b" 2>/dev/null | awk '{print $NF}' || true
done >> "$OUT/tahoe-exports.raw"
sort -u "$OUT/tahoe-exports.raw" > "$OUT/tahoe-exports.txt"
rm "$OUT/tahoe-exports.raw"
echo "export pool total: $(wc -l < "$OUT/tahoe-exports.txt") unique symbols"

echo "--- Diffing TGL kext imports ---"
for k in "$KEXT_DIR"/*.kext; do
  n=$(basename "$k" .kext)
  b=$(kext_binary "$k")
  nm -u -arch x86_64 "$b" | awk '{print $NF}' | sort -u > "$OUT/$n.undef.txt"
  comm -23 "$OUT/$n.undef.txt" "$OUT/tahoe-exports.txt" > "$OUT/$n.blockers.txt"
  c++filt < "$OUT/$n.blockers.txt" > "$OUT/$n.blockers.demangled.txt"
  echo "$n: $(wc -l < "$OUT/$n.undef.txt") imports, $(wc -l < "$OUT/$n.blockers.txt") NOT exported by Tahoe (Gate-A blockers)"
done
# Report-only: blockers are the deliverable, not a CI failure.

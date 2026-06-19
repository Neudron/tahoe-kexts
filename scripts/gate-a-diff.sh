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
# Report-only: blockers are the deliverable, not a CI failure. Both TGL and ICL (fallback) kexts
# are processed if present in KEXT_DIR, so the two blocker counts can be compared side-by-side.

# Resolve a kext bundle's Info.plist (handles Contents/ and flat layouts).
kext_plist() {
  local kext="$1"
  [ -f "$kext/Contents/Info.plist" ] && { echo "$kext/Contents/Info.plist"; return; }
  [ -f "$kext/Info.plist" ] && { echo "$kext/Info.plist"; return; }
  return 1
}

echo "--- PCI-match audit (which device IDs each kext natively matches) ---"
# Proves the spoof is genuinely required: the leaked kexts match their own codename's id
# (TGL 0x9A49 / ICL 0x8A52) but NEVER a real Raptor Lake 0xA7xx id, which is why DeviceProperties
# must rewrite the iGPU's device-id. A future kext revision dropping the spoof-target id would
# silently break the bring-up even with clean symbols — this surfaces that.
for k in "$KEXT_DIR"/*.kext; do
  [ -d "$k" ] || continue
  n=$(basename "$k" .kext)
  p=$(kext_plist "$k") || { echo "$n: no Info.plist"; continue; }
  # IOPCIPrimaryMatch/IOPCIMatch values look like "0x9a498086 0x9a788086"; the low 16 bits are
  # the device id, the high 16 (0x8086) the Intel vendor id.
  grep -ioE 'IOPCI(Primary)?Match' "$p" >/dev/null || true
  /usr/libexec/PlistBuddy -c 'Print :IOKitPersonalities' "$p" 2>/dev/null \
    | grep -ioE '0x[0-9a-f]{4}8086' | sort -u \
    | sed -E 's/^0x([0-9a-f]{4})8086$/0x\1/I' > "$OUT/$n.pcimatch.txt" || true
  # Fallback for binary/compiled personalities: scan the Mach-O strings too.
  if [ ! -s "$OUT/$n.pcimatch.txt" ]; then
    b=$(kext_binary "$k") && strings "$b" 2>/dev/null \
      | grep -ioE '0x[0-9a-f]{4}8086' | sort -u \
      | sed -E 's/^0x([0-9a-f]{4})8086$/0x\1/I' > "$OUT/$n.pcimatch.txt" || true
  fi
  matched=$(tr '\n' ' ' < "$OUT/$n.pcimatch.txt")
  case "$n" in
    *TGL*) want=0x9a49 ;;
    *ICL*) want=0x8a52 ;;
    *)     want="" ;;
  esac
  note=""
  [ -n "$want" ] && { grep -iq "$want" "$OUT/$n.pcimatch.txt" \
      && note="spoof-target $want PRESENT" || note="WARNING spoof-target $want MISSING"; }
  grep -iqE '0xa7[0-9a-f]{2}' "$OUT/$n.pcimatch.txt" \
    && note="$note; WARNING native 0xA7xx matched (unexpected)" \
    || note="$note; no native 0xA7xx (expected)"
  echo "$n: matches [ ${matched}]; $note"
done

#!/bin/bash
# Authoritative Gate-A check on a Tahoe runner: ask kmutil to build a throwaway
# auxiliary kext collection containing the leaked TGL kexts — that performs the
# exact dependency + link resolution `kmutil load` would do on the real machine.
# The leaked kexts declare OSBundleLibraries deps on org.smichaud.HookCase, so
# dependency kexts must be supplied via extra dirs/paths. Everything is staged
# in /Library/Extensions because kmutil only resolves dependencies from there
# (mirrors the real install workflow from the NootedGreen README).
# kmutil create requires a KDK matching the running build (macOS 13+); it is
# fetched from the dortania/KdkSupportPkg mirror (needs GH_TOKEN).
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
sudo cp -R "$WORK"/*.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/*.kext
sudo chmod -R 755 /Library/Extensions/*.kext
ls -la /Library/Extensions/ | tee "$OUT/dry-link-workdir.txt"

# KDK matching this build — required by kmutil create since macOS 13
BUILD=$(sw_vers -buildVersion)
KDK_PATH=""
if gh release download "$BUILD" -R dortania/KdkSupportPkg -p '*.dmg' -O /tmp/kdk.dmg --clobber; then
  hdiutil attach /tmp/kdk.dmg -nobrowse -mountpoint /Volumes/KDK
  sudo installer -pkg /Volumes/KDK/KernelDebugKit.pkg -target /
  KDK_PATH=$(ls -d /Library/Developer/KDKs/*.kdk | head -1)
  echo "KDK installed: $KDK_PATH"
else
  echo "WARNING: no KDK for build $BUILD in dortania/KdkSupportPkg; kmutil create may fail"
fi

# Per-kext dependency/link resolution (stops at load policy on a SIP runner —
# the dependency and symbol errors before that are the signal)
for k in /Library/Extensions/AppleIntelTGL*.kext; do
  n=$(basename "$k" .kext)
  r="$OUT/$n.kextutil.txt"
  {
    echo "=== kmutil load -p $n ==="
    sudo kmutil load -p "$k" 2>&1
    echo "exit=$?"
  } > "$r"
  echo "--- $n ---"
  grep -iE 'undefined|symbol|link|error|unable' "$r" | head -20 || true
done

# Build a throwaway aux KC including everything we staged = full link resolution
args=(create --arch x86_64 --new aux
  --boot-path /System/Library/KernelCollections/BootKernelExtensions.kc
  --auxiliary-path /tmp/test-aux.kc
  --no-system-collection --no-authentication --no-authorization
  --explicit-only --repository /Library/Extensions)
[ -n "$KDK_PATH" ] && args+=(--kdk "$KDK_PATH")
for k in "$WORK"/*.kext; do
  args+=(--bundle-path "/Library/Extensions/$(basename "$k")")
done
{
  echo "=== kmutil ${args[*]} ==="
  sudo kmutil "${args[@]}" 2>&1
  echo "exit=$?"
  ls -la /tmp/test-aux.kc 2>&1 || true
} > "$OUT/kmutil-create.txt"
grep -iE 'undefined|symbol|link|error|unable' "$OUT/kmutil-create.txt" | head -60 || true
exit 0

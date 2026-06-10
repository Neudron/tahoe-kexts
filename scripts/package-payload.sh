#!/bin/bash
# Assemble the USB payload directory from job artifacts + the NootedGreen clone.
# Usage: package-payload.sh <artifacts-dir> <nootedgreen-clone-dir> <out-dir>
set -euo pipefail
ART="$1"; NG="$2"; OUT="$3"
mkdir -p "$OUT"
ABS_OUT=$(cd "$OUT" && pwd)

# 1. CI-built kexts (paths inside the artifact vary; find is robust)
find "$ART" -name 'NootedGreen-*-RELEASE.zip' -exec cp {} "$ABS_OUT/" \;
find "$ART" -name 'HookCase-RELEASE.zip'      -exec cp {} "$ABS_OUT/" \;

# 2. Leaked TGL kexts (same le/ layout as the existing USB TGL-kexts.zip)
#    plus the 5 GPU bundles + lep/ FB variant that were missing from the USB
(cd "$NG/sle_Internal" && zip -qry "$ABS_OUT/TGL-kexts.zip" le)
(cd "$NG/sle_Internal" && zip -qry "$ABS_OUT/TGL-bundles.zip" sle lep)

# 3. Gate-A reports
mkdir -p "$ABS_OUT/gate-a"
cp -R "$ART"/gate-a-reports/. "$ABS_OUT/gate-a/"

ls -laR "$ABS_OUT"

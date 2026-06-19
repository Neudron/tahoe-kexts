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

# 3. Gate-A reports (rpl-config-check.txt, *.pcimatch.txt, spoof-sanity.txt, kdk-missing.txt are
#    written into the reports/ dir by the gate-a job and ride along inside this artifact)
mkdir -p "$ABS_OUT/gate-a"
cp -R "$ART"/gate-a-reports/. "$ABS_OUT/gate-a/"

# 4. RPL->Tahoe install config + runbook (from this repo, checked out at the repo root)
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ABS_OUT/config"
cp -R "$REPO/config/." "$ABS_OUT/config/"
[ -f "$REPO/docs/INSTALL-V15G4.md" ]    && cp "$REPO/docs/INSTALL-V15G4.md"    "$ABS_OUT/"
[ -f "$REPO/docs/raptor-lake-tahoe.md" ] && cp "$REPO/docs/raptor-lake-tahoe.md" "$ABS_OUT/"

ls -laR "$ABS_OUT"

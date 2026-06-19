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

# 5. Compile SSDT-PLUG-ALT.aml (XCPM Device->Processor table for Alder/Raptor Lake multi-core)
sudo apt-get update -qq && sudo apt-get install -y -qq acpica-tools
mkdir -p "$ABS_OUT/acpi"
{
  printf 'DefinitionBlock ("", "SSDT", 2, "ACDT", "CpuPlugA", 0x00003000)\n{\n'
  printf '    External (_SB_, DeviceObj)\n    Scope (\\_SB)\n    {\n'
  for i in $(seq 0 63); do
    nm=$(printf 'CP%02d' "$i"); ad=$(printf '0x%02X' "$i")
    printf '        Processor (%s, %s, 0x00000510, 0x06)\n        {\n' "$nm" "$ad"
    printf '            Name (_HID, "ACPI0007")\n            Name (_UID, %s)\n' "$i"
    printf '            Method (_STA, 0, NotSerialized) { If (_OSI ("Darwin")) { Return (0x0F) } Else { Return (Zero) } }\n'
    if [ "$i" -eq 0 ]; then
      printf '            Method (_DSM, 4, NotSerialized) { If (LEqual (Arg2, Zero)) { Return (Buffer (One) { 0x03 }) } Return (Package (0x02) { "plugin-type", One }) }\n'
    fi
    printf '        }\n'
  done
  printf '    }\n}\n'
} > /tmp/SSDT-PLUG-ALT.dsl
iasl /tmp/SSDT-PLUG-ALT.dsl
cp /tmp/SSDT-PLUG-ALT.aml "$ABS_OUT/acpi/SSDT-PLUG-ALT.aml"
cp /tmp/SSDT-PLUG-ALT.aml "$ABS_OUT/SSDT-PLUG-ALT.aml"
ls -laR "$ABS_OUT"

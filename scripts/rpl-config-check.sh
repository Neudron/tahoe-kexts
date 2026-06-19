#!/bin/bash
# Pure-data consistency gate (no hardware, no network): proves the hand-edited OpenCore
# DeviceProperties fragment agrees with the single source of truth config/rpl-tgl-map.json.
# Endianness in the <data> values is the #1 hand-edit bug, so we decode and compare bytes.
# Unlike the symbol/link probes this CAN fail CI: it depends on nothing but the repo's own files.
# Usage: rpl-config-check.sh <output-dir> [map.json] [DeviceProperties.plist]
set -euo pipefail
OUT="$1"; mkdir -p "$OUT"
HERE=$(cd "$(dirname "$0")/.." && pwd)
MAP="${2:-$HERE/config/rpl-tgl-map.json}"
PLIST="${3:-$HERE/config/V15G4-DeviceProperties.plist}"
REPORT="$OUT/rpl-config-check.txt"

python3 - "$MAP" "$PLIST" <<'PY' | tee "$REPORT"
import json, plistlib, struct, sys, re

map_path, plist_path = sys.argv[1], sys.argv[2]
fails = []
def ok(msg):   print(f"PASS  {msg}")
def bad(msg):  print(f"FAIL  {msg}"); fails.append(msg)

with open(map_path) as f:
    m = json.load(f)
prim = m["primary"]
dev_id = int(prim["device_id"], 16)
ig_id  = int(prim["ig_platform_id"], 16)

with open(plist_path, "rb") as f:
    pl = plistlib.load(f)
# Single iGPU device entry, whatever the PciRoot key is named.
entry = next(iter(pl.values()))

def want_le(value, label, key):
    expect = struct.pack("<I", value)
    got = entry.get(key)
    if not isinstance(got, (bytes, bytearray)):
        bad(f"{key}: missing or not <data> in plist"); return
    if bytes(got) == expect:
        ok(f"{key} == {expect.hex(' ')} (little-endian {label})")
    else:
        bad(f"{key}: plist has {bytes(got).hex(' ')}, expected {expect.hex(' ')} for {label} {hex(value)}")

want_le(ig_id,  "ig-platform-id", "AAPL,ig-platform-id")
want_le(dev_id, "device-id",      "device-id")

# Spoof target must be Tiger Lake 0x9A49.
if dev_id == 0x9A49: ok("spoof target device_id is 0x9A49 (Tiger Lake)")
else: bad(f"spoof target device_id is {hex(dev_id)}, expected 0x9A49")

# Every real RPL id the driver must recognise should be a well-formed Gen12 0xA7xx id.
ids = m.get("rpl_device_ids", [])
if not ids: bad("rpl_device_ids is empty")
for d in ids:
    if re.fullmatch(r"0x[Aa]7[0-9A-Fa-f]{2}", d): ok(f"rpl device id {d} well-formed")
    else: bad(f"rpl device id {d} is not a 0xA7xx form")

print(f"\n{'PASS' if not fails else 'FAIL'}: {len(fails)} problem(s)")
sys.exit(1 if fails else 0)
PY

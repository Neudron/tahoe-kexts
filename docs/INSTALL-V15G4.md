# Installing Raptor Lake iGPU acceleration on the V15 G4 (macOS 26 Tahoe)

End-user runbook for bringing up the Raptor Lake (RPL-P/U **Iris Xe**) integrated GPU with graphics
acceleration on a Lenovo V15 G4-class board running **macOS 26 "Tahoe"**, by spoofing the iGPU to
Tiger Lake and driving it with NootedGreen + the leaked Apple Gen12 GPU kexts.

> Read [`docs/raptor-lake-tahoe.md`](raptor-lake-tahoe.md) first for how the spoof works and what the
> Gate-A reports mean. Everything here is data-driven from
> [`config/rpl-tgl-map.json`](../config/rpl-tgl-map.json).

## What's in the payload
- `NootedGreen-*-RELEASE.zip`, `HookCase-RELEASE.zip` — the CI-built kexts
- `TGL-kexts.zip` — leaked Tiger Lake kexts (`AppleIntelTGLGraphics` + `AppleIntelTGLGraphicsFramebuffer`)
- `TGL-bundles.zip` — TGL userspace driver bundles (Metal / GL / VA / shared)
- `config/` — `V15G4-DeviceProperties.plist`, `boot-args.txt`, `rpl-tgl-map.json`
  (and `V15G4-DeviceProperties.icl.plist` for the Ice Lake fallback)
- `gate-a/` — the validation reports (read these before flashing — see below)

## 1. EFI / OpenCore config
1. Merge `config/V15G4-DeviceProperties.plist` into your `config.plist` under
   **DeviceProperties → Add** (the `PciRoot(0x0)/Pci(0x2,0x0)` dict). It sets
   `AAPL,ig-platform-id = 0x9A490000` and fake `device-id = 0x9A49` (Tiger Lake).
2. Set **NVRAM → boot-args** to the line in `config/boot-args.txt`:
   `-ngreentglwithgfx -disablegfxfirmware`.
3. Make sure **Lilu**, **WhateverGreen** are loaded as usual, and set the NootedGreen scheduler
   property to host-preemptive type 5 (`ngreenSched=5`).

## 2. Kext install order
Install into `/Library/Extensions` (`/L/E`) in this order, then rebuild the kext cache:

```
Lilu  →  NootedGreen  →  HookCase  →  AppleIntelTGLGraphicsFramebuffer  →  AppleIntelTGLGraphics
```

Then drop the userspace bundles from `TGL-bundles.zip` into their `sle`/`lep` destinations.
Fix ownership/permissions exactly as the dry-link validation does:

```sh
sudo cp -R *.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/*.kext
sudo chmod -R 755 /Library/Extensions/*.kext
sudo kmutil install --update-all     # or: sudo kextcache -i /
```

## 3. First boot — what to expect
- The system should reach the **login screen** with the iGPU active.
- Verify:
  - `ioreg -l | grep -i AppleIntelTGL` — the accelerator/framebuffer attached
  - `system_profiler SPDisplaysDataType` — Metal reported as supported
- **Known open issue:** Metal/WindowServer compositing can stall (~215 ms after WindowServer becomes
  active). Mitigations already in the config are scheduler type 5 + `-disablegfxfirmware`. This is a
  NootedGreen runtime problem tracked upstream, not a config error.

## 4. Ice Lake fallback
If the Gate-A report shows **unfixable Tiger Lake symbol blockers** on your Tahoe build (see
`gate-a/*.blockers.txt` and [`docs/raptor-lake-tahoe.md`](raptor-lake-tahoe.md)):
1. Swap the DeviceProperties fragment to `config/V15G4-DeviceProperties.icl.plist`
   (`ig-platform-id = 0x8A520000`, `device-id = 0x8A52`).
2. Install the Ice Lake kexts (`AppleIntelICLGraphics` + `AppleIntelICLLPGraphicsFramebuffer`) and
   bundles instead of the TGL ones. Boot-args stay the same.

## 5. Recovery if it panics
Boot to another macOS / Recovery, remove the injected kexts, and rebuild the cache:

```sh
sudo rm -rf /Library/Extensions/AppleIntelTGL*.kext /Library/Extensions/NootedGreen.kext
sudo kmutil install --update-all
```

Or temporarily boot with the iGPU kexts disabled by removing the boot-args and the DeviceProperties
fragment from `config.plist`.

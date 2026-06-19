# Raptor Lake iGPU acceleration on macOS 26 Tahoe — bring-up & porting guide

How this repo validates, and how `Neudron/NootedGreen` must change, to get hardware graphics
acceleration on a Raptor Lake (RPL-P/U **Iris Xe**) iGPU under **macOS 26 "Tahoe"**.

## Why a spoof is required
macOS never shipped a driver for any **Gen12** Intel iGPU (Tiger Lake onward), so Raptor Lake has no
native path. Raptor Lake is **Gen12.2 Xe-LP**, a close cousin of Tiger Lake **Gen12.1**, so the
community approach is to **device-ID-spoof the RPL iGPU to Tiger Lake** (`device-id 0x9A49`,
`ig-platform-id 0x9A490000`) and inject Apple's leaked Gen12 GPU kexts, with **NootedGreen** (a Lilu
plugin) patching the MMIO / ForceWake / combo-PHY / scheduler deltas at runtime. All device IDs and
the spoof target live in [`config/rpl-tgl-map.json`](../config/rpl-tgl-map.json) — the single source
of truth every other artifact derives from.

The PCI-match audit in `scripts/gate-a-diff.sh` proves the necessity: the leaked kexts match their
own codename's id (TGL `0x9A49`) but **never** a real Raptor Lake `0xA7xx` id.

## The two risks
1. **Tahoe symbol drift** — the leaked TGL kexts were built against an older macOS; their undefined
   symbols may no longer be exported by Tahoe's kernel / kernel collections
   (`IOAcceleratorFamily2`, `IOGraphicsFamily`, `IOPCIFamily`). This is exactly what **Gate-A**
   measures. Make-or-break for the 14.7.1 → 26 jump.
2. **Metal / WindowServer stability** — a NootedGreen *runtime* problem (compositing stalls ~215 ms
   after WindowServer becomes active). Out of scope for this repo; tracked upstream.

## Gate-A → action decision tree
Read the reports from the `gate-a` CI job (artifact `gate-a-reports`):

| Report | Success | If not |
| --- | --- | --- |
| `rpl-config-check.txt` | `PASS` | Fix the DeviceProperties bytes (endianness) — CI-gating |
| `*.blockers.txt` / `.demangled.txt` | 0 lines | **Shim** the blockers (below) or **fall back to ICL** |
| `*.pcimatch.txt` | `0x9A49` matched, no `0xA7xx` | Investigate kext revision |
| `kmutil-create.txt` | `exit=0`, aux KC built | `kdk-missing.txt` present ⇒ KDK not mirrored yet (defer, not a failure); else fix dependency staging |
| `spoof-sanity.txt` | `9A49` present in FB kext | Spoof target dropped from kext — re-source it |

### When blockers are non-empty
For each demangled symbol in `*.blockers.txt`, map it to its owning family and shim it in NootedGreen
via Lilu `routeFunction` / a stub:

- `__ZN...IOAccelerator...` → `IOAcceleratorFamily2`
- `__ZN...IOFramebuffer / IODisplay...` → `IOGraphicsFamily`
- `__ZN...IOPCIDevice / IOPCIBridge...` → `IOPCIFamily`

### When to switch to the Ice Lake fallback
Ice Lake (Gen11) **was** shipped by Apple in real Macs, so `AppleIntelICLGraphics` /
`AppleIntelICLLPGraphicsFramebuffer` symbols are likelier to survive on Tahoe. Switch when the **TGL
blocker count is large/unfixable but the ICL blocker count is small**. ICL is a worse architectural
match (more patching, weaker acceleration). Mechanics: swap to
[`config/V15G4-DeviceProperties.icl.plist`](../config/V15G4-DeviceProperties.icl.plist)
(`0x8A52` / `0x8A520000`) and install the ICL kexts/bundles. NootedGreen already carries an ICL code
path.

## NootedGreen source changes (`Neudron/NootedGreen`, separate repo)
These are implemented in the driver repo, not here; this guide is the spec.

1. **RPL detection / spoof table.** Add the `0xA7xx` ids from `rpl-tgl-map.json` to the existing V52
   CPUID `isRealTGL` path so the kext recognises the *real* Raptor Lake iGPU before rewriting its PCI
   `device-id` → `0x9A49`. Reuse the existing TGL spoof routine; keep the RPL patch branch enabled
   (skip only when `isRealTGL == true`).
2. **RPL-P vs TGL PHY/display deltas.** Validate/extend combo-PHY calibration, `force-online`,
   `complete-modeset`, `rps-control`, and pipe-offset rewrites for the `0xA7Ax` Iris Xe parts — they
   differ from TGL-GT2 in EU count and display-PHY topology.
3. **Scheduler / firmware.** Default RPL to host-preemptive **scheduler type 5** and
   `-disablegfxfirmware` (GuC/HuC unsupported on the spoofed part).
4. **Tahoe symbol shims (conditional on Gate-A).** Add the Lilu shims per the mapping above — only
   for symbols `*.blockers.txt` reports.
5. **ICL fallback wiring.** Ensure the existing ICL path accepts the `0x8A52` spoof for RPL.
6. **Metal / WindowServer stability.** Continue the upstream execlist/CSB-cleanup and
   compositor-fallback work (the genuinely open problem).

## Verification (CI)
1. Actions → **Build Tahoe payload** → *Run workflow* (`workflow_dispatch`), pick
   `spoof_target = TGL`.
2. `build-kexts` (macos-15) emits `NootedGreen-*-RELEASE.zip` + `HookCase-RELEASE.zip`.
3. `gate-a` (macos-26-intel) runs `rpl-config-check.sh`, `gate-a-diff.sh`, `dry-link.sh`; read the
   reports per the decision tree above.
4. `package` assembles the payload (kext zips, `TGL-kexts.zip`, `TGL-bundles.zip`, `config/`,
   `INSTALL-V15G4.md`, `gate-a/`).

**Success** = `rpl-config-check` PASS, all `blockers.txt` empty, `kmutil-create exit=0` (or KDK
deferred), `spoof-sanity` OK ⇒ the leaked kexts link cleanly on Tahoe and the spoof config is
consistent; the only remaining risk is runtime Metal stability (item 6).

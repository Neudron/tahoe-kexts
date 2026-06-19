# Tahoe kexts

CI: Gate-A analysis on real Tahoe + kext payload for the V15 G4 hackintosh

## Overview

This project performs Gate-A analysis and testing on kernel extensions (kexts) for the V15 G4 hackintosh system running on real Tahoe hardware. It serves as a continuous integration pipeline for validating kext payloads and ensuring compatibility and stability.

## Raptor Lake iGPU acceleration on macOS 26 Tahoe

The headline target is hardware graphics acceleration for a **Raptor Lake (RPL-P/U Iris Xe)** iGPU on
**macOS 26 "Tahoe"**. macOS has no native driver for any Gen12 Intel iGPU, so the iGPU is
**device-ID-spoofed to Tiger Lake** (`0x9A49` / `ig-platform-id 0x9A490000`) and driven by NootedGreen
plus the leaked Apple Gen12 kexts, with an **Ice Lake fallback** if Tiger Lake symbols don't survive
on Tahoe. The CI here validates the spoof config and the symbol/link compatibility, then packages a
ready-to-install payload.

- **[docs/raptor-lake-tahoe.md](docs/raptor-lake-tahoe.md)** — how the spoof works, the Gate-A → action
  decision tree, and the NootedGreen source changes required.
- **[docs/INSTALL-V15G4.md](docs/INSTALL-V15G4.md)** — end-user install runbook for the V15 G4 board.
- **[config/rpl-tgl-map.json](config/rpl-tgl-map.json)** — single source of truth (device IDs, spoof
  target, boot-args, scheduler) that the DeviceProperties fragment, scripts and docs derive from.

## Project Purpose

- **Gate-A Analysis**: Conduct gate-level analysis on kernel extensions
- **Real Hardware Testing**: Test kext payloads on actual Tahoe hardware
- **V15 G4 Hackintosh**: Support for V15 G4 hackintosh systems
- **CI Pipeline**: Automated testing and validation through continuous integration

## Contents

This repository contains shell scripts and configuration for managing and testing kext payloads.

## Getting Started

### Prerequisites

- Tahoe hardware platform
- V15 G4 hackintosh system setup
- macOS environment with kernel extension support
- Bash shell environment

### Installation

1. Clone this repository:
```bash
git clone https://github.com/Neudron/tahoe-kexts.git
cd tahoe-kexts
```

2. Review the shell scripts and configuration files:
```bash
ls -la
```

## Usage

Refer to the individual shell scripts in this repository for specific testing and analysis procedures.

## Contributing

Contributions are welcome! Please ensure that:
- All changes maintain compatibility with the V15 G4 hackintosh
- Gate-A analysis passes for any kext modifications
- CI pipeline validation succeeds before submitting changes

## License

Please refer to the LICENSE file (if present) for licensing information.

## Resources

- [Tahoe Hardware Documentation](#)
- [macOS Kernel Extensions Documentation](#)
- [Hackintosh Community](#)

## Support

For issues, questions, or suggestions, please open an issue in the GitHub repository.

---

**Note**: This project is specifically designed for the V15 G4 hackintosh system on Tahoe hardware. Compatibility with other systems is not guaranteed.

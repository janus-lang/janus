<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->



# Windows Packaging

Windows distribution packages for Janus using pure Zig cross-compilation.

## Package Types

### ZIP Archives
- **janus-windows-x86_64.zip** - Windows x64 executable
- **janus-windows-aarch64.zip** - Windows ARM64 executable

### Chocolatey Package (Future)
- **janus.nuspec** - Chocolatey package specification
- **tools/chocolateyinstall.ps1** - Installation script

### MSI Installer (Future)
- **janus.wxs** - WiX installer definition
- **janus.msi** - Windows Installer package

## Contents

Each Windows package includes:
- `janus.exe` - Main compiler executable
- `janus-lsp-server.exe` - Language Server Protocol server
- `README.txt` - Installation and usage instructions
- `LICENSE.txt` - License information
- `VERSION.txt` - Version information

## Installation

### Manual Installation
1. Extract ZIP archive to desired location
2. Add directory to PATH environment variable
3. Verify installation: `janus --version`

### Chocolatey (Future)
```powershell
choco install janus-lang
```

### Winget (Future)
```powershell
winget install janus-lang
```

## Cross-Compilation

Built using pure Zig cross-compilation:
```bash
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-windows -Doptimize=ReleaseSafe
```

No GNU toolchain or MinGW dependencies required.

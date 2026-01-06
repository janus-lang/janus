<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->



# macOS Packaging

macOS distribution packages for Janus using pure Zig cross-compilation.

## Package Types

### TAR.GZ Archives
- **janus-macos-x86_64.tar.gz** - macOS Intel executable
- **janus-macos-aarch64.tar.gz** - macOS Apple Silicon executable

### Homebrew Formula (Future)
- **janus.rb** - Homebrew formula
- Hosted in homebrew-janus tap

### DMG Installer (Future)
- **janus.dmg** - macOS disk image installer
- Code-signed and notarized

## Contents

Each macOS package includes:
- `janus` - Main compiler executable
- `janus-lsp-server` - Language Server Protocol server
- `README.md` - Installation and usage instructions
- `LICENSE` - License information
- `VERSION` - Version information

## Installation

### Manual Installation
```bash
# Extract and install
tar -xzf janus-macos-aarch64.tar.gz
sudo cp janus-macos-aarch64/janus /usr/local/bin/
sudo cp janus-macos-aarch64/janus-lsp-server /usr/local/bin/

# Verify installation
janus --version
```

### Homebrew (Future)
```bash
brew tap janus-lang/homebrew-janus
brew install janus
```

## Cross-Compilation

Built using pure Zig cross-compilation:
```bash
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
```

No Xcode or macOS SDK dependencies required for compilation.

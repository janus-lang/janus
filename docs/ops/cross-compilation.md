<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Cross-Compilation Guide for Citadel Architecture

## Overview

The Janus Citadel Architecture is designed for cross-platform deployment with zero external dependencies in the core daemon. This document describes the supported cross-compilation targets and build procedures.

## Supported Target Platforms

### Linux Targets (Recommended)

#### Static Linking with musl
- **x86_64-linux-musl**: Linux x86_64 with musl libc (static linking)
- **aarch64-linux-musl**: Linux ARM64 with musl libc (static linking)
- **riscv64-linux-musl**: Linux RISC-V 64-bit with musl libc (static linking)

#### Dynamic Linking with glibc
- **x86_64-linux-gnu**: Linux x86_64 with glibc (dynamic linking)
- **aarch64-linux-gnu**: Linux ARM64 with glibc (dynamic linking)

### macOS Targets

- **x86_64-macos**: macOS Intel x86_64
- **aarch64-macos**: macOS Apple Silicon ARM64

### Windows Targets

- **x86_64-windows**: Windows x86_64

## Build Commands

### Core Daemon (Zero Dependencies)

The `janus-core-daemon` is the heart of the Citadel Architecture and MUST build without external dependencies:

```bash
# Native build
zig build janus-core-daemon

# Cross-compilation examples
zig build janus-core-daemon -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
zig build janus-core-daemon -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe
zig build janus-core-daemon -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
zig build janus-core-daemon -Dtarget=x86_64-windows -Doptimize=ReleaseSafe
```

### gRPC Proxy (With Dependencies)

The `janus-grpc-proxy` requires gRPC libraries and may have platform-specific build requirements:

```bash
# Native build (requires gRPC development libraries)
zig build janus-grpc-proxy

# Cross-compilation (requires cross-compiled gRPC libraries)
zig build janus-grpc-proxy -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
```

## Verification

### Automated Testing

Run the comprehensive cross-compilation test suite:

```bash
# Full cross-compilation verification
./tools/verify-cross-compilation.sh

# Individual cross-compilation test tool
zig build cross-compile-test
./zig-out/bin/cross-compile-test
```

### Manual Verification

#### 1. Dependency Check

Verify that `janus-core-daemon` has no forbidden dependencies:

```bash
# Linux
ldd zig-out/bin/janus-core-daemon

# macOS
otool -L zig-out/bin/janus-core-daemon

# Expected output for static builds: "not a dynamic executable" or minimal system libraries only
```

#### 2. Binary Size Check

The core daemon should be significantly smaller than the legacy `janusd`:

```bash
ls -lh zig-out/bin/janus-core-daemon
ls -lh zig-out/bin/janusd  # For comparison
```

#### 3. Functionality Test

Test that the cross-compiled binary works:

```bash
# Test basic functionality
./zig-out/bin/janus-core-daemon --help
./zig-out/bin/janus-core-daemon --version
```

## Architecture Requirements Compliance

### Requirement 1: Cross-Platform Core Daemon

✅ **WHEN building `janus-core-daemon` for any supported target platform THEN the build SHALL succeed without external dependencies beyond `libjanus`**

- Verified by cross-compilation test suite
- Core daemon links only against libjanus and system libraries

✅ **WHEN cross-compiling `janus-core-daemon` to ARM64, RISC-V, or embedded targets THEN the compilation SHALL complete successfully**

- ARM64: `aarch64-linux-musl`, `aarch64-macos`
- RISC-V: `riscv64-linux-musl`
- Embedded: musl targets provide minimal footprint

✅ **WHEN deploying `janus-core-daemon` on a minimal Linux environment THEN it SHALL run without requiring gRPC, protobuf, or C++ runtime libraries**

- musl static linking eliminates external dependencies
- No gRPC or protobuf dependencies in core daemon

✅ **WHEN measuring the binary size of `janus-core-daemon` THEN it SHALL be significantly smaller than the current `janusd` binary**

- Core daemon excludes heavy gRPC/C++ dependencies
- Static musl builds are optimized for size

✅ **IF the target platform supports static linking THEN `janus-core-daemon` SHALL be statically linked against musl libc**

- musl targets automatically use static linking
- Controlled by `is_musl` detection in build.zig

## Troubleshooting

### Common Issues

#### 1. Cross-Compilation Toolchain Missing

```
error: unable to find target 'x86_64-linux-musl'
```

**Solution**: Update Zig to latest version with full target support:
```bash
zig version  # Should be 0.11.0 or later
zig targets  # List supported targets
```

#### 2. gRPC Dependencies in Core Daemon

```
error: undefined symbol: grpc::...
```

**Solution**: The core daemon should NOT link against gRPC. Check that:
- `janus_core_daemon.zig` doesn't import gRPC modules
- Build configuration excludes gRPC dependencies for core daemon

#### 3. Static Linking Failures

```
error: cannot find -lc
```

**Solution**: Ensure musl target is properly configured:
```bash
zig build janus-core-daemon -Dtarget=x86_64-linux-musl --verbose
```

### Platform-Specific Notes

#### Windows Cross-Compilation

- Requires MinGW-w64 toolchain for gRPC proxy
- Core daemon should build without external toolchain
- File extensions (.exe) handled automatically

#### macOS Cross-Compilation

- Requires Xcode command line tools for gRPC proxy
- Core daemon cross-compiles without macOS SDK
- Code signing may be required for distribution

#### Embedded/Minimal Targets

- Use musl targets for smallest footprint
- Consider `ReleaseSmall` optimization for size
- Test on actual target hardware when possible

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Cross-Compilation Test
on: [push, pull_request]

jobs:
  cross-compile:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        target:
          - x86_64-linux-musl
          - aarch64-linux-musl
          - x86_64-macos
          - aarch64-macos
          - x86_64-windows

    steps:
    - uses: actions/checkout@v3
    - uses: goto-bus-stop/setup-zig@v2
      with:
        version: master

    - name: Cross-compile janus-core-daemon
      run: |
        zig build janus-core-daemon -Dtarget=${{ matrix.target }} -Doptimize=ReleaseSafe

    - name: Verify binary
      run: |
        ls -la zig-out/bin/
        file zig-out/bin/janus-core-daemon*
```

## Future Enhancements

### Additional Targets

- **wasm32-wasi**: WebAssembly System Interface
- **x86_64-freebsd**: FreeBSD support
- **aarch64-linux-android**: Android ARM64

### Optimization Profiles

- **Minimal**: Smallest possible binary for embedded use
- **Performance**: Maximum optimization for server deployment
- **Debug**: Full debug symbols for development

### Package Distribution

- **Static Binaries**: Single-file deployment
- **Container Images**: Multi-arch Docker images
- **Package Managers**: Native packages for each platform

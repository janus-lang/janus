<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Release Process

Comprehensive guide to Janus release management using pure Zig cross-compilation.

## 🚀 Overview

Janus uses **pure Zig cross-compilation** to build for all supported platforms without requiring GNU toolchains or platform-specific build environments. This approach provides:

- **Zero GNU dependencies** - No need for mingw-w64, cross-gcc, or other GNU tools
- **Single build machine** - Cross-compile to all targets from any Zig-supported host
- **Static binaries** - No runtime dependencies on target systems
- **Reproducible builds** - Deterministic compilation across all platforms

## 🎯 Supported Platforms

### Binary Targets (Pure Zig Cross-Compilation)

| Platform | Architecture | Static | Package Format | Status |
|----------|-------------|--------|----------------|--------|
| Linux | x86_64 | ✅ (musl) | tar.gz | ✅ Tested |
| Linux | aarch64 | ✅ (musl) | tar.gz | ✅ Tested |
| Windows | x86_64 | ✅ | zip | ✅ Tested |
| Windows | aarch64 | ✅ | zip | ✅ Ready |
| macOS | x86_64 | ✅ | tar.gz | ✅ Ready |
| macOS | aarch64 | ✅ | tar.gz | ✅ Tested |
| WASM | wasm32 | ✅ | tar.gz | ✅ Ready |

**Key Advantages:**
- **No GNU toolchain dependencies** - Pure Zig cross-compilation
- **Static linking by default** - No runtime dependencies
- **Single build machine** - Cross-compile to all targets from Linux
- **Reproducible builds** - Deterministic compilation across platforms

## 🔧 Build Commands

### Cross-Compilation Testing

```bash
# Test Windows x86_64 cross-compilation
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe

# Test macOS ARM64 cross-compilation
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe

# Test Linux ARM64 static cross-compilation
zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe

# Build all supported platforms
zig build -Drelease-all=true
```

### Verification Commands

```bash
# Verify Windows executable
file zig-out/bin/janus.exe
# Expected: PE32+ executable for MS Windows

# Verify macOS ARM64 executable
file zig-out/bin/janus
# Expected: Mach-O 64-bit arm64 executable

# Verify Linux static executable
file zig-out/bin/janus
ldd zig-out/bin/janus  # Should show "statically linked"
```

## 📦 Release Workflow

### 1. Version Management

```bash
# Bump version using Zig tool
zig run scripts/version-bump.sh -- minor  # 0.1.0 -> 0.2.0
zig run scripts/version-bump.sh-- patch  # 0.1.0 -> 0.1.1
zig run scripts/version-bump.sh -- major  # 0.1.0 -> 1.0.0
```

### 2. Local Release Build

```bash
# Full multi-platform release build
./scripts/release.sh build

# Results in dist/ directory:
# - janus-linux-x86_64-static.tar.gz
# - janus-linux-aarch64-static.tar.gz
# - janus-windows-x86_64.zip
# - janus-windows-aarch64.zip
# - janus-macos-x86_64.tar.gz
# - janus-macos-aarch64.tar.gz
# - janus-wasm32.tar.gz
```

### 3. Automated Release (CI/CD)

```bash
# Create and push version tag
git tag v0.1.1
git push origin v0.1.1

# Forgejo automatically:
# 1. Builds all platforms using pure Zig cross-compilation
# 2. Creates release packages
# 3. Generates checksums
# 4. Creates GitHub/Forgejo release
# 5. Uploads all assets
```

## 🏗️ Build System Architecture

### Cross-Compilation Configuration

The build system automatically detects cross-compilation and adjusts dependencies:

```zig
// build.zig - Cross-platform Blake3 configuration
const is_native = target.result.cpu.arch == builtin.cpu.arch and
                  target.result.os.tag == builtin.os.tag;

if (is_native and is_x86) {
    // Native x86 build - use optimized implementations
    blake3_lib.addCSourceFile(.{
        .file = b.path("third_party/blake3/c/blake3_avx2.c"),
        .flags = &[_][]const u8{ "-std=c99", "-DIS_X86=1", "-mavx2" },
    });
} else {
    // Cross-compilation - use portable implementation only
    blake3_lib.addCSourceFiles(.{
        .files = &[_][]const u8{
            "third_party/blake3/c/blake3_portable.c",
        },
        .flags = &[_][]const u8{ "-std=c99", "-DBLAKE3_NO_AVX512" },
    });
}
```

### Component Separation

For cross-compilation, components are separated by dependencies:

- **Core Compiler** (`janus`) - Pure Zig, cross-compiles to all platforms
- **LSP Server** (`janus-lsp-server`) - Pure Zig, cross-compiles to all platforms
- **Daemon** (`janusd`) - Includes gRPC (Linux-only for now)
- **Examples/Demos** - Pure Zig, cross-compile to all platforms

## 🔒 Security & Verification

### Static Analysis

```bash
# Security scan during build
zig build -Dsanitizers=true

# License compliance check
./scripts/validate-license-headers.sh

# Dependency audit
./scripts/license-compliance-scan.sh
```

### Binary Verification

```bash
# Generate checksums
cd dist/
sha256sum *.tar.gz *.zip > SHA256SUMS
md5sum *.tar.gz *.zip > MD5SUMS

# Verify signatures (future)
# gpg --verify janus-linux-x86_64-static.tar.gz.sig
```

## 📊 Performance Characteristics

### Cross-Compilation Performance

| Target | Build Time | Binary Size | Notes |
|--------|------------|-------------|-------|
| Linux x86_64 (musl) | ~30s | ~500KB | Static, no dependencies |
| Windows x86_64 | ~25s | ~450KB | Static, includes debug info |
| macOS aarch64 | ~28s | ~480KB | Static, optimized for Apple Silicon |
| WASM32 | ~20s | ~200KB | Minimal runtime |

### Blake3 Optimization Strategy

- **Native builds**: Use platform-specific SIMD (AVX2, SSE4.1, NEON)
- **Cross-compilation**: Use portable C implementation only
- **Performance impact**: ~15% slower on cross-compiled binaries
- **Compatibility**: 100% - works on all target systems

## 🚨 Troubleshooting

### Common Cross-Compilation Issues

**Blake3 intrinsic errors:**
```bash
# Error: always_inline function '_mm256_set1_epi32' requires target feature 'avx'
# Solution: Build system automatically uses portable implementation for cross-compilation
```

**Missing GNU tools:**
```bash
# Error: x86_64-w64-mingw32-g++: command not found
# Solution: This only affects gRPC components, core compiler cross-compiles fine
```

**Target not supported:**
```bash
# Check available targets
zig targets | grep -A 20 "os ="

# Test specific target
zig build -Dtarget=your-target-here -Doptimize=ReleaseSafe
```

### Debug Cross-Compilation

```bash
# Verbose build output
zig build -Dtarget=x86_64-windows --verbose

# Check target resolution
zig build -Dtarget=x86_64-windows --verbose 2>&1 | grep "target"

# Test minimal cross-compilation
zig build-exe -target x86_64-windows src/janus_main.zig
```

## 🔮 Future Enhancements

### Planned Improvements

- [ ] **Code signing** for Windows and macOS binaries
- [ ] **gRPC cross-compilation** using Zig-native gRPC implementation
- [ ] **WASM optimization** for browser-based Janus compiler
- [ ] **ARM32** support for embedded systems
- [ ] **RISC-V** support for emerging platforms

### Integration Opportunities

- [ ] **GitHub Actions** native Zig cross-compilation
- [ ] **Docker multi-arch** builds using Zig
- [ ] **Package repositories** automated updates
- [ ] **CDN distribution** for faster downloads

## 📚 References

- [Zig Cross-Compilation Guide](https://ziglang.org/learn/cross-compilation/)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Blake3 C Implementation](https://github.com/BLAKE3-team/BLAKE3/tree/master/c)
- [Semantic Versioning](https://semver.org/)

---

**Maintained by:** Janus Release Engineering Team
**Last Updated:** 2025-09-06
**Version:** 2.0.0 (Pure Zig Cross-Compilation)

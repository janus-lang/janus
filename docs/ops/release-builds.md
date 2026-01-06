<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Release Build System

The Janus project implements a controlled release build system that allows developers to optionally trigger release builds during commits, preventing broken release builds from blocking development while ensuring production-ready artifacts.

## Overview

The release build system provides three levels of build control:

- **`no`** (default): Skip release builds, development mode only
- **`testing`**: ReleaseSafe optimization with debug info for testing
- **`stable`**: ReleaseFast optimization, stripped for production

## Quick Start

### Testing Release Builds Locally

Use the provided test script to validate release builds before committing:

```bash
# Test a testing release (ReleaseSafe + debug info)
./tools/test-release.sh testing

# Test a stable release (ReleaseFast + stripped)
./tools/test-release.sh stable

# Skip release builds (default development mode)
./tools/test-release.sh no
```

### Committing with Release Builds

To trigger a release build during commit, include the `--release-level` flag in your commit message:

```bash
# Commit with testing release validation
git commit -m "feat(parser): add parameter parsing --release-level=testing"

# Commit with stable release validation
git commit -m "fix(astdb): resolve memory leak --release-level=stable"

# Normal development commit (no release build)
git commit -m "refactor(parser): simplify token handling"
```

## Build Targets

### Testing Release (`testing`)

**Purpose:** Validation and debugging of release-candidate code

**Characteristics:**
- **Optimization:** ReleaseSafe (runtime safety checks enabled)
- **Debug Info:** Preserved for debugging
- **Binary Size:** ~5.3MB
- **Use Case:** Pre-production testing, debugging release issues

**Command:**
```bash
zig build controlled-release -Drelease-level=testing
```

### Stable Release (`stable`)

**Purpose:** Production-ready binaries for distribution

**Characteristics:**
- **Optimization:** ReleaseFast (maximum performance)
- **Debug Info:** Stripped (smaller binaries)
- **Binary Size:** ~1.6MB (69% smaller than testing)
- **Use Case:** Production deployment, distribution packages

**Command:**
```bash
zig build controlled-release -Drelease-level=stable
```

## Pre-Commit Validation

The git pre-commit hook automatically detects release build requests in commit messages and validates them before allowing the commit:

1. **Detects** `--release-level=testing|stable` in commit messages
2. **Builds** the requested release level
3. **Runs** all tests to ensure quality
4. **Blocks** commit if release build fails
5. **Allows** commit if all validations pass

### Example Pre-Commit Flow

```bash
$ git commit -m "feat: new feature --release-level=stable"

🔍 Janus Pre-Commit Quality Gates
=================================
🎨 Checking code formatting... ✅
📄 Checking license headers... ✅
🔨 Checking build... ✅
🧪 Running tests... ✅
📝 Checking commit message format... ✅
🚀 Release build requested: stable
🔨 Testing release build... ✅
✅ Release build OK for level: stable

🎉 All pre-commit checks passed!
✅ Code is ready for commit
```

## Build Artifacts

Release builds produce optimized binaries in `zig-out/bin/`:

### Testing Release Artifacts
- `janus-testing` - Main compiler with debug info

### Stable Release Artifacts
- `janus` - Main compiler (stripped)
- `janus-lsp-server` - LSP server (if built with `-Dwith_lsp=true`)

## Binary Analysis

The test script provides detailed analysis for stable builds:

```
📊 Binary analysis:
  janus:
    Size: 1,6M
    Type: ELF 64-bit LSB executable, x86-64, dynamically linked, stripped
    Debug info: stripped
```

## Integration with CI/CD

The release build system is designed to integrate with continuous integration:

### GitHub Actions Example

```yaml
name: Release Build Validation
on: [push, pull_request]

jobs:
  test-releases:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        release-level: [testing, stable]

    steps:
    - uses: actions/checkout@v3
    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
    - name: Test Release Build
      run: ./tools/test-release.sh ${{ matrix.release-level }}
```

## Development Workflow

### Normal Development
```bash
# Regular development - no release builds
git add .
git commit -m "refactor(parser): improve error handling"
git push
```

### Pre-Release Testing
```bash
# Test release build locally first
./tools/test-release.sh testing

# If successful, commit with release validation
git add .
git commit -m "feat(core): implement new feature --release-level=testing"
git push
```

### Production Release
```bash
# Test stable build locally
./tools/test-release.sh stable

# Commit with stable release validation
git add .
git commit -m "release: version 0.2.0 --release-level=stable"
git push

# Tag the release
git tag v0.2.0
git push --tags
```

## Troubleshooting

### Release Build Fails

If a release build fails during commit:

1. **Check the error message** in the pre-commit output
2. **Test locally** using `./tools/test-release.sh [level]`
3. **Fix the issues** identified in the build or tests
4. **Retry the commit** once issues are resolved

### Common Issues

**Static Linking Errors:**
- The system automatically falls back to dynamic linking if static linking is not supported
- This is normal on most Linux distributions

**Memory Issues:**
- Release builds may expose memory issues not visible in debug builds
- Use the testing release level first to debug with safety checks enabled

**Missing Dependencies:**
- Ensure all required modules and libraries are properly linked
- Check that gRPC stubs are generated (`bash tools/gen_grpc.sh`)

## Git Push Control

### **Normal Push (No Release Builds)**

By default, `git push` does **NOT** trigger release builds. Release builds only occur when you explicitly include release flags in commit messages.

```bash
# Safe - no release builds triggered
git push

# Also safe - skips all git hooks
git push --no-verify
```

### **When Release Builds Trigger**

Release builds only trigger during **commits** (not pushes) when you include explicit flags:

```bash
# These commit messages WILL trigger release builds
git commit -m "feat: new feature --release-level=testing"
git commit -m "fix: critical bug --release-level=stable"

# These commit messages will NOT trigger release builds
git commit -m "feat: new feature"
git commit -m "refactor: improve code structure"
git commit -m "fix: minor bug --release-level=no"
```

### **Push After Release Build Commits**

Once you've committed with a release build flag, pushing is safe and normal:

```bash
# Commit with release build (triggers build validation)
git commit -m "feat: parameter parsing --release-level=testing"

# Push normally (no additional builds triggered)
git push
```

## Troubleshooting

### **Build Errors During Release**

If release builds fail during commit or testing:

#### **1. Unreachable Code Errors**
```
error: unreachable else prong; all cases already handled
```

**Solution:** Remove unreachable `else` clauses in switch statements. ReleaseFast mode is stricter about dead code.

```zig
// Bad - unreachable else
const error_message = switch (err) {
    error.OutOfMemory => "Out of memory",
    else => "Other error", // Unreachable if only OutOfMemory possible
};

// Good - only handle actual cases
const error_message = switch (err) {
    error.OutOfMemory => "Out of memory",
};
```

#### **2. Static Linking Errors**
```
error: libc of the specified target requires dynamic linking
```

**Solution:** The system automatically falls back to dynamic linking. This is normal and expected on most Linux distributions.

#### **3. Memory Issues in Release Builds**
Release builds may expose memory issues not visible in debug builds.

**Solution:**
1. Use `testing` level first (ReleaseSafe with runtime checks)
2. Fix any memory issues identified
3. Then test with `stable` level (ReleaseFast)

### **Pre-Commit Hook Issues**

#### **Formatting Errors**
```
❌ Code formatting issues found. Run 'zig fmt .' to fix.
```

**Solutions:**
```bash
# Fix formatting for specific files
zig fmt path/to/file.zig

# Fix formatting for entire repository (may take time)
zig fmt .

# Bypass formatting check for urgent fixes
git commit --no-verify -m "fix: urgent fix"
```

#### **Test Failures**
If tests fail during pre-commit validation:

1. **Run tests locally:** `zig build test`
2. **Fix failing tests** before committing
3. **Verify fix:** Run tests again to confirm

#### **Release Build Failures**
If release builds fail during commit with `--release-level` flag:

1. **Test locally first:** `./tools/test-release.sh [level]`
2. **Fix build issues** identified in local testing
3. **Retry commit** once issues are resolved

### **Common Issues**

**Missing Dependencies:**
- Ensure gRPC stubs are generated: `bash tools/gen_grpc.sh`
- Check that all required modules are properly linked

**Performance Issues:**
- Release builds may take longer due to optimization
- Use `testing` level for faster iteration during development

**Binary Size:**
- `testing` builds (~5.3MB) include debug info
- `stable` builds (~1.6MB) are stripped and optimized

## Best Practices

1. **Test Locally First:** Always run `./tools/test-release.sh` before committing with release flags
2. **Use Testing Level:** Use `testing` level for feature development and debugging
3. **Reserve Stable Level:** Use `stable` level only for production releases and critical fixes
4. **Incremental Releases:** Test with `testing` first, then promote to `stable`
5. **Clean Builds:** The test script automatically cleans previous builds for consistency
6. **Normal Development:** Use regular commits without release flags for day-to-day work
7. **Push Safely:** Normal `git push` never triggers additional builds

## Architecture

The release build system is implemented through:

- **`build.zig`**: Core build logic with release level detection
- **`.githooks/pre-commit`**: Git hook for automatic validation
- **`tools/test-release.sh`**: Developer testing utility
- **Build options**: `-Drelease-level=[testing|stable|no]`

This architecture ensures that release builds are:
- **Consistent** across all environments
- **Validated** before entering the repository
- **Optional** to avoid blocking development
- **Documented** for team collaboration

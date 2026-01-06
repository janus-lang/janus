# Janus Version Management

**Status**: ✅ Operational (Standalone Script)  
**Format**: Linux Kernel Style (`MAJOR.MINOR.PATCH-PKGREL`)

---

## Overview

The Janus version management system follows **Linux kernel-style versioning** with a package release number (pkgrel) for daily builds.

### Version Format

```
MAJOR.MINOR.PATCH-PKGREL
```

**Examples**:
- `0.2.0-1` - First build of 0.2.0
- `0.2.0-2` - Second build (daily commit)
- `0.2.0-3` - Third build
- `0.2.1-1` - After patch bump (resets pkgrel)
- `1.0.0-1` - After major bump (resets pkgrel)

---

## Quick Start

### Show Current Version
```bash
./janus version show
# or
./scripts/version.sh show
```

### Bump Version
```bash
# Daily commit (increment pkgrel)
./scripts/version.sh bump pkgrel
# 0.2.0-1 → 0.2.0-2

# Bug fix (patch bump, resets pkgrel)
./scripts/version.sh bump patch
# 0.2.0-5 → 0.2.1-1

# New feature (minor bump, resets pkgrel)
./scripts/version.sh bump minor
# 0.2.5-3 → 0.3.0-1

# Breaking change (major bump, resets pkgrel)
./scripts/version.sh bump major
# 0.3.0-7 → 1.0.0-1
```

### Validate Version
```bash
./scripts/version.sh validate
```

---

## Bump Types

| Type | Effect | Use Case |
|:-----|:-------|:---------|
| `pkgrel` / `build` / `rel` | `0.2.0-1` → `0.2.0-2` | Daily commits, small changes |
| `patch` / `task` / `fix` | `0.2.0-5` → `0.2.1-1` | Bug fixes |
| `minor` / `feature` | `0.2.5-3` → `0.3.0-1` | New features |
| `major` | `0.3.0-7` → `1.0.0-1` | Breaking changes |

> **Note**: All version bumps except `pkgrel` reset the pkgrel to `-1`.

---

## Branch Structure

| Branch | Purpose | Example Version |
|:-------|:--------|:----------------|
| `stable` | LTS release (default) | `0.2.0-1` |
| `edge` | Active rolling release | `0.2.0-5` |
| `dev` | Development tracking | `0.2.0-12` |

---

## Git Hook Integration

The version management system is integrated with Git hooks:

### Pre-commit Hook
- ✅ Validates `VERSION` file exists
- ✅ Checks version format (`MAJOR.MINOR.PATCH-PKGREL`)
- ✅ Validates branch-specific version requirements

### Post-commit Hook
- ✅ Detects Forge Cycle artifacts
- ✅ Suggests appropriate version bumps
- ✅ Detects breaking changes in commit messages

---

## Workflow Examples

### Daily Development
```bash
# Make changes
git add -A
git commit -m "feat: improve parser"

# Bump pkgrel for next commit
./scripts/version.sh bump pkgrel
# 0.2.0-1 → 0.2.0-2
git add VERSION
git commit -m "chore: bump version to 0.2.0-2"
```

### Bug Fix Release
```bash
# Fix bug
git add -A
git commit -m "fix: resolve memory leak"

# Bump patch (resets pkgrel)
./scripts/version.sh bump patch
# 0.2.0-5 → 0.2.1-1
git add VERSION
git commit -m "chore: bump version to 0.2.1-1"
```

### Feature Release
```bash
# Complete feature
git add -A
git commit -m "feat: add new compiler pass"

# Bump minor (resets pkgrel)
./scripts/version.sh bump minor
# 0.2.5-3 → 0.3.0-1
git add VERSION
git commit -m "chore: bump version to 0.3.0-1"
```

---

## Implementation Details

**File**: `scripts/version.sh`  
**Language**: Bash  
**Status**: ✅ Fully functional

The standalone script:
- ✅ Parses Linux-style version format
- ✅ Increments version components
- ✅ Resets pkgrel on patch/minor/major bumps
- ✅ Validates format
- ✅ Integrates with Git hooks

---

## Troubleshooting

### "Invalid version format"
```bash
# Check current version
cat VERSION

# Fix by resetting to valid format
echo "0.2.0-1" > VERSION
```

### Missing pkgrel suffix
The version format **requires** the `-PKGREL` suffix. Legacy semver format (`0.2.0`) is no longer valid.

---

## References

- **Git Hooks**: `.githooks/pre-commit`, `.githooks/post-commit`
- **Version Script**: `scripts/version.sh`

---

**Status**: ✅ **OPERATIONAL**

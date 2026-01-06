# Version Management Policy

## Core Principle: Branch-Based Versioning

The Janus project follows a strict branch-based versioning policy to ensure consistency between the core compiler and tooling (VS Code extension, LSP server, etc.).

## Rules

### 1. **Core VERSION File is Source of Truth**
- `VERSION` file at repository root defines the canonical version
- Format: `MAJOR.MINOR.PATCH-BUILD` (e.g., `0.2.1-0`)
- All tooling MUST sync to this version

### 2. **Branch-Based Extension Versioning**

| Branch | Role | VS Code Version | Update Frequency |
|--------|------|-----------------|------------------|
| **`stable`** | **LTS** (Long Term Support) | Matches `VERSION` | Rare (Major/Critical) |
| **`edge`** | **Rolling Release** | Matches `VERSION` (`-edge`) | Frequent (User Testing) |
| **`dev`** | **Experimental** | Matches `VERSION` (`-dev`) | Daily (Unstable) |
| **`main`** | *Release Staging* | Matches `VERSION` | Ad-hoc (Release candidates) |

**Example:**
- `VERSION` = `0.2.1-0`
- `stable` → VS Code version: `0.2.1`
- `edge` → VS Code version: `0.2.1-edge`
- `dev` → VS Code version: `0.2.1-dev`
- `main` → VS Code version: `0.2.1`

### 3. **Current Implementation (Simplified)**
For now, we use a **simplified policy**:
- **All branches** use the same version from `VERSION` file
- VS Code extension version = `MAJOR.MINOR.PATCH` (without build number)
- Users understand that `dev` branch may have unstable features

**Rationale:** Simplicity over complexity. The branch name itself signals stability.

## Enforcement

### Manual Sync (Current)
When `VERSION` changes, manually update:
1. `tools/vscode/package.json` → `version` field
2. `tools/vscode/package.json` → `description` field (includes version)

### Automated Sync (Future)
Create `scripts/sync-versions.sh`:
```bash
#!/usr/bin/env bash
# Sync VS Code extension version with core VERSION file

VERSION=$(cat VERSION | head -n1 | cut -d'-' -f1)
BRANCH=$(git branch --show-current)

# Update package.json
cd tools/vscode
npm version "$VERSION" --no-git-tag-version
```

Add to `.githooks/pre-commit` to enforce on commit.

## Version Bump Workflow

### For Release (on `main`):
```bash
# 1. Update VERSION file
echo "0.2.2-0" > VERSION

# 2. Sync VS Code extension
cd tools/vscode
npm version 0.2.2 --no-git-tag-version

# 3. Commit
git add VERSION tools/vscode/package.json
git commit -m "chore: bump version to 0.2.2"

# 4. Tag
git tag v0.2.2
```

### For Development (on `dev`):
```bash
# VERSION file tracks next release
# VS Code extension matches (users know dev = unstable)
# No tags on dev branch
```

## Current Status

✅ **Synced:** VS Code extension version now matches `VERSION` file (0.2.1)

**Branch:** `dev`  
**Core Version:** `0.2.1-0`  
**VS Code Version:** `0.2.1`

---

**Policy Owner:** Voxis Forge  
**Last Updated:** 2025-12-16

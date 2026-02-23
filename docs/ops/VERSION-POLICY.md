# Version Management Policy

## Core Principle: Calendar Versioning (CalVer)

The Janus project uses **Calendar Versioning (CalVer)** instead of Semantic Versioning (SemVer). This reflects that Janus evolves through temporal profiles (:core → :service → :cluster → :sovereign), not through breaking API changes.

## CalVer Format

**Format:** `YYYY.MAJOR.MINOR`

Where:
- **YYYY** = Year (e.g., 2026)
- **MAJOR** = Major milestone or profile completion (e.g., 1 = :core complete)
- **MINOR** = Minor updates, fixes, polish (incremented per release)

**Examples:**
- `2026.1.6` = Year 2026, :core complete (1), 6th minor update
- `2026.2.0` = Year 2026, :service complete (2), initial release
- `2027.3.4` = Year 2027, :cluster complete (3), 4th minor update

**Rationale:** Janus's philosophy is temporal ("Monastery and Bazaar"). Versions represent time and evolution, not breaking changes.

## Rules

### 1. **Core VERSION File is Source of Truth**
- `VERSION` file at repository root defines the canonical version
- Format: `YYYY.MAJOR.MINOR` (e.g., `2026.1.6`)
- All tooling MUST sync to this version

### 2. **Branch-Based Extension Versioning**

| Branch | Role | VS Code Version | Update Frequency |
|--------|------|-----------------|------------------|
| **`stable`** | **LTS** (Long Term Support) | Matches `VERSION` | Rare (Major/Critical) |
| **`edge`** | **Rolling Release** | Matches `VERSION` (`-edge`) | Frequent (User Testing) |
| **`dev`** | **Experimental** | Matches `VERSION` (`-dev`) | Daily (Unstable) |
| **`main`** | *Release Staging* | Matches `VERSION` | Ad-hoc (Release candidates) |

**Example:**
- `VERSION` = `2026.1.6`
- `stable` → VS Code version: `2026.1.6`
- `edge` → VS Code version: `2026.1.6-edge`
- `dev` → VS Code version: `2026.1.6-dev`
- `main` → VS Code version: `2026.1.6`

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
# 1. Update VERSION file (increment MINOR)
echo "2026.1.7" > VERSION

# 2. Sync VS Code extension
cd tools/vscode
npm version 2026.1.7 --no-git-tag-version

# 3. Commit
git add VERSION tools/vscode/package.json
git commit -m "chore(release): bump version to 2026.1.7"

# 4. Tag
git tag v2026.1.7
```

### For Major Profile Milestones:
```bash
# When completing :service profile
echo "2026.2.0" > VERSION
git tag v2026.2.0-service

# When completing :cluster profile
echo "2026.3.0" > VERSION
git tag v2026.3.0-cluster
```

### For Development (on `dev`):
```bash
# VERSION file tracks next release
# VS Code extension matches (users know dev = unstable)
# No tags on dev branch
```

## Profile Version Mapping

| Profile | CalVer MAJOR | Status | Version Example |
|---------|--------------|--------|-----------------|
| **:core** | 1 | ✅ Complete | `2026.1.6` |
| **:service** | 2 | 🔨 Planned | `2026.2.0` |
| **:cluster** | 3 | 📋 Planned | `2026.3.0` |
| **:npu** | 4 | 📋 Planned | `2026.4.0` |
| **:sovereign** | 5 | 📋 Planned | `2026.5.0` |

## Current Status

✅ **CalVer Adopted:** Version now follows `YYYY.MAJOR.MINOR` format

**Branch:** `main`
**Core Version:** `2026.1.6` (:core profile complete)
**VS Code Version:** TBD (needs sync)

---

**Policy Owner:** Voxis Forge
**Last Updated:** 2026-01-29

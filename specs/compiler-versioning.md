<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC — Compiler Versioning Scheme
**Version:** 0.1.0
**Status:** Draft → Implementation
**Author:** Voxis Forge (AI Symbiont)
**Date:** 2025-10-15
**License:** LSL-1.0
**Epic:** Versioning & Distribution

---

## 0. Purpose

Establish a **hybrid versioning scheme** that serves both **packager ecosystems** (Arch AUR, Nix, pkgsrc, Debian, Red Hat) and **Janus's doctrinal requirements** for transparency, reproducibility, and cryptographic integrity.

**Core Problem:** Git-based versioning (`0.1.7-r2.git+214a4a8`) is pragmatic but mutable (rebases forge history, no crypto proofs). Packagers demand monotonic revisions and short hashes for rolling releases.

**Solution:** Hybrid scheme with dials for different distribution needs.

---

## 1. Versioning Philosophy

| Doctrine | Versioning Implementation |
|----------|--------------------------|
| **Reveal the Cost** | Version components explicitly show temporal state, git history, and crypto proofs |
| **Mechanism over Policy** | Dials choose format; no hardcoded policies for different ecosystems |
| **Determinism** | Same commit → same version components (except temporal elements) |
| **No Ambient Authority** | Version parsing requires explicit format specification |
| **Sovereign Security** | Optional CID component enables cryptographic verification |

---

## 2. Hybrid Versioning Scheme

### 2.1 Format Grammar

```
version ::= stable_version | dev_version | snapshot_version

stable_version ::= semver [ "." cid_component ]
semver ::= major "." minor "." patch

dev_version ::= "dev" "." date "." rev_component "." git_component [ "." cid_component ]
snapshot_version ::= date "." rev_component "." git_component [ "." cid_component ]

date ::= YYYYMMDD (ISO date)
rev_component ::= "r" number (monotonic revision counter)
git_component ::= "g" hex (7+ character git commit hash)
cid_component ::= "cid" hex (8 character BLAKE3 content ID)
```

### 2.2 Version Examples

| Context | Example | Meaning |
|---------|---------|---------|
| **Main/LTS Release** | `0.1.8` | Stable release, semver only |
| **Main/LTS with Crypto** | `0.1.8.cid1a2b3c4d` | Stable with BLAKE3 verification |
| **Unstable Branch** | `dev.20251015.r42.g214a4a8` | Development build with full traceability |
| **Testing Branch** | `dev.20251015.r42.g214a4a8.cid1a2b3c4d` | Testing with crypto verification |
| **Snapshot** | `20251015.r42.g214a4a8` | Point-in-time snapshot |

---

## 3. Distribution Compatibility Matrix

| Distribution | Preferred Format | Janus Adaptation | Rationale |
|-------------|------------------|------------------|-----------|
| **Arch AUR** | `semver.r<rev>.g<short>-pkgrel` | `dev.<date>.r<rev>.g<short>` | Monotonic revisions, short git hash |
| **Nix Unstable** | `<date>.git<short>` or `rev` | `dev.<date>.r<rev>.g<short>` | Temporal pinning, git revision tracking |
| **Pkgsrc** | `<date>` for snapshots | `<date>.r<rev>.g<short>` | Date-based snapshots with git precision |
| **Debian** | `semver` for releases | `semver` for main/lts | Standard semver for stable releases |
| **Red Hat** | `semver` with epochs | `semver` for main/lts | Enterprise-grade semver |
| **Guix** | Git commit or content hash | `.cid<short>` dial | Cryptographic reproducibility |

---

## 4. Component Generation Rules

### 4.1 Date Component (`YYYYMMDD`)
- **Source:** Build timestamp in UTC
- **Stability:** Changes daily (for dev builds)
- **Purpose:** Temporal anchoring for packagers

### 4.2 Revision Component (`r<number>`)
- **Source:** `git rev-list --count HEAD ^<last_tag>`
- **Monotonic:** Auto-incremented on each promotion
- **Reset:** On version bumps (patch/minor/major)
- **Purpose:** Track distance from last stable release

### 4.3 Git Component (`g<hex>`)
- **Source:** `git rev-parse --short HEAD` (minimum 7 characters)
- **Stability:** Changes with each commit
- **Purpose:** Git history traceability for packagers

### 4.4 CID Component (`cid<hex>`)
- **Source:** BLAKE3 hash of compiler binary (8 characters)
- **Optional:** Enabled via `--cid=on` dial
- **Purpose:** Cryptographic verification of compiler integrity

---

## 5. Dial Configuration

| Dial | Values | Default | Purpose |
|------|--------|---------|---------|
| `--format` | `semver`, `hybrid`, `snapshot` | `hybrid` | Choose version format family |
| `--cid` | `on`, `off` | `off` | Include cryptographic verification |
| `--git-short` | `7`, `8`, `12` | `7` | Git hash length for packagers |
| `--rev-reset` | `auto`, `manual` | `auto` | Reset revision counter on bumps |

---

## 6. Branch-Specific Versioning

| Branch Pattern | Format | Example | Quality Gates |
|---------------|--------|---------|---------------|
| `experimental/*` | `dev.<date>.r<rev>.g<short>` | `dev.20251015.r12.g214a4a8` | Basic compilation |
| `unstable` | `dev.<date>.r<rev>.g<short>` | `dev.20251015.r42.g214a4a8` | Full test suite |
| `testing` | `dev.<date>.r<rev>.g<short>` | `dev.20251015.r42.g214a4a8` | Integration tests |
| `main` | `<semver>` | `0.1.8` | Production release |
| `lts/*` | `<semver>` | `0.1.8` | LTS maintenance |

---

## 7. Implementation Architecture

### 7.1 Version Parser (`std/version/parser.zig`)

```zig
pub const ParsedVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
    date: ?[]const u8,
    rev: ?u32,
    git: ?[]const u8,
    cid: ?[]const u8,
};

pub fn parseVersion(str: []const u8) !ParsedVersion;
pub fn formatVersion(parsed: ParsedVersion, format: VersionFormat) ![]u8;
```

### 7.2 Version Generator (`scripts/version-bump.sh`)

```bash
#!/bin/bash
# Enhanced version-bump.sh with hybrid scheme support

detect_branch_type() {
    branch=$(git branch --show-current)
    case "$branch" in
        experimental/*) echo "dev" ;;
        unstable) echo "dev" ;;
        testing) echo "dev" ;;
        main|lts/*) echo "stable" ;;
        *) echo "dev" ;;
    esac
}

generate_version() {
    local format="$1"
    local date=$(date -u +%Y%m%d)
    local rev=$(git rev-list --count HEAD ^$(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~))
    local git=$(git rev-parse --short=7 HEAD)

    case "$format" in
        "stable")
            # For main/lts: just semver
            echo "$(cat VERSION | sed 's/-.*$//')"
            ;;
        "dev")
            # For experimental/unstable/testing: full hybrid
            echo "dev.${date}.r${rev}.g${git}"
            ;;
        "snapshot")
            # For point-in-time: date+git only
            echo "${date}.r${rev}.g${git}"
            ;;
    esac
}
```

---

## 8. Packager Ecosystem Integration

### 8.1 Arch AUR Compatibility
```
# Janus package for AUR
pkgname=janus-language
pkgver=0.1.7.r42.g214a4a8
pkgrel=1
```

### 8.2 Nix Flakes Compatibility
```nix
# flake.nix
janus = {
  pname = "janus-language";
  version = "unstable-2025-10-15";
  src = fetchFromGitHub {
    owner = "janus-lang";
    repo = "janus";
    rev = "214a4a8";
  };
};
```

### 8.3 Debian Package Compatibility
```
# debian/control
Version: 0.1.8
# For snapshots: Version: 0.1.8+snapshot20251015
```

---

## 9. Migration Strategy

### 9.1 Current → Hybrid Migration

| Current Format | Migration Path | New Format |
|---------------|----------------|------------|
| `0.1.7-dev.20251007` | → | `dev.20251007.r0.g214a4a8` |
| `0.1.7-r2.git+214a4a8` | → | `dev.20251015.r2.g214a4a8` |
| `0.1.8` (release) | → | `0.1.8` (unchanged) |

### 9.2 Tool Migration

- **Version Bumping:** `scripts/version-bump.sh bump dev` → hybrid format
- **Package Building:** `scripts/strategic-release.sh` detects branch → appropriate format
- **CI/CD:** Version parsing handles all formats for compatibility

---

## 10. Security Considerations

### 10.1 Cryptographic Integrity (CID Component)
- **BLAKE3 Verification:** Optional `.cid<hex>` component for binary verification
- **Supply Chain:** Enables verification of compiler binary integrity
- **Sovereign Builds:** Users can verify compiler hasn't been tampered with

### 10.2 Git History Protection
- **Monotonic Revisions:** `r<rev>` prevents rebase-induced confusion
- **Short Hashes:** 7+ characters provide collision resistance for packagers
- **Temporal Anchoring:** Date component provides additional verification

---

## 11. Testing Strategy

### 11.1 Unit Tests (`tests/version/`)
- **Parsing Tests:** All format variations parse correctly
- **Generation Tests:** Version bumping produces expected formats
- **Compatibility Tests:** Old formats still parse (with warnings)

### 11.2 Integration Tests
- **Package Tests:** Generated versions work with Arch/Nix/Debian tools
- **Promotion Tests:** Branch promotion updates version components correctly
- **CID Tests:** Optional CID component validates correctly

### 11.3 Property Tests
- **Monotonicity:** Revisions never decrease inappropriately
- **Determinism:** Same commit → same version components
- **Format Consistency:** Branch type → correct format

---

## 12. Success Criteria

✅ **Packager Compatibility:** Arch AUR, Nix, pkgsrc, Debian, Red Hat all accept Janus versions
✅ **Rolling Release Support:** Unstable/testing branches have traceable git history
✅ **Cryptographic Integrity:** Optional CID component enables sovereign verification
✅ **Doctrinal Compliance:** All components explicit, no hidden mutability
✅ **Migration Path:** Existing versions continue to work during transition

---

## 13. Implementation Plan

| Phase | Deliverable | Timeline | Owner |
|-------|-------------|----------|-------|
| 1 | Version parser (`std/version/parser.zig`) | Week 1 | Runtime Team |
| 2 | Enhanced `version-bump.sh` with hybrid support | Week 1 | Build Team |
| 3 | Integration with `strategic-release.sh` | Week 2 | Release Team |
| 4 | Package ecosystem validation | Week 3 | Distribution Team |
| 5 | Migration documentation and tooling | Week 4 | Documentation Team |

---

**THE VERSIONING SCHEME FORGES PACKAGER ALLIANCES WHILE MAINTAINING DOCTRINAL PURITY.**
**HYBRID FORMAT UNITES ROLLING CHAOS WITH STABLE ORDER.**

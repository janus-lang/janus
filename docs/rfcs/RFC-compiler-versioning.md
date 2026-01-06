<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# RFC — Compiler Versioning Scheme Optimization
**Version:** 0.1.0
**Status:** Draft → Implementation
**Author:** Voxis Forge (AI Symbiont)
**Date:** 2025-10-15
**License:** LSL-1.0
**Task ID:** 2025-50-Versioning-Scheme-for-Compiler

---

## 0. Summary

**Problem:** Current git+rev versioning scheme (`0.1.7-r2.git+214a4a8`) is pragmatic but mutable (rebases forge history, no crypto proofs). Packagers (Arch AUR, Nix, pkgsrc) demand monotonic revisions and short hashes for rolling releases.

**Solution:** Hybrid versioning scheme with dials:
- **Semver** for main/lts branches (packager bliss)
- **dev.<date>.r<rev>.g<short>** for unstable/testing/experimental (temporal+git for rolling)
- **Optional .cid<short>** dial for crypto-reproducible builds

---

## 1. Current State Analysis

### 1.1 Existing Scheme Critique

| Component | Current | Problem | Impact |
|-----------|---------|---------|---------|
| **Git Hash** | `214a4a8` | Mutable (rebases forge) | No crypto verification |
| **Revision** | `r2` | Manual increment | Error-prone, non-monotonic |
| **Date** | `20251007` | Inconsistent format | Not ISO, hard to parse |
| **Format** | `0.1.7-r2.git+214a4a8` | Non-standard | Packagers struggle |

### 1.2 Packager Requirements

| Distribution | Version Format | Requirements |
|-------------|----------------|--------------|
| **Arch AUR** | `semver.r<rev>.g<short>-pkgrel` | Monotonic pkgrel, short git hash |
| **Nix Unstable** | `<date>.git<short>` or `rev` | Temporal pinning, git revision |
| **Pkgsrc** | `<date>` for snapshots | Date-based snapshots |
| **Debian** | `semver` for releases | Standard semver |
| **Red Hat** | `semver` with epochs | Enterprise semver |

---

## 2. Proposed Hybrid Scheme

### 2.1 Format Grammar

```
version ::= stable_version | dev_version | snapshot_version

stable_version ::= semver [ ".cid" hex ]
semver ::= major "." minor "." patch

dev_version ::= "dev" "." date "." "r" number "." "g" hex [ ".cid" hex ]
snapshot_version ::= date "." "r" number "." "g" hex [ ".cid" hex ]

date ::= YYYYMMDD (ISO 8601)
number ::= monotonically increasing revision counter
hex ::= git commit hash (7+ characters)
```

### 2.2 Version Examples

| Branch | Format | Example | Packager Love |
|--------|--------|---------|---------------|
| **main/lts** | `semver` | `0.1.8` | ✅ Standard semver |
| **main/lts + crypto** | `semver.cid<hex>` | `0.1.8.cid1a2b3c4d` | ✅ Crypto verification |
| **unstable** | `dev.<date>.r<rev>.g<short>` | `dev.20251015.r42.g214a4a8` | ✅ Full traceability |
| **testing** | `dev.<date>.r<rev>.g<short>` | `dev.20251015.r42.g214a4a8` | ✅ Git precision |
| **experimental** | `dev.<date>.r<rev>.g<short>` | `dev.20251015.r12.g214a4a8` | ✅ Rolling development |

---

## 3. Component Generation

### 3.1 Date Component (`YYYYMMDD`)
- **Source:** `date -u +%Y%m%d` (UTC build timestamp)
- **Purpose:** Temporal anchoring for packagers
- **Stability:** Changes daily for dev builds

### 3.2 Revision Component (`r<number>`)
- **Source:** `git rev-list --count HEAD ^<last_semver_tag>`
- **Monotonic:** Auto-incremented on each promotion
- **Reset:** On semver bumps (patch/minor/major)
- **Purpose:** Track distance from last stable release

### 3.3 Git Component (`g<hex>`)
- **Source:** `git rev-parse --short=7 HEAD`
- **Purpose:** Git history traceability
- **Length:** 7+ characters (configurable via dial)

### 3.4 CID Component (`cid<hex>`)
- **Source:** BLAKE3 hash of compiler binary (8 characters)
- **Optional:** `--cid=on` dial
- **Purpose:** Cryptographic verification

---

## 4. Implementation Plan

### Phase 1: Parser & Generator (Week 1)

**Deliverables:**
- `std/version/parser.zig` - Parse all version formats
- Enhanced `scripts/version-bump.sh` - Generate hybrid versions
- Unit tests for parsing and generation

**Risks:**
- Parser complexity with multiple formats
- Mitigation: Comprehensive test matrix

### Phase 2: Integration (Week 2)

**Deliverables:**
- Integration with `strategic-release.sh`
- Build system version detection
- CI/CD version validation

**Risks:**
- Branch detection edge cases
- Mitigation: Explicit branch type configuration

### Phase 3: Package Validation (Week 3)

**Deliverables:**
- Arch AUR package generation test
- Nix flake compatibility test
- Pkgsrc snapshot validation

**Risks:**
- Packager tool differences
- Mitigation: Test with actual package managers

### Phase 4: Migration (Week 4)

**Deliverables:**
- Migration guide from current scheme
- Backward compatibility tests
- Documentation updates

---

## 5. Doctrinal Alignment

| Doctrine | Versioning Implementation |
|----------|---------------------------|
| **Reveal the Cost** | Version components explicitly show temporal state and git history |
| **Mechanism over Policy** | Dials choose format; no hardcoded packager policies |
| **Determinism** | Same commit → same version (except temporal components) |
| **Sovereign Security** | Optional CID enables cryptographic verification |
| **No Ambient Authority** | Version parsing requires explicit format specification |

---

## 6. Migration Strategy

### 6.1 Backward Compatibility

**Current Format → Hybrid:**
- `0.1.7-dev.20251007` → `dev.20251007.r0.g214a4a8`
- `0.1.7-r2.git+214a4a8` → `dev.20251015.r2.g214a4a8`
- `0.1.8` (release) → `0.1.8` (unchanged)

### 6.2 Tool Migration

**Version Commands:**
```bash
# Current
scripts/version-bump.sh bump dev

# New hybrid
scripts/version-bump.sh bump dev  # → dev.20251015.r42.g214a4a8
```

**Package Building:**
```bash
# Current
scripts/strategic-release.sh build unstable

# New (auto-detects branch → format)
scripts/strategic-release.sh build unstable  # → hybrid format
```

---

## 7. Testing Strategy

### 7.1 Unit Tests
- **Parsing:** All format variations parse correctly
- **Generation:** Version bumping produces expected formats
- **Component Extraction:** Date/rev/git/cid components correct

### 7.2 Integration Tests
- **Branch Detection:** Correct format for each branch type
- **Promotion:** Version components update correctly on promotion
- **Package Tools:** Generated versions work with Arch/Nix/Debian tools

### 7.3 Property Tests
- **Monotonicity:** Revisions never decrease inappropriately
- **Determinism:** Same commit → same components
- **Format Consistency:** Branch type → correct format

---

## 8. Success Criteria

✅ **Packager Compatibility:** All major distributions accept Janus versions
✅ **Rolling Release Support:** Unstable/testing have traceable git history
✅ **Cryptographic Integrity:** Optional CID enables sovereign verification
✅ **Doctrinal Compliance:** All components explicit, no hidden mutability
✅ **Migration Safety:** Existing versions continue working during transition

---

## 9. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **Parser Complexity** | Medium | Medium | Comprehensive test matrix |
| **Packager Tool Differences** | High | Medium | Test with actual package managers |
| **Branch Detection Edge Cases** | Low | High | Explicit configuration options |
| **CID Performance** | Low | Low | Optional dial, cached computation |

---

## 10. Future Considerations

### 10.1 Extension Points
- **Custom Formats:** Plugin architecture for distribution-specific formats
- **Signature Integration:** GPG signatures for release versions
- **Metadata Embedding:** Rich version metadata for debugging

### 10.2 Ecosystem Evolution
- **Guix Integration:** Native Guile scheme format support
- **Container Tags:** OCI image tag compatibility
- **Semantic Versioning:** Extended semver for language evolution

---

**THE VERSIONING SCHEME FORGES PACKAGER ALLIANCES WHILE MAINTAINING SOVEREIGN SECURITY.**
**HYBRID FORMAT UNITES ROLLING CHAOS WITH STABLE ORDER.**

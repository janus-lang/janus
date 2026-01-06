<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Specification — Build System Core
**Version:** 0.1.0
**Profile key:** all (min|go|full)
**Source grammar:** SPEC-syntax.md (commit 8f30abc4)

This document defines the core build system requirements: content-addressable storage, deterministic builds, lockfile format, and comptime sandboxing policies.

---

## 1. Content-Addressable Storage (CAS)

### 1.1 Hash Algorithm
**Law: BLAKE3 for all content IDs**
- All sources, AST, IR, objects addressed by BLAKE3 hash
- Path-stable builds independent of filesystem layout
- Automatic deduplication and integrity verification

### 1.2 Lockfile Format
**Single source of truth: `JANUS.lock`**
- Contains hashes of all dependencies
- Records granted comptime capabilities
- Optional build attestations for supply chain security
- Machine-readable, diff-friendly format

---

## 2. Deterministic Builds

### 2.1 Reproducibility Requirements
- **SOURCE_DATE_EPOCH** honored everywhere
- Deterministic compilation order
- Stable symbol ordering in output
- Platform-independent intermediate representations

### 2.2 Determinism Mode
**Flag: `--deterministic`**
- Cages time, entropy, and scheduling behind `ContextDeterministic`
- Disables fast-math and other non-deterministic optimizations
- Ensures bit-identical outputs across builds

---

## 3. Comptime Sandboxing

### 3.1 Default Policy
**Hermetic by default:**
- No network access
- No filesystem access
- No environment variable access
- Can only read vendored inputs from CAS

### 3.2 Capability Grants
**Explicit policy file: `janus.build.policy`**
```toml
[comptime]
net = false
env = []
fs_ro = ["schemas/", "vendor/"]
```
- All grants recorded in `JANUS.lock`
- Auditable and diff-reviewable
- Principle of least privilege

---

This specification ensures build reproducibility and security.

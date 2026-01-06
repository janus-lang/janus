<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# SPEC-hinge: The Sovereign Supply Chain

**Codename:** `HINGE`
**Status:** DRAFT (Implementing Epics 2.6 & 2.7)
**Doctrine:** [GARDEN_WALL](../doctrines/DOCTRINE-garden-wall.md)

---

## 1. Core Philosophy

The Janus package manager `hinge` is not a utility. It is the **sovereign backbone of the Janus ecosystem**.

It enforces **The Supply Chain Trident**:
1.  **Determinism:** Content-addressed artifacts.
2.  **Trust:** Cryptographic signatures and Proof Certificates.
3.  **Transparency:** Ledger-based transparency.

### 1.1 The "Capsule" Standard

A **Capsule** is an atomic unit of distribution containing:
1.  **Source:** Logic (Structs, Functions).
2.  **Proof:** Tests + Proof Certificate (`proof.json`).
3.  **Contract:** Capability Manifest (`janus.kdl`).

### 1.2 Tooling Consolidation

`janus` is the single binary interface:
- `janus build` → Compiles.
- `janus test` → Verifies and generates `proof.json`.
- `janus publish` → Wraps `hinge` to seal and upload the Capsule.

---

## 2. The Manifests

We separate **Human Intent** from **Machine Reality**.

### 2.1 The Human Interface (`janus.kdl`)

Based on KDL (nodes, readable, structural).

```kdl
package "std.collections" {
    version "0.1.0"
    description "Standard collections capsule"
    license "LSL-1.0"
    
    // The Guarantee (Quality Gate)
    // Hinge REFUSES to publish if these metrics aren't met.
    verify {
        coverage "95%"
        tests "pass"
        benchmarks "regress < 5%"
    }
}

dependencies {
    // Janus native
    "std.core" version="0.1.0"
    
    // Grafting Foreign Deps
    graft "zlib" {
        system "c"
        source "git+https://github.com/madler/zlib"
        version "1.3"
    }
}
```

### 2.2 The Machine Interface (`hinge.lock.json`)

Flat, deterministic, content-addressed JSON.

```json
{
  "version": 1,
  "packages": [
    {
      "name": "std.collections",
      "version": "0.1.0",
      "source": "local",
      "dependencies": ["std.core", "zlib"],
      "checksum": "blake3:abc123..."
    },
    {
      "name": "zlib",
      "system": "c",
      "version": "1.3",
      "resolution": {
        "git": "https://github.com/madler/zlib",
        "commit": "51b7f2abd..."
      },
      "checksum": "blake3:def456..."
    }
  ]
}
```

---

## 3. The Quality Gate (`janus test`)

`hinge` is aware of `janus test` results. Publishing requires a **Proof Certificate**.

### 3.1 Proof Generation

When `janus test --json` is run:
1.  All tests are executed.
2.  Coverage is calculated (if enabled).
3.  A `proof.json` is generated containing:
    - Test results.
    - Coverage metrics.
    - Source content hash (CID).
    - Timestamp and environment metadata.

### 3.2 The Gate

`janus publish` performs the following check:
1.  Does `proof.json` exist?
2.  Does the Source CID in `proof.json` match the current source?
3.  Do the metrics in `proof.json` meet the `verify` block in `janus.kdl`?

If **NO**, publish is rejected.

---

## 4. Workflows

### 4.1 Development (The "First Capsule")
1.  Create `janus.kdl`.
2.  Implement code.
3.  Run `janus test --json`.
4.  Verify `proof.json` is generated.

### 4.2 Consumption
1.  `janus add package_name`.
2.  `hinge` resolves dependency graph.
3.  `hinge` downloads verified Capsules (with proofs).
4.  `janus build` verifies CIDs match `hinge.lock.json`.

---

## 5. Roadmap: Epics 2.6 & 2.7

1.  **Epic 2.6 (Test Runner):**
    - Implement `janus test`.
    - Implement `proof.json` emission.

2.  **Epic 2.7 (The First Capsule):**
    - Implement KDL Parser for `janus.kdl`.
    - Build `std.collections` as the first independent Capsule.
    - Demonstrate `janus test` gating `std.collections`.

---

**"Trust is not assumed; it is proven."**

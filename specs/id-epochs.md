<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





 **Title:** ID Width & Epoch Strategy
 **Version:** 0.1.0 (Aug 2025)
 **Profile key:** meta (applies to all profiles)
 **Depends on:** SPEC‑astdb‑query, SPEC‑semantics, development_coding_standards

## 0. Purpose

Define how Janus represents internal identifiers (NodeId/DeclId/TypeId/…) over time, ensuring **hot‑path performance now** and **seamless widening later** without breaking CIDs, reproducibility, or tooling. The doctrine: **IDs are local handles; CIDs are identity.**

## 1. Scope & Non‑Goals

- In‑process ID widths, sharding, and epoching for ASTDB, Sema, IR.
- Wire stability (disk/RPC) via varints and capability negotiation.
- Deterministic behavior across width changes.
   Non‑goals: hash function changes (covered by CID spec) or grammar/semantics.

## 2. Definitions

- **ID**: Snapshot‑local, table‑local dense integer handle (`NodeId`, `DeclId`, `TypeId`, `ScopeId`).
- **Epoch**: Toolchain version epoch that may change internal ID width/layout.
- **CID**: BLAKE3‑256 content ID of normalized semantics (unchanged by ID width).
- **Shard**: File/module partition with its own local ID space.

## 3. ID Domains & Current Default

- Default **Width**: `u32` per ID domain.
- **Limit**: 4,294,967,296 rows per table per snapshot (before sharding).
- **Sharding**: Every unit (file/module) forms a shard; cross‑shard references use `(shard_id, local_id)` logically, while hot loops operate on `local_id: u32`.

## 4. Future‑Proofing: Three Encodings

1. **Narrow (Today):** `u32`
2. **Wide (Future):** `u64` (flip type alias)
3. **Packed Shard Form (Hybrid):** `struct PackedId { shard_id: u16, local_id: u32 }` (effective 48 bits)
    Hot paths still use `local_id: u32`; packing/unpacking occurs at boundaries.

> Choice among (2) or (3) is an implementation decision per epoch; both are wire‑compatible.

## 5. Wire & Disk Formats (Stable)

- **ULEB128 for IDs** on all RPC/disk surfaces.
- Small numbers remain 1–5 bytes; large values expand as needed.
- **Schema stability:** existing artifacts remain readable when widening.

## 6. RPC Negotiation (janusd)

- Handshake advertises:
   `id_width = 32|64`, `packed = true|false`, `epoch = u32`, `features = {...}`.
- Clients send `accept_id_width = [32,64]` list. Server selects the **narrowest** mutually supported width; mapping is internal to the server.
- LSP bridge insulates editors from width details.

## 7. CIDs & Canonicalization

- CIDs **do not** encode raw IDs; they encode **TypeId/StrId** logical identities and normalized semantics as specified by canonicalization rules.
- Width changes do **not** alter CIDs.
- **Domain separation** already includes toolchain version; epoch bumps naturally invalidate stale caches.

## 8. Determinism

- In `--deterministic`:
  - Fixed hash seeds and stable sorts irrespective of ID width.
  - Same inputs → same CIDs/IR/object bytes across 32/64‑bit builds within the same epoch.
- Cross‑epoch outputs may differ in cache keys but must be behavior‑identical.

## 9. Performance Guidance

- Maintain `u32` in scan/join hot paths as long as feasible.
- If widening, keep **local hot IDs** `u32` and widen only at boundaries (RPC, cross‑shard maps).
- Columnar tables remain 4/8‑byte aligned accordingly; avoid padding explosions.

## 10. Error Codes (Query/Daemon)

- `Q1010_IdOverflow`: attempted allocation beyond current ID space.
  - Fix: auto‑enable sharding or switch to `id_width=64` when supported.
- `D1011_IdWidthNegotiationFailed`: no compatible width between client/server.
- `Q1012_PackedIdMismatch`: mixed packed/non‑packed forms in an epoch boundary.

## 11. EARS Acceptance Criteria

**[E‑ID‑1] Wire Compatibility (Varint)**

- **WHEN** a project serialized with `id_width=32` is read by a toolchain supporting `id_width=64`
- **THEN** the loader SHALL parse all IDs via ULEB128 without schema changes **SO THAT** artifacts remain readable.

**[E‑ID‑2] CID Stability Across Width**

- **WHEN** the same sources are compiled with `id_width=32` and `id_width=64` under the same epoch and `--deterministic`
- **THEN** all CIDs, IR digests, and final object bytes SHALL be identical **SO THAT** reproducibility is guaranteed.

**[E‑ID‑3] Overflow Escalation**

- **WHEN** any table in a shard would exceed the current ID capacity
- **THEN** the system SHALL (a) auto‑split shard or (b) surface `Q1010_IdOverflow` with a fix hint to increase `id_width` or enable sharding **SO THAT** builds fail safe, not corrupt.

**[E‑ID‑4] Negotiation**

- **WHEN** a client requests RPC and advertises acceptable widths
- **THEN** `janusd` SHALL select the minimal mutually supported width and confirm in handshake **SO THAT** older clients continue to work.

**[E‑ID‑5] No‑Work Rebuild Invariance**

- **WHEN** only ID width is changed between builds (no source changes)
- **THEN** the rebuild SHALL report zero recomputed semantics/IR/codegen (cache keys differ only by epoch if bumped) **SO THAT** developer UX remains instant.

## 12. Migration Procedure (u32 → u64 or Packed)

1. **Flip the alias** in `ids.zig` (`pub const NodeId = u64;` or `PackedId`), gated by **epoch bump**.
2. **Keep wire stable** (ULEB128); no schema changes.
3. **Bump toolchain epoch** to avoid cache poisoning.
4. **RPC**: enable dual‑width handshake; prefer 32 for legacy clients, translate internally.
5. **Hot Loops**: retain `local_id: u32` in shard internals; widen only at boundaries.
6. **Golden Tests**: run **CID Stability Across Width** and **No‑Work Rebuild** suites.

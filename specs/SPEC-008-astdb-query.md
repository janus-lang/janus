<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).


# Janus Specification — ASTDB & Query Engine (SPEC-008)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-astdb-query v0.1.0

## 0. Purpose & Scope

Define the **AST-as-Database (ASTDB)** and **Query Engine** that power `libjanus` and `janusd`. Replace pointer-walk trees with **immutable, arena-allocated, columnar tables** addressed by stable IDs and **content IDs (CIDs)**. All higher compiler stages and tools interact **exclusively** via **pure, memoized queries**. This spec is authoritative for data layout, hashing, caching, invalidation, determinism, performance, and diagnostics.

Non‑goals: grammar, type rules, IR instruction set (specified elsewhere).

## 1. Terminology

* **StrId/TypeId/SymId/NodeId/DeclId/ScopeId/RefId**: 32‑bit stable IDs within a snapshot.
* **Snapshot**: immutable arena instance of AST produced by a text edit/build.
* **CID**: BLAKE3 hash of **normalized semantic content**; Merkle-folded bottom‑up.
* **Memo**: demand-driven, deterministic cache keyed by tuples of CIDs + parameters.
* **Region parser**: parses only dirty ranges to produce a new snapshot.

## 2. Data Model (Columnar, Immutable)

### 2.1 Global Interners (process-wide)

* `StrInterner`: UTF‑8 bytes → `StrId` (BLAKE3 keyed, deduplicated).
* `TypeInterner`: canonical types/effects/caps → `TypeId`.
* `SymInterner`: `(scope_chain, StrId, kind)` → `SymId`.

### 2.2 Per‑Snapshot ASTDB

```
AstDB {
  tokens:  Table<TokenId, { kind, str: StrId?, span: Span, trivia_lo: u32, trivia_hi: u32 }>
  nodes:   Table<NodeId,  { kind: NodeKind, first_tok: TokenId, last_tok: TokenId
                           child_lo: u32, child_hi: u32 }>
  edges:   Vec<NodeId>  // flattened child array for all nodes
  scopes:  Table<ScopeId, { parent: ScopeId?, first_decl: DeclId? }>
  decls:   Table<DeclId,  { node: NodeId, name: StrId, scope: ScopeId, kind: DeclKind }>
  refs:    Table<RefId,   { at_node: NodeId, name: StrId, decl: DeclId? }>
  diags:   Table<DiagId,  { code, severity, span, message, fix: FixIt? }>
  cids:    Table<NodeId,  { cid: Blake3_256 }> // semantic content ids
}
```

* Tables are arena‑backed; rows are **never mutated**. New snapshots add new rows; old snapshots are reclaimed wholesale (O(1) arena free).

## 3. Content Identity (Hashing Rules)

### 3.1 String Interning (baseline)

* Every identifier/keyword/literal interned once per daemon, referenced by `StrId`.
* All equality & map keys are integer-based.

### 3.2 Semantic CIDs (incremental weapon)

For each node, compute BLAKE3 over **normalized semantics**:

* Include: node kind, operator kinds, literal values (normalized), **TypeIds** after inference where applicable, effect/capability masks, profile gates, **desugared forms** for honest sugar.
* Exclude: whitespace/comments/trivia, source spans, formatting.
* Fold children by `(kind_tag || child_cid)` order.

**Stage scoping:** Memo keys include `(CID(subject) ⊗ target_triple ⊗ opt_level ⊗ safety_dial ⊗ profile_mask ⊗ fastmath_bit)`.

## 4. Query Engine

### 4.1 Purity & Determinism

* All queries are pure functions of their inputs.
* Results are memoized by **CID tuples**, not by addresses.
* In `--deterministic`, hashing seeds, clocks, RNG, and scheduling are fixed.

### 4.2 Canonical Queries (normative API surface)

* `Q.TokenSpan(node: NodeId) -> (TokenId..TokenId)`
* `Q.Children(node: NodeId) -> []NodeId`
* `Q.NodeAt(pos: BytePos) -> NodeId?`
* `Q.Lookup(scope: ScopeId, name: StrId) -> DeclId?`
* `Q.TypeOf(node: NodeId) -> TypeId`
* `Q.Dispatch(call_node: NodeId) -> ImplId!E2001` (ambiguity → E2001)
* `Q.IROf(func_decl: NodeId, target, opt, safety, profile) -> IRFuncId`
* `Q.ObjsOf(module: NodeId, target, opt) -> ObjSet`
* `Q.RefsTo(decl: DeclId) -> []RefId`
* `Q.DefsInSpan(span) -> []DeclId`
* `Q.DocsOf(node) -> DocBlock?`

**Memoization is required** for `Q.TypeOf`, `Q.Dispatch`, `Q.IROf/ObjsOf`.

### 4.3 Dependency Tracking

* Each query records dependencies (Salsa‑style). If any **input CID** changes, invalidate only dependents.
* Parser/binder produce `scopes/decls/refs` in linear scans to minimize upstream fan‑out.

## 5. Incrementality Pipeline

1. LSP edit → re‑lex dirty slice → region‑parse → **new snapshot**.
2. Recompute CIDs bottom‑up only for affected subtrees.
3. Invalidate memo entries keyed by changed CID tuples.
4. Re‑answer queries on demand; **unchanged** functions reuse IR/objects from cache.

## 6. Diagnostics & Error Codes

* Every query returns `(result, diagset)`; diag rows persist in `diags`.
* Code ranges: `Pxxxx` (parser), `Sxxxx` (sema), `Ixxxx` (IR), `Dxxxx` (daemon), profile gates: `E20xx/:core`, `E21xx/:script`, `E25xx/:service`, `E26xx/:cluster`, `E27xx/:compute`, `E30xx/:sovereign`.
* Each diagnostic includes a **single suggested fix** (atomic edit) when available.

## 7. Concurrency & Sharding

* Shard by file/module; each shard has a worker, region parser, memo.
* Cross‑shard queries hop via in‑proc channels; deadlocks are forbidden.
* Work‑stealing allowed; deterministic schedule when flagged.

## 8. Security & Capability Discipline

* No ambient globals. Allocator/Clock/Rng/Capabilities passed explicitly or via context injection (see SPEC‑syntax/semantics).
* Comptime queries are capability‑gated; their memo keys must include the capability grants' CID.

## 9. Performance Targets (Must‑Have)

* **Lookup latency** (hover/definition): ≤ 10ms @ 100k LOC hot cache.
* **Parse of dirty slice**: ≤ 3ms per 1k LOC changed (median).
* **TypeOf** mean: ≤ 1ms; **Dispatch** mean: ≤ 1ms; **IROf** hit: ≤ 0.3ms (cache).
* **No‑work rebuild**: recompilation reports **zero IR/obj builds** when CIDs unchanged.

## 10. EARS Acceptance Criteria

### 10.1 Columnar ASTDB
* **WHEN** a source file is parsed **THEN** nodes/edges/scopes/decls/refs SHALL be stored in immutable, arena‑allocated columnar tables **SO THAT** pointer stability and O(1) snapshot tear‑down are guaranteed.

### 10.2 Semantic CID Normalization
* **WHEN** comments/whitespace or equivalent formatting changes occur **THEN** function CIDs SHALL remain identical **SO THAT** downstream stages do zero work.
* **WHEN** any literal/type/effect/profile changes **THEN** the function's CID SHALL change **SO THAT** caches invalidate precisely.

### 10.3 Demand‑Driven Queries
* **WHEN** `Q.IROf(func)` is requested **THEN** only the minimal prerequisite queries SHALL execute, and subsequent `Q.IROf(func)` calls with identical CID tuples SHALL hit the memo cache **SO THAT** rebuilds are incremental.

### 10.4 Determinism
* **WHEN** `--deterministic` mode is enabled **THEN** identical inputs and options SHALL yield identical CIDs and IR/objects across machines **SO THAT** builds are reproducible.

### 10.5 Tooling Latency
* **WHEN** an IDE issues hover/definition/refs within a hot snapshot **THEN** responses SHALL complete within 10ms P50 **SO THAT** editor UX meets target responsiveness.

### 10.6 Diagnostics
* **WHEN** a query fails due to profile gates or semantic ambiguity **THEN** a diagnostic with stable code, primary span, and **one** fix suggestion SHALL be produced **SO THAT** developer feedback is actionable.

### 10.7 Snapshot Isolation
* **WHEN** a new edit is applied **THEN** a new snapshot SHALL be produced without mutating prior snapshots **SO THAT** time‑travel/undo and concurrent reads remain safe.

## 11. janusd RPC (Required Surface)

* `snapshot.apply_text(file, diff) -> SnapshotId + Diags`
* `query.node_at(snapshot, pos) -> NodeId?`
* `query.type_of(snapshot, node) -> TypeString + Diags`
* `query.ir_of(snapshot, func, target, opt) -> ObjHandle + Stats`
* `query.refs/defs/hover(snapshot, …) -> …`

All responses include **diagsets** and **cache stats** (hits/misses).

## 12. Compliance & Interop

* `libjanus` is the **single source of truth**; CLI/LSP/refactors must call queries—not reimplement logic.
* Public APIs versioned; breaking changes bump major.

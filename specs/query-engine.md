<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus SPEC — ASTDB Query Engine Core
**Version:** 0.1.0 (Aug 2025)
**Scope:** libjanus + janusd
**Depends on:** SPEC-astdb-query.md (ASTDB & CID), SPEC-semantics.md, SPEC-profiles.md
**Error ranges:** QExxxx (Query Engine), QIxxxx (Invalidation), QRxxxx (RPC)

## 0. Purpose
Provide a **pure, memoized, demand‑driven** query layer over ASTDB that:
- Computes semantic facts deterministically from **canonical inputs** (CID tuples)
- Tracks **fine‑grained dependencies** for precise invalidation
- Guarantees **no‑work rebuilds** when inputs’ semantic CIDs are unchanged
- Powers **janusd** (LSP, refactors, AI analysis) with ≤10 ms p95 hover @ 100k LOC

## 1. Model & Identity

### 1.1 Query Identity (QID)
Every query instance is identified by:
```
QID = BLAKE3("Q:" || QueryName || "\n" ||
canonical\_encode(Args) || "\n" ||
profile\_key || "\n" ||
toolchain\_key || "\n" ||
language\_version)

```
- **canonical_encode** follows ASTDB canonicalization rules (ULEB128, NFC strings, float normalization).
- Arguments are **CIDs or small scalars**; no raw pointers/paths.
- **Domain separation**: `"Q:"` and profile/toolchain keys prevent cross-profile collisions.

### 1.2 Determinism
For identical (QueryName, Args, knobs), the result bytes are identical across platforms in `--deterministic` mode.

### 1.3 Purity
Queries are **pure functions** of their inputs and the ASTDB snapshot they reference. They cannot access wall‑clock, RNG, FS, or network. Any non‑deterministic attempt yields **QE0003_NondeterministicAccess**.

## 2. Query Catalogue (v1)

| Name                | Input (canonical)                     | Output (value)                                   |
|---------------------|---------------------------------------|--------------------------------------------------|
| `Q.ResolveName`     | (ModuleCID, ScopeNodeId, InternedStr) | SymbolId                                          |
| `Q.TypeOf`          | (NodeCID)                             | TypeCID                                           |
| `Q.Dispatch`        | (CalleeSymbolId, ArgTypeCID[])        | ImplSymbolId or Ambiguity/Error                   |
| `Q.EffectsOf`       | (SymbolId)                            | EffectsBitset (canonical encoded)                 |
| `Q.CapabilitiesOf`  | (SymbolId)                            | CapabilitySet (canonical encoded)                 |
| `Q.DefinitionOf`    | (SymbolId)                            | DefSpan (stable span encoding)                    |
| `Q.FindRefs`        | (SymbolId)                            | Array<RefSpan>                                    |
| `Q.IROf`            | (FunctionCID, CodegenKnobsCID)        | IRCID (points to CAS entry)                       |
| `Q.Hover`           | (FileCID, ByteOffset)                 | HoverDoc (markdown, canonicalized)                |
| `Q.ComptimeEval`    | (ExprCID, CtPolicyCID)                | ValueCID or Error                                 |

> Extensions (v1.x) may add `Q.FlowFacts`, `Q.DataflowDefUse`, `Q.DocsOf`, etc.

## 3. Execution & Memoization

### 3.1 Memo Table
- In‑memory concurrent hash map keyed by **QID** → {ResultBytes, DepSet, GasUsed, Generation}.
- Persistent write‑through option stores ResultBytes in CAS by **ResultCID** for cross‑session reuse.

### 3.2 Dependency Tracking
- During evaluation, the engine records **edges** from the current QID → any **CIDs/QIDs** it reads.
- Dep edges are stored as compact Roaring bitmaps over **dep slots** (per‑shard integer IDs).
- Reads are **declared** through the query context (no hidden global reads).

### 3.3 Invalidation
- When a base artifact changes (e.g., ModuleCID or NodeCID), the **ChangeSet** lists (OldCID → NewCID).
- The engine performs **reverse‑topo invalidation** over the dep graph, clearing stale QIDs.
- **Precision rule:** If an upstream CID changes but its **SemanticCID** is identical, results remain valid.

### 3.4 Gas/Quota
- Each query has gas limits for CPU steps and memory. Exceeding yields **QE0011_QuotaExceeded**.
- Defaults for LSP: 1 ms CPU budget soft, 5 ms hard; CLI builds use higher caps.

## 4. Canonical Results & Stability
- All query results are serialized with the **ASTDB canonical encoder**.
- **Stable spans** encode (FileCID, Line, Col, Len) with LF‑normalized line maps.
- Markdown payloads are normalized (line endings, link canonicalization).

## 5. Concurrency & Scheduling
- Work‑stealing pool; each worker owns a **local query stack** to detect cycles (QE0007_Cycle).
- **Re‑entrancy:** Allowed; cycles are detected by QID presence in stack.
- **Shard‑local caches** reduce contention; promotion to global on completion.

## 6. janusd Integration (RPC)
- RPC `query.run(name, args, knobs)` returns `{result_bytes, result_cid, deps[], diag[]}`.
- Clients may pass **KnownCIDHints** to short‑circuit recomputation.
- Protocol is versioned; feature flags gate experimental queries.

## 7. Performance Targets
- **Hover** (`Q.Hover`) p95 ≤ **10 ms** @ 100k LOC (hot daemon, warm cache).
- **Dispatch** p95 ≤ **150 µs** for 8‑candidate families; ≤ **1 ms** for 64 candidates.
- Memory overhead of dep graph ≤ **1.5×** total Q entries (cap with compaction).

## 8. Security & Isolation
- Queries run in **No‑IO** mode. `Q.ComptimeEval` uses the **comptime sandbox** with policy CIDs.
- Capability checks for effect/cap queries must map to **explicit CapabilityCIDs** from ASTDB.

## 9. Errors (selected)
- **QE0001_UnknownQuery**
- **QE0003_NondeterministicAccess**
- **QE0005_BadArgsCanonicalization**
- **QE0007_Cycle**
- **QE0011_QuotaExceeded**
- **QI0101_DepGraphCorrupt** (invalidation)
- **QR0201_RPCSchemaMismatch**

## 10. EARS Acceptance Criteria

**Story A — Pure, stable identity**
- *When* `Q.TypeOf(NodeCID=X)` runs on two machines with identical ASTDB snapshots
- *Then* the **ResultCID** is identical and **ResultBytes** are byte‑equal.

**Story B — Canonical inputs only**
- *When* a client tries to invoke a query with a path or pointer
- *Then* the engine rejects it with **QE0005_BadArgsCanonicalization**.

**Story C — Memoization hit**
- *Given* `Q.Dispatch` computed once for (F,S)
- *When* called again with same QID
- *Then* it serves from cache with no re‑evaluation and records a **cache_hit** metric.

**Story D — Precise invalidation**
- *Given* formatting changes that do not alter **SemanticCIDs**
- *When* the project rebuilds
- *Then* downstream queries are **not** invalidated (no‑work rebuild holds).

**Story E — Hover latency**
- *Given* a 100k LOC workspace and hot daemon
- *When* `Q.Hover(FileCID, Offset)` is requested
- *Then* p95 latency ≤ 10 ms, p99 ≤ 25 ms.

**Story F — Cycle detection**
- *When* a query directly or indirectly depends on itself
- *Then* evaluation aborts with **QE0007_Cycle** and an explanatory diagnostic.

**Story G — Sandbox enforcement**
- *When* `Q.ComptimeEval` code reads FS without a granted capability in CtPolicyCID
- *Then* it fails with a sandbox error (mapped to QE0003).

## 11. Metrics
- `qe.cache_hit{query}` / `qe.cache_miss{query}`
- `qe.eval_time_us{query}` histogram
- `qe.invalidations{reason}`
- `qe.dep_edges_total`, `qe.dep_graph_bytes`, `qe.result_bytes_total`

## 12. Implementation Notes
- **ResultBytes** may contain CIDs (e.g., TypeCID). Avoid embedding raw pointers.
- **DepSet** stores **both** base CIDs and QIDs; invalidation honors both.
- **Cold start** builds: enable CAS-backed result cache for `Q.IROf` and `Q.Dispatch`.

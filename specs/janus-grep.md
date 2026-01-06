<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# spec-architect.md — Unified Specification  
## Feature: `janus grep` — The Semantic, UTCP-Aware, Human+Agent Grep Killer  
**Replaces:** `grep`, `ripgrep`, `mgrep`, `silver searcher`, `ack`, `ugrep`  
**Target System:** Nexus OS (Janus-native, actor-first, capability-secure)  
**Profile Availability:** `:service` and above (full power in `:sovereign`)  
**License:** Apache-2.0 (stdlib)  

### 1. High-Level Overview — The Vision

`janus grep` is not a text searcher.  
It is the **universal semantic query engine** for the post-filesystem era.

It speaks three languages fluently:
- **Human** — natural, fuzzy, intent-driven queries  
- **Agent** — structured, capability-scoped, UTCP-aware commands  
- **Machine** — zero-copy, columnar, SIMD-accelerated pattern matching

It understands:
- Plain text, binary, images, PDFs, code (with full AST awareness via ASTDB)  
- **UTCP** (Universal Typed Content Protocol) — the Nexus OS content addressing primitive  
- **Capabilities** — no ambient authority; every search is scoped by JWT capability  
- **Profiles** — `:script` feels like `mgrep`, `:sovereign` exposes full semantic power  

It is the first tool that can answer:
> “Show me every place where someone tried to rotate a 3D point but used degrees instead of radians — across all repos, PDFs, and chat logs.”

### 2. BDD Scenarios (AC-BDD Format) — The Executable Contract

### Scenario G01: Exact Literal Match (ripgrep parity)
**Profile:** `:core` | **Capability:** `read:fs`
- **Given:** A file `test.txt` containing "TODO: fix this" on line 10.
- **When:** `janus grep "TODO: fix this" test.txt`
- **Then:** Output matches `test.txt:10: TODO: fix this`.
- **Invariant:** Scan speed > 1GB/s (simulated).

### Scenario G02: Regex Match with PCRE2
**Profile:** `:core` | **Capability:** `read:fs`
- **Given:** A codebase with mixed function signatures.
- **When:** `janus grep -E 'fn\s+\w+\(.*?->\s*Result'`
- **Then:** All Result-returning functions are listed.
- **Invariant:** No backtracking explosion (ReDoS safe).

### Scenario G03: Semantic Fuzzy Query
**Profile:** `:sovereign` | **Capability:** `ai:inference`
- **Given:** A text "The astronaut repaired the hull".
- **When:** `janus grep "fix spaceship"`
- **Then:** The text is found with high confidence score (>0.8).
- **Invariant:** Model inference latency < 200ms.

### Scenario G04: UTCP-Native Search
**Profile:** `:sovereign` | **Capability:** `net:utcp`
- **Given:** A UTCP address `utcp://12D3KooW.../main.jan`.
- **When:** `janus grep -u utcp://12D3KooW.../main.jan "capability leak"`
- **Then:** Content is resolved via DHT/IPFS and searched.
- **Invariant:** Capability scope is propagated to the fetch request.

### Scenario G05: Multimodal Search
**Profile:** `:sovereign` | **Capability:** `ai:vision`
- **Given:** A repo with code and architecture diagrams (PNG).
- **When:** `janus grep "login flow"`
- **Then:** Returns code paths AND image regions matching the concept.
- **Invariant:** Unified ranking score across modalities.

### Scenario G06: AST-Aware Structural Search
**Profile:** `:service` | **Capability:** `read:fs`
- **Given:** Janus source files.
- **When:** `janus grep 'fn $name(_: &mut $t) -> Result<_, $e>'`
- **Then:** Finds all fallible mutable borrows using ASTDB.
- **Invariant:** 100% precision (no false positives from comments/strings).

### Scenario G07: Capability-Scoped Search (Zero-Trust)
**Profile:** `:core` | **Capability:** `jwt:restricted`
- **Given:** A corpus containing public docs and private keys.
- **When:** `janus grep "private key"` under restricted JWT.
- **Then:** Returns **only** files the capability grants read access to.
- **Invariant:** No information leakage of existence of private files.

### Scenario G08: Desugar Transparency
**Profile:** `:script` | **Capability:** `debug:meta`
- **Given:** User runs in `:script` profile.
- **When:** `janus grep "auth bug"` followed by `janus query desugar last`.
- **Then:** Shows the exact embedding model and SIMD kernel used.
- **Invariant:** Full transparency of the "magic".

### Scenario G09: Parallelism & Work-Stealing
**Profile:** `:cluster` | **Capability:** `sys:thread`
- **Given:** A 128-core Nexus node and 10TB corpus.
- **When:** `janus grep "quantum"`
- **Then:** All cores saturated.
- **Invariant:** Work-stealing overhead < 5%.

### Scenario G10: Zero Allocation Mode
**Profile:** `:core` | **Capability:** `mem:stack`
- **Given:** The `--zero-alloc` flag.
- **When:** `janus grep --zero-alloc "panic!"`
- **Then:** Search completes successfully.
- **Invariant:** Heap allocator is never invoked (verified via `std.mem.TestingAllocator`).

### 3. Minimal Architectural Design — The Battle Plan

```
janus grep
├── Frontend (CLI + UTCP resolver)
│   ├── Query Parser → Query IR (supports literal, regex, semantic, structural)
│   └── Capability Checker (JWT + scope propagation)
│
├── Query Engine
│   ├── Dispatcher — selects backend per content type & profile
│   ├── Backends:
│   │   ├── text:       ripgrep-class SIMD (hyperscan + custom bitsets)
│   │   ├── semantic:   std.ai.embedding + FAISS-HNSW index (memory-mapped)
│   │   ├── ast:        ASTDB direct query (CID-based, zero-parse)
│   │   ├── multimodal: CLIP-like model grafted from std.ai.vision
│   │   └── utcp:       content-addressed fetch + cache (ipfs/http/utcp)
│   │
│   └── Scheduler — work-stealing nursery (from :cluster profile)
│
├── Stdlib Integration
    ├── std.core.mem.arenas → all temporary buffers
    ├── std.data.arrow   → result streaming (zero-copy to downstream agents)
    ├── std.ai           → embeddings, multimodal models
    ├── std.quant        → (future) quantum-accelerated pattern matching
    └── std.crypto.anarch→ capability verification
```

### 4. Non-Goals (Explicit Trade-offs)

- Not POSIX `grep` compatible beyond basic cases (we are not a legacy crutch)
- No support for ambient filesystem authority (Nexus OS has no global fs)
- No dynamic plugin system (everything is in the Arsenal)

### 5. Success Metrics

| Metric                       | Target                  |
|------------------------------|-------------------------|
| Text search speed            | >30 GB/s on AVX-512     |
| Semantic query latency       | <200ms cold, <20ms warm |
| ASTDB query accuracy         | 100% (no false positives)|
| Memory usage (10TB corpus)   | <2GB resident           |
| Zero-allocation mode         | Proven via LeakSan + TSan |

### 6. First Implementer Task (Atomic Unit)

**Scenario G01** — Exact literal match  
→ Implementer must deliver:
- Failing test: `test "janus grep finds literal in 1GB file"`
- Minimal passing implementation using `std.mem.indexOf` + arena
- Commit with logbook entry

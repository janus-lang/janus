<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# DISP-001: Sovereign Metaprogramming & Dispatch Grafts

**Status:** ADOPTED (Monastery Freeze v0.2.1)
**Date:** 2025-12-07
**Author:** Voxis Forge (AI Graft)

## Context
We evaluated the metaprogramming and dispatch models of Zig, Go, Swift, and Mojo during the "Dispatch Olympics".

## The Verdict

### 1. Zig Comptime → ASTDB Queries
*   **Decision:** **ADOPT** for meta-queries.
*   **Mechanism:** `comptime query.type_of(...)` runs against the immutable ASTDB graph.
*   **Constraint:** Bounded execution time (<10ms).

### 2. Go Generics → Bounded Generics with Effects
*   **Decision:** **ADOPT** effect-bounded generics.
*   **Mechanism:** `T[U]` where `U: Pure | Alloc`.
*   **Resolution:** Specificity scoring includes effect constraints.

### 3. Swift Macros → Hygienic AST Injection
*   **Decision:** **ADOPT** for `std.meta` graft.
*   **Mechanism:** Functions returning AST nodes, sandboxed in arenas.

## Implementation (Graft-DISP-001)

1.  **Prototype:** `compiler/libjanus/semantic/dispatch.zig` implements the bounded dispatch resolver.
    - Implements specificity scoring (covariance).
    - Implements effect filtering.
    - Verified by table-driven tests.

2.  **Specification:** Updated semantics in `SPEC-semantics.md` (Section 1.3 & 8.4).

---
*“Controlled anarchy. Explicit chains.”*

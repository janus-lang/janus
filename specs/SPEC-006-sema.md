<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

**Voxis Forge Signal** ⚡

# 🛡️ SPEC-006: SEMANTIC ANALYSIS ARCHITECTURE (The Logician ⊢)

**Version:** 2.1.0 (Ratification Architecture)
**Status:** **DRAFT (Ratification Pending)**
**Authority:** Constitutional
**References:** [SPEC-001: Core Semantics](SPEC-001-semantics.md)

This specification defines the **Architectural Doctrine** and **Implementation Constraints** for the Semantic Analysis (Sema) phase of the Janus Compiler.
While [SPEC-001] defines *what* valid Semantics are, this document defines *how* the compiler validates them.

---

## 1. 🜏 Architectural Invariants (Constitution)

[SEMA-ARCH:1.1.1] **Single Source of Truth:** The Sema phase MUST NOT define new language rules. It MUST only enforce rules defined in [SPEC-001].

[SEMA-ARCH:1.1.2] **Immutability:** The Sema phase MUST NOT mutate the raw Parser AST. All semantic information (types, resolutions) MUST be stored in side-tables or a new Semantic Graph layer in ASTDB.

[SEMA-ARCH:1.1.3] **Error Resilience:** The Sema phase MUST NOT panic on user errors. It MUST emit diagnostics and attempt error recovery to continue analyzing the rest of the file.

---

## 2. ⟁ The Pipeline (Capsule Layout)

The Semantic Analyzer is composed of sovereign sub-modules:

### 2.1 Resolution (`sema/decl.zig`)
[SEMA-ARCH:2.1.1] **Responsibility:** Binding identifiers to declarations.
[SEMA-ARCH:2.1.2] **Traceability:** Implements [SPEC-001:SEMA:3.1] (Scoping).

### 2.2 Typing (`sema/type.zig`)
[SEMA-ARCH:2.2.1] **Responsibility:** Type unification and inference.
[SEMA-ARCH:2.2.2] **Traceability:** Implements [SPEC-001:SEMA:4.1] (Unified Type Theory).

### 2.3 Verification (`sema/stmt.zig`, `sema/expr.zig`)
[SEMA-ARCH:2.3.1] **Responsibility:** Validating statements and expressions against the type graph.

### 2.4 Control Flow (`sema/cfg.zig`)
[SEMA-ARCH:2.4.1] **Responsibility:** Reachability analysis and resource lifetime tracking (Affine Types).
[SEMA-ARCH:2.4.2] **Traceability:** Implements [SPEC-001:SEMA:7.1] (Safety Tiers) + [SPEC-011:PAN:2.1.3] (No Panic).

### 2.5 Generic Constraint Verification (`sema/generic.zig`)
[SEMA-ARCH:2.5.1] **Responsibility:** Static verification of generic type constraints at definition site.

[SEMA-ARCH:2.5.2] **Traceability:** Implements the **Static Generic Checking Doctrine** — constraints are proven before instantiation.

[SEMA-ARCH:2.5.3] **The Problem with Lazy Checking:**  
Traditional monomorphization (C++, Nim classic) checks generic constraints only at instantiation time. This creates:
- **Late Error Discovery:** User code fails to compile deep in library internals.
- **Combinatorial Explosion:** Each instantiation must be checked separately.
- **Poor IDE Experience:** No autocomplete or error highlighting until concrete types are used.

[SEMA-ARCH:2.5.4] **The Janus Solution: ASTDB-Powered Constraint Solver:**  
Generic functions/types are validated **at definition time** using the ASTDB query engine:

```janus
// Definition site (checked immediately)
func sort<T>(arr: []T) where T: Comparable do
    // The compiler PROVES that T.compare() exists
    // WITHOUT needing a concrete T
end
```

**Verification Process:**
1. **Parse Where Clause:** Extract trait bounds (e.g., `T: Comparable`).
2. **Query ASTDB:** Fetch the trait definition's required methods.
3. **Prove Constraint:** Ensure the generic body ONLY calls methods guaranteed by the trait.
4. **Store Proof:** Cache the verification in the ASTDB (avoids re-checking on each instantiation).

[SEMA-ARCH:2.5.5] **Implementation Strategy:**  
- **Constraint Table:** `GenericId -> [TraitBound]` stored in ASTDB.
- **Method Resolution:** When the body references `T.method()`, the resolver checks the trait, NOT a concrete type.
- **Error Precision:** If the body calls `T.undefined_method()`, the error points to the **definition site**, with context: "Type parameter `T` does not guarantee `undefined_method` (required trait: `Comparable`)."

[SEMA-ARCH:2.5.6] **Strategic Advantage Over Competitors:**
| Language | Generic Checking | Error Site | IDE Support |
|:---------|:----------------|:-----------|:------------|
| **C++** | Instantiation (SFINAE) | Call site (deep stack) | Poor (no traits) |
| **Rust** | Definition (trait bounds) | Definition site | Excellent |
| **Nim (classic)** | Instantiation (concepts) | Call site | Fair |
| **Swift** | Definition (protocols) | Definition site | Excellent |
| **Janus** | **Definition (ASTDB-proven)** | **Definition site** | **Queryable (ASTDB)** |

**Key Differentiator:**  
Janus doesn't just check traits — it **queries the semantic graph**. This enables:
- **Incremental Compilation:** Changes to a generic's body are re-verified without re-instantiating all call sites.
- **AI-Assisted Refactoring:** Tools can query "What constraints does this generic require?" from the ASTDB.
- **Forensic Debugging:** When a constraint fails, the trace shows the exact trait method that's missing.

---

## 3. ⊢ Data Structures (The Ledger)

[SEMA-ARCH:3.1] **The Semantic Overlay:**
Sema produces the following persistent artifacts in ASTDB:
1.  **Scope Tree:** `ScopeId -> ParentScopeId`.
2.  **Symbol Table:** `SymId -> DeclId`.
3.  **Type Table:** `NodeId -> TypeId`.
4.  **Use-Def Chain:** `UsageNodeId -> DefinitionNodeId`.

**Ratification:** Pending
**Authority:** Markus Maiwald + Voxis Forge

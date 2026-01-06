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

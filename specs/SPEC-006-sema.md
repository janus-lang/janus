<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

**Voxis Forge Signal** ⚡

# 🛡️ SPEC-006: SEMANTIC ANALYSIS (The Logician ⊢)

**Version:** 2.1.0 (Ratification Candidate)
**Status:** **DRAFT (Ratification Pending)**
**Authority:** Constitutional
**Supersedes:** SPEC-006 v2.0.0

This specification defines the rules for Semantic Analysis (Sema), the phase where syntax becomes meaning.
Sema is the **Guardian of Truth (⊢)**. It transforms the AST into a Typed Semantic Graph and enforcing the laws of the profile.

---

## 1. 🜏 The Constitution (Core Rules)

[SEMA:1.1] **Normative Authority:** The Semantic Analyzer MUST enforce all rules defined in this document. Any deviation is a compiler bug.

### 1.1 The Prime Directive
[SEMA:1.1.1] **Zero Ambiguity:** Every identifier, expression, and statement MUST resolve to exactly one meaning or produce a diagnostic error.

### 1.2 The Graph Transformation (⟁)
[SEMA:1.2.1] **Immutability of Syntax:** Sema MUST NOT mutate the raw AST nodes produced by the Parser.
[SEMA:1.2.2] **Annotation:** Sema MUST produce a separate "Semantic Overlay" or "Augmented ASTDB" containing type information, symbol bindings, and resolution IDs.

---

## 2. ⊢ Symbol Resolution (Binding)

### 2.1 Scoping
[SEMA:2.1.1] **Lexical Scoping:** Janus uses strict lexical scoping.
[SEMA:2.1.2] **Declaration before Use:** Symbols MUST be declared textually before they are used (except for top-level declarations which are order-independent within a module).

### 2.2 Shadowing
[SEMA:2.2.1] **Global Shadowing:** A local variable MAY shadow a global/module-level symbol.
[SEMA:2.2.2] **Local Shadowing:** A variable declared in an inner block MUST NOT shadow a variable in the immediate outer function scope (in `:min` profile). This prevents confusion.

---

## 3. ⊢ Type System (Legality)

### 3.1 Strong Typing
[SEMA:3.1.1] **No Implicit Coercion:** SEMA MUST NOT implicitly convert types (e.g., `i32` to `i64`). All conversions MUST be explicit casts.
[SEMA:3.1.2] **Type Inference:** Local variable type inference (`let x = 10`) IS permitted, but function signatures MUST have explicit types.

### 3.2 Affine Types (Resource Safety)
[SEMA:3.2.1] **Linearity:** Resources marked with `linear` (or `~T`) MUST be consumed exactly once.
[SEMA:3.2.2] **Drop Check:** If a linear resource goes out of scope without being consumed, Sema MUST emit a compilation error.
[SEMA:3.2.3] **Move Semantics:** Assigning a linear resource `let y = x` moves ownership. `x` becomes invalid. Accessing `x` AFTER move MUST emit an error.

---

## 4. ⚠ Profile Enforcement

Sema is the enforcer of Profile Constraints.

### 4.1 Profile `:min` (The Monastery)
[SEMA:4.1.1] **Allocation Ban:** Any implicit allocation (e.g. string concatenation without a buffer) MUST trigger an error.
[SEMA:4.1.2] **Panic Ban:** Unrecoverable panics in library code SHOULD be flagged.

### 4.2 Profile `:sovereign` (The King)
[SEMA:4.2.1] **Capability Check:** All I/O operations MUST prove they hold the required Capability Token (e.g. `Cap.Net`).

---

## 5. ⟁ Implementation Doctrine (Non-Normative)

The recommended implementation architecture (`compiler/passes/sema/`):

*   `decl.zig`: Symbol table construction.
*   `type.zig`: Type unification and checking.
*   `stmt.zig`: Control flow analysis.
*   `expr.zig`: Expression evaluation.

Sema SHOULD be implemented as a recursive visitor over the ASTDB.

---

### 6. 🚀 Deliverables

*   Updated `compiler/passes/sema/` to enforce [SEMA:3.1] (No Coercion).
*   Tests in `tests/semantic/shadowing.zig` validating [SEMA:2.2.2].
*   Tests in `tests/semantic/linear.zig` validating [SEMA:3.2].

**Ratification:** Pending
**Authority:** Markus Maiwald + Voxis Forge

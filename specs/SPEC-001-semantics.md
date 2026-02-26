<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — Core Semantics (SPEC-001)

**Version:** 2.0.0  

## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).

**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-semantics v0.2.0

## 1. Introduction

This document defines the **Canonical Semantic Model** for the Janus programming language. It establishes the rules for evaluation, name resolution, typing, dispatch, and effect tracking across all profile tiers.

### 1.1 Normative References
All definitions in this document SHALL follow the normative language defined in [SPEC-000: Meta-Specification](meta.md).

## 2. Evaluation Model

[SEMA:2.1.1] The evaluation order of expressions SHALL be **strict** and **left-to-right**.

[SEMA:2.1.2] Function argument evaluation and operator operand evaluation SHALL proceed left-to-right with no reordering allowed, unless the callee is proven `{.effects: pure.}` by explicit annotation and compiler verification.

[SEMA:2.1.3] Purity is a property of the **declaration**. A callsite MUST NOT assert purity for a non-pure callee; it MAY only benefit from the callee's declared purity for optimization purposes (e.g., memoization or reordering).

## 3. Name Resolution & Scoping

[SEMA:3.1.1] Janus SHALL follow **lexical scoping** with the following precedence for identifier resolution:
1.  Local variables and parameters in the current scope.
2.  Module-local declarations.
3.  Explicitly imported identifiers (aliases).
4.  Package-level defaults.

[SEMA:3.1.2] Shadowing of local variables in nested scopes SHOULD trigger a warning but is permitted. Shadowing of built-in reserved keywords SHALL be a compile-time error.

## 4. Unified Type Theory ⊢

Janus enforces a strict separation between **Data** (Bits/Layout) and **Behavior** (Dispatch/Traits).

### 4.1 Data Types (Structural)
[SEMA:4.1.1] Data types unify by **structure**. A sealed table `Shape { x: i32 }` in module A is identical to a sealed table `Shape { x: i32 }` in module B.

1.  **Value Types (Data):** These are copied by value. No identity.
    - Primitives: `i64`, `f64`, `bool`, `String`.
    - Aggregates: `Table`, `Array`, `Tuple`.
2.  **Resource Types (Identity):** These are moved by default. Unique identity tracked by the compiler.
    - Resources: `File`, `Socket`, `ActorHandle`.
3.  **View Types (Access):** Slices and references into existing memory.
    - Managed via the safety dials (see SPEC-002: Safety).

### 4.2 Nominals & Traits (Behavior)
[SEMA:4.2.1] Dispatch SHALL NOT be performed on raw structural data. All behavior MUST be bound to a nominal Type or Trait implementation.

[SEMA:4.2.2] **Orphan Rule:** A module SHALL only implement a Trait `T` for Type `X` if it defines either `T` or `X`.

## 5. Dispatch & Resolution (The "No Guessing" Law)

### 5.1 Multiple Dispatch
[SEMA:5.1.1] Janus SHALL resolve function calls based on the signatures of **all** arguments (Multiple Dispatch).

[SEMA:5.1.2] The resolution algorithm SHALL select the **most specific** implementation by subtyping distance.

[SEMA:5.1.3] If two or more candidates are incomparable (no clear "most specific" implementation), the compiler SHALL produce error **E2001: AmbiguousDispatch**. The compiler SHALL NOT use source order to break ties.

[SEMA:5.1.4] The system SHALL perform **zero implicit conversions** during dispatch resolution. (e.g., an `i64` will not satisfy a parameter expecting `f64` without an explicit cast or a specific implementation).

## 6. The Effect System ⧉

[SEMA:6.1.1] Effects SHALL be tracked through the call graph. If function `f` calls `g`, and `g` has effect `E`, then `f` implicitly possesses effect `E` unless handled.

### 6.2 The Effect Lattice
[SEMA:6.2.1] Effects are organized into a lattice where `pure` is the root (identity).
- `pure` ⊑ `cpu` (Pure computation)
- `cpu` ⊑ `io` (Input/Output)
- `io` is the parent of `fs` (Filesystem) and `net` (Network).

### 6.3 Capability-Gated Effects
[SEMA:6.3.1] Performing an effect `E` SHALL require a corresponding capability token `CapE` provided via the **Context** or as an explicit parameter.

[SEMA:6.3.2] Ambient authority is FORBIDDEN ∅. Functions SHALL NOT access the filesystem or network without an explicitly passed or injected capability.

## 7. Memory Model & Safety ⚠

[SEMA:7.1.1] Janus supports three safety tiers, selectable via the `{.safety: tier.}` dial:

1.  **`:raw`**: No runtime checks. Manual memory management. Violations result in Undefined Behavior (UB). ⚠
2.  **`:checked`**: Runtime bounds, null, and overflow checks enabled. Violations result in controlled traps. ⊢
3.  **`:owned`**: Compile-time ownership and lifetime analysis. Linear/Affine types enforced. 🜏

[SEMA:7.1.2] In `:raw` mode, integer overflow SHALL wrap. In all other modes, it SHALL trap unless explicitly annotated (e.g., using `std.math.wrapping_add`).

## 8. Metaprogramming ⟁

[SEMA:8.1.1] Metaprogramming SHALL be performed via `comptime` execution of standard Janus code.

[SEMA:8.1.2] `comptime` blocks SHALL operate on the **typed semantic graph**, not on token or AST text.

[SEMA:8.1.3] `comptime` execution SHALL be subject to the same capability security model as runtime code, with permissions declared in project policy files.

---

**Ratified:** 2026-01-06  
**Authority:** Markus Maiwald + Voxis Forge

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Specification — Core Language Semantics
**Version:** 0.1.0
**Profile key:** all (min|go|full)
**Source grammar:** SPEC-syntax.md

This document defines the fundamental semantic laws that govern Janus across all profiles: evaluation order, name resolution, undefined behavior policy, memory model, and core type system rules.

---

## 1. Evaluation Semantics

### 1.1 Evaluation Order
**Law: Left-to-right, strict evaluation**
- All expressions evaluate left-to-right, including function arguments
- No reordering optimizations unless `{.effects: pure.}` proves safety
- Side effects occur in source order

```janus
// Guaranteed evaluation order
let result = f(a(), b(), c())  // a() → b() → c() → f()
```

### 1.2 Name Resolution
**Law: Lexical scoping with module precedence**
- Resolution order: local scope → module-local → imported alias → package default
- Shadowing allowed but **must warn** unless `{.shadow: allow.}`
- No dynamic scoping or global namespace pollution

### 1.3 Visibility Rules
**Law: Explicit exports only**
- `export` keyword required at declaration site
- No re-export by default (use explicit `pub use` forwarding)
- Module boundaries are security boundaries

---

## 2. Undefined Behavior Policy

### 2.1 Safety Regions
**In `{.safety: raw.}` regions only:**
- Out-of-bounds access
- Null pointer dereference
- Use-after-free
- Misaligned `repr(packed)` access
- Data races

**Everywhere else:**
- No undefined behavior
- Violations **trap** with clear diagnostics
- Compile-time prevention where possible

---

## 3. Type System Laws

### 3.1 Sum Types
- **Closed by default**: `type Result = Ok(T) | Err(E)`
- **Open sums**: `open sum Event` with registry for variants
- **Exhaustiveness**: `match` must handle all cases (wildcard only in open sums)

### 3.2 Multiple Dispatch Resolution
**Law: Most-specific wins, ties are errors**
- Pick most-specific by subtyping distance
- Ties = compile error E0021 (force disambiguation)
- No implicit conversions during dispatch
- Static dispatch for sealed types, compressed tables for open types

---

## 4. Memory Model

### 4.1 Ownership System
- `unique T` moves by default
- Copying requires explicit `{.dup.}` implementation
- Borrowing via `&T/&mut T` only in `{.safety: owned.}` regions

### 4.2 Concurrency Model
- C11 memory model with seq-cst fences available
- Default atomics are acquire/release
- Exposed as functions: `atomic.load/store/fence`

---

This specification establishes the non-negotiable semantic foundation of Janus.

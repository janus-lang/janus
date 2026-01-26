<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Specification: Core Data Doctrine (Honest Data)

**Status:** APPROVED (2025-12-07)
**Version:** 0.1.0
**Influences:** C++ "vector<bool>" Pitfalls, Data-Oriented Design

---

## 1. The Doctrine of Syntactic Honesty

Janus adheres to **Revealed Complexity**. Data types must never lie about their memory layout, access cost, or semantics for the sake of hidden optimization.

### 1.1 The "No Magic Specialization" Rule

**The `vector<bool>` Trap:**
In C++, `std::vector<bool>` specializes to distinct bits, returning proxy objects instead of references. This breaks generic contracts.

**Janus Decree:**
* **`Array[Bool]`** MUST imply a contiguous array of `bool` capabilities (typically bytes).
* **Reference Equality:** `&array[i]` must return a valid pointer to a `bool`.
* **Optimization is Opt-In:** If bit-packing is required, it must be a distinct type:
    * `BitSet`
    * `Array[u1]` (if `u1` is a valid storage type)
    * `Tensor[Bool, Packed]`

**Rule:** A generic container `T[U]` must behaviorally resemble `T[V]` for any `U` and `V`. No behavioral shifts based on type parameters without explicit trait bounds asking for it.

### 1.2 Explicit Initialization

**The Initialization Order Fiasco:**
C++ initializes based on declaration order, not constructor list order, leading to uninitialized reads.

**Janus Decree:**
* **Struct Initialization:** Must use explicit field naming or strict declaration order.
    * Preferred: `Point { .x = 1, .y = 2 }`
* **Compiler Enforcement:** The compiler MUST error if initialization depends on a field that hasn't been initialized yet (DAG dependency check) OR simply enforce strict declaration order.
* **Zero Values:** All memory is zeroed by default unless `undefined` is explicitly requested.

---

## 2. Layout & Alignment

### 2.1 The "What You See Is What You Get" Struct

```janus
struct User {
    id: u64,
    active: bool,
}
```

* **Standard Layout:** C-compatible by default (reorder allowed only if `packed` or `extern` is NOT specified, but Janus prefers predictable C-like layout for `:core`).
* **Padding:** Explicitly visible in "Inspect" tooling. A `bool` is a byte. Padding bytes are zeroed to prevent data leaks.

### 2.2 Profile Considerations

* **`:core` / `:sovereign`:**
    * Zero magic.
    * No hidden vtables (interfaces are explicit `struct` with function pointers or standard ABI).
* **`:script`:**
    * "Honest Sugar" applies. Arrays might technically be `ArrayList` behind the scenes, but the *semantics* (copy-by-value vs reference) remain consistent.

---

## 3. Reflection & Visibility

**The Testing Gap:**
C++ makes testing private members hard.

**Janus Decree:**
* **ASTDB as Oracle:** Testing tools have privileged access to the ASTDB.
* **White-Box Testing:** Tests can query private members because they operate on the *source of truth* (AST), not just the binary interface.
* **Syntactic visibility != Semantic visibility:**
    * `pub` means callable by other modules.
    * Internal details are visible to the **Inspector** (`janus inspect`) and **Test Runner**.

---

## 4. Build & Metaprogramming

### 4.1 The Build System is Specification

* `janus.kdl` is the only build file.
* No external CMake/Make reliance for pure Janus projects.
* Build logic is declarative, ensuring reproducible builds.

### 4.2 Generics & Concepts

* **Bounded Generics:** No SFINAE. Constraints (Traits/Interfaces) are checked at the call site.
* Error messages must point to the *constraint violation*, not a template expansion failure 50 levels deep.

---

**Summary:**
Janus types are **honest**. Optimization is an explicit choice, not a compiler trick.

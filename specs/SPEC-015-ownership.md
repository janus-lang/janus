<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

**Voxis Forge Signal** ⚡

# 🛡️ SPEC-015: OWNERSHIP & AFFINITY (The Covenant 🜏)

**Version:** 0.2.0 (Semantic Lock Draft)
**Status:** **DRAFT**
**Tier:** 3 (Meaning Before Shape)
**Authority:** Constitutional
**References:** [SPEC-001: Semantics](SPEC-001-semantics.md), [SPEC-006: Analysis](SPEC-006-sema.md)

---

## 1. Introduction

This specification defines the **Ownership Model**, **Affine Types**, and **Lifetime Analysis** rules enforced in the `:owned` safety tier. It serves as the "Semantic Lock" for Janus v0.3.0, defining how resources are managed without a garbage collector.

Janus rejects the "Implicit Drop" magic of C++ (`RAII`). Resources must be handled with geometric precision. If a type is Linear (`~T`), it MUST be consumed effectively. Use-after-move and double-free are impossible by construction.

---

## 2. 🜏 The Three Laws of Ownership

[OWN:2.1] **Single Ownership:** Every value has exactly **one** owner scope at any given instruction pointer.
[OWN:2.2] **Move Semantic:** Assignment (`let y = x`) transfers ownership. The source `x` becomes **Uninitialized (Dead)**. Any subsequent access to `x` is a compile-time error.
[OWN:2.3] **Affine Destruction:** All linear resources (marked `~T`) **MUST** be consumed (moved or explicitly destroyed) before their owner scope ends. Implicit drop is **FORBIDDEN (∅)** for linear types.

---

## 3. ⊢ Affine Types (The Hot Potato)

### 3.1 Definition

[OWN:3.1.1] A type `T` is **Linear** (or Affine) if it represents a finite, non-copiable resource (File Handle, Network, Heap Allocation).
[OWN:3.1.2] **Sigil Syntax:** The `~` sigil denotes a linear type constraint.
*   `~File`: A file handle that must be closed.
*   `~Box(T)`: An owned heap allocation.
*   `~Socket`: A network socket.

[OWN:3.1.3] **Propagation:** If a struct contains a field of type `~T`, the struct itself becomes `~Struct`. Linearity effectively "infects" the container.

### 3.2 Consumption Rules

[OWN:3.2.1] A linear binding `let f: ~File` MUST end its life in one of three ways:
1.  **Move:** Passed to another function (`write(f, ...)`).
2.  **Destructure:** Unpacked via `match`.
3.  **Close:** Explicit method call consuming `self` (`f.close()`).

[OWN:3.2.2] **Leak Check:** If control flow reaches the end of scope and a `~T` variable is still **Live**, the compiler MUST emit error **E3001: LinearLeak**.

```janus
func process() !void do
    let f: ~File = File.open("data.txt")!
    // Error: 'f' is dropped here implicitly. E3001.
    // Fix: f.close()
end
```

---

## 4. ⊢ Borrowing & Views (The Looking Glass)

### 4.1 Immutable Borrows (`&T`)

[OWN:4.1.1] **Shared Read:** Multiple `&T` references may exist simultaneously.
[OWN:4.1.2] **Freezing:** While `&T` is live, the owner is **Frozen**. No mutation or move allowed on the owner.

### 4.2 Mutable Borrows (`&mut T`)

[OWN:4.2.1] **Exclusive Write:** Only **one** `&mut T` reference may exist at a time.
[OWN:4.2.2] **No Aliasing:** While `&mut T` is live, no other references (mutable or immutable) to the same data may exist.
[OWN:4.2.3] **Owner Lock:** While `&mut T` is live, the owner cannot be accessed.

### 4.3 The Law of Exclusivity

[OWN:4.3.1] **Readers-Writer Lock:** At any program point, you may have:
*   (N) Readers `&T`
*   **XOR**
*   (1) Writer `&mut T`

Never both.

---

## 5. ⊢ Lifetimes (The Timeline)

### 5.1 Named Lifetimes

[OWN:5.1.1] A Lifetime is a named region of code execution, denoted by `'name`.
[OWN:5.1.2] **Syntax:** `&'a T` reads as "a reference to T that lives at least as long as 'a".

```janus
func longest<'a>(x: &'a String, y: &'a String) -> &'a String
```

### 5.2 The 'static Lifetime

[OWN:5.2.1] The `'static` lifetime lasts for the entire program execution. String literals have type `&'static str`.

### 5.3 Lifetime Elision (The 80/20 Rule)

[OWN:5.3.1] To reduce verbosity, lifetimes can be elided (omitted) in function signatures if unambiguous.
[OWN:5.3.2] **Rule 1 (1-to-1):** If there is exactly one input lifetime, it is assigned to all output lifetimes.
*   `func get(x: &T) -> &T` desugars to `func get<'a>(x: &'a T) -> &'a T`
[OWN:5.3.3] **Rule 2 (The Self):** If there asks a `self` parameter (method), its lifetime is assigned to all output lifetimes.
*   `func get(self: &Context) -> &Data` desugars to `func get<'a>(self: &'a Context) -> &'a Data`

---

## 6. ⟁ Ghost Memory (Verification Architecture)

[OWN:6.1.1] Semantic Analysis tracks ownership state using **Ghost Variables** in the Control Flow Graph (CFG). This allows flow-sensitive analysis (similar to Rust's NLL).

[OWN:6.1.2] **State Tracking:**
Each linear variable `x` has a ghost state `σ(x)`:
*   `Live`: Initialized and usable.
*   `Moved`: Ownership transferred. Reading is illegal.
*   `Dropped`: Explicitly consumed.
*   `Partial(Field)`: Only some fields moved (for structs).

[OWN:6.1.3] **Control Flow Merge:**
At a CFG merge point (e.g., end of `if/else`), the state `σ(x)` must be consistent.
*   If `x` is `Moved` in `then` block but `Live` in `else` block, `x` is considered **Maybe-Moved** after the merge.
*   Accessing a **Maybe-Moved** value is a compile-time error.

---

## 7. ⚠ Unsafe Escapes

### 7.1 Raw Pointers (`*T`)

[OWN:7.1.1] In `:sovereign` profile, raw pointers bypass ownership checks.
[OWN:7.1.2] Pointers are neither linear nor tracked. They are simply addresses.
[OWN:7.1.3] **Dereferencing:** Requires `unsafe` block.

---

## 8. Profiles

### 8.1 :core / :service
*   **Enforced:** All Laws (1-3).
*   **Leak Check:** Strict.

### 8.2 :script
*   **Relaxed:** Affine types are effectively reference-counted or GC-backed (depending on backend).
*   **Drop:** Cleanups may happen automatically (RAII enabled for `:script`).

---

**Ratified:** Pending
**Authority:** Markus Maiwald + Voxis Forge

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

**Voxis Forge Signal** ⚡

# 🛡️ SPEC-015: OWNERSHIP & AFFINITY (The Covenant 🜏)

**Version:** 0.1.0
**Status:** **DRAFT**
**Tier:** 3 (Meaning Before Shape)
**Authority:** Constitutional

This specification defines the **Ownership Model**, **Affine Types**, and **Lifetime Analysis** rules enforced in the `:owned` safety tier.
Janus rejects the "Implicit Drop" magic of C++. Resources must be handled with geometric precision.

---

## 1. 🜏 The Three Laws of Ownership (Constitution)

[OWN:1.1] **Single Ownership:** Every value has exactly one owner scope at any given instruction pointer.
[OWN:1.2] **Move Semantic:** Assignment (`let y = x`) moves ownership. The source `x` becomes **Uninitialized (Dead)**. Any subsequent access to `x` is a compile-time error.
[OWN:1.3] **Affine Destruction:** All linear resources (marked `~T`) **MUST** be consumed (moved or explicitly destroyed) before their owner scope ends. Implicit drop is FORBIDDEN (∅) for linear types.

---

## 2. ⊢ Affine Types (The Hot Potato)

### 2.1 Definition
[OWN:2.1.1] A type `T` is **Linear** (or Affine) if it represents a finite resource (File Handle, Network, Allocation).
[OWN:2.1.2] Syntax: `~File`, `~Socket`, `~Box(T)`. (The `~` sigil denotes "This must be handled").

### 2.2 Consumption
[OWN:2.2.1] A linear binding `let f: ~File` MUST end its life in one of three ways:
1.  **Move:** Passed to another function (`write(f, ...)`).
2.  **Destructure:** Unpacked via `match`.
3.  **Close:** Explicit method call consuming `self` (`f.close()`).

[OWN:2.2.2] **Leak check:** If control flow reaches the end of scope and `f` is still live, the compiler MUST emit error **E3001: LinearLeak**.

---

## 3. ⊢ Borrowing & Views (The Looking Glass)

### 3.1 Immutable Borrows (`&T`)
[OWN:3.1.1] **Shared Read:** Multiple `&T` references may exist simultaneously.
[OWN:3.1.2] **No Mutation:** Data behind `&T` is immutable.

### 3.2 Mutable Borrows (`&mut T`)
[OWN:3.2.1] **Exclusive Write:** Only one `&mut T` reference may exist at a time.
[OWN:3.2.2] **No Aliasing:** While `&mut T` is live, the original owner cannot be accessed.

### 3.3 The Law of Exclusivity
[OWN:3.3.1] **Readers-Writer Lock:** You may have (N Readers) XOR (1 Writer). Never both.

---

## 4. ⟁ Ghost Memory (Verification)

[OWN:4.1.1] Semantic Analysis tracks ownership state using **Ghost Variables** in the Control Flow Graph (CFG).
[OWN:4.1.2] Each linear variable `x` has a ghost boolean `x_alive`.
*   Init: `x_alive = true`
*   Move: `x_alive = false`
*   Branch Merge: `x_alive` MUST be consistent across all incoming edges (or handled).

Type Checking is effectively **Dataflow Analysis** on these ghost variables.

---

## 5. ⚠ Unsafe Escapes

### 5.1 Raw Pointers (`*T`)
[OWN:5.1.1] In `:sovereign` profile, raw pointers bypass ownership checks.
[OWN:5.1.2] Dereferencing `*T` requires `unsafe` block.

**Ratification:** Pending
**Authority:** Markus Maiwald + Voxis Forge

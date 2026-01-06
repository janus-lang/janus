# Janus 0.2.0-alpha: The Logic Gate

**Release Date**: 2025-12-15
**Codename**: "The Turing Pivot"
**Status**: Feature Complete / Turing Complete

---

## 🚪 The Turing Pivot

With this release, Janus transitions from a linear execution pipeline to a fully **Turing Complete** language. We have unlocked the ability to express arbitrary logic through control flow, recursion, and dynamic dispatch.

This is the moment Janus becomes a *real* language.

---

## ✅ Delivered Capabilities

### 1. Turing Completeness
- **Full Control Flow**: `if/else` branches and `while` loops (in enabled profiles).
- **Recursion**: Stack-safe recursion with tail-call optimization hooks.
- **Dynamic Logic**: The language can now compute anything computable.

### 2. Sovereign Numerics
- **f64 Precision**: Native 64-bit floating point support.
- **VectorF64**: Dynamic handles for numerical vectors.
- **Math Library**: Basic `std.math` primitives.

### 3. Deterministic Safety
- **Resource Management**: `defer` keyword for guaranteed cleanup.
- **Heap Discipline**: `std.io` and `std.string` with explicit heap management.
- **Zero-Copy Architecture**: Tokenizer and Interpreter now share the same zero-copy semantics.

### 4. Advanced Semantic Engine
- **O(1) Type System**: Replaced N² lookups with canonical hashing.
- **Validation Engine**: Production-ready semantic analysis (15ms/10k nodes).
- **Error Deduplication**: Sophisticated hashing to prevent error floods.

---

## 🧠 The Dispatch Revolution (Task 19)

We implemented an **Advanced Dispatch Strategy Selection** engine that optimizes function calls based on:
1.  **Call Frequency**: Hot paths get optimized.
2.  **Complexity**: Inline small functions, dispatch large ones.
3.  **Cache Locality**: Optimize for instruction cache hits.

This includes **AI-Auditable Decision Tracking**, ensuring every optimization choice is logged and justifiable.

---

## 🏛️ Architectural Updates

- **Unified Semantics**: Merged disparate semantic specs into a single engine.
- **Performance Gates**: CI now enforces `validation_ms <= 25ms`.
- **Arena Management**: Unified memory model for semantic passes.

---

## 🔮 What's Next

The road to 0.3.0 is paved with **Ownership**. We are moving towards the "Semantic Lock" where affine types and borrow checking will be enforced at the compiler level.

---

**Forged By**: Voxis Forge & SSSF
**License**: LSL-1.0

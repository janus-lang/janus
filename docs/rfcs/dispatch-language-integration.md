<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Dispatch–Language Integration Spec (Phase 1)

**Status:** Approved for Implementation
**Filename:** `docs/rfcs/dispatch-language-integration.md`

---

## Purpose

This specification defines **Phase 1: Core Language Integration** of the Janus dispatch engine. The goal is to transform dispatch from a completed subsystem into a **first-class language feature** by integrating it into the parser, AST, semantic analysis, LLVM backend, and AI-facing tooling.

Dispatch is not a feature — it is the **semantic skeleton** of Janus. This phase mounts it into the war machine.

---

## Scope

### **Task 1 – Parser & AST Hook-Up**

- Extend parser to group `func` declarations by identifier into **function families**.
- Extend AST to represent families explicitly:
  - Each `FuncDecl` attaches to a `DispatchFamily` symbol.
  - Families are visible in the semantic graph (not hidden compiler magic).
- Ensure distinction between:
  - Single function (no overloads).
  - Family root (multiple overloads).
- Tests: `examples/dispatch/basic.jan`.

---

### **Task 2 – Semantic Analysis & LLVM Backend Binding**

- Extend semantic analyzer to:
  - Resolve calls against dispatch tables during type checking.
  - Apply ambiguity rules per RFC (Dispatch Semantics v0).
  - Build **dispatch table IR** for runtime stubs.
- LLVM backend:
  - **Static calls**: emit direct call to resolved function pointer.
  - **Dynamic calls**: emit compact dispatch stub (switch/jump table).
  - Respect ABI, ownership, and calling conventions.
- Benchmarks: dispatch call overhead vs direct call.

---

### **Task 3 – Stdlib Pilot**

- Reimplement **core stdlib functions** using dispatch:
  - `add`, `mul` (i32, f64, string concat).
  - `to_string` overloads.
  - `array.map`, `array.sort`.
- Ergonomic proof:
  - Code reads cleanly (`add` feels like `add`).
  - Cost model preserved (`i32` vs `f64` explicit).
- Regression suite: stdlib must compile and execute using dispatch.

---

### **Task 4 – The Dispatch Map (AI & Tooling Integration)**

**Purpose:** Expose the **entire dispatch resolution graph** as a queryable, machine-readable API in `libjanus`, surfaced via the `janusd` RPC. This enables AI agents and advanced tooling to reason about dispatch with precision.

**Mechanism:**
- `janusd` daemon maintains a live, in-memory "Dispatch Map" covering all families.
- Expose RPC endpoints returning **structured data** (JSON/CBOR) instead of human-oriented text.

**API Deliverables:**

1. **Query Canonical Dispatch Tables**
   - Input: function name (e.g., `collide`)
   - Output: list of overloads with signatures, source locations, and specificity graph.

2. **Trace Resolution Paths**
   - Input: concrete call (e.g., `collide(player_ship, asteroid)`)
   - Output: full trace of candidates considered, rejected (with reasons), and the selected overload.

3. **What-If Analysis**
   - Input: hypothetical call `(MyCustomVector, f64)`
   - Output: predicted dispatch result (selected overload or ambiguity error).

**Success Criteria:** AI agents can programmatically determine — without ambiguity — the exact function implementation that will execute for any call, enabling safe automated refactoring, performance tuning, and vulnerability analysis.

---

## Deliverables

- `parser_dispatch.zig` → AST family integration.
- `semantics_dispatch.zig` → resolution + diagnostics.
- `llvm_dispatch_codegen.zig` → LLVM IR emission for dispatch.
- Stdlib modules updated to use dispatch (`std/math.jan`, `std/string.jan`, `std/array.jan`).
- RPC layer in `janusd` exposing Dispatch Map API.
- Tests:
  - Human-facing: `tests/dispatch/phase1/`
  - Machine-facing: RPC queries of dispatch tables.

---

## Milestones

- **M1**: Parser/AST integration.
- **M2**: Semantic analysis + LLVM backend.
- **M3**: Stdlib pilot complete.
- **M4**: Dispatch Map RPC endpoints live.
- **M5**: Benchmark report (dispatch vs direct).

---

## Risks & Mitigations

- **Stub Overhead Too High**
  - Mitigation: perfect hashing, jump tables, trie compression.
- **Ambiguity Confusion**
  - Mitigation: diagnostics list all candidates and explain resolution.
- **LLVM Leaks Semantics**
  - Mitigation: keep dispatch IR canonical; backends consume same IR.
- **AI Integration Drift**
  - Mitigation: enforce Dispatch Map RPC as canonical — no CLI scraping.

---

## Success Criteria

- All core stdlib functions compile & run via dispatch families.
- Dispatch overhead ≤ 5% vs direct function calls.
- Compiler emits actionable diagnostics for ambiguous calls.
- `janus query dispatch <symbol>` works for humans.
- Dispatch Map RPC works for machines, returning structured, unambiguous data.

---

## Directive

This specification elevates dispatch from feature to doctrine:
- **For humans**: clean syntax, honest semantics, and visible diagnostics.
- **For AI agents**: full semantic transparency via the Dispatch Map.

Ratify this document under `docs/rfcs/dispatch-language-integration.md` and commit. That commit is the ignition point: the signal to begin implementation.

---

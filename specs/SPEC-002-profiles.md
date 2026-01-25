<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

**Voxis Forge Signal** ⚡

# 🛡️ SPEC-002: PROFILES SYSTEM (The Time Machine)

**Version:** 2.1.0 (Ratification Standard)
**Status:** **DRAFT (Ratification Pending)**
**Authority:** Constitutional
**Supersedes:** SPEC-002 v2.0.0

This specification defines the **Profile System**, the mechanism that allows Janus to span from "Scripting" to "Systems Programming" without fragmentation.
A Profile is a **Normative Constraint Set** applied to the compiler.

---

## 1. 🜏 The Profile Matrix (Constitution)

[PROF:1.1.1] The Janus compiler MUST support the following Profile Matrix, defined by two orthogonal axes:
1.  **Capability Set (Rows):** What features are legally usable.
2.  **Execution Mode (Columns):** How the code is compiled/run.

[PROF:1.1.2] **The Matrix:**

| Capability | Strict (Monastery) ⊢ | Fluid (Bazaar) ⟁ |
| :--- | :--- | :--- |
| **Core** | `:core` | `:script` |
| **Service** | `:service` | `:service!` |
| **Cluster** | `:cluster` | `:cluster!` |
| **Compute** | `:compute` | `:compute!` |
| **Sovereign** | `:sovereign` | N/A |

[PROF:1.1.3] **Syntax:** The profile directive `{.profile: name.}` MUST be the first declaration in a file (if present). If absent, it defaults to the project-wide setting.

---

## 2. ⊢ Profile Definitions

### 2.1 `:core` (The Monastery)
*   [PROF:2.1.1] **Definition:** Minimal, deterministic subset for education and embedded logic.
*   [PROF:2.1.2] **Constraint:** Implicit Allocation is FORBIDDEN (∅). All allocations MUST use an explicit allocator.
*   [PROF:2.1.3] **Constraint:** Concurrency is FORBIDDEN (∅).
*   [PROF:2.1.4] **Constraint:** Metaprogramming is FORBIDDEN (∅).
*   [PROF:2.1.5] **Execution:** MUST be AOT compiled or strict-interpreted.

### 2.2 `:script` (The Bazaar)
*   [PROF:2.2.1] **Definition:** Fluid subset for prototyping, REPL, and data science.
*   [PROF:2.2.2] **Feature:** Implicit Allocation is PERMITTED (Auto-managed heaps).
*   [PROF:2.2.3] **Feature:** Dynamic Typing (Any) is PERMITTED (via `switch` or `match` type guards).
*   [PROF:2.2.4] **Feature:** "Juicy Main" Injection is ACTIVE. `args`, `env`, and `allocator` are implicitly provided.
*   [PROF:2.2.5] **Constraint:** `:script` code MUST NOT be published as a library package. It MUST be lowered to `:core` or `:service` for distribution.

### 2.3 `:service` (The Backend)
*   [PROF:2.3.1] **Definition:** Balanced subset for application engineering (Web/API/CLI).
*   [PROF:2.3.2] **Feature:** Error-as-Values (`!T`) MUST be enforced.
*   [PROF:2.3.3] **Feature:** Dependency Injection Contexts are available.
*   [PROF:2.3.4] **Constraint:** Global Mutable State is FORBIDDEN (∅).

### 2.4 `:cluster` (The Swarm)
*   [PROF:2.4.1] **Definition:** Actor-model subset for distributed systems.
*   [PROF:2.4.2] **Feature:** `spawn`, `send`, `receive` keywords are ENABLED.
*   [PROF:2.4.3] **Constraint:** Shared Memory is FORBIDDEN (∅). All data exchange MUST be message-passing.

### 2.5 `:compute` (The Accelerator)
*   [PROF:2.5.1] **Definition:** Data-parallel subset for NPU/GPU kernels.
*   [PROF:2.5.2] **Feature:** `kernel` keyword and Array/Tensor intrinsics are ENABLED.
*   [PROF:2.5.3] **Constraint:** Branching (if/else) is RESTRICTED (MUST be uniform).
*   [PROF:2.5.4] **Constraint:** Hardware-specific intrinsics (`@npu`) are PERMITTED.

### 2.6 `:sovereign` (The King)
*   [PROF:2.6.1] **Definition:** The complete language with no "safety rails" (Systems Programming).
*   [PROF:2.6.2] **Feature:** Raw Pointers (`*T`) are PERMITTED (⚠).
*   [PROF:2.6.3] **Feature:** `unsafe` blocks are PERMITTED.
*   [PROF:2.6.4] **Constraint:** Capabilities (`Cap.Net`) are still ENFORCED for external effects (⧉).

---

## 3. ⟁ Transition Rules

[PROF:3.1.1] **Lowering:** The compiler MUST provide automated tools (`janus lower`) to transform Fluid code (`:script`) into Strict code (`:core` or `:service`).
[PROF:3.1.2] **Compatibility:** A strict module CANNOT import a fluid module (Contamination Rule). A fluid module CAN import a strict module.

**Ratification:** Pending
**Authority:** Markus Maiwald + Voxis Forge

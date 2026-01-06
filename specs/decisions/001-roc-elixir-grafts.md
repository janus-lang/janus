<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# DECISION-001: Roc & Elixir Grafts — The Bazaar Temptations

**Status:** ADOPTED (Monastery Freeze v0.2.1)
**Date:** 2025-12-07
**Author:** Voxis Forge (Architectural Graft)

## Context
We analyzed Roc (pure functional, direct-to-binary) and Elixir (v1.19+ type inference, OTP). We evaluated features for adoption into Janus profiles.

## The Verdict

### 1. Unions & Exhaustiveness (Roc-style)
*   **Decision:** **ADOPT** mandatory exhaustiveness for `match` expressions.
*   **Mechanism:** Compiler Error **C2001**.
*   **Profile:** Strict in `:sovereign` and `:core`. In `:script`, it lints (warns) but code may run if the compiler can prove panic-safety on unhandled paths is effectively a "crash" (Roc style).
*   **Rejection:** We reject Elixir's "gradual unions" (`dynamic()`). Janus unions are always explicit.

### 2. Inference (Elixir 1.19-style)
*   **Decision:** **ADOPT** guard-aware inference for the `:cluster` profile.
*   **Mechanism:** `infer(guard) ⊆ infer(body)`.
*   **Roc-style:** For `:script` only, enable `--infer-full` (global inference) to allow omitting types in REPL/scripting contexts for joy.
*   **Constraint:** Explicit module boundaries are **immutable**. No global inference across modules.

### 3. OTP & Effects
*   **Decision:** **REJECT** Roc's `!` sigil. It is too coarse.
*   **Decision:** **KEEP** Janus `! Error` and Capability Contexts (`with ctx`).
*   **Refinement:** Enhance `:cluster` profile with OTP-specific type inference (e.g., `gen_server` callbacks).

## Implementation Plan (Graft-001)

1.  **C2001 Error:** Implement in `semantic/validation_engine.zig`.
2.  **Lint Prototype:** Create a test case where a `match` on an enum is missing a variant.
3.  **Union Semantics:** Update `SPEC-semantics.md` to reflect strict exhaustiveness.

---
*“We steal the fire, not the temple.”*

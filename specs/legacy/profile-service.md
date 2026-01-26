<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — :service Profile (SPEC-P-SERVICE)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-profile-go v0.1.0

## 1. Profile Purpose

The `:service` profile specializes Janus for **backend services and API development**. It builds upon the `:core` capability set by adding error-as-values, simple generics, and structured concurrency.

## 2. Capability Set ⊢

[PSVC:2.1.1] The `:service` profile SHALL inherit all capabilities of the `:core` profile.

[PSVC:2.1.2] **Error-as-Values:** The `:service` profile SHALL support the `Result[T, E]` pattern and the `try` / `?` operator for error propagation.

[PSVC:2.1.3] **Structured Concurrency:** The `:service` profile MUST support nurseries and task spawning for I/O-bound operations.

## 3. Execution Mode: Hybrid ⟁

[PSVC:3.1.1] The `:service` profile SHALL support both **Strict** and **Fluid** execution modes.
- `:service` (Strict): Monastery-style, AOT compiled.
- `:service!` (Fluid): Bazaar-style, JIT enabled with more aggressive inference.

---

**Ratified:** 2026-01-06  
**Authority:** Markus Maiwald + Voxis Forge

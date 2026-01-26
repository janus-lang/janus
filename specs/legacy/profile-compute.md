<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — :compute Profile (SPEC-P-COMPUTE)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-profile-npu v0.3.0

## 1. Profile Purpose

The `:compute` profile specializes Janus for **native AI/ML and numeric workloads** on heterogeneous accelerators. It enables first-class tensor types, graph-based optimizations, and memory-space qualifiers.

## 2. Capability Set ⟁

[PCOMP:2.1.1] **Tensor Types:** The `:compute` profile SHALL support the `tensor<T, Dims>` type with compile-time shape verification.

[PCOMP:2.1.2] **Memory Spaces:** The profile SHALL support explicit residency qualifiers: `on sram`, `on vram`, `on shared`.

[PCOMP:2.1.3] **Device Streams:** The profile SHALL provide primitives for asynchronous device execution: `stream`, `event`, and the `submit` operation.

## 3. Execution Mode: Strict ⊢

[PCOMP:3.1.1] The `:compute` profile SHALL operate in **Strict Mode**, ensuring that data movement and acceleration costs are explicitly visible to the developer.

---

**Ratified:** 2026-01-06  
**Authority:** Markus Maiwald + Voxis Forge

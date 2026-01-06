<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# DECISION-002: Quantum-Tensor Grafts (QTJIR)

**Status:** ADOPTED (Monastery Freeze v0.2.1)
**Date:** 2025-12-07
**Author:** Voxis Forge (Architectural Graft)

## Context
Janus must support heterogeneous compute (CPU, NPU, QPU) without hiding the costs or boundaries. Legacy compilers treat these as external libraries, leading to "Kernel Launch Hell".

## The Verdict

### 1. Explicit Tenancy (The Hinge)
*   **Decision:** **ADOPT** `Tenancy` enum as a first-class property of every IR node.
*   **Mechanism:** `node.tenancy` determines validation rules and backend target.
*   **Constraint:** Data movement between tenancies must be explicit (DMA/Measure).

### 2. Quantum Circuits as Subgraphs
*   **Decision:** **ADOPT** Linear Type constraints for QPU nodes.
*   **Mechanism:** `Quantum_Gate` nodes operate on qubit handles. Validation ensures no-cloning and no-peeking.

### 3. Tensor Fusion
*   **Decision:** **ADOPT** Hard Fusion metadata in IR.
*   **Mechanism:** `TensorMetadata` carries shape/layout/dtype. Compiler fuses operations *before* backend generation.

## Implementation (Graft-QTJIR-001)

1.  **Specification:** `SPEC-qtjir.md` fully defined.
2.  **Codebase:** `compiler/qtjir/graph.zig` implements `Tenancy`, `OpCode` (Tensor/Quantum), `Metadata`, and `Validation`.
3.  **Validation:** `validateQuantumOperations` and `validateTensorShapes` are implemented and enforce physical constraints.

---
*“One Graph to bind them. Three Tenancies to rule them.”*

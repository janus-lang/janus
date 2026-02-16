<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).


# Janus Specification — QTJIR Hardware Accelerator Interface (SPEC-010)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-qtjir-backend v0.1.0

---

## 1. Objective

To define a standardized, stable interface for creating **QTJIR Backends**. This enables community developers and hardware vendors to build first-class support for new accelerators (TPUs, NPUs, QPUs, FPGAs) without modifying the Janus compiler core.

## 2. The Doctrine of Explicit Tenancy

Janus differs from other languages by enforcing **Explicit Hardware Tenancy** at the IR level. A backend does NOT perform auto-discovery or magical offloading. It is responsible solely for executing the operations specifically assigned to its tenancy.

> **Rule:** A backend MUST only process nodes with a matching `Tenancy` tag. It MUST NOT silently execute or emulate operations belonging to other tenancies unless explicitly configured as a "Fallback Backend" (e.g., CPU Simulation).

## 3. The `QTJIRBackend` Interface

A compliant backend is a Zig module (likely a "Sovereign Hexadron" following Panopticum doctrine) that exposes a specific public API.

### 3.1 Core Structure

```zig
/// The standardized interface for a Janus Backend
pub const QTJIRBackend = struct {
    allocator: std.mem.Allocator,
    target_info: TargetInfo,

    /// 1. Initialize the backend
    pub fn init(allocator: std.mem.Allocator, target: TargetInfo) !QTJIRBackend;

    /// 2. Emit/Compile the graph
    ///
    /// Takes a fully lowered QTJIR Graph.
    /// Returns a BackendArtifact (binary, text, or executable handle).
    pub fn emit(self: *QTJIRBackend, graph: *const QTJIRGraph) !BackendArtifact;

    /// 3. Clean up
    pub fn deinit(self: *QTJIRBackend) void;
};
```

### 3.2 Key Types

*   **`QTJIRGraph`**: The immutable, verified input graph.
*   **`BackendArtifact`**: A tagged union representing the output.
    *   `.text`: Generic text (e.g., MLIR, LLVM IR, C source).
    *   `.binary`: Machine code or bytecode (e.g., ELF, WASM).
    *   `.executable`: An in-memory handle for JIT execution (e.g., `Simulator`).

## 4. Implementation Strategy: The Emitter Pattern

For most hardware targets, the backend will function as an **Emitter**. It translates QTJIR nodes into an intermediate format consumed by a vendor toolchain.

**Reference Implementation:** `compiler/npu_backend/mlir_emitter.zig`

### 4.1 Tenancy Filtering

The backend must iterate through the monolithic graph but only act on relevant nodes.

```zig
fn emitGraph(self: *Self, graph: *Graph) !void {
    for (graph.nodes) |node| {
        if (node.tenancy == .NPU_Tensor) {
            try self.emitTensorOp(node);
        } else if (node.tenancy == .CPU_Serial) {
            // IGNORE or DELEGATE
            // A dedicated NPU backend usually ignores CPU nodes 
            // relying on the Runtime Linker to stitch them together.
        }
    }
}
```

### 4.2 Handling Metadata

For `Tensor` and `Quantum` operations, the backend MUST consume the `IRNode.metadata`.

*   **Tensor Metadata:** Shape, Rank, Dimension info.
*   **Quantum Metadata:** Qubit indices, Gate parameters.

## 5. Integration with Build System

New backends are registered in `build.zig` as separate modules. They should follow the **Panopticum** layout:

```text
compiler/
├── my_accelerator.zig          # Sovereign Index
└── my_accelerator/             # Feature Folder
    ├── emitter.zig             # Core Logic
    ├── runtime.zig             # (Optional) JIT Runtime
    └── target_spec.zig         # Hardware constraints
```

## 6. Validation & Compliance

A new backend MUST provide a **Simulator** or **Validator** mode (see `npu_backend/simulator.zig`) to verify semantic correctness without requiring physical hardware. This serves as the "Integrated Proof Package."

---

## 7. Future: The Runtime Linker

(Scheduled for v0.3.0)

Currently, backends emit standalone artifacts. In the future, the **Janus Runtime Linker** will accept artifacts from multiple backends (e.g., CPU Object + NPU XLA + QPU Quantum circuit) and fuse them into a single `janus` executable, managing data movement between tenancies.

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Specification — Quantum-Tensor Janus IR (SPEC-009)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-qtjir v0.2.1

## 1. Overview
QTJIR is the **Sovereign Intermediate Representation** for Janus. Unlike LLVM IR (which assumes a uniform CPU memory model), QTJIR is a hyper-graph that explicitly models **Hardware Tenancy**.

It is designed to solve the "Accelerator Gap":
- CPUs are serial/scalar.
- NPUs (TPUs) are tensor/matrix.
- QPUs are quantum/probabilistic.

Janus treats these as first-class citizens, not external libraries.

## 2. The Hinge: Explicit Tenancy
Every node in QTJIR has a `Tenancy` tag. This is rigid.

```zig
pub const Tenancy = enum {
    CPU_Serial,      // Thread-local, stack-based (Normal Code)
    CPU_Parallel,    // Worker-pool, channel-based (Actors)
    NPU_Tensor,      // Systolic array, local memory (Matrix Ops)
    QPU_Quantum,     // Superposition, collapse-only (Quantum Gates)
};
```

### 2.1 Crossing the Threshold
Data cannot implicitly flow between tenancies. It must bridge.
- `CPU -> NPU`: `Tensor_Load` (DMA transfer)
- `NPU -> CPU`: `Tensor_Store` (DMA readback)
- `CPU -> QPU`: `Quantum_Prepare` (State initialization)
- `QPU -> CPU`: `Quantum_Measure` (Wavefunction collapse)

## 3. Quantum Operations (The QPU Subgraph)
The QPU subgraph is a **Quantum Circuit** embedded in the control flow.

### 3.1 Opcodes
- `Quantum_Gate`: Applies a unitary operator ($ U $) to set of qubits.
- `Quantum_Measure`: Observes qubits, returning classical bits (`i1`).

### 3.2 Metadata
Quantum nodes carry strict metadata payload:
```zig
pub const QuantumMetadata = struct {
    gate_type: GateType,     // H, CNOT, RX, etc.
    qubits: []const usize,   // Physical/Virtual Qubit IDs
    parameters: []const f64, // For rotation gates (RX, RY, RZ)
};
```

### 3.3 Quantum Validation (Strict Mode)
The compiler enforces physical laws at compile time:
1.  **No Cloning:** Qubits cannot be copied. (Linear Types)
2.  **No Peeking:** Intermediate states cannot be read without `Measure`.
3.  **Topological Order:** Gates on the same qubit are strictly ordered.

## 4. Tensor Operations (The NPU Subgraph)
The NPU subgraph represents a Dataflow Graph (DFG) for matrix math.

### 4.1 Opcodes
- `Tensor_Matmul`: $ C = A \times B $
- `Tensor_Conv`: Convolution (1D/2D/3D)
- `Tensor_Contract`: Einstein Summation (einsum)
- `Tensor_Fused*`: Compiler-fused kernels (e.g., Matmul+ReLU)

### 4.2 Fusion Strategy
QTJIR performs **Hard Fusion** before lowering to device kernels:
1.  Identify `NPU_Tensor` subgraphs.
2.  Fuse compatible ops (e.g., `Add` -> `Relu` -> `FusedAddRelu`).
3.  Emit as a single Kernel Launch (CUDA/Metal/WebGPU).

### 4.3 Parallel Loop Construct (CPU_Parallel Data Parallelism)
**Profile:** `:compute`, `:science`  
**Motivation:** Bridge the gap between serial `:min` code and full `:npu` tensor operations for CPU-bound scientific computing.

#### 4.3.1 Syntax
The parallel range iterator uses the `||` operator:

```janus
// Parallel iteration (CPU_Parallel tenancy)
for i in 0 || N do
    a[i] = compute(i)  // Each iteration is independent
end
```

**Semantics:**
- The loop body is executed in parallel across worker threads.
- The compiler enforces **independence**: the body must be pure (no shared mutable state).
- If the body contains IO or other effects, a compile-time error is issued in `:compute` profile.

#### 4.3.2 QTJIR Lowering
The parallel loop is lowered to a **structured parallel region** in QTJIR:

```
ParallelRegion [CPU_Parallel]
├─ RangeIterator(0, N)
├─ LoopBody [CPU_Parallel]
│  ├─ Load(a, i)
│  ├─ Call(compute, i)
│  └─ Store(a, i, result)
└─ Barrier [CPU_Parallel → CPU_Serial]
```

**Optimizations:**
1. **SIMD Fusion:** If the body is vectorizable math, fuse into SIMD instructions.
2. **Work Stealing:** Runtime uses a work-stealing scheduler for load balancing.
3. **Prophetic JIT:** Analyze the body at comptime; if it's pure math with known types, emit optimized machine code directly.

#### 4.3.3 Constraints (Safety)
[QTJIR:4.3.3.1] **No Shared Mutable State:** The compiler MUST reject loops where the body writes to variables outside the loop iteration scope.

[QTJIR:4.3.3.2] **Deterministic Execution:** The parallel loop MUST produce the same result as the serial version. Race conditions are compile-time errors.

[QTJIR:4.3.3.3] **Effect Tracking:** In `:compute` profile, the body MUST NOT contain `io`, `net`, or other non-deterministic effects.

#### 4.3.4 Comparison to Actor-Based Parallelism
| Feature | Parallel Loop (`||`) | Actors (`:full` nurseries) |
|:--------|:---------------------|:---------------------------|
| **Use Case** | Data parallelism (SIMD/CPU) | Task parallelism (concurrency) |
| **Overhead** | Minimal (work-stealing) | Higher (message passing) |
| **Determinism** | Guaranteed (pure body) | Not guaranteed (async) |
| **Profile** | `:compute`, `:science` | `:full`, `:service` |

**Strategic Value:**  
This construct allows scientists and engineers to write parallel CPU code without understanding the Actor model, while maintaining Janus's doctrine of **Explicit Costs**.

---

## 5. Lowering Strategy
QTJIR lowers to multiple backends simultaneously:

1.  **CPU Nodes** -> LLVM IR -> Machine Code (x86/ARM)
2.  **NPU Nodes** -> TOSA / StableHLO -> GPU Kernel (SPIR-V/PTX)
3.  **QPU Nodes** -> OpenQASM 3.0 -> Quantum Control (Pulse)

## 6. Example Graph

```janus
func entanglement() -> bool {
    // tenancy: CPU
    let q0 = qpu.alloc(1) // -> QPU
    let q1 = qpu.alloc(1) // -> QPU
    
    // tenancy: QPU
    qpu.h(q0)             // Hadamard
    qpu.cnot(q0, q1)      // Entangle
    
    // tenancy: CPU (via Measurement)
    return qpu.measure(q1) // Collapse
}
```

**Generates:**
1. `QAlloc(0)` [QPU]
2. `QAlloc(1)` [QPU]
3. `Gate(H, [0])` [QPU]
4. `Gate(CNOT, [0, 1])` [QPU]
5. `Measure([1])` [QPU -> CPU] -> `i1`

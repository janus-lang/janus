<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# QTJIR Examples

This directory contains practical examples demonstrating the Quantum-Tensor Janus IR (QTJIR) system.

## Overview

QTJIR is a multi-level intermediate representation designed for future-proof hardware acceleration. These examples show how to:

1. Construct QTJIR graphs programmatically
2. Emit LLVM IR for different execution targets
3. Leverage heterogeneous acceleration (CPU, NPU, QPU)

## Examples

### 1. CPU Arithmetic (`cpu_arithmetic.zig`)

**Purpose:** Demonstrates basic CPU-only arithmetic operations

**What it shows:**
- Graph construction with IRBuilder
- Arithmetic operations (Add, Sub, Mul, Div)
- LLVM IR emission for CPU execution
- Graph validation

**Computation:** `(a + b) * (c - d)` where a=10, b=20, c=30, d=5

**Expected result:** `(10 + 20) * (30 - 5) = 750`

**Run:**
```bash
zig build-exe examples/qtjir/cpu_arithmetic.zig -I. --dep astdb_core
./cpu_arithmetic
```

### 2. Tensor Operations (`tensor_operations.zig`)

**Purpose:** Demonstrates NPU tensor acceleration

**What it shows:**
- NPU_Tensor tenancy
- Tensor metadata (shape, dtype, layout)
- Tensor operation lowering
- Backend function calls to NPU runtime

**Operation:** Matrix multiplication on NPU
- Input A: [128, 256] f32 matrix
- Input B: [256, 512] f32 matrix
- Output: [128, 512] f32 matrix

**Run:**
```bash
zig build-exe examples/qtjir/tensor_operations.zig -I. --dep astdb_core
./tensor_operations
```

### 3. Quantum Circuit (`quantum_circuit.zig`)

**Purpose:** Demonstrates QPU quantum acceleration

**What it shows:**
- QPU_Quantum tenancy
- Quantum gate operations (Hadamard, CNOT)
- Quantum measurement
- Quantum metadata (gate type, qubits, parameters)

**Circuit:** Bell state preparation
1. Hadamard gate on qubit 0: creates superposition
2. CNOT gate (control=0, target=1): creates entanglement
3. Measurement: collapses the state

**Quantum state:** `(|00⟩ + |11⟩)/√2` (maximally entangled)

**Run:**
```bash
zig build-exe examples/qtjir/quantum_circuit.zig -I. --dep astdb_core
./quantum_circuit
```

### 4. Mixed Tenancy (`mixed_tenancy.zig`)

**Purpose:** Demonstrates heterogeneous acceleration with multiple backends

**What it shows:**
- CPU_Serial for scalar arithmetic
- NPU_Tensor for matrix operations
- QPU_Quantum for quantum algorithms
- Cross-tenancy data flow
- Multiple backend integration

**Computation:**
1. CPU: `100 + 50` (scalar arithmetic)
2. NPU: Tensor matmul [64, 128]
3. QPU: Hadamard gate on qubit 0
4. Measurement: collapse quantum state

**Run:**
```bash
zig build-exe examples/qtjir/mixed_tenancy.zig -I. --dep astdb_core
./mixed_tenancy
```

## Building Examples

### Individual Build
```bash
zig build-exe examples/qtjir/cpu_arithmetic.zig -I. --dep astdb_core
```

### All Examples
```bash
for example in examples/qtjir/*.zig; do
    zig build-exe "$example" -I. --dep astdb_core
done
```

## Understanding the Output

Each example produces:

1. **Execution trace:** Shows the steps being performed
2. **LLVM IR:** The generated intermediate representation
3. **Verification:** Confirms backend calls are present
4. **Explanation:** Describes what the code does

### Example Output Structure

```
QTJIR Example: CPU Arithmetic
==============================

Creating constants...
Creating addition: 10 + 20...
Creating subtraction: 30 - 5...
Creating multiplication: (a + b) * (c - d)...

Validating graph...
✅ Graph validation passed

Emitting LLVM IR...
✅ LLVM IR emission successful

Generated LLVM IR:
==================
[LLVM IR code here]

Expected result: (10 + 20) * (30 - 5) = 750
```

## Key Concepts

### Tenancy

QTJIR supports multiple execution targets:

- **CPU_Serial:** Sequential CPU execution
- **CPU_Parallel:** Parallel CPU execution (SIMD)
- **NPU_Tensor:** Neural Processing Unit (tensor operations)
- **QPU_Quantum:** Quantum Processing Unit (quantum gates)

### Graph Construction

1. Create a `QTJIRGraph` instance
2. Create an `IRBuilder` for the graph
3. Create nodes using `builder.createNode()` or `builder.createConstant()`
4. Connect nodes by adding inputs
5. Validate the graph with `graph.validate()`
6. Emit LLVM IR with `LLVMEmitter.emit()`

### Metadata

Different operations require different metadata:

- **Tensor operations:** Shape, dtype, layout
- **Quantum operations:** Gate type, qubits, parameters
- **CPU operations:** None required

## Advanced Topics

### Adding Custom Operations

To add a new operation:

1. Define the OpCode in `compiler/qtjir/graph.zig`
2. Implement lowering in `compiler/qtjir/lowerer.zig`
3. Implement emission in `compiler/qtjir/emitter.zig`
4. Add tests in `compiler/qtjir/test_*.zig`

### Extending Backends

To add a new backend:

1. Define backend-specific metadata
2. Implement lowering for your backend
3. Implement LLVM IR emission
4. Add validation for your backend
5. Add tests for your backend

### Performance Optimization

QTJIR provides several optimization opportunities:

- **Operation fusion:** Combine adjacent operations
- **Gate cancellation:** Remove redundant quantum gates
- **Memory optimization:** Minimize tensor allocations
- **Scheduling:** Optimize operation ordering

## References

- **API Documentation:** `compiler/qtjir/QTJIR_API_DOCUMENTATION.md`
- **Developer Guide:** `compiler/qtjir/QTJIR_DEVELOPER_GUIDE.md`
- **Source Code:** `compiler/qtjir/`

## License

These examples are licensed under Apache-2.0.
See LICENSE file for details.

---

**Last Updated:** 2025-11-24
**QTJIR Version:** 0.3.0
**Status:** Production Ready

<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# NPU Backend - AI-First Runtime Codegen

**Status:** Phase 1 - Simulation Backend  
**Profile:** `:npu`  
**Doctrine:** Panopticum-compliant feature module

---

## Purpose

This module implements the NPU (Neural Processing Unit) backend for Janus, enabling compilation of tensor and SSM operations to specialized hardware accelerators.

**Current Phase:** Simulation backend for semantic validation  
**Future Phase:** MLIR emission for production TPU/NPU targets

---

## Architecture

```
NPU Backend Pipeline:
  QTJIR (NPU_Tensor nodes) → NPU Simulator → Validation Proof
                          ↓
                    (Future: MLIR → XLA → TPU)
```

### Components

1. **`simulator.zig`** - NPU Simulation Backend
   - **Purpose**: Validate semantic correctness of tensor/SSM lowering
   - **Scope**: Interprets NPU_Tensor nodes, asserts correctness
   - **Doctrine**: Integrated Proof - This IS the proof package

2. **`mlir_emitter.zig`** (Future)
   - **Purpose**: Production NPU backend via MLIR
   - **Scope**: QTJIR → MLIR Tensor Dialect → XLA → TPU/NPU
   - **Doctrine**: Trojan Horse Strategy - Leverage industry IR

---

## Supported Operations

### Tensor Operations (NPU_Tensor tenancy)
- `tensor.matmul` → Matrix multiplication
- `tensor.conv2d` → 2D convolution
- `tensor.relu` → ReLU activation
- `tensor.softmax` → Softmax activation
- `tensor.reduce_sum` → Reduction (sum)
- `tensor.reduce_max` → Reduction (max)

### SSM Operations (Mamba-3 inspired)
- `ssm.scan` → Linear recurrence scan
- `ssm.selective_scan` → Selective scan with input-dependent dynamics

---

## Usage

### Simulation Backend (Current)

```zig
const npu = @import("npu_backend");

// Create simulator
var simulator = try npu.Simulator.init(allocator);
defer simulator.deinit();

// Execute QTJIR graph with NPU operations
const result = try simulator.execute(qtjir_graph);

// Validate correctness
try testing.expect(result.is_valid);
```

### MLIR Backend (Future)

```zig
const npu = @import("npu_backend");

// Emit MLIR
var emitter = try npu.MLIREmitter.init(allocator);
defer emitter.deinit();

const mlir_module = try emitter.emit(qtjir_graph);
```

---

## Design Principles

1. **Mechanism over Policy**: Explicit hardware tenancy, no auto-offloading
2. **Revealed Complexity**: All costs visible (no hidden transfers)
3. **Syntactic Honesty**: Operations explicitly declare NPU intent
4. **Integrated Proof**: Simulator validates semantic correctness

---

## Testing

All tests are colocated in this feature folder:
- `test_simulator.zig` - Simulation backend tests
- `test_mlir_emitter.zig` - MLIR emission tests (future)

Run tests:
```bash
zig build test-npu-backend
```

---

## References

- **QTJIR Spec**: `compiler/qtjir/README.md`
- **AI-First Runtime**: `.kiro/specs/_ARCHIVE/ai-first-janus-runtime/design.md`
- **Mamba-3 Primitives**: SSM operations for long-sequence modeling
- **MLIR Tensor Dialect**: https://mlir.llvm.org/docs/Dialects/TensorOps/

---

**Author:** Voxis Forge  
**Created:** 2025-12-12  
**Doctrine:** PANOPTICUM (Effective: 2025-12-07)

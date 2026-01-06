<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# ⚡ QTJIR — The Canonical Janus IR

> **⚠️ AI AGENTS: This is the ONLY IR system you should use.**  
> Legacy `ir.zig` has been deprecated and moved to `attic/legacy_ir/`.

**Sovereign Index:** `compiler/qtjir.zig`  
**Status:** ✅ CANONICAL (v0.2.0+)  
**Doctrine:** Panopticum-compliant

---

## Overview

QTJIR (Quantum-Tensor Janus Intermediate Representation) is the **multi-level hyper-graph IR** with explicit hardware tenancy. It solves the "Accelerator Gap" by treating CPU, NPU/TPU (tensor), and QPU (quantum) as first-class citizens.

## Quick Start

```zig
const qtjir = @import("qtjir");

// Lower ASTDB → QTJIR
var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot, unit_id);
defer {
    for (ir_graphs.items) |*g| g.deinit();
    ir_graphs.deinit(allocator);
}

// Emit QTJIR → LLVM IR
var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "janus_module");
defer emitter.deinit();
try emitter.emit(ir_graphs.items);
const llvm_ir = try emitter.toString();
```

## Files in This Folder

| File | Purpose |
|------|---------|
| `graph.zig` | Core IR graph structure, nodes, opcodes, validation |
| `lower.zig` | ASTDB → QTJIR lowering (expressions, statements) |
| `llvm_emitter.zig` | QTJIR → LLVM IR emission |
| `builtin_calls.zig` | Built-in function registry |
| `ssa.zig` | SSA form utilities |
| `transforms.zig` | IR optimization passes |
| `test_*.zig` | Unit tests (colocated per Panopticum) |

## Key Concepts

### Tenancy
Every node has a `Tenancy` tag:
- `CPU_Serial` — Standard thread execution
- `CPU_Parallel` — Actor/worker pool  
- `NPU_Tensor` — Matrix acceleration (TPU/GPU)
- `QPU_Quantum` — Quantum superposition

### OpCodes
Core operations: `Constant`, `Add`, `Call`, `Return`, `Tensor_Matmul`, `Quantum_Gate`, etc.

## Canonical Pipeline

The main compilation pipeline (`src/pipeline.zig`) uses QTJIR exclusively:

```
Parse → ASTDB Snapshot → QTJIR Lower → LLVM Emit → llc → Link
```

## Specifications

- Semantic: `docs/specs/SPEC-qtjir.md`
- Decision: `docs/specs/decisions/003-qtjir-grafts.md`

---

*This folder is self-contained per Panopticum doctrine.*

<!--
SPDX-License-Identifier: LSL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Prophetic JIT Forge

**Status:** Foundation Implementation
**Version:** 0.1.0
**Profile:** `:script`, `:full`

## Overview

The Prophetic JIT Forge is Janus's revolutionary just-in-time compilation engine. It fuses semantic analysis, speculative optimization, and sovereign execution to deliver Python-like interactivity with systems-language performance.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Prophetic JIT Forge                         │
├─────────────────────────────────────────────────────────────────┤
│  Phase 1: Semantic Prophecy                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ASTDB Query → EffectSet + OptimizationHints            │   │
│  │  ComplexityMetrics → PAYJIT Threshold Calculation       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            ↓                                    │
│  Phase 2: Speculative Forging                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  SemanticProfile → SpeculationStrategy                  │   │
│  │  Insert DeoptGuards for runtime bailout                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            ↓                                    │
│  Phase 3: Sovereign Execution                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Strategy → ExecutionUnit (machine code + validators)   │   │
│  │  Capability-bounded, auditable, deoptimizable           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. `jit.zig` (Sovereign Index)

The public API for the JIT Forge.

**Key Types:**
- `OrcJitEngine`: Main JIT engine with profile-specific backends
- `Module`: QTJIR wrapper with invocation counting
- `ExecutionTrace`: Learning Ledger data for prophetic optimization

**Key Functions:**
- `compileLazy(module)`: On-demand JIT compilation
- `recordLearning(trace)`: Store execution patterns for future prediction
- `deoptimize(unit)`: Invalidate speculative code

### 2. `jit/semantic.zig` (Phase 1)

ASTDB-guided semantic analysis.

**Key Types:**
- `EffectSet`: Capability requirements (fs, net, sys, accelerator)
- `OptimizationHint`: Semantic hints (Pure, HotPath, TensorOp, etc.)
- `SemanticProfile`: Complete analysis output

### 3. `jit/speculation.zig` (Phase 2)

Speculative optimization with safety guards.

**Key Types:**
- `SpeculationLevel`: None → Low → Medium → High → Maximum
- `DeoptGuard`: Runtime bailout triggers
- `SpeculationStrategy`: Optimization decisions + adjusted thresholds

### 4. `jit/execution.zig` (Phase 3)

Code generation and execution management.

**Key Types:**
- `ExecutionUnit`: Compiled code + validators + audit trail
- `ExecutionResult`: Return value from execution
- `CapabilityValidator`: Runtime capability enforcement

## Usage

```zig
const jit = @import("std/ai/jit.zig");

// Initialize with profile-appropriate backend
var engine = jit.OrcJitEngine.init(allocator, .Simulation);
defer engine.deinit();

// Configure capability bounds
engine.capability_bounds = .{
    .allow_fs = false,
    .allow_net = false,
    .allow_accelerator = true,
};

// Compile a module
const exec_unit = try engine.compileLazy(&module);
defer exec_unit.deinit();

// Execute
const result = try exec_unit.execute(.{});
```

## Compilation Backends

| Backend | Profile | Compile Speed | Runtime Speed | Use Case |
|:--------|:--------|:--------------|:--------------|:---------|
| MIR | `:min` | Very Fast | Good | REPL, scripts |
| Cranelift | `:npu` | Fast | Better | Numerical, ML |
| LLVM ORC | `:full` | Slower | Best | Production |
| Simulation | Test | Instant | N/A | Validation |

## PAYJIT (Pay-As-You-JIT)

Adaptive compilation thresholds based on:
1. **Base Threshold**: Minimum invocations before compilation
2. **Complexity Factor**: Higher complexity = delay compilation
3. **Size Factor**: Logarithmic scaling with module size

```
effective_threshold = base × complexity_factor × size_factor
```

## Learning Ledger Integration

The JIT Forge integrates with the ASTDB-backed Learning Ledger:
1. **Record**: Execution traces stored with BLAKE3 CIDs
2. **Predict**: Future compilations use learned patterns
3. **Verify**: Cryptographic integrity prevents tampering

## Doctrinal Compliance

- **Temporal Honesty**: JIT path has identical semantics to AOT
- **Capability Safety**: All compilation bounded by granted capabilities
- **Revealed Complexity**: No hidden optimization magic
- **Content-Addressed**: All artifacts have BLAKE3 CIDs

## Testing

```bash
# Run JIT tests
zig build test --summary all 2>&1 | grep "jit"
```

## Future Work

- [ ] MIR backend implementation
- [ ] Cranelift integration
- [ ] LLVM ORC bindings
- [ ] Learning Ledger storage
- [ ] Runtime deoptimization
- [ ] Profile-guided optimization

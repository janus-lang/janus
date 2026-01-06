# ⚠️ DEPRECATED: Legacy IR System

**Archived:** 2025-12-15  
**Status:** DEAD CODE - DO NOT USE

## Why This Was Deprecated

The Janus compiler has transitioned to the **QTJIR** (Quantum-Tensor Janus IR) system which is:
- Designed for ASTDB integration
- Supports quantum and tensor operations
- Uses a graph-based IR representation
- Has proper SSA form and validation

## Canonical IR System

**All new development MUST use:**
```zig
const qtjir = @import("qtjir");

// Lower ASTDB → QTJIR
var ir_graphs = qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);

// Emit QTJIR → LLVM IR
var emitter = qtjir.llvm_emitter.LLVMEmitter.init(allocator, "janus_module");
emitter.emit(ir_graphs.items);
```

## Files Moved Here

| Original Location | Description |
|------------------|-------------|
| `compiler/libjanus/ir.zig` | Old instruction-based IR module |
| `compiler/libjanus/runner.zig` | Old non-ASTDB pipeline runner |
| `compiler/libjanus/tests/libjanus_ir_test.zig` | Tests for old IR |
| `compiler/passes/codegen/llvm/ir.zig` | Duplicate LLVM codegen |
| `compiler/libjanus/passes/codegen/ir.zig` | Another duplicate LLVM codegen |
| `tools/fuzz_ir.zig` | Fuzzer using old API |

## Do Not Resurrect

If you need IR functionality, look at:
- `compiler/qtjir.zig` — Sovereign index (public API)
- `compiler/qtjir/graph.zig` — IR graph representation
- `compiler/qtjir/lower.zig` — ASTDB → QTJIR lowering
- `compiler/qtjir/llvm_emitter.zig` — QTJIR → LLVM emission

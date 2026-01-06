# Legacy IR Cleanup - Summary

**Date:** 2025-12-15  
**Status:** ✅ COMPLETE

## Objective

Move deprecated legacy IR system (`ir.zig`) and related codegen files to `attic/legacy_ir/` and update all documentation to reflect that **QTJIR is the canonical IR system**.

## Files Moved to `attic/legacy_ir/`

### Legacy IR Files
- `compiler/libjanus/ir.zig` → `attic/legacy_ir/libjanus/ir.zig`
- `compiler/libjanus/runner.zig` → `attic/legacy_ir/libjanus/runner.zig`  
- `compiler/libjanus/tests/libjanus_ir_test.zig` → `attic/legacy_ir/libjanus/libjanus_ir_test.zig`

### Legacy Codegen Files
- `compiler/libjanus/passes/codegen/*.zig` → `attic/legacy_ir/passes/codegen/`
  - `codegen.zig`
  - `llvm.zig`
  - `c.zig`
  - `module.zig`
  - `dispatch_strategy.zig`
  - etc.

- `compiler/passes/codegen/llvm/ir.zig` → `attic/legacy_ir/passes/codegen/llvm/ir.zig`
- `compiler/libjanus/passes/codegen/ir.zig` → `attic/legacy_ir/passes/codegen/ir.zig`

### Legacy Tools
- `tools/fuzz_ir.zig` → `attic/legacy_ir/tools/fuzz_ir.zig`

## Files Modified

### 1. `compiler/libjanus/libjanus.zig`
**Changes:**
- Removed: `pub const ir = @import("ir.zig");`
- Removed: `pub const codegen = @import("passes/codegen/module.zig");`
- Added: Clear documentation blocks explaining QTJIR is canonical

### 2. `compiler/libjanus/api.zig`
**Changes:**
- Removed imports for deleted files (`Dispatch`, `llvm_text`, `Diag`, etc.)
- Deprecated all legacy API functions with `@compileError`:
  - `generateIR()`
  - `generateLLVM()`
  - `generateExecutableWithOptions()`
  - `generateExecutableWithSource()`
  - `generateExecutableFromJanusIR()`
  - `compileToExecutable()`
  - `compileToExecutableWithOptions()`
  - `emitLLVMFromSource()`
  - `runSema()`
  - `compileAndCodegen()`
- Defined `CodegenOptions` locally (was imported from deleted codegen)
- Implemented `checkLLVMTools()` locally (simple llc check)

### 3. `compiler/qtjir/README.md`
**Changes:**
- Added prominent AI agent warning: "⚠️ AI AGENTS: This is the ONLY IR system you should use."
- Emphasized canonical status throughout
- Added quick-start examples
- Updated file descriptions

### 4. `attic/legacy_ir/README.md`
**NEW FILE** - Created deprecation notice explaining:
- Why these files were deprecated
- What the canonical replacement is (QTJIR)
- Where to find the new code
- Clear warnings not to resurrect legacy code

## Canonical Pipeline

The **ONLY** compilation pipeline is now:

```
Parse → ASTDB Snapshot → QTJIR Lower → LLVM Emit → llc → Link
```

Implemented in: **`src/pipeline.zig`**

## AI Agent Guidance

All documentation now clearly states:
- **DO NOT** use `compiler/libjanus/ir.zig` (moved to attic)
- **DO NOT** use `compiler/libjanus/passes/codegen/` (moved to attic)
- **DO** use `compiler/qtjir.zig` (sovereign index)
- **DO** use `src/pipeline.zig` for compilation

## Remaining Work

### Known Issue: QTJIR Bug
There's a separate bug in `compiler/qtjir/lower.zig:396`:
```
error: expected type '*const core.AstNode', found '*const *const core.AstNode'
    try lowerBlock(ctx, bid, &block);
                             ^~~~~~
```

This needs to be fixed separately - it's a pointer dereferencing issue unrelated to the IR cleanup.

## Testing Status

- ✅ QTJIR tests pass: `zig build test-qtjir`
- ❌ Main build has QTJIR bug (separate issue)
- ✅ No references to deleted files remain (except in attic)

## Migration Guide

For any code still using legacy APIs:

**Before:**
```zig
const libjanus = @import("libjanus");
var ir_module = try libjanus.api.generateIR(snapshot, &sem, allocator);
try libjanus.api.generateExecutableWithOptions(&ir_module, "output", allocator, .{});
```

**After:**
```zig
const pipeline = @import("pipeline");
var p = pipeline.Pipeline.init(allocator, .{
    .source_path = "input.jan",
    .output_path = "output",
});
const result = try p.compile();
```

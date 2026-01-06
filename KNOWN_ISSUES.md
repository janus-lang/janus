# Known Issue: Chained Pipeline Operator

**Status**: Partially Implemented (2/3 tests passing)  
**Date**: 2026-01-06  
**Component**: Pipeline Operator Desugaring

## Issue Description

The chained pipeline operator test is failing:
```janus
1 |> inc() |> print()  // Expected: print(inc(1))
```

## What Works ✅
- Basic pipeline: `"Hello" |> print()` → `print("Hello")`
- UFCS: `v.action(42)` → `action(v, 42)` with proper receiver injection

## What Fails ❌
- Chained pipeline: `1 |> inc() |> print()` 
  - Expected AST: `print(inc(1))` where `inc(1)` is a nested call_expr
  - Current behavior: Incorrect edge references in the intermediate call_expr

## Root Cause

When processing chained pipelines, the intermediate desugared call_expr (e.g., `inc(1)`) is added to the nodes array, but subsequent pipeline operations may not correctly reference it. The issue appears to be in how `child_lo`/`child_hi` indices are managed across multiple pipeline transformations.

## Debug Evidence

Edge construction appears correct during parsing:
- First pipeline (`1 |> inc()`): Creates 2 edges (callee + argument)
- Second pipeline (`inc(1) |> print()`): Creates 2 edges (callee + argument)

However, the final AST shows the inner call_expr with only 1 edge instead of 2.

## Next Steps

1. Investigate node/edge index stability when adding desugared call_expr to nodes array
2. Verify that `left` variable correctly references the node added to the array
3. Consider whether intermediate pipeline results need special handling

## Files Affected

- `compiler/libjanus/janus_parser.zig` (lines 2667-2730)
- `compiler/libjanus/tests/pipeline_desugar_test.zig` (test: "pipeline operator: chained desugaring")

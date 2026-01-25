# Known Issues

*No known issues at this time.*

---

## Resolved Issues

### Chained Pipeline Operator (RESOLVED 2026-01-25)

**Status**: ✅ Fixed (3/3 tests passing)
**Date Resolved**: 2026-01-25
**Component**: Pipeline Operator Desugaring

**Issue**: Chained pipelines like `1 |> inc() |> print()` produced incorrect AST.

**Root Cause**: When parsing the RHS of a pipeline operator, `parseExpression` was called with `.none` precedence. This caused the recursive call to handle subsequent `|>` operators, creating deeply nested structures instead of flat left-associative chains.

**Fix**: Changed RHS parsing to use `.call` precedence (higher than `.pipeline`), ensuring left-associative behavior where each `|>` is handled iteratively at the same level.

```zig
// Before (wrong - right-associative):
const rhs = try parseExpression(parser, nodes, .none);

// After (correct - left-associative):
const rhs = try parseExpression(parser, nodes, .call);
```

**Files Changed**:
- `compiler/libjanus/janus_parser.zig` (line 2672)

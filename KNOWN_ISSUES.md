# Known Issues

*No known issues at this time.*

---

## Resolved Issues

### User-Defined Function Calls End-to-End (RESOLVED 2026-01-25)

**Status**: ✅ Complete (5/5 E2E tests passing)
**Date Resolved**: 2026-01-25
**Component**: Function Call Compilation Pipeline

**Milestone**: User-defined functions can now call other user-defined functions end-to-end.

**Features Tested**:
- Simple function with parameters: `func add(a: i32, b: i32) -> i32`
- Chained function calls: `double(x)` then `add(a, b)`
- Nested calls: One function calling another multiple times
- Functions with loops: Parameter used in for loop
- Functions with conditionals: If/else inside function body

**Implementation**:
- QTJIR Lowering: `lowerUserFunctionCall()` creates Call nodes with function name
- LLVM Emitter: Generic call fallback uses `LLVMGetNamedFunction()` to resolve user functions
- Functions emitted before callers, ensuring symbol availability

**Files Changed**:
- `tests/integration/function_call_e2e_test.zig` - New E2E test (5 tests)
- `build.zig` - Added `test-function-call-e2e` step

---

### While Loop End-to-End (RESOLVED 2026-01-25)

**Status**: ✅ Complete (4/4 E2E tests passing)
**Date Resolved**: 2026-01-25
**Component**: While Loop Compilation Pipeline

**Milestone**: While loops now compile and execute end-to-end.

**Syntax**: `while condition do ... end`

**Features**:
- Condition evaluation at loop header
- Body execution when condition is true
- Exit when condition becomes false
- Proper CFG: Header → Branch → Body → Jump(Header) | Exit

**Files Changed**:
- `tests/integration/while_loop_e2e_test.zig` - New E2E test
- `build.zig` - Added `test-while-loop-e2e` step

---

### If/Else Conditionals End-to-End (RESOLVED 2026-01-25)

**Status**: ✅ Complete (3/3 E2E tests passing)
**Date Resolved**: 2026-01-25
**Component**: Conditional Compilation Pipeline

**Milestone**: If/else conditionals now compile and execute end-to-end.

**Syntax Supported**:
- If with else: `if condition do ... else do ... end`
- If without else: `if condition do ... end`
- All comparison operators: `> < >= <= == !=`

**Features**:
- Constant folding: `if 5 > 3` optimizes to direct branch
- Proper control flow: Branch → TrueBlock → Merge, FalseBlock → Merge

**Files Changed**:
- `tests/integration/if_else_e2e_test.zig` - New E2E test
- `build.zig` - Added `test-if-else-e2e` step

---

### For Loop End-to-End Compilation (RESOLVED 2026-01-25)

**Status**: ✅ Complete (2/2 E2E tests passing)
**Date Resolved**: 2026-01-25
**Component**: For Loop Compilation Pipeline

**Milestone**: For loops now compile and execute end-to-end through the complete pipeline:
Source → Parser → ASTDB → QTJIR Lowering → LLVM IR → Native Executable

**Syntax Supported**:
- Exclusive range: `for i in 0..<5 do ... end`
- Inclusive range: `for i in 0..3 do ... end`

**Implementation**:
- Parser: `for identifier in iterable do ... end` or `{ ... }`
- QTJIR Lowering: Creates Phi, Label, Branch, Add, Jump nodes
- LLVM Emitter: Added Phi node support with deferred incoming edge resolution

**Files Changed**:
- `compiler/qtjir/llvm_emitter.zig` - Added `emitPhi()` and `resolveDeferredPhis()`
- `tests/integration/for_loop_e2e_test.zig` - New E2E test
- `build.zig` - Added `test-for-loop-e2e` step

---

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

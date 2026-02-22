# Known Issues

## Active Issues

### Zig 0.16-dev Compatibility (OPEN 2026-02-22)

**Status**: ⚠️ Under Investigation
**Date Reported**: 2026-02-22
**Component**: Toolchain
**Impact**: High — blocks Zig 0.16 migration

**Issue**: Zig 0.16-dev hangs on all compilation tasks on Debian 12 (bookworm) with kernel 6.1.0-42-amd64.

**Symptoms**:
- ✅ `zig version` works
- ❌ `zig build` → hangs indefinitely
- ❌ `zig run` → hangs indefinitely
- ❌ `zig build-exe` → hangs indefinitely
- ❌ `zig build --list-steps` → hangs indefinitely

**Tested Versions**:
- 0.16.0-dev.2623+27eec9bd6 — BROKEN
- 0.16.0-dev.2637+6a9510c0e (latest, Feb 20) — BROKEN

**Hypothesis**: Zig 0.16's new async-first stdlib (`std.Io` vs `std.io`) has a threading/IO issue on this kernel/glibc combination.

**Workaround**: Use **Zig 0.15.2** (fully functional for Janus builds)

**Environment**:
- Debian 12 bookworm
- Kernel 6.1.0-42-amd64
- x86_64

**Coordination**: Need confirmation from @Virgil if Zig 0.16 works on his system.

**Related Reports**:
- `agent-reports/2026-02-22-0750-voxis-zig016-blocker.md`

---

### Test Suite Failures (RESOLVED 2026-02-22 08:48)

**Status**: ✅ **RESOLVED** — 931/934 passing (99.7%)
**Date Reported**: 2026-02-22
**Date Resolved**: 2026-02-22 08:48
**Component**: Test Suite / LLVM Integration
**Impact**: ~~Medium~~ → **HIGH (Resolved)**

**Summary**: ~~83/934 tests failing (91%)~~ → **3/934 failing (99.7%)**

**Root Cause (RESOLVED)**:
```
llc: error: ptr type is only supported in -opaque-pointers mode
```

Janus LLVM emitter generates opaque pointer IR (`ptr` type), but LLVM 14.0.6 requires explicit `-opaque-pointers` flag.

**Fix Applied**: Added `-opaque-pointers` flag to 24 test files in `tests/integration/`

**Tests Fixed (80 tests)**:
- ✅ for_loop_e2e: 0/2 → 2/2
- ✅ function_call_e2e: 0/5 → 5/5
- ✅ array_e2e_tests: 0/12 → 12/12
- ✅ import_e2e_tests: 0/6 → 6/6
- ✅ logical_e2e_tests: 0/10 → 10/10
- ✅ compound_assignment_e2e: 0/12 → 12/12
- ✅ string_e2e_tests: 1/12 → 12/12
- ✅ while_loop_e2e: 2/7 → 7/7
- ✅ async_await_e2e: 8/10 → 10/10
- (+ 60+ more tests)

**Remaining Issues (3 tests)**:
- type_inference_tests (module path config)
- type_system_tests (module path config)
- pattern_coverage_tests (module path config)

These are build.zig configuration issues, not code bugs.

**Related Reports**:
- `agent-reports/2026-02-22-0848-voxis-llvm-opaque-pointers-fix.md`

---

### Test Suite Failures (HISTORICAL — Pre-08:48 Fix)

**Status**: ✅ RESOLVED
**Date Reported**: 2026-02-22
**Component**: Test Suite
**Impact**: ~~Medium~~ → Resolved

**Summary**: ~~83/934 tests failing (91% pass rate)~~ → FIXED

**Passing Tests (Highlights)**:
- ✅ UTCP Transport BDD: 11/11
- ✅ QTJIR tests: All (emitter, validation, SSA, fusion, etc.)
- ✅ Numeric literals e2e: 19/20
- ✅ Modulo e2e: 7/8
- ✅ Struct e2e: 4/5
- ✅ Async/await: 8/10

**Failing Tests (High Impact)**:
| Test Suite | Status | Notes |
|------------|--------|-------|
| type_inference_tests | ❌ Compile error | Module path issue |
| type_system_tests | ❌ Compile error | Module path issue |
| array_e2e_tests | 0/12 ❌ | Arrays not working |
| import_e2e_tests | 0/6 ❌ | Imports not working |
| logical_e2e_tests | 0/10 ❌ | Logical operators not working |
| compound_assignment_e2e | 0/12 ❌ | Compound assignment not working |
| function_call_e2e | 0/5 ❌ | Function calls not working |
| string_e2e_tests | 1/12 ❌ | Strings mostly broken |
| for_loop_e2e | 0/2 ❌ | For loops broken (despite Jan 25 fix) |

**Root Cause Found (2026-02-22 08:45)**:
```
llc: error: ptr type is only supported in -opaque-pointers mode
```

**Analysis**: Janus LLVM emitter generates opaque pointer IR (`ptr` type), but `llc` (LLVM 14.0.6) requires `-opaque-pointers` flag which isn't being passed.

**Fix Options**:
1. Add `-opaque-pointers` flag to `llc` invocation in LLVM emitter
2. Upgrade to LLVM 15+ (opaque pointers by default)
3. Generate typed pointers instead of opaque `ptr`

**Impact**: This explains many e2e test failures — they're LLVM IR compatibility issues, not feature bugs.

**Affected Tests**:
- for_loop_e2e: 0/2
- function_call_e2e: 0/5
- array_e2e_tests: 0/12
- compound_assignment_e2e: 0/12
- (likely others using LLVM codegen)

**Next Steps**:
1. Investigate module path issues
2. Confirm if regressions from recent changes
3. Prioritize fixes based on feature importance

**Related Reports**:
- `agent-reports/2026-02-22-0757-voxis-janus-build-verify.md`

---

## Resolved Issues

### Continue/Break Statements End-to-End (RESOLVED 2026-01-25)

**Status**: ✅ Complete (3/3 E2E tests passing)
**Date Resolved**: 2026-01-25
**Component**: Control Flow Statements

**Milestone**: Continue and break statements now work in for and while loops.

**Syntax**: `continue` and `break` within loop bodies

**Features**:
- Continue in for loop: skips to next iteration (jumps to latch/increment)
- Continue in while loop: skips to next iteration (jumps to header/condition)
- Break exits the loop immediately
- Works with nested conditions (if inside loop)

**Implementation**:
- Parser: Added `break_stmt` and `continue_stmt` parsing to `parseBlockStatements()`
- QTJIR Lowering: Deferred patching system with `pending_breaks` and `pending_continues`
- lowerIf: Skip merge jumps when body ends with terminator (break/continue/return)
- For loops: continue jumps to latch (before increment)
- While loops: continue jumps to header (condition re-evaluation)

**Files Changed**:
- `compiler/libjanus/janus_parser.zig` - Added break/continue parsing
- `compiler/qtjir/lower.zig` - Added `lastNodeIsTerminator()`, modified `lowerIf()`, deferred patching
- `tests/integration/continue_e2e_test.zig` - New E2E test (3 tests)
- `build.zig` - Added `test-continue-e2e` step

---

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

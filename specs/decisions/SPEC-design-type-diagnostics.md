<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# SPEC-design: Type Mismatch Diagnostic Improvements

**Epic:** Type Inference Improvements
**Status:** IN PROGRESS
**Priority:** High (User Experience)

---

## 1. Problem Statement

Current type mismatch errors are technically correct but lack context:

```
error: Type mismatch: expected 'i64', found 'i32'
  --> test.jan:5:10
```

**What's missing:**
1. **Why** was `i64` expected?
2. **Where** does `i32` come from?
3. **How** can the user fix it?

---

## 2. Target Diagnostic Format

### 2.1 Variable Assignment Context

```
error[E3001]: Type mismatch in variable assignment
  --> test.jan:5:10
   |
 5 | let count: i64 = get_value()
   |            ---   ^^^^^^^^^^^ `get_value()` returns `i32`
   |            |
   |            expected `i64` due to type annotation
   |
help: Consider an explicit cast:
   |     let count: i64 = @intCast(get_value())
```

### 2.2 Function Argument Context

```
error[E3002]: Type mismatch in function argument
  --> test.jan:12:20
   |
12 | print_number(value * 2)
   |              ^^^^^^^^^ argument 1 has type `f64`
   |
note: function `print_number` expects argument 1 to be `i32`
  --> lib.jan:7:1
   |
 7 | func print_number(n: i32) do
   |                   ------
   |
help: Consider an explicit cast:
   |     print_number(@intToFloat(value * 2))
```

### 2.3 Return Type Context

```
error[E3003]: Return type mismatch
  --> test.jan:9:12
   |
 9 |     return value
   |            ^^^^^ returns `String`, expected `i32`
   |
note: function `calculate` declared to return `i32`
  --> test.jan:5:1
   |
 5 | func calculate() -> i32 do
   |                     ---
```

### 2.4 Binary Operation Context

```
error[E3004]: Incompatible types in binary operation
  --> test.jan:8:15
   |
 8 | let result = count + name
   |              -----   ^^^^ `name` is `String`
   |              |
   |              `count` is `i32`
   |
note: operator `+` requires both operands to be the same numeric type
```

---

## 3. Implementation Checklist

### 3.1 Error Codes Taxonomy

| Code | Category | Description |
|:-----|:---------|:------------|
| E3001 | Assignment | Type mismatch in variable/let binding |
| E3002 | Call | Type mismatch in function argument |
| E3003 | Return | Return value doesn't match signature |
| E3004 | Binary | Incompatible types in binary op |
| E3005 | Unary | Invalid type for unary operator |
| E3006 | Index | Non-integer index or non-indexable |
| E3007 | Field | Field access on non-struct type |
| E3008 | ConditionI  | Non-boolean condition in if/while |

### 3.2 Required Enhancements

1. **`TypeInferenceDiagnostics.reportTypeMismatchWithContext()`**
   - Accept a `InferenceContext` enum: `assignment`, `argument`, `return_value`, `binary_op`, etc.
   - Print the "why" line based on context.

2. **Secondary Span Support**
   - Link errors to the **declaration site** (e.g., function signature, variable annotation).
   - Show both spans in the diagnostic.

3. **Suggestion Generation**
   - If `i32` -> `i64`: suggest `@intCast()` or `as i64`.
   - If `f64` -> `i32`: warn about truncation, suggest `@floatToInt()`.
   - If `String` -> numeric: error, no suggestion.

4. **Source Line Rendering**
   - Fetch source text from `AstDB` unit.
   - Underline the precise span with `^^^^^`.
   - Show multi-line context if span crosses lines.

---

## 4. Acceptance Criteria (BDD)

### Scenario: Assignment type mismatch shows annotation site
**Given:** Janus source `let x: i64 = 42i32`
**When:** Semantic analysis runs
**Then:** Error message includes:
  - Primary span on `42i32`
  - Secondary span on `i64` annotation
  - Suggestion: `@intCast(42i32)` or remove annotation

### Scenario: Function argument mismatch shows signature
**Given:** Janus source `foo(1.5)` where `foo(n: i32)`
**When:** Semantic analysis runs
**Then:** Error message includes:
  - Primary span on `1.5`
  - Note with function signature location
  - Suggestion for cast

---

## 5. Implementation Order

1. **Extend `error_manager.zig`:**
   - Add `reportTypeMismatchWithContext()`.
   - Add `InferenceContext` enum.

2. **Extend `type_inference_diagnostics.zig`:**
   - Wire up new context-aware reporting.

3. **Modify `type_inference.zig`:**
   - Pass context when generating constraints.
   - On constraint failure, invoke enriched diagnostics.

4. **Add tests:**
   - `test_type_mismatch_diagnostics.zig` with golden output checks.

---

**Estimated Time:** 2-3 hours for core, 1 hour for polish.


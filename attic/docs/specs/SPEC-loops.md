# Specification: Loop Constructs in Janus IR

**Version:** 1.0
**Status:** Draft
**Author:** Voxis Forge

## Overview
This specification defines how `while` loops are represented in the Janus Intermediate Representation (JanusIR).

## Control Flow Graph Structure

A `while` loop generates **three basic blocks**:

1. **Header Block**: Evaluates the loop condition.
2. **Body Block**: Executes the loop body.
3. **Exit Block**: Continues after the loop terminates.

## IR Pattern

```
entry:
    ...
    br header

header:
    %cond = <evaluate condition>
    conditional_branch %cond, body, exit

body:
    <loop body statements>
    br header  // Back-edge

exit:
    <code after loop>
```

## Compilation Logic

### While Statement (`while x < 10 { ... }`)

1. **Terminate Current Block**: Jump to `header`.
2. **Create Header Block**:
   - Evaluate condition expression -> `cond_reg`.
   - Emit `conditional_branch(cond_reg, body, exit)`.
3. **Create Body Block**:
   - Generate body statements.
   - Emit `branch(header)` (back-edge).
4. **Create Exit Block**:
   - Continue with subsequent code.

## Example

**Janus Source:**
```janus
func count() do
    let i = 0
    while i < 10 do
        i = i + 1
    end
    return i
end
```

**Expected IR:**
```
entry:
    %0 = load_constant 0
    alloca(0, 8)
    store(%0, local_var(0))
    br header

header:
    %1 = load_local(0)
    %2 = load_constant 10
    %3 = binary_op(lt, %1, %2)
    conditional_branch(%3, body, exit)

body:
    %4 = load_local(0)
    %5 = load_constant 1
    %6 = binary_op(add, %4, %5)
    store(%6, local_var(0))
    br header

exit:
    %7 = load_local(0)
    return_value(%7)
```

## Infinite Loop Detection
The IR Generator does **not** detect infinite loops. This is the responsibility of:
- **Optimizer**: Dead code elimination.
- **Runtime**: Execution timeout.

## Nested Loops
Nested loops generate nested CFG structures. Each loop has its own header/body/exit blocks.

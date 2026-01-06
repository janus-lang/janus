# Specification: For Loop Constructs in Janus IR

**Version:** 1.0
**Status:** Draft
**Author:** Voxis Forge

## Overview
This specification defines how `for` loops (range-based iteration) are represented in the Janus Intermediate Representation (JanusIR).

## Control Flow Graph Structure

A `for` loop over a range generates **four basic blocks**:

1. **Init Block**: Initializes the loop counter.
2. **Header Block**: Evaluates the loop condition (counter < end).
3. **Body Block**: Executes the loop body.
4. **Exit Block**: Continues after the loop terminates.

## IR Pattern

```
entry:
    <init counter>
    br header

header:
    %counter = load_local(counter_idx)
    %end = <end value>
    %cond = binary_op(lt, %counter, %end)
    conditional_branch %cond, body, exit

body:
    <loop body statements>
    %counter_val = load_local(counter_idx)
    %next = binary_op(add, %counter_val, 1)
    store(%next, counter_idx)
    br header

exit:
    <code after loop>
```

## Compilation Logic

### For Statement (`for i in 0..10 { ... }`)

1. **Initialize Counter**:
   - Allocate local variable for counter.
   - Store start value.
2. **Create Header Block**:
   - Load counter.
   - Compare with end value.
   - Conditional branch to body or exit.
3. **Create Body Block**:
   - Generate body statements.
   - Increment counter.
   - Jump back to header.
4. **Create Exit Block**:
   - Continue with subsequent code.

## Example

**Janus Source:**
```janus
func sum_range() do
    let total = 0
    for i in 0..10 do
        total = total + i
    end
    return total
end
```

**Expected IR:**
```
entry:
    %0 = load_constant 0
    alloca(0, 8)  // total
    store(%0, local_var(0))
    %1 = load_constant 0
    alloca(1, 8)  // i
    store(%1, local_var(1))
    br header

header:
    %2 = load_local(1)  // i
    %3 = load_constant 10
    %4 = binary_op(lt, %2, %3)
    conditional_branch(%4, body, exit)

body:
    %5 = load_local(0)  // total
    %6 = load_local(1)  // i
    %7 = binary_op(add, %5, %6)
    store(%7, local_var(0))
    %8 = load_local(1)  // i
    %9 = load_constant 1
    %10 = binary_op(add, %8, %9)
    store(%10, local_var(1))
    br header

exit:
    %11 = load_local(0)
    return_value(%11)
```

## Range Semantics
- `a..b` is **inclusive** (includes both a and b)
- `a..<b` is **half-open** (includes a, excludes b)
- Step is always 1 (for now)

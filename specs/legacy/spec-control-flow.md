<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Control Flow Specification (Epic 3.2)

> "The Nervous System: Logic must flow, but never ambiguously."

## 1. Overview
This specification defines the behavior of the three core control flow primitives for the `:core` profile: `if`, `while`, and `recursion`.

## 2. Primitives

### 2.1 Conditional (`if` / `else`)
* **Syntax:** `if <condition> <block> [else <block>]`
* **Semantics (MVP):** Statement-level control flow.
    * The condition must evaluate to a boolean (or `i32` != 0 for C-compat).
    * Blocks introduce a new scope.
* **LLVM Lowering:**
    * `icmp ne` (not equal to zero) for the condition.
    * `br i1 %cond, label %then, label %else`
    * Must handle "Merge Blocks" where flow reconvenes.

### 2.2 Loop (`while`)
* **Syntax:** `while <condition> <block>`
* **Semantics:** Pre-checked loop.
* **LLVM Lowering:**
    * Block 1: Header/Condition Check (`icmp` + `br`).
    * Block 2: Body.
    * Block 3: Jump back to Header.
    * Block 4: Exit (Merge).
* **Back-edge Constraint:** The jump back to the header creates the loop cycle.

### 2.3 Recursion
* **Syntax:** Standard function calls where a function calls itself.
* **Invariant:** Stack safety is delegated to the host (LLVM).
* **Constraint:** Recursive calls must eventually terminate.

## 3. The Test Case (Factorial & Fibonacci)
The ultimate proof of this epic is the correct execution of recursive integer math.

### 3.1 Factorial
```janus
func factorial(n: i32) -> i32 do
    if n < 2 do
        return 1
    end
    return n * factorial(n - 1)
end
```

### 3.2 Fibonacci
```janus
func fib(n: i32) -> i32 do
    if n < 2 do
        return n
    end
    return fib(n-1) + fib(n-2)
end
```

---
**Status:** DRAFT
**Owner:** Voxis
**Version:** 1.0

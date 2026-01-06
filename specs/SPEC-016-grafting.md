<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# 🛡️ SPEC-016: GRAFTING - SYNTAX & FLOW (Phase 2)

**Version:** 1.0.0
**Status:** **DRAFT**
**Authority:** Constitutional
**References:** [SPEC-005: Grammar](SPEC-005-grammar.md), [SPEC-007: ASTDB](SPEC-007-astdb-schema.md)

## 1. Introduction

v0.3.0 represents the "Grafting" of specialized language features onto the Janus core. This specification defines the syntactic and semantic rules for **Pipeline Operators** and **Uniform Function Call Syntax (UFCS)**.

---

## 2. ⟁ The Pipeline Operator (`|>`)

### 2.1 Definition
[GRAFT:2.1.1] The **Pipeline Operator** (`|>`) performs left-to-right function application. It takes the expression on the left and passes it as the **first argument** to the call expression on the right.

[GRAFT:2.1.2] **Syntax:** `LHS |> RHS(args...)`
[GRAFT:2.1.3] **Honest Desugaring:** The parser (or lowerer) MUST transform `a |> f(b, c)` into a semantic equivalent of `f(a, b, c)`.

### 2.2 Precedence & Associativity
[GRAFT:2.2.1] **Precedence:** The pipeline operator has lower precedence than unary operators but higher precedence than assignment and logical operators.
[GRAFT:2.2.2] **Associativity:** Left-associative. `a |> b() |> c()` desugars to `c(b(a))`.

### 2.3 Visual Representation
```mermaid
graph LR
    A[Data Source] -->| |> | B[Process A]
    B -->| |> | C[Process B]
    C -->| |> | D[Result]
```

---

## 3. ⊢ Uniform Function Call Syntax (UFCS)

### 3.1 Definition
[GRAFT:3.1.1] **UFCS** allows a function `func f(x: T, ...)` to be called as a method on its first argument: `x.f(...)`.
[GRAFT:3.1.2] **Resolution:** When the compiler encounters `viewer.action(args)`, it MUST attempt to resolve `action` in the following order:
1.  As a native member of the struct/type `viewer`.
2.  As a free function in the current scope that accepts `viewer` (or a reference to it) as the first parameter.

### 3.2 Doctrine: Revealed Complexity
[GRAFT:3.2.1] UFCS MUST NOT hide allocations. If the transformation requires a temporary copy, the compiler MUST emit a warning or require explicit `clone()` if the safety profile is `:core` or `:owned`.

---

## 4. ⟁ Implicit Iterators (`yield`)

### 4.1 Definition
[GRAFT:4.1.1] The `yield` keyword transforms a function into a **Generator**.
[GRAFT:4.1.2] **State Machine:** A generator function is lowered into a state-machine struct with a `.next()` method.
[GRAFT:4.1.3] **Zero Allocation:** Generators are stack-allocated by default unless explicitly moved to the heap.

```janus
func count(n: i32) -> Iterator[i32] do
    var i = 0
    while i < n do
        yield i
        i += 1
    end
end
```

---

## 5. Verification protocol

### Scenario: Pipeline Chaining
- **Given:** `[1, 2, 3] |> map(it * 2) |> filter(it > 2)`
- **When:** Lowered to QTJIR
- **Then:** Resulting graph shows direct call sequence `filter(map([1,2,3], ...), ...)`.

### Scenario: UFCS Substitution
- **Given:** `source.read()` where `read` is a free function.
- **When:** Type checked.
- **Then:** Reference is successfully resolved to `std.io.read(source)`.

---

**Ratified:** Pending
**Authority:** Markus Maiwald + Voxis Forge

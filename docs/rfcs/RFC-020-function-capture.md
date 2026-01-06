<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# RFC 020: Function Capture Shorthand

**Status:** PROPOSED  
**Version:** 0.1.0  
**Author:** Janus Language Architecture Team  
**Target Profile:** `:script` and above  
**Doctrines:** Syntactic Honesty, Mechanism > Policy  
**Inspired By:** Gleam, Elixir  
**Created:** 2025-12-15  

---

## 1. Abstract

This RFC proposes **Function Capture Shorthand** — using `_` as a placeholder to create anonymous functions with partial application. `add(5, _)` becomes shorthand for `|x| add(5, x)`.

## 2. Motivation

### The Problem: Verbose Lambdas
```janus
// Pipeline with explicit lambdas
numbers
    |> list.map(|n| multiply(n, 2))
    |> list.filter(|n| greater_than(n, 10))
    |> list.map(|n| format_number(n, precision: 2))
```

### The Capture Solution
```janus
// Clean partial application
numbers
    |> list.map(multiply(_, 2))
    |> list.filter(greater_than(_, 10))
    |> list.map(format_number(_, precision: 2))
```

### Strategic Value (The "Sticky" Part)
1. **Natural partial application** — `add(5, _)` reads as "add 5 to something"
2. **Pipeline synergy** — Perfect companion to `|>` operator
3. **Muscle memory builder** — Becomes second nature quickly
4. **Going back feels verbose** — `|x|` for every position is tedious

---

## 3. Grammar

```peg
# Function capture creates an anonymous function
capture_expr <- call_expr where args contain '_'

# The underscore is a capture placeholder
capture_placeholder <- '_'
```

---

## 4. Syntax Examples

### Single Capture
```janus
let add_five = add(5, _)
// Equivalent to: |x| add(5, x)

add_five(10)  // Returns 15
```

### Multiple Captures (Positional)
```janus
let swap_sub = subtract(_, _)
// Equivalent to: |a, b| subtract(a, b)

swap_sub(10, 3)  // Returns 7
```

### With Named Arguments
```janus
let send_to = send(_, to: "admin@example.com")
// Equivalent to: |msg| send(msg, to: "admin@example.com")

send_to("Hello!")
```

### Pipeline Integration
```janus
users
    |> list.filter(_.is_active)  // Method shorthand
    |> list.map(format_user(_, style: "brief"))
    |> list.sort_by(_.created_at)
```

### Chained Captures
```janus
// Each _ is a new parameter
let compute = add(_, multiply(_, 2))
// Equivalent to: |a, b| add(a, multiply(b, 2))

compute(10, 5)  // 10 + (5 * 2) = 20
```

---

## 5. The Honest Desugar

Capture expressions are **pure syntactic sugar**:

```janus
add(5, _)
```

Desugars to:
```janus
|$0| add(5, $0)
```

Multiple captures:
```janus
compute(_, _, 3)
```

Desugars to:
```janus
|$0, $1| compute($0, $1, 3)
```

Verification:
```bash
$ janus query desugar 'add(5, _)'
# Output: |$0| add(5, $0)
```

---

## 6. Method Capture Shorthand

For property access and method calls, `_` can be used as the receiver:

### Property Access
```janus
users |> list.map(_.name)
// Equivalent to: list.map(users, |u| u.name)
```

### Method Call
```janus
users |> list.filter(_.is_active())
// Equivalent to: list.filter(users, |u| u.is_active())
```

### Chained
```janus
users |> list.map(_.profile.avatar_url)
// Equivalent to: list.map(users, |u| u.profile.avatar_url)
```

---

## 7. Semantics

### Capture Binding Order
Captures are bound left-to-right, depth-first:
```janus
f(_, g(_, _), _)
// Desugars to: |$0, $1, $2, $3| f($0, g($1, $2), $3)
```

### No Nested Function Capture
Each `_` creates a new lambda parameter:
```janus
outer(inner(_))
// Desugars to: |$0| outer(inner($0))
// NOT: |$0| outer(|$1| inner($1))
```

### Explicit Lambda Takes Precedence
```janus
list.map(|x| add(_, x))
// The _ inside refers to outer capture, not the |x| parameter
// Desugars to: |$0| list.map(|x| add($0, x))
```

---

## 8. Implementation Plan

### Phase 1: Parser
1. Recognize `_` in argument position as capture placeholder
2. Track capture positions during call parsing
3. Generate `CaptureExpr` AST node

### Phase 2: AST Node
```zig
const CaptureExpr = struct {
    call: NodeId,           // The function call being captured
    capture_count: u32,     // Number of _ placeholders
    capture_positions: []u32, // Positions of each _
};
```

### Phase 3: Lowering
Transform capture to anonymous function:
```zig
fn lowerCapture(capture: CaptureExpr) -> LambdaExpr {
    var params = ArrayList(Param).init(allocator);
    for (0..capture.capture_count) |i| {
        params.append(Param{ .name = format("$%d", i) });
    }
    
    // Replace _ placeholders with parameter references
    var body = replacePlaceholders(capture.call, params);
    
    return LambdaExpr{ .params = params, .body = body };
}
```

### Phase 4: Type Inference
- Infer parameter types from call site
- Propagate return type from wrapped function

---

## 9. Interaction with Pipelines

Captures and pipelines are complementary:

### Pipeline with Capture
```janus
data |> transform(_, config)
// Desugars to: transform(data, config)
```

### Capture with Pipeline Hole
```janus
data |> process |> format(__, style: _)
// __ is pipeline hole, _ is capture placeholder
// Desugars to: |$0| format(process(data), style: $0)
```

**Note:** `__` (double underscore) is the pipeline hole; `_` (single) is capture.

---

## 10. Edge Cases

### Empty Capture (Reference, Not Call)
```janus
let fn_ref = add  // This is a function reference, not capture
let captured = add(_, _)  // This is a capture
```

### Nested Calls
```janus
outer(inner(_), _)
// Two separate _ placeholders
// Desugars to: |$0, $1| outer(inner($0), $1)
```

### With Error Propagation
```janus
users |> list.map(fetch_profile(_)?).collect()
// The ? applies to the inner call, not the capture
// Desugars to: users |> list.map(|$0| fetch_profile($0)?).collect()
```

---

## 11. Competitive Analysis

| Language | Capture Syntax | Notes |
|:---------|:---------------|:------|
| **Gleam** | `function(_)` | Direct inspiration |
| **Scala** | `function(_)` | Well-established |
| **Elixir** | `&function(&1)` | More verbose |
| **F#** | `function >>` | Composition, not capture |
| **Kotlin** | `{ function(it) }` | `it` parameter |
| **Janus** | `function(_)` | Gleam-style |

---

## 12. Doctrinal Compliance

| Doctrine | Compliance |
|:---------|:-----------|
| **Syntactic Honesty** | ✅ Desugars to explicit lambda |
| **Mechanism > Policy** | ✅ Works with any function |
| **Revealed Complexity** | ✅ Desugar shows the lambda |
| **Law 3 (Property vs Call)** | ✅ `_.prop` is access, `_.method()` is call |

---

## 13. Profile Gating

| Profile | Function Capture |
|:--------|:-----------------|
| `:core` | ❌ Disabled (use explicit lambdas) |
| `:script` | ✅ Enabled |
| `:service` | ✅ Enabled |
| `:sovereign` | ✅ Enabled |

---

## 14. Risks & Mitigations

| Risk | Mitigation |
|:-----|:-----------|
| **Confusion with wildcard** | `_` in pattern = wildcard; `_` in call = capture |
| **Readability concerns** | IDE shows expanded form on hover |
| **Ordering confusion** | Left-to-right order is intuitive |

---

## 15. References

- [Gleam Function Capture](https://gleam.run/book/tour/functions.html#capture)
- [Scala Placeholder Syntax](https://docs.scala-lang.org/tour/higher-order-functions.html)
- [Elixir Capture Operator](https://hexdocs.pm/elixir/Kernel.SpecialForms.html#&/1)

---

**Voting:**
- [ ] Accept
- [ ] Accept with modifications
- [ ] Defer
- [ ] Reject

---

*Forge Protocol: This RFC was forged to make partial application feel native.*

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# RFC 019: `with` Expression (Chained Scoped Matching)

**Status:** PROPOSED  
**Version:** 0.1.0  
**Author:** Janus Language Architecture Team  
**Target Profile:** `:script` and above  
**Doctrines:** Syntactic Honesty, Mechanism > Policy  
**Inspired By:** Elixir (refined)  
**Created:** 2025-12-15  

---

## 1. Abstract

This RFC proposes the **`with` expression** — a mechanism for chaining multiple pattern matches or fallible operations with early-exit on failure. It replaces 40+ lines of nested `if`/`match` with 10 lines of linear logic.

## 2. Motivation

### The Problem: Nested Match Hell
```janus
func process_order(order_id: i32) -> Result!Error do
    match fetch_order(order_id) {
        .Ok(order) => match validate_order(order) {
            .Ok(valid_order) => match charge_payment(valid_order) {
                .Ok(payment) => match ship_order(valid_order, payment) {
                    .Ok(shipment) => Result.Ok(shipment),
                    .Err(e) => Result.Err(e),
                },
                .Err(e) => Result.Err(e),
            },
            .Err(e) => Result.Err(e),
        },
        .Err(e) => Result.Err(e),
    }
end
```

### The `with` Solution
```janus
func process_order(order_id: i32) -> Shipment!Error do
    with
        .Ok(order) <- fetch_order(order_id),
        .Ok(valid) <- validate_order(order),
        .Ok(payment) <- charge_payment(valid),
        .Ok(shipment) <- ship_order(valid, payment)
    do
        return shipment
    else |error|
        return error
    end
end
```

### Strategic Value (The "Sticky" Part)
1. **The single most addictive construct** — Elixir users call it "genius"
2. **Linear error handling** — Replaces nested pyramids with clean pipelines
3. **Visible early-exit** — The `else` clause shows what happens on failure
4. **Going back is painful** — After using `with`, nested matches feel barbaric

---

## 3. Grammar

```peg
with_expr <- 'with' with_clause (',' with_clause)* block ('else' block)?

with_clause <- pattern '<-' expr     # Pattern match clause
             / expr                   # Boolean guard clause
```

---

## 4. Syntax Examples

### Basic Result Chain
```janus
with
    .Ok(user) <- find_user(id),
    .Ok(profile) <- load_profile(user),
    .Ok(settings) <- fetch_settings(user)
do
    render_dashboard(user, profile, settings)
else |error|
    handle_error(error)
end
```

### Mixed Patterns and Guards
```janus
with
    .Ok(config) <- load_config(path),
    config.version >= MIN_VERSION,          # Boolean guard
    .Some(db_url) <- config.database_url,
    .Ok(conn) <- connect(db_url)
do
    use_connection(conn)
else |_|
    use_fallback()
end
```

### Without Else (Propagates Error)
```janus
func load_data(path: string) -> Data!Error do
    with
        .Ok(content) <- fs.read(path),
        .Ok(parsed) <- json.parse(content),
        .Ok(data) <- Data.from_json(parsed)
    do
        return data
    end  // Errors propagate automatically
end
```

### Nested Destructuring
```janus
with
    .Ok({ user, token }) <- authenticate(credentials),
    .Ok({ permissions }) <- authorize(token),
    .Admin <- user.role when permissions.contains(.all)
do
    enable_admin_features()
end
```

---

## 5. The Honest Desugar

The `with` expression desugars to nested `match`:

```janus
with
    .Ok(a) <- expr1,
    .Ok(b) <- expr2(a)
do
    use(a, b)
else |e|
    handle(e)
end
```

Desugars to:
```janus
match expr1 {
    .Ok(a) => match expr2(a) {
        .Ok(b) => use(a, b),
        e => handle(e),
    },
    e => handle(e),
}
```

This can be verified:
```bash
$ janus query desugar file.jan
# Shows nested match structure
```

---

## 6. Semantics

### Clause Evaluation
1. Clauses are evaluated left-to-right, top-to-bottom
2. Each clause must succeed for the next to execute
3. Bindings from earlier clauses are available in later clauses
4. First failing clause jumps to `else` block

### Pattern Match Failure
If a pattern doesn't match, the non-matching value is passed to `else`:
```janus
with
    .Some(x) <- maybe_value  // If None, None goes to else
do
    use(x)
else |failed_value|
    // failed_value is .None here
    handle_missing()
end
```

### Boolean Guard Failure
Boolean guards that return `false` pass `false` to `else`:
```janus
with
    .Ok(config) <- load_config(),
    config.version >= MIN_VERSION  // If false, false goes to else
do
    use(config)
else |guard_result|
    // guard_result is false here
    log.error("Version too old")
end
```

### Binding Scope
Bindings are available:
- In subsequent clauses
- In the `do` block
- NOT in the `else` block (they may not have been bound)

---

## 7. Implementation Plan

### Phase 1: Parser
1. Add `with` expression to expression grammar
2. Parse `with_clause` list with `,` separators
3. Parse `do` block and optional `else` block

### Phase 2: AST Node
```zig
const WithExpr = struct {
    clauses: []const WithClause,
    success_block: NodeId,
    failure_block: ?NodeId,  // Optional else block
};

const WithClause = union(enum) {
    pattern_match: struct {
        pattern: NodeId,
        expr: NodeId,
    },
    guard: NodeId,  // Boolean expression
};
```

### Phase 3: Lowering
Transform `with` to nested `match` in lowering pass:
```zig
fn lowerWithExpr(with_expr: WithExpr) -> MatchExpr {
    // Build nested match from inside out
    var result = with_expr.success_block;
    for (with_expr.clauses.reverse()) |clause| {
        result = createMatch(clause, result, with_expr.failure_block);
    }
    return result;
}
```

### Phase 4: Type Inference
- Infer types from patterns
- Ensure `else` block handles all possible failure types
- Union failure types if multiple clauses can fail differently

---

## 8. Error Type Handling

### Homogeneous Errors
When all clauses fail with same type:
```janus
with
    .Ok(a) <- op1(): Result[A, Error],
    .Ok(b) <- op2(): Result[B, Error]
do
    use(a, b)
else |e: Error|  // All failures are Error
    handle(e)
end
```

### Heterogeneous Errors
When clauses fail with different types:
```janus
with
    .Ok(a) <- op1(): Result[A, E1],
    .Ok(b) <- op2(): Result[B, E2]
do
    use(a, b)
else |e: E1 | E2|  // Union type
    match e {
        .E1(e1) => handle_e1(e1),
        .E2(e2) => handle_e2(e2),
    }
end
```

---

## 9. Competitive Analysis

| Language | Similar Feature | Notes |
|:---------|:----------------|:------|
| **Elixir** | `with` expression | Direct inspiration |
| **Scala** | `for` comprehension | More verbose |
| **Haskell** | `do` notation | Requires Monad knowledge |
| **Rust** | `?` + `let else` | More fragmented |
| **Go** | Nothing | Just nested `if err != nil` |
| **Janus** | `with` expression | Elixir-inspired, simplified |

---

## 10. Doctrinal Compliance

| Doctrine | Compliance |
|:---------|:-----------|
| **Syntactic Honesty** | ✅ Desugars to nested `match` |
| **Mechanism > Policy** | ✅ Works with any pattern, not just Result |
| **Revealed Complexity** | ✅ `janus query desugar` shows the truth |
| **Readability First** | ✅ Primary motivation is linear readability |

---

## 11. Profile Gating

| Profile | `with` Expression |
|:--------|:------------------|
| `:core` | ❌ Disabled (use explicit `match`) |
| `:script` | ✅ Enabled |
| `:service` | ✅ Enabled |
| `:sovereign` | ✅ Enabled |

---

## 12. Risks & Mitigations

| Risk | Mitigation |
|:-----|:-----------|
| **Learning curve** | Good error messages; `janus query desugar` |
| **Hidden complexity** | Desugaring is explicit and queryable |
| **Error type confusion** | Clear type inference; union types visible |

---

## 13. References

- [Elixir with Expression](https://hexdocs.pm/elixir/Kernel.SpecialForms.html#with/1)
- [Scala for Comprehensions](https://docs.scala-lang.org/tour/for-comprehensions.html)
- [Haskell do Notation](https://wiki.haskell.org/Do_notation)

---

**Voting:**
- [ ] Accept
- [ ] Accept with modifications
- [ ] Defer
- [ ] Reject

---

*Forge Protocol: This RFC was forged to eliminate nested match pyramids.*

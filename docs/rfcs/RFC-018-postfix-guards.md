<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# RFC 018: Postfix Guard Clauses

**Status:** PROPOSED (Already in Grammar)  
**Version:** 0.1.0  
**Author:** Janus Language Architecture Team  
**Target Profile:** `:core` and above  
**Doctrines:** Syntactic Honesty, Readability  
**Created:** 2025-12-15  

---

## 1. Abstract

This RFC formalizes **Postfix Guard Clauses** — allowing `when` and `unless` to appear after statements, enabling linear early-exit patterns that read like prose.

**Note:** This feature is already in the grammar spec. This RFC formalizes the semantics and implementation.

## 2. Motivation

### The Problem: Pyramid of Doom
```janus
func process(user: User?) -> Result do
    if user == null do
        return Error.NotFound
    end
    if not user.is_active do
        return Error.Inactive
    end
    if user.balance < 0 do
        return Error.InsufficientFunds
    end
    // Finally, the actual logic
    return do_work(user)
end
```

### The Postfix Solution
```janus
func process(user: User?) -> Result do
    return Error.NotFound when user == null
    return Error.Inactive when not user.is_active
    return Error.InsufficientFunds when user.balance < 0

    // Linear flow, no nesting
    return do_work(user)
end
```

### Strategic Value (The "Sticky" Part)
1. **Reads like prose** — "return error when user is null"
2. **Eliminates nesting** — Guards are at the margin, not indented
3. **Encourages early-exit** — Pattern aligns with best practices
4. **Going back feels cluttered** — Once you have this, `if x { return }` feels verbose

---

## 3. Grammar (Already Specified)

From `specs/syntax.md`:
```peg
# Postfix conditional statements
postfix_when_stmt <- simple_stmt 'when' expr    # return error when x == null
postfix_unless_stmt <- simple_stmt 'unless' expr # log.info msg unless quiet
```

---

## 4. Syntax Examples

### Basic Guard
```janus
return Error.NotFound when user == null
```

### Multiple Guards
```janus
func validate(request: Request) -> Result do
    return Error.MissingAuth when request.auth == null
    return Error.BadMethod when request.method != "POST"
    return Error.TooLarge when request.body.len > MAX_SIZE
    return Error.RateLimited when rate_limiter.check(request.ip)

    return process(request)
end
```

### With `unless` (Inverse Logic)
```janus
log.debug "Processing request" unless quiet_mode
process(item) unless item.is_processed
panic("Invariant violated") unless invariant_holds()
```

### Combined with Other Statements
```janus
// Assignment guard
let user = cache.get(id) when cache.has(id)

// Expression guard
send_notification(user) when user.wants_notifications

// Break/continue guard
break when iteration_count > MAX_ITERATIONS
continue when item.is_skip_marked
```

---

## 5. The Honest Desugar

Postfix guards are **pure syntactic sugar**:

```janus
return Error.NotFound when user == null
```

Desugars to:
```janus
if user == null do
    return Error.NotFound
end
```

This can be verified:
```bash
$ janus query desugar 'return error when x == null'
# Output: if x == null do return error end
```

---

## 6. Semantics

### Evaluation Order
1. Guard condition is evaluated first
2. If condition is true (for `when`) or false (for `unless`), statement executes
3. If condition is false/true respectively, execution continues to next statement

### Short-Circuit Behavior
The guarded statement is NOT evaluated if guard fails:
```janus
// expensive_call() is NOT called if should_skip
let result = expensive_call() when not should_skip
```

### Type Implications
Guard clauses do not affect type narrowing after the statement:
```janus
return Error.NotFound when user == null
// After this line, user is still User? (not narrowed)
// Use 'if let' for type narrowing
```

---

## 7. Implementation Plan

### Phase 1: Parser Wiring
1. Postfix `when`/`unless` already in grammar
2. Wire up in `parseStatement()` in `janus_parser.zig`
3. After parsing simple statement, check for `when`/`unless`
4. Parse guard expression

### Phase 2: AST Node
Create `PostfixGuardStmt` node:
```zig
const PostfixGuardStmt = struct {
    statement: NodeId,      // The guarded statement
    guard: NodeId,          // The condition expression
    is_unless: bool,        // when = false, unless = true
};
```

### Phase 3: Lowering
Transform to `if` statement in lowering pass:
```zig
fn lowerPostfixGuard(stmt: PostfixGuardStmt) -> IfStmt {
    const condition = if (stmt.is_unless) 
        negate(stmt.guard) 
    else 
        stmt.guard;
    return IfStmt{ .condition = condition, .then = stmt.statement };
}
```

### Phase 4: Flow Analysis
- Mark unreachable code after `return ... when true`
- Integrate with type narrowing for combined patterns

---

## 8. Edge Cases

### Chained Guards
Guards cannot be chained:
```janus
// ❌ Invalid
return error when x when y

// ✅ Use 'and'
return error when x and y
```

### Nested Expressions
The guard expression can be arbitrarily complex:
```janus
return error when (a > b and c) or d.check()
```

### With Blocks
Guard clauses only work with simple statements:
```janus
// ❌ Invalid - blocks not allowed
if x do y end when z

// ✅ Use standard if
if z do
    if x do y end
end
```

---

## 9. Competitive Analysis

| Language | Postfix Guards | Syntax |
|:---------|:---------------|:-------|
| **Ruby** | ✅ Full | `return if x`, `puts "hi" unless y` |
| **Perl** | ✅ Full | `return if $x`, `print "hi" unless $y` |
| **Elixir** | ❌ No | Guards in function heads only |
| **Rust** | ❌ No | No postfix conditionals |
| **Python** | ❌ No | No postfix conditionals |
| **Janus** | ✅ Full | `return when x`, `action unless y` |

---

## 10. Doctrinal Compliance

| Doctrine | Compliance |
|:---------|:-----------|
| **Syntactic Honesty** | ✅ Desugars to simple `if` |
| **Readability First** | ✅ Primary motivation is readability |
| **Mechanism > Policy** | ✅ Works with any simple statement |
| **Law 2 (Structural Divide)** | ✅ Simple statements only, no blocks |

---

## 11. Profile Gating

| Profile | Postfix Guards |
|:--------|:---------------|
| `:core` | ✅ Enabled |
| `:script` | ✅ Enabled |
| `:service` | ✅ Enabled |
| `:sovereign` | ✅ Enabled |

---

## 12. IDE Support

- **Autocomplete:** After `when`/`unless`, suggest boolean expressions
- **Formatting:** Guards stay on same line as statement
- **Highlighting:** `when`/`unless` as control-flow keywords

---

## 13. References

- [Ruby Postfix Conditionals](https://ruby-doc.org/docs/ruby-doc-bundle/Manual/man-1.4/syntax.html#postfix)
- [Janus Grammar Specification](../specs/syntax.md) (Lines 344-346)

---

**Voting:**
- [ ] Accept
- [ ] Accept with modifications
- [ ] Defer
- [ ] Reject

---

*Forge Protocol: This RFC was forged to eliminate the pyramid of doom.*

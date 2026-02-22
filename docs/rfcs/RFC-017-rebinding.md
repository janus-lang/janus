<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# RFC 017: Rebinding (Immutable Shadowing)

**Status:** PROPOSED  
**Version:** 0.1.0  
**Author:** Janus Language Architecture Team  
**Target Profile:** `:script` and above  
**Doctrines:** Syntactic Honesty, Mechanism > Policy  
**Created:** 2025-12-15  

---

## 1. Abstract

This RFC proposes **Rebinding** — allowing `let` declarations to shadow previous bindings of the same name within a scope. This reduces naming fatigue and makes data transformation pipelines more readable.

## 2. Motivation

### The Problem
Without rebinding, you're forced to invent names for intermediate states:
```janus
// Naming hell
let data_raw = http.get(url)
let data_json = json.parse(data_raw)
let data_validated = validate(data_json)
let data_processed = process(data_validated)
use(data_processed)
```

### The Rebinding Solution
```janus
// Clean pipeline — always 'data', always refined
let data = http.get(url)
let data = json.parse(data)
let data = validate(data)?
let data = process(data)
use(data)
```

### Strategic Value (The "Sticky" Part)
1. **Zero naming tax** — You care about the current state, not the history
2. **Immutability preserved** — Each `let` creates a NEW binding
3. **Looks like mutation, behaves like values** — Best of both worlds
4. **Going back feels primitive** — Once you have this, `data1`, `data2` feels barbaric

---

## 3. The Mechanism

### Rule
A `let` declaration may shadow a previously declared `let` binding in the same scope:

```janus
let x = 1       // x: i32 = 1
let x = x + 1   // x: i32 = 2 (NEW binding, shadows previous)
let x = $"{x}"  // x: string = "2" (NEW binding, different type allowed)
```

### Important Distinctions

#### This is NOT Mutation
```janus
let x = 1
let x = 2  // This creates a NEW binding, x=1 still exists (just shadowed)
```

#### `var` is Different
```janus
var x = 1
x = 2      // This MUTATES the existing binding
```

#### Type Change is Allowed
```janus
let data = "123"     // data: string
let data = i32.parse(data)  // data: i32 (different type!)
```

---

## 4. Syntax Examples

### Data Transformation Pipeline
```janus
func fetch_user(id: i32) -> User!Error do
    let response = http.get($"/api/users/{id}")
    let response = response?             // Propagate error
    let response = json.parse(response)?
    let user = User.from_json(response)?
    let user = user.validate()?
    return user
end
```

### Configuration Refinement
```janus
let config = Config.defaults()
let config = config.merge(file_config)?
let config = config.merge(env_config)?
let config = config.merge(cli_config)?
// Final config is fully merged
use_config(config)
```

### Numeric Processing
```janus
let n = read_input()
let n = n.trim()
let n = i32.parse(n)?
let n = n * 2
let n = n.abs()
print($"Result: {n}")
```

---

## 5. Scope Rules

### Block Scope
```janus
let x = 1
if condition do
    let x = 100   // Shadows outer x within this block
    print(x)      // Prints: 100
end
print(x)          // Prints: 1 (outer x unchanged)
```

### Function Scope
```janus
func process(input: string) -> string do
    let input = input.trim()      // Shadows parameter
    let input = input.to_upper()  // Shadows previous
    return input
end
```

### No Cross-Scope Bleeding
```janus
if condition do
    let x = 1
end
print(x)  // ❌ Error: x not in scope (inner x doesn't leak)
```

---

## 6. The Honest Desugar

Rebinding is **pure syntactic sugar**. Each `let` creates a genuinely new binding:

```janus
let x = 1
let x = x + 1
let x = $"{x}"
```

Desugars conceptually to:
```janus
let x_0 = 1
let x_1 = x_0 + 1
let x_2 = $"{x_1}"
// x refers to x_2 after this point
```

This can be verified with `janus query desugar`:
```bash
$ janus query desugar file.jan
# Shows unique internal names for each binding
```

---

## 7. Error Handling Integration

Rebinding pairs elegantly with error propagation:

```janus
func load_config(path: string) -> Config!Error do
    let content = fs.read(path)?
    let content = content.trim()
    let config = toml.parse(content)?
    let config = config.validate()?
    return config
end
```

Each `?` can transform the type, and the shadow keeps the name clean.

---

## 8. Implementation Plan

### Phase 1: Parser Changes
No parser changes needed. `let x = ...` is already valid syntax.

### Phase 2: Semantic Analysis Changes
1. Modify `semantic_analyzer.zig` to allow shadowing with `let`
2. Each `let` creates a new symbol in the symbol table
3. Previous binding becomes inaccessible (but still exists for lifetime)

### Phase 3: LLVM Codegen
1. Each shadowed binding gets a unique SSA name
2. Lifetime of shadowed bindings extends until overwritten
3. Optimizer can often eliminate dead shadowed bindings

### Phase 4: IDE/LSP Integration
1. Show which binding a reference resolves to
2. "Find all references" includes shadowing declarations
3. Rename refactoring handles shadows correctly

---

## 9. Competitive Analysis

| Language | Shadowing Support | Notes |
|:---------|:------------------|:------|
| **Rust** | ✅ Full | First-class feature |
| **Elixir** | ✅ Full | Idiomatic in pipelines |
| **F#** | ✅ Full | Part of ML heritage |
| **Go** | ⚠️ Partial | Only with `:=` in new scope |
| **Python** | ✅ Full | No distinction (all mutable) |
| **C/C++** | ⚠️ Warnings | Usually flagged by linters |
| **Janus** | ✅ Full | `let` shadows, `var` mutates |

---

## 10. Doctrinal Compliance

| Doctrine | Compliance |
|:---------|:-----------|
| **Syntactic Honesty** | ✅ Each `let` truly creates a new binding |
| **Mechanism > Policy** | ✅ Shadowing is a tool, not mandated |
| **Revealed Complexity** | ✅ `janus query desugar` shows unique bindings |
| **Immutability Default** | ✅ Reinforces immutability — no mutation, just new values |

---

## 11. Risks & Mitigations

| Risk | Mitigation |
|:-----|:-----------|
| **Accidental shadowing** | Linter warning for unused shadows |
| **Debugging confusion** | Debugger shows shadow chain |
| **Type confusion** | IDE shows type at each shadow point |
| **Memory concerns** | Optimizer eliminates dead shadows |

---

## 12. Profile Gating

| Profile | Rebinding Support |
|:--------|:------------------|
| `:core` | ✅ Enabled (useful for teaching) |
| `:script` | ✅ Enabled |
| `:service` | ✅ Enabled |
| `:sovereign` | ✅ Enabled |

Rebinding is allowed in all profiles because:
1. It simplifies code
2. It reinforces immutability
3. It has zero runtime cost

---

## 13. Interaction with `var`

`var` declarations CANNOT be shadowed by `let`:

```janus
var x = 1
let x = 2  // ❌ Error: Cannot shadow mutable 'var x' with 'let x'
```

Rationale: Shadowing a `var` would be confusing — does `x` refer to the mutable or immutable binding?

However, `var` CAN be shadowed by `var`:
```janus
var x = 1
var x = x + 1  // ✅ New mutable binding
```

---

## 14. References

- [Rust Shadowing](https://doc.rust-lang.org/book/ch03-01-variables-and-mutability.html#shadowing)
- [Elixir Variable Rebinding](https://elixir-lang.org/getting-started/pattern-matching.html)
- [F# Shadowing](https://docs.microsoft.com/en-us/dotnet/fsharp/language-reference/values/index#let-bindings)

---

**Voting:**
- [ ] Accept
- [ ] Accept with modifications
- [ ] Defer
- [ ] Reject

---

*Forge Protocol: This RFC was forged to eliminate naming hell.*

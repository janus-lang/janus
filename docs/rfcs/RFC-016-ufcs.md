<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# RFC 016: Uniform Function Call Syntax (UFCS)

**Status:** PROPOSED  
**Version:** 0.1.0  
**Author:** Janus Language Architecture Team  
**Target Profile:** `:script` and above  
**Doctrines:** Syntactic Honesty, Discoverability  
**Created:** 2025-12-15  

---

## 1. Abstract

This RFC proposes **Uniform Function Call Syntax (UFCS)** — a mechanism allowing any function to be called using method syntax on its first argument. This enables fluent, discoverable APIs without forcing everything into classes.

## 2. Motivation

### The Problem
Traditional function calls require wrapping:
```janus
// Nested, hard to read, evaluation order unclear
let result = validate(parse(fetch(url)))

// Explicit, but requires importing and prefix-calling
import std.string
let upper = std.string.to_upper(my_str)
```

### The UFCS Solution
```janus
// Fluent, left-to-right reading, discoverable via IDE
let result = url.fetch().parse().validate()

// Type "my_str." and see all available functions
let upper = my_str.to_upper()
```

### Strategic Value (The "Sticky" Part)
1. **IDE feels psychic** — Type `.` and see all functions that accept this type
2. **Fluent APIs for free** — No need to design builder patterns
3. **Module functions as methods** — `string.to_upper(s)` becomes `s.to_upper()`
4. **Going back feels primitive** — Once you have this, nested calls feel barbaric

---

## 3. The Mechanism

### Rule
If a function `func foo(x: T, ...)` exists in scope, you can call it as:
```janus
value.foo(...)  // Equivalent to foo(value, ...)
```

### Resolution Order
1. **True methods first** — If `T` has a method named `foo`, use it
2. **UFCS second** — If a function `foo(T, ...)` exists in scope, use it
3. **Error if ambiguous** — Multiple candidates = compile error

### Scope Rules
UFCS only considers functions that are:
1. In the current module
2. Explicitly imported
3. In the prelude (`:script` profile)

---

## 4. Syntax Examples

### Basic Usage
```janus
import std.string

let name = "markus"

// Traditional call
let upper1 = std.string.to_upper(name)

// UFCS call
let upper2 = name.to_upper()

// Both equivalent, UFCS preferred for readability
```

### Chaining
```janus
import std.array
import std.string

let result = users
    .filter(|u| u.is_active)
    .map(|u| u.name.to_upper())
    .join(", ")
```

### With Pipelines
UFCS and pipelines are complementary:
```janus
// UFCS style
users.filter(|u| u.is_active).map(|u| u.name)

// Pipeline style (when you need hole positioning)
users |> filter(__, |u| u.is_active) |> map(__, |u| u.name)
```

---

## 5. The Honest Desugar

UFCS is **pure syntactic sugar**. The compiler transforms:

```janus
x.foo(a, b)
```

Into:

```janus
foo(x, a, b)
```

This can be verified with `janus query desugar`:
```bash
$ janus query desugar 'name.to_upper()'
# Output: std.string.to_upper(name)
```

---

## 6. Resolution Examples

### No Ambiguity (Common Case)
```janus
import std.string

let s = "hello"
s.to_upper()  // Resolves to std.string.to_upper(s)
```

### Method Takes Precedence
```janus
struct User {
    name: string
    
    func greet(self) -> string do
        return $"Hello, {self.name}"
    end
}

func greet(u: User) -> string do
    return $"Hi there, {u.name}"
end

let u = User { name: "Markus" }
u.greet()  // Calls User.greet (method wins)
```

### Explicit Disambiguation
```janus
import std.string as str
import std.bytes as bytes

let data = get_data()  // Could be string or bytes

// Explicit qualification when needed
str.length(data)      // Force string interpretation
bytes.length(data)    // Force bytes interpretation

// Or use type annotation
let s: string = data
s.length()            // Unambiguous
```

---

## 7. Implementation Plan

### Phase 1: Semantic Analysis Changes
1. Modify function resolution in `semantic_analyzer.zig`
2. When encountering `expr.ident(args)`:
   - Check if `expr` has method `ident`
   - If not, search scope for functions named `ident` with first param matching `typeof(expr)`
3. Collect candidates and apply overload resolution

### Phase 2: Error Messages
1. "No method or function 'foo' for type 'T'"
2. "Ambiguous UFCS call: multiple candidates for 'foo' on type 'T'"
3. Suggestion: "Did you mean to import 'std.string'?"

### Phase 3: IDE/LSP Integration
1. Autocomplete `.` to show available functions
2. Show "UFCS" badge for non-method functions
3. Go-to-definition works correctly

---

## 8. Competitive Analysis

| Language | UFCS Support | Notes |
|:---------|:-------------|:------|
| **Nim** | ✅ Full | First-class feature |
| **D** | ✅ Full | First-class feature |
| **Rust** | ⚠️ Limited | Only for traits, not free functions |
| **C++** | ❌ No | Proposed but rejected |
| **Go** | ❌ No | Methods only on types in same package |
| **Janus** | ✅ Full | First-class feature |

---

## 9. Doctrinal Compliance

| Doctrine | Compliance |
|:---------|:-----------|
| **Syntactic Honesty** | ✅ `janus query desugar` reveals the function call |
| **Law 1 (Command/Call)** | ✅ UFCS follows same rules — `()` still required for zero-arg |
| **Discoverability** | ✅ Primary motivation is discoverability |
| **Mechanism > Policy** | ✅ Works with any function, not just designated ones |

### Zero-Arg Rule Still Applies
```janus
func len(s: string) -> i32 do ... end

let s = "hello"
s.len()   // ✅ Valid UFCS call
s.len     // ❌ Invalid - this is a function value, not a call
```

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|:-----|:-----------|
| **Name collisions** | Methods take precedence; explicit qualification available |
| **Confusion about method vs function** | IDE shows "UFCS" badge; `janus query desugar` reveals truth |
| **Performance** | Zero runtime cost — pure compile-time transformation |
| **Readability ambiguity** | Explicit imports required; no global pollution |

---

## 11. Profile Gating

| Profile | UFCS Support |
|:--------|:-------------|
| `:core` | ❌ Disabled (explicit calls only) |
| `:script` | ✅ Enabled with prelude functions |
| `:service` | ✅ Enabled with imported functions |
| `:sovereign` | ✅ Enabled with imported functions |

---

## 12. Future Work

- UFCS with generic functions
- UFCS in pattern matching contexts
- Extension traits (a la Rust)

---

## 13. References

- [Nim UFCS Documentation](https://nim-lang.org/docs/manual.html#procedures-method-call-syntax)
- [D Language UFCS](https://dlang.org/spec/function.html#pseudo-member)
- [Janus Law 1: Command/Call Bifurcation](../specs/syntax.md)

---

**Voting:**
- [ ] Accept
- [ ] Accept with modifications
- [ ] Defer
- [ ] Reject

---

*Forge Protocol: This RFC was forged to make the IDE feel psychic.*

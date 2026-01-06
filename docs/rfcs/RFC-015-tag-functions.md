<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# RFC 015: Generalized Tag Functions (Honest Sugar)

**Status:** PROPOSED  
**Version:** 0.1.0  
**Author:** Janus Language Architecture Team  
**Target Profile:** `:script` (Ergonomics), `:sovereign` (Implementation)  
**Doctrines:** Syntactic Honesty, Mechanism > Policy  
**Created:** 2025-12-15  

---

## 1. Abstract

This RFC proposes **Generalized Tag Functions** — a mechanism to allow arbitrary identifiers as prefixes to string literals, enabling compile-time validated DSLs (SQL, HTML, Shell, Regex) with zero runtime overhead.

## 2. Motivation

### The Problem
JavaScript's Tagged Templates (`html`\`...\`) are beloved but flawed:
- They happen entirely at **runtime**
- Zero type safety for interpolated values
- SQL injection is prevented by convention, not by design

### The Janus Solution
We adopt the **syntax** but move the **semantics** to compile-time:
- SQL parsing happens during the build, not the request
- Type-safe interpolation prevents injection by design
- DSL authors use standard Janus functions, no macro system

### Strategic Value (The "Sticky" Part)
1. **For the JS Developer:** Familiar syntax: `html"..."`, `sql"..."`, `sh"..."`
2. **For the Systems Engineer:** Comptime validation, zero runtime cost
3. **For the Enterprise:** Security by design (SQL injection impossible)

---

## 3. Grammar Amendment

### Current Grammar (String Literals)
```peg
literal <- STRING / INT / FLOAT ...
```

### Proposed Amendment
```peg
literal <- tag_literal / STRING / INT ...

# A tag is an identifier immediately followed by a string or interpolated string
# NO WHITESPACE allowed between identifier and quote
tag_literal <- IDENT string_literal
string_literal <- '"' ... '"' 
                / '$"' interp_part* '"'
```

### Syntax Examples
```janus
// Valid Tag Literals
let q = sql"SELECT * FROM users WHERE id = {uid}"
let h = html"<div class='{cls}'>{content}</div>"
let c = sh"ls -la {dir}"
let r = re"^\d{4}-\d{2}-\d{2}$"
let b = hex"DE AD BE EF 00 00"

// Invalid (Whitespace is forbidden between tag and quote)
let q = sql "SELECT..."  // ❌ Parse Error: Call requires parens
```

---

## 4. The Honest Desugar (The Mechanism)

This feature is **pure syntactic sugar**. No magic runtime behavior.

### Transformation Rule

A tag literal `tag"s0 {e1} s1 {e2} s2"` desugars into:

```janus
tag(
    // Argument 1: Static Fragments (Comptime Slice)
    &["s0", "s1", "s2"], 
    
    // Argument 2: Dynamic Values (Tuple)
    (e1, e2)
)
```

### Concrete Example

**User writes:**
```janus
let user_id = 105
let query = sql"SELECT * FROM users WHERE id = {user_id} AND active = true"
```

**Compiler sees:**
```janus
sql(
    &["SELECT * FROM users WHERE id = ", " AND active = true"],
    (user_id,)
)
```

**The Tag Function Implementation (`std/sql.jan`):**
```janus
func sql(fragments: []string, args: tuple) -> Query {
    // 1. COMPTIME VALIDATION:
    // 'fragments' is a compile-time constant slice
    comptime {
        if not SqlParser.is_valid(fragments) {
             compile_error("Invalid SQL syntax in query string")
        }
    }

    // 2. RUNTIME BUILD:
    // We do NOT concatenate. We build a parameterized query object.
    // This makes SQL injection impossible by definition.
    return Query.new(sql: fragments.join("?"), params: args)
}
```

---

## 5. Use Cases

### 5.1 SQL Injection Killer
```janus
let user_input = "'; DROP TABLE users; --"
let query = sql"SELECT * FROM users WHERE name = {user_input}"
// Compiles to: Query { sql: "SELECT * FROM ... WHERE name = ?", params: ("'; DROP...") }
// The dangerous input is NEVER interpolated into the SQL string
```

### 5.2 Shell Script Replacement
```janus
let file = "data with spaces.csv"
sh"grep 'error' {file} | sort > errors.log"
// 'file' is passed as an argument to execve, not concatenated
// No shell escaping hell
```

### 5.3 HTML Templates (XSS Prevention)
```janus
let name = "<script>alert('pwn')</script>"
let page = html"<h1>Hello {name}</h1>"
// The 'html' function knows 'name' is between tags
// Automatic contextual encoding: &lt;script&gt;...
```

### 5.4 Hex/Binary Literals
```janus
let packet = hex"DE AD BE EF 00 00"  // Returns []u8
let magic = b64"SGVsbG8gV29ybGQ="    // Base64 decoded at comptime
```

### 5.5 Regex with Compile-Time Validation
```janus
let pattern = re"^\d{4}-\d{2}-\d{2}$"  // Regex syntax validated at comptime
// Invalid regex = compile error
let bad = re"[invalid("  // ❌ Compile Error: Unclosed character class
```

---

## 6. Implementation Plan

### Phase 1: Tokenizer Changes
1. Modify `janus_tokenizer.zig` to recognize `IDENT"..."` as a single token
2. Add new token type: `tag_string_literal`
3. Store both tag name and string content

### Phase 2: Parser Changes
1. Modify `janus_parser.zig` to parse tag literals in primary expressions
2. Create `TaggedStringLiteral` node in ASTDB
3. Store: `tag_name`, `static_fragments[]`, `interpolations[]`

### Phase 3: Lowering/Desugar Pass
1. Transform `TaggedStringLiteral` into function call
2. Split string at interpolation points
3. Generate comptime slice for fragments
4. Generate tuple for dynamic values

### Phase 4: Standard Library
1. Implement `sql`, `html`, `sh`, `re`, `hex`, `b64` tag functions
2. Each validates at comptime and builds safe runtime representations

---

## 7. Competitive Analysis

| Feature | JavaScript | Rust (`format!`) | Janus Tag Functions |
|:--------|:-----------|:-----------------|:--------------------|
| **Syntax** | \`tag\`...\` | `macro!("...")` | `tag"..."` |
| **Parsing** | Runtime | Comptime (Macro) | **Comptime (Function)** |
| **Overhead** | High (Allocations) | Zero | **Zero** |
| **Extensibility** | High | Low (Need Macro) | **High (Just a Func)** |
| **Learning Curve** | Low | High (Macro DSL) | **Low (Just funcs)** |

**Superiority Verdict:** Janus combines JavaScript's extensibility with Rust's zero-cost, without requiring a separate macro language.

---

## 8. Doctrinal Compliance

| Doctrine | Compliance |
|:---------|:-----------|
| **Syntactic Honesty** | ✅ Desugaring is explicit and queryable |
| **Mechanism > Policy** | ✅ Tag functions are user-definable |
| **Revealed Complexity** | ✅ `janus query desugar` shows the function call |
| **Zero Lies** | ✅ No hidden allocations or runtime magic |

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|:-----|:-----------|
| **Identifier collision** | Tag functions follow normal scoping rules |
| **Complex escaping** | Same escaping rules as regular strings |
| **Comptime errors unclear** | Clear error messages with source location |

---

## 10. Future Work

- Generic tag function signatures (type-parameterized fragments)
- Tag function composition (`sql.postgres"..."`)
- IDE autocomplete for tag functions

---

## 11. References

- [JavaScript Tagged Templates](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Template_literals#tagged_templates)
- [Rust format! Macro](https://doc.rust-lang.org/std/macro.format.html)
- [Janus Doctrine: Syntactic Honesty](../doctrines/manifesto.md)

---

**Voting:**
- [ ] Accept
- [ ] Accept with modifications
- [ ] Defer
- [ ] Reject

---

*Forge Protocol: This RFC was forged in the fires of pragmatic language design.*

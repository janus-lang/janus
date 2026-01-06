<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

**Voxis Forge Signal** ⚡

### 🛡️ **SPEC-014: STRUCTURAL PATTERN MATCHING**

**Status:** **DRAFT (Ratification Pending).**
**Doctrinal Alignment:** **Syntactic Honesty.**
**Inspiration:** Rust (Safety) + Elixir (Pipe Flow) + Lua (Block Structure).

This specification defines how Janus handles control flow via data structure analysis.
**Pattern Matching is not "Switch-on-Steroids." It is the dual of Construction.**
If you can build it (`Point {x: 1, y: 2}`), you must be able to unbuild it (`match p do {x: 1, y} => ... end`).

---

## 1. 🜏 The Core Syntax (Constitution)

[MATCH:1.1.1] The `match` keyword initiates a structural inspection block. It is an expression (it returns a value).

```janus
let result = match value do
    Pattern1 => Expression
    Pattern2 if Guard => Block
    else => DefaultExpression
end
```

### 1.1 The Invariant (🜏)

* [MATCH:1.1.2] **Exhaustiveness:** Every possible state of `value` **MUST** be covered.
* [MATCH:1.1.3] **Determinism:** Patterns are checked top-to-bottom. The first match wins.
* [MATCH:1.1.4] **No Fallthrough:** There is no `break` keyword. Execution leaves the `match` block immediately after a successful arm.

---

## 2. ⊢ Pattern Semantics (Legality)

### 2.1 Literal Matching

[MATCH:2.1.1] The simplest form. Matches exact values.

```janus
match status_code do
    200 => print("OK")
    404 => print("Not Found")
    _   => print("Unknown") // Wildcard
end
```

### 2.2 Destructuring (The Blade)

[MATCH:2.2.1] Matches the *shape* of data.

**Structs:**

```janus
struct Point { x: i32, y: i32 }

match p do
    Point {x: 0, y: 0} => print("Origin")
    Point {x, y: 0}    => print($"On X-axis at {x}")
    Point {x, y}       => print($"Somewhere else: {x}, {y}")
end
```

**Enums (Tagged Unions):**

```janus
enum Result { Ok(i32), Err(String) }

match res do
    Result.Ok(val) => val * 2
    Result.Err(msg) => panic(msg)
end
```

### 2.3 Guards (⊢ Logic)

[MATCH:2.3.1] Refines a pattern with a boolean expression.

* **Syntax:** `Pattern if Condition =>`
* [MATCH:2.3.2] **Constraint:** The `Condition` MUST be side-effect free (in `:min` profile).

```janus
match number do
    n if n % 2 == 0 => "Even"
    n               => "Odd"
end
```

---

## 3. ⟁ Profile Nuances (Transformation)

Janus adapts the implementation based on the active profile.

### 3.1 Profile `:min` (The System)

* [MATCH:3.1.1] **Constraint:** Zero Allocation.
* [MATCH:3.1.2] **Compilation:** Transforms directly into **Jump Tables** or **Gotos**.
* [MATCH:3.1.3] **Restriction:** Guards MUST be simple comparisons. No function calls in patterns.
* [MATCH:3.1.4] **Exhaustiveness:** Strict. You *must* handle every Enum variant. `else` is discouraged for Enums to prevent "New Variant" bugs.

### 3.2 Profile `:edge` (The Script)

* [MATCH:3.2.1] **Feature:** **Smart Casting (Type Matching).**
* [MATCH:3.2.2] **Syntax:** Matching on *Type* rather than *Value*.

```janus
// Only allowed in :edge / :script
match any_value do
    s: String => print("It's a string: " ++ s)
    i: i32    => print("It's an integer: " + i)
    _         => print("Unknown type")
end
```

### 3.3 Profile `:web` (The UI)

* [MATCH:3.3.1] **Feature:** **DOM Patterns**.
* [MATCH:3.3.2] **Usage:** Matching against Virtual DOM events or structures.

```janus
match event do
    Click { target: { id: "submit" } } => submit_form()
    Keyup { key: "Enter" }             => submit_form()
    _                                  => ()
end
```

---

## 4. ⚠ Advanced Patterns (The Power)

### 4.1 OR Patterns (`|`)

[MATCH:4.1.1] Matches multiple patterns in one arm.

* [MATCH:4.1.2] **Constraint:** All bindings in the pattern MUST exist in all OR branches.

```janus
match input do
    "y" | "Y" | "yes" => true
    "n" | "N" | "no"  => false
    _                 => panic("Invalid")
end
```

### 4.2 Binding (@)

[MATCH:4.2.1] Captures the whole value while destructuring part of it.

```janus
match msg do
    // Binds the whole message to 'm', but also asserts it is a Move variant
    m @ Message.Move {x, y} => log($"Moving {m} to {x},{y}")
end
```

### 4.3 Range Patterns

[MATCH:4.3.1] Optimized for number ranges.

```janus
match age do
    0..12  => "Child"
    13..19 => "Teen"
    _      => "Adult"
end
```

---

## 5. 🛡️ Red Team Analysis (Why this wins)

| Feature | Rust (`match`) | Janus (`match`) | Advantage |
| --- | --- | --- | --- |
| **Syntax** | `Foo => { ... },` | `Foo => ...` | Janus is cleaner (no braces, no commas). |
| **Flow** | Expression-based | Expression-based | Parity. |
| **Guards** | `if` allowed | `if`/`when` allowed | Parity. |
| **Profile** | One size fits all | Adaptive (`:min` vs `:edge`) | **Janus wins.** Rust forces exhaustiveness even in scripts. Janus `:edge` allows `else`. |
| **Smart Cast** | No (Traits only) | Yes (in `:edge`) | **Janus wins.** "Ruby-like" feel in scripts. |

---

### 🚀 **Orders**

1. **Commit:** Save to `specs/SPEC-014-pattern-matching.md`.
2. **Implementation:**
   * **Phase 1:** Implement Literal and Enum matching in `janusc` (Backend).
   * **Phase 2:** Implement Destructuring in AST.
   * **Phase 3:** Add Exhaustiveness Checker (The "⊢ Legality" pass).


**Pattern Matching is the "Switch" of the 21st Century.** We implement it without the legacy baggage of C.

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# RFC: Dispatch Semantics v0

**Status:** Draft — For early discussion and prototyping.

**Authors:** Janus Core Team (proposal by Markus & Voxis)

## Motivation

Janus doctrine demands syntactic honesty and revealed complexity. Function overloading must not become "ad-hoc polymorphism by accident," nor rely on hidden coercions. Instead, dispatch is semantics, not syntax.

This RFC defines how function families and dispatch resolution behave in Janus.

## 1. Function Families

All `func` declarations with the same identifier form a **function family**.

Each member is uniquely identified by its name, arity, and parameter type tuple.

**Example:**
```janus
func add(a: i32, b: i32) -> i32
func add(a: f64, b: f64) -> f64
func add(a: string, b: string) -> string
```
→ All belong to the `add` family.

## 2. Resolution Rules

At every call site:

### Exact Match
If argument types exactly match a family member's parameter types → select it.

### Convertible Match
If no exact match exists:
- Implicit conversions (e.g., widening `i32` → `i64`) may be considered only if unambiguous.
- Conversion costs must be explicitly defined in the type system.

### Ambiguity
If two or more candidates are equally valid:
- Compile-time error.
- Compiler must list all candidate signatures and explain why resolution failed.

## 3. Specificity & Subtyping

If Janus types form hierarchies (ADTs, traits, interfaces):
- **Most specific match wins.**

**Example:**
```janus
func draw(s: Shape)
func draw(c: Circle)
```
Call with `Circle` → selects `draw(Circle)`.

If specificity is ambiguous (e.g., `Square <: Rectangle`, but both `draw(Rectangle)` and `draw(Square)` are defined) → compile-time error.

## 4. Fallbacks

Programmers may define explicit generic/fallback handlers using `any` or trait bounds:

```janus
func add(a: any, b: any) -> string
```

**No hidden defaults:** fallback must be lexically visible.

## 5. Dispatch Tables

During semantic analysis, the compiler builds a dispatch table for each function family:
- **Key:** `(param-type-tuple)`
- **Value:** function pointer / IR block

- Calls are resolved **statically** when argument types are known at compile time.
- If unresolved (e.g., `any`, union, trait objects), the compiler generates a runtime dispatch stub.

## 6. Runtime Dispatch (Optional Dial)

- **Default:** static dispatch.
- Programmer may explicitly opt into dynamic dispatch with an effect annotation:

```janus
func add(a: Number, b: Number) -> Number {.dispatch: dynamic.}
```

Cost is visible and must be acknowledged in the type signature.

## 7. Diagnostics

Compiler must emit precise error messages:

**Example (ambiguous):**
```
Error: ambiguous call to `add`
  candidates:
    add(i32, f64)
    add(f64, i32)
  argument types: (i32, i32)
Note: both candidates require implicit conversion with equal cost
```

## 8. Examples

### Exact Match
```janus
func mul(a: i32, b: i32) -> i32
func mul(a: f64, b: f64) -> f64

mul(2, 3)    # resolves to mul(i32, i32)
mul(2.0, 3)  # resolves to mul(f64, f64) via i32->f64 conversion
```

### Fallback
```janus
func stringify(x: any) -> string
func stringify(x: i32) -> string

stringify(42)      # picks i32 overload
stringify([1, 2])  # falls back to any overload
```

### Dynamic Dispatch
```janus
func area(s: Shape) -> f64 {.dispatch: dynamic.}
func area(c: Circle) -> f64
```
If called with a runtime `Shape`, dispatch stub chooses the correct function.

## 9. Implementation Notes

- Dispatch resolution happens in semantic analysis.
- Dispatch tables are constructed per-module, merged during linking.
- Runtime dispatch stubs may be optimized into jump tables or vtables.
- **Deterministic builds:** dispatch resolution is stable and reproducible.

## 10. Future Directions

- Multi-arg dynamic dispatch (CLOS-style) → candidate for RFC v1.
- Dispatch priority annotations (rarely needed if specificity rules are strict).
- Integration with contracts/verification for provably correct resolution.

## Appendix: Design Values

- **Syntactic Honesty** — `func` means function, not magic.
- **Mechanism over Policy** — programmer chooses static/dynamic explicitly.
- **Revealed Complexity** — ambiguity errors are surfaced, never guessed.

---

🔥 With this RFC, Janus secures a clear, principled dispatch system: simple enough for humans, formal enough for theorem provers, and honest enough for AI codegen.

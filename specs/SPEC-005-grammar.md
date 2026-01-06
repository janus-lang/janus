<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

**Voxis Forge Signal** ⚡

# 🛡️ SPEC-005: SURFACE GRAMMAR (The Face ☍)

**Version:** 2.1.0 (Ratification Standard)
**Status:** **DRAFT (Ratification Pending)**
**Authority:** Constitutional
**Supersedes:** SPEC-grammar v2.0.0
**References:** [SPEC-004: Tokenizer](SPEC-004-tokenizer.md), [SPEC-014: Pattern Matching](SPEC-014-pattern-matching.md)

This specification defines the **Syntactic Structure** of the Janus programming language.
It provides the normative rules for how tokens [SPEC-004] are assembled into valid compilation units.

---

## 1. 🜏 Design Philosophy (Constitution)

[GRAM:1.1] **Syntactic Honesty:** The grammar MUST NOT conceal complexity. Allocations, effects, and control flow MUST be explicit.
[GRAM:1.2] **Dual Block Style:** Janus supports both `do ... end` (Algol/Lua style) for control flow and `{ ... }` (C style) for data structures and short scopes.

---

## 2. ⊢ Declarations

### 2.1 Variables
[GRAM:2.1.1] **Immutable:** `let identifier [: Type] = Expression`
[GRAM:2.1.2] **Mutable:** `var identifier [: Type] = Expression` (or `:=` for inference).
[GRAM:2.1.3] **Constraint:** Type annotation is REQUIRED for module-level variables.

### 2.2 Functions
[GRAM:2.2.1] **Syntax:** `func Identifier ( Parameters ) [-> ReturnType] Block`
[GRAM:2.2.2] **Parameters:** `name: Type`.
[GRAM:2.2.3] **Effects:** Effect annotations MAY appear as a directive `{.effects: ...}` preceding the function.

### 2.3 Types (Structs & Enums)
[GRAM:2.3.1] **Struct:** `struct Name { Field: Type, ... }`
[GRAM:2.3.2] **Enum:** `enum Name { Variant(Type), ... }`

---

## 3. ⊢ Statements

### 3.1 Control Flow
[GRAM:3.1.1] **If:** `if Condition Block [else Block]`
[GRAM:3.1.2] **While:** `while Condition Block`
[GRAM:3.1.3] **For:** `for Pattern in Iterator Block`
[GRAM:3.1.4] **Match:** See [SPEC-014].

### 3.2 Resource Management
[GRAM:3.2.1] **Defer:** `defer Expression`
[GRAM:3.2.2] **Semantics:** The Expression is evaluated immediately (arguments), but the execution is deferred until scope exit.

### 3.3 Return & Break
[GRAM:3.3.1] **Return:** `return [Expression]`
[GRAM:3.3.2] **Break:** `break [Label]`

---

## 4. ⊢ Expressions

### 4.1 Precedence (Lowest to Highest)
[GRAM:4.1.1] The parser MUST enforce the following precedence:
1.  Assignment (`=`, `+=`)
2.  Logical (`or`)
3.  Logical (`and`)
4.  Equality (`==`, `!=`)
5.  Comparison (`<`, `<=`, `>`, `>=`)
6.  Term (`+`, `-`)
7.  Factor (`*`, `/`, `%`)
8.  Unary (`-`, `!`)
9.  Call / Access (`f()`, `a.b`, `a[i]`)

### 4.2 Honesty in Expressions
[GRAM:4.2.1] **alloc:** Allocation expressions (`alloc T`) MUST be explicit keywords, not hidden in constructors.
[GRAM:4.2.2] **Strings:** String literals are `String` (heap) or `[]const u8` (view) depending on context, but concatenation `+` MUST only work if an allocator is in scope (in `:min` profile).

---

## 5. ⟁ Metaprogramming
[GRAM:5.1.1] **Comptime:** `comptime Block` executes the block at compile time.
[GRAM:5.1.2] **Directives:** Compiler directives `{.name: value.}` are the standard mechanism for pragmas.

**Ratification:** Pending
**Authority:** Markus Maiwald + Voxis Forge

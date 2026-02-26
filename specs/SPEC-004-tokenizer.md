<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).


# Janus Specification — Tokenizer & Lexical Structure (SPEC-004)

**Version:** 2.0.0  
**Status:** CANONICAL — Lexical Truth  
**Authority:** Constitutional  
**Supersedes:** SPEC-tokenizer v0.2.1

## 1. Introduction

This document defines the **Lexical Truth** of the Janus programming language. It establishes the rules for tokenization, capability recognition, and literal formatting.

### 1.1 Normative References
All definitions in this document SHALL follow the normative language defined in [SPEC-000: Meta-Specification](meta.md).

## Overview

The Tokenizer is the first line of defense. It enforces "Honest Sugar" and validates the "37 Keys" before the parser ever sees them. It is not just splitting strings; it is enforcing doctrine.

---

## 2. Capability Primitives
[LEX:2.1.1] Capability primitives are a distinct token type: `TOKEN_CAPABILITY`.

### Rules
[LEX:2.2.1] **Format:** A dot `.` followed immediately by a lowercase identifier.
    *   Regex: `\.[a-z][a-z0-9_]*`
[LEX:2.2.2] **Validation:** The tokenizer matches the identifier against the **closed set of 37 primitives**.
    *   If valid: Emits `TOKEN_CAPABILITY` (e.g., value = `.fs_read`).
    *   If invalid (e.g., `.fs_hack`, `.magic_42`): Emits `TOKEN_ERROR` with "Unknown Capability Primitive".
[LEX:2.2.3] **No Context:** These tokens are recognized anywhere. Usage outside `where ctx.has(...)` is a parser error, but the *lexer* identifies them as special atoms.

### The 37 Keys (Lexer Table)
The lexer contains a perfect hash (or hardcoded switch) for:
`.fs_read`, `.fs_write`, `.fs_exec`, `.fs_metadata`,
`.net_connect`, `.net_listen`, `.net_raw`,
`.alloc`, `.alloc_scratch`, `.alloc_persist`,
`.log_write`, `.trace_span`,
`.time_monotonic`, `.time_wall`, `.sleep`,
`.thread_spawn`, `.actor_spawn`,
`.crypto_rng`, `.crypto_sign`, `.crypto_verify`,
`.sys_env`, `.sys_args`, `.sys_hostname`,
`.raw_pointer`, `.raw_ffi`,
`.reflect_ast`, `.reflect_comptime`,
`.test_mock`, `.test_time_freeze`.

---

## 3. Honest Strings (Interpolation)
[LEX:3.1.1] String interpolation uses `"Honest Sugar"`. It desugars directly to a formatted write. The lexer MUST handle nested expressions correctly.

### Syntax
[LEX:3.2.1] **Format:** `$"{expr}"`
[LEX:3.2.2] **Delimiters:** `$` followed immediately by `"`.

### Lexing States
[LEX:3.3.1] The lexer SHALL maintain a **mode stack** to handle nesting: `ROOT` -> `STRING_INTERP`.

1.  **Entry:** Encounter `$"` -> Push `STRING_INTERP`, emit `TOKEN_STRING_START`.
2.  **Content:**
    *   Literal chars: Emit `TOKEN_STRING_PART` ("Hello ").
    *   Interpolation start `{`: Push `ROOT` (recurse), emit `TOKEN_INTERP_START`.
    *   Inside `{...}`: Lex normal Janus code (recursive).
    *   Interpolation end `}`: Pop `ROOT`, emit `TOKEN_INTERP_END`.
3.  **Exit:** Encounter `"`: Pop `STRING_INTERP`, emit `TOKEN_STRING_END`.

### Honest Rejection
[LEX:3.4.1] The lexer SHALL **reject** ambiguous or hidden complexity.
*   `$ "${x}"` (nested quotes without braces? No.)
*   Binary blobs in strings? No. Use `b"..."` syntax.

---

## 4. Numeric Literals & The "No 42" Rule
[LEX:4.1.1] While generally valid, the lexer SHALL enforce specific cultural norms via warnings or errors in strict mode.

[LEX:4.1.2] **Formatting:**
*   **Hex:** `0xDEAD_BEEF` (valid).
*   **Binary:** `0b1010` (valid).
*   **Octal:** `0o755` (valid).

[LEX:4.1.3] **Magic Numbers:** The lexer passes numbers to the parser, but the *Linter* (integrated 2nd pass) SHALL flag bare numbers like `42` used as logic codes.
    *   *Note:* The "No 42" capability rule is enforced at the `TOKEN_CAPABILITY` check. `.cap42` is invalid.

---

## 4. Contextual Keywords

The lexer emits specific tokens for `ctx`, `with`, `where`, and `has` to allow the parser to enforce the rigid structure of:
`with ctx where ctx.has(...)`

*   `ctx`: `TOKEN_CTX` (Reserved in function signatures).
*   `has`: `TOKEN_HAS` (Contextual, valid identifier elsewhere but special here).

---

## 5. Implementation Strategy (Zig)

```zig
pub const TokenKind = enum {
    // ... standard tokens ...
    
    // The Keys
    Capability,      // .fs_read (payload: enum index)
    
    // Honest Strings
    StringStart,     // $"
    StringPart,      // literal text
    InterpStart,     // {
    InterpEnd,       // }
    StringEnd,       // "
    
    // Context
    KeywordCtx,      // ctx
    KeywordHas,      // has
    // ...
};

pub fn next(self: *Lexer) Token {
    // ...
    if (c == '.') {
        // Peek ahead. If lowercase alpha, it's a capability or field.
        // If it matches the 37 Keys Table -> TOKEN_CAPABILITY.
        // Else -> TOKEN_DOT or TOKEN_FIELD_ACCESS.
    }
    // ...
}
```

This tokenizer ensures that **privilege is lexical**. A simple grep for `.fs_write` will *always* find every usage, because the token itself is unique.

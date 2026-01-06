<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC-tokenizer.md — The Lexical Truth

**Status:** COMMITTED (Monastery Freeze v0.2.1)  
**Author:** Voxis Forge  
**Date:** 2025-12-07

## Overview

The Tokenizer is the first line of defense. It enforces "Honest Sugar" and validates the "37 Keys" before the parser ever sees them. It is not just splitting strings; it is enforcing doctrine.

---

## 1. Capability Primitives

Capability primitives are a distinct token type: `TOKEN_CAPABILITY`.

### Rules
1.  **Format:** A dot `.` followed immediately by a lowercase identifier.
    *   Regex: `\.[a-z][a-z0-9_]*`
2.  **Validation:** The tokenizer matches the identifier against the **closed set of 37 primitives**.
    *   If valid: Emits `TOKEN_CAPABILITY` (e.g., value = `.fs_read`).
    *   If invalid (e.g., `.fs_hack`, `.magic_42`): Emits `TOKEN_ERROR` with "Unknown Capability Primitive".
3.  **No Context:** These tokens are recognized anywhere. Usage outside `where ctx.has(...)` is a parser error, but the *lexer* identifies them as special atoms.

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

## 2. Honest Strings (Interpolation)

String interpolation uses `"Honest Sugar"`. It desugars directly to a formatted write, but the lexer must handle the nested expressions correctly.

### Syntax
*   Format: `$"{expr}"`
*   Delimiters: `$` followed immediately by `"`.

### Lexing States
The lexer maintains a **mode stack** to handle nesting: `ROOT` -> `STRING_INTERP`.

1.  **Entry:** Encounter `$"` -> Push `STRING_INTERP`, emit `TOKEN_STRING_START`.
2.  **Content:**
    *   Literal chars: Emit `TOKEN_STRING_PART` ("Hello ").
    *   Interpolation start `{`: Push `ROOT` (recurse), emit `TOKEN_INTERP_START`.
    *   Inside `{...}`: Lex normal Janus code (recursive).
    *   Interpolation end `}`: Pop `ROOT`, emit `TOKEN_INTERP_END`.
3.  **Exit:** Encounter `"`: Pop `STRING_INTERP`, emit `TOKEN_STRING_END`.

### Honest Rejection
*   The lexer **rejects** ambiguous or hidden complexity.
*   `$ "${x}"` (nested quotes without braces? No.)
*   Binary blobs in strings? No. Use `b"..."` syntax.

---

## 3. Numeric Literals & The "No 42" Rule

While generally valid, the lexer enforces specific cultural norms via warnings or errors in strict mode.

*   **Hex:** `0xDEAD_BEEF` (valid).
*   **Binary:** `0b1010` (valid).
*   **Octal:** `0o755` (valid).
*   **Magic Numbers:** The lexer passes numbers to the parser, but the *Linter* (integrated 2nd pass) flags bare numbers like `42` used as logic codes.
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

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Specification — Semantic Analysis Capsule (SPEC-006)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-sema v0.1.0

## 1. Purpose
The **Sema Capsule** enforces Janus language semantics by validating the AST and annotating it with type information, symbol bindings, and diagnostics.
It consumes the ASTDB and produces typed entities and error reports.

---

## II. Capsule Layout

```
compiler/passes/sema/
 ├── type.zig       # Type resolution & checking
 ├── expr.zig       # Expression type checking
 ├── stmt.zig       # Statement checking
 ├── decl.zig       # Declarations & symbol table insertion
 ├── builtin.zig    # Built-in functions & operators
 └── README.md      # Capsule doctrine & entrypoints
```

---

## III. Inputs & Outputs

**Inputs:**
- `AstDb` (nodes, regions, interner symbols, CIDs)
- Raw AST from parser
- Diagnostics context

**Outputs:**
- Annotated ASTDB with type information
- Symbol table entries for declarations
- Diagnostics (multi-span, with primary index)
- CIDs for typed entities (types, functions, structs, enums)

---

## IV. Submodules

### 1. `type.zig`
- Resolves type identifiers into canonical `Type` objects.
- Applies default typing rules for untyped literals (e.g., `42` → `int`).
- Distinguishes builtin vs. user-defined vs. generic types.

### 2. `expr.zig`
- Checks expressions for type correctness.
- Validates binary/unary operator compatibility.
- Resolves function calls and argument matching (incl. varargs).
- Emits diagnostics for mismatches, with hints (`H_TYP_SUGGEST_CAST`).

### 3. `stmt.zig`
- Validates statements:
  - Variable declarations (no illegal shadowing/redeclaration).
  - Control flow (`if`, `while`, `for`) conditions must be `bool`.
  - `return` must match enclosing function type.
- Attaches statement spans into ASTDB regions for IDE use.

### 4. `decl.zig`
- Handles top-level and local declarations:
  - Functions, constants, variables, struct/enum/type definitions.
  - Inserts into ASTDB’s symbol table.
  - Ensures visibility consistency (public/private).
- Assigns stable CIDs for declarations.

### 5. `builtin.zig`
- Registry of built-in functions/operators (e.g., `len`, `cap`, `append`).
- Each builtin validates args and returns type.
- Profile-aware (some builtins available only in :service/:cluster/:sovereign).

---

## V. Error Handling Protocol

- All checker functions return `!Type` or `!void`.
- On error, emit diagnostics into `DiagContext`:
  - Severity: `error`, `warning`, `info`, `note`, `help`, `hint`.
  - Multi-span with `primary` index.
- Checker never panics or aborts. Recovery always attempted.

---

## VI. Integration with Pipeline

1. Parser builds raw AST.  
2. AST is inserted into ASTDB.  
3. **Sema Capsule runs:**  
   - Resolves types, symbols, declarations.  
   - Produces annotated ASTDB + diagnostics.  
4. Codegen consumes annotated ASTDB.

Entry call (example in `libjanus/api.zig`):
```zig
pub fn runSema(db: *AstDb, diags: *DiagContext) !void {
    try sema.decl.checkAll(db, diags);
    try sema.stmt.checkAll(db, diags);
    try sema.expr.checkAll(db, diags);
}
```

---

## VII. Capsule Doctrine

- No printing. Diagnostics only.
- No mutation of raw AST; all annotations go into ASTDB.
- Explicit allocators, error propagation always.
- Capsule boundaries are strict. No leaking symbols/types across submodules without going through ASTDB.

---

## VIII. Deliverables

- `compiler/passes/sema/` with submodules scaffolded.
- Smoke test in `tests/compiler/sema.zig` to validate:
  - Type mismatch error detection.
  - Invalid return type in function.
  - Correct typing of literals and builtin calls.
- Documentation: this SPEC in `docs/spec/SPEC-sema.md`.

---

🔥 The Sema Capsule is the **mind of Janus**: it transforms syntax into semantics, ensuring the language remains sound, explicit, and diagnosable.

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC — `:script` Profile
**Version:** 0.2.0
**Status:** Draft → Public Review
**Author:** Self Sovereign Society Foundation
**Date:** 2025-10-15
**License:** LSL-1.0
**Epic:** Profiles System
**Depends on:** SPEC-profiles.md, SPEC-grammar.md, SPEC-profile-min.md
**Compatible engines:** `janus script`, `janus run`

---

## 0. Purpose

The `:script` profile defines the **dynamic, interactive execution surface** of Janus —
a disciplined environment for rapid prototyping, exploration, and live evaluation.

It is **not a different language**: all syntactic and semantic laws of Janus still apply.
What changes is *how code exists in time*:

> `:core` builds the monastery.
> `:script` opens the bazaar.

---

## 1. Profile Philosophy

| Principle | `:core` | `:script` |
|------------|---------|-----------|
| **Temporal model** | Static & deterministic | Dynamic & live |
| **Execution** | Compiled AOT or cached JIT (`janus run`) | Incremental JIT / interpreter (`janus script`) |
| **Primary goal** | Reliable micro-systems, pedagogy, embedded tools | Rapid prototyping, exploration, REPL use |
| **Surface** | Minimal, explicit allocators | Full Janus grammar, allocator defaults at entry |
| **Reflection** | Disabled | Enabled (ASTDB, meta-introspection) |
| **Top-level stmts** | Disallowed | Allowed (lowered to `main()`) |
| **Publishable** | ✅ | ❌ (`E31xx`) |
| **Analogy** | Zig-min / Nim-tiny | "Better Python / Ruby" under honest semantics |

---

## 2. Engine Integration

### 2.1 `janus run` — *Builder's Path*
- Compiles and executes ahead-of-time or via cached JIT.
- Enforces deterministic semantics and allocator sovereignty.
- Used for `:core`, `:service`, `:sovereign` profiles.

### 2.2 `janus script` — *Interpreter's Path*
- Executes source incrementally through the **Oracle JIT**.
- Maintains a live **ASTDB** that supports redefinition and introspection.
- Provides a REPL and notebook-style interface.
- Defaults to profile `:script` when top-level statements are detected.

Both engines share the same compiler frontend and semantic model.

---

## 3. Language Surface Adjustments

### 3.1 Top-Level Statements

In `:script`, a file or REPL cell may contain bare statements or expressions:

```janus
print "Hello, world!"
x := 1 + 2
print x
````

**Lowering rule:**
At compile time, these are wrapped in an implicit `func main()`:

```janus
func main() {
  print "Hello, world!"
  let x := 1 + 2
  print x
}
```

### 3.2 Entry-Point Allocator Injection

At the topmost entry point (e.g., `main`, REPL cell), the runtime injects a **thread-local scratch allocator**.
Functions called from there may omit explicit allocator arguments.

```janus
// :script
var list = List(string).with()   # uses implicit TLS allocator
list.append "hi"
print list
```

Equivalent `:core` form:

```janus
let alloc = ctx.alloc
var list = List(string).with(alloc)
list.append "hi"
print list
```

Allocator injection is limited to one stack frame depth to preserve cost visibility.

### 3.3 Reflection and Meta-Introspection

`import std.meta` becomes available automatically:

* `meta.astof(expr)` → returns AST node from live ASTDB.
* `meta.eval(code: string)` → compiles and executes in the current context.
* `meta.reload(module)` → reloads imported module live.

These facilities are sandboxed behind `CapMeta` and only available under `janus script`.

### 3.4 Capability Defaults

| Capability        | Default in `:script`                               | Notes                         |
| ----------------- | -------------------------------------------------- | ----------------------------- |
| `CapConsoleWrite` | Granted                                            | Enables `print`, `debug.log`. |
| `CapFsRead`       | Granted for current directory                      | Sandbox enforced.             |
| `CapFsWrite`      | Denied by default.                                 |                               |
| `CapNetHttp`      | Granted for localhost only (`127.0.0.1`).          |                               |
| `CapRng`          | Granted with deterministic PRNG unless `--secure`. |                               |
| `CapMeta`         | Granted (REPL & eval).                             |                               |
| All others        | Must be explicitly requested.                      |                               |

---

## 4. Temporal Semantics

### 4.1 Incremental Execution

Each top-level statement or REPL input forms a **transaction**:

```
parse → typecheck → emit → execute → persist in ASTDB
```

Re-defining a symbol replaces its entry in the ASTDB and invalidates dependent scopes.

### 4.2 Hot Reloading

`janus script --reload` watches imported modules; on change:

* Re-compiles affected modules,
* Preserves live values via structural migration where possible.

### 4.3 Introspection API

```janus
meta.symbols()          # list loaded symbols
meta.reload("std.http") # reload module
meta.time()             # last execution timestamp
```

---

## 5. CLI Behavior

### 5.1 Invocation

```bash
# Run a script file
janus script file.jan

# Start REPL
janus script --repl

# Pipe code
echo 'print 42' | janus script
```

### 5.2 Shebang Support

```bash
#!/usr/bin/env -S janus script --profile=script
print "Hello"
```

### 5.3 Profile Resolution Priority

1. Command-line flag `--profile`
2. Source annotation `{.profile: script.}`
3. Project config (`janus.project.kdl`)
4. Environment variable `JANUS_PROFILE`
5. Default heuristic:

   * If top-level statements exist → `:script`
   * Else → `:core`

### 5.4 Publication Restrictions

Artifacts built with `--profile=script` cannot be published or installed:

```
E3101_PROFILE_NOT_PUBLISHABLE
```

---

## 6. Error Codes (`E31xx`)

| Code                                       | Description                                                   |
| ------------------------------------------ | ------------------------------------------------------------- |
| **E3101_PROFILE_NOT_PUBLISHABLE**          | Attempted to publish or install binary built under `:script`. |
| **E3103_ALLOCATOR_AMBIENT_SCOPE_EXCEEDED** | Implicit allocator used beyond permitted scope depth.         |
| **E3105_RELOAD_CONFLICT**                  | Hot reload attempted with incompatible type shape.            |
| **E3107_META_CAPABILITY_REQUIRED**         | Meta-introspection used without `CapMeta`.                    |

---

## 7. Migration and Tooling

### 7.1 `janus migrate --target=min`

Rewrites a script into deterministic form:

* Wraps top-level stmts in `main()`
* Inserts explicit allocator/context parameters
* Removes meta/eval usage (replacing with static imports)
* Generates diff and patch

### 7.2 LSP / IDE Support

* **Profile detection**: automatically switches hover/fix-it rules.
* **Quick-fixes**:

  * "Make allocator explicit"
  * "Wrap top-level statements into `main()`"
* **Code lenses**:

  * "Run in REPL"
  * "Migrate to :core"

### 7.3 Determinism Check

`janus validate --tri-build` ensures code passes in `:script`, `:core`, and `:sovereign`.
If not, it emits advisory diagnostics (E3109_TRI_BUILD_FAIL).

---

## 8. Integration with Profiles System

`SPEC-profiles.md` hierarchy now becomes:

```
:sovereign      → complete Janus (capabilities, actors, comptime)
:cluster    → OTP-style actors and supervision
:service        → Go-style simplicity, concurrency, and error-values
:core       → monastic subset for deterministic, small code
:script    → dynamic surface for interactive and exploratory code
```

All share one grammar and semantics; `:script` merely widens the **temporal execution window**.

---

## 9. Implementation Outline

| Phase | Deliverable                                                         |
| ----- | ------------------------------------------------------------------- |
| 1     | Extend parser: allow `stmt*` at module root when profile==`:script` |
| 2     | Implement `main()` lowering pass (frontend transform)               |
| 3     | Add TLS allocator injection at entry points                         |
| 4     | Enable meta API under `janus script`                                |
| 5     | Add REPL & incremental evaluator (Oracle JIT)                       |
| 6     | Enforce capability defaults & sandbox                               |
| 7     | Wire CLI heuristics + error codes                                   |
| 8     | Update `janus migrate` and LSP tooling                              |
| 9     | Integrate tri-build validation                                      |

---

## 10. Strategic Impact

### 10.1 For Developers

* Immediate feedback loop (like Python)
* Same syntax and semantics as production code
* Effortless transition from exploration → production

### 10.2 For Janus Ecosystem

* Positions Janus as a **"better Python"** without semantic rot
* Bridges teaching and professional workflows
* Enables AI-assisted scripting directly atop ASTDB

### 10.3 For Philosophy

> The Bazaar and the Monastery share one faith: honesty.
> One builds with stone; the other experiments with light.

---

## 11. Success Criteria

✅ `janus script` REPL functional with live reload
✅ `janus migrate script→min` produces deterministic output
✅ TLS allocator injection limited and traceable
✅ Tri-build (script|min|full) passes core test suite
✅ Meta-API gated and auditable
✅ No second semantics introduced

---

**THE MONASTERY AND THE BAZAAR SPEAK ONE LANGUAGE.**
**THE DIFFERENCE IS ONLY IN TIME.**

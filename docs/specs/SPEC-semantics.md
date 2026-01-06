# SPEC-semantics.md — Janus Semantic Specification

**Status:** Normative  
**Version:** 0.2.5  
**Classification:** 🜏 Constitution

---

## 1. The Profile Ladder

[SEM-01] Janus is a spectrum of control. Code exists in distinct **Profiles**.

[SEM-02] Moving "down" the ladder increases control but requires explicit "hardening."

### 1.1 Profile Hierarchy

[SEM-03] **legality-rule** The following profiles are defined (in order of capability):

| Profile | Purpose | Capability Level |
|---------|---------|------------------|
| `:core` | Teaching subset | Minimal |
| `:script` | Exploration (`:core` + fluid mode) | Minimal + Sugar |
| `:service` | Application backend | Standard |
| `:cluster` | Distributed systems | Distributed |
| `:compute` | Parallel compute (NPU/GPU) | Accelerated |
| `:sovereign` | Total control | Full |

### 1.2 `:core` — The Teaching Subset

[SEM-04] **Target:** Education, simple tools, deterministic execution.

[SEM-05] **legality-rule** `:core` **MUST** provide:
- 6 core types: `i64`, `f64`, `bool`, `String`, `Array`, `HashMap`
- 8 constructs: `func`, `let`, `var`, `if`, `else`, `for`, `while`, `return`
- No concurrency (single-threaded)

[SEM-06] **legality-rule** `:core` code **MUST** be publishable without modification.

### 1.3 `:script` — The Gateway

[SEM-07] **Target:** Rapid prototyping, REPL, Python/Ruby parity.

[SEM-08] **dynamic-semantics** `:script` is `:core` with:
- Implicit types, returns, allocators
- REPL/interpreted execution
- Top-level code allowed
- ASTDB reflection access

[SEM-09] **legality-rule** `:script` code **MUST NOT** be publishable (must migrate to `:core`).

### 1.4 `:service` — Application Backend

[SEM-10] **Target:** Backend services, APIs, production applications.

[SEM-11] **dynamic-semantics** `:service` provides:
- Error-as-values (`Result` types)
- CSP channels, goroutine-style concurrency
- Context injection
- Simple generics

### 1.5 `:cluster` — Distributed Systems

[SEM-12] **Target:** Fault-tolerant systems, game servers, actors.

[SEM-13] **dynamic-semantics** `:cluster` provides:
- Actors (ephemeral)
- Grains (virtual actors with auto-lifecycle)
- OTP-style supervision trees
- Location transparency

### 1.6 `:compute` — Parallel Compute

[SEM-14] **Target:** AI/ML, scientific computing, NPU/GPU kernels.

[SEM-15] **dynamic-semantics** `:compute` provides:
- `tensor<T, Dims>` types
- Device streams and events
- Memory spaces (`sram`, `dram`, `vram`, `shared`)
- J-IR graph extraction

### 1.7 `:sovereign` — Total Control

[SEM-16] **Target:** Operating systems, drivers, performance-critical code.

[SEM-17] **dynamic-semantics** `:sovereign` provides:
- Raw pointers (`*T`)
- Compile-time metaprogramming (`comptime`)
- Complete effect system
- Multiple dispatch
- `unsafe { }` blocks

---

## 2. Execution Modes

[SEM-18] **legality-rule** Profiles have two orthogonal execution modes:

| Mode | Alias | Compilation | Syntax |
|------|-------|-------------|--------|
| strict | Monastery | AOT | Explicit |
| fluid | Bazaar | JIT/Interpreted | Sugared |

[SEM-19] **syntax** Fluid mode is indicated by `!` suffix: `:service!`

[SEM-20] **legality-rule** `:sovereign` **MUST NOT** support fluid mode.

---

## 3. Migration Tooling

[SEM-21] **informative** `janus harden <function> --to :core` migrates high-level code.

[SEM-22] **dynamic-semantics** Hardening:
1. Scans for high-level abstractions
2. Generates lower-profile variant
3. Inserts TODO markers for manual work
4. Verifies contract tests pass

---

## 4. Capability & Context

[SEM-23] **legality-rule** All side effects **MUST** be controlled via capabilities.

[SEM-24] **syntax** Functions performing I/O receive a `ctx` object.

[SEM-25] **dynamic-semantics** Capability violations result in:
- `:core`/`:script`: Panic or Result error
- `:sovereign`: Compile-time error if capability not granted

---

## 5. Compatibility Aliases

[SEM-26] **informative** Legacy aliases are supported forever:

| Alias | Resolves To |
|-------|-------------|
| `:core` | `:core` |
| `:service` | `:service` |
| `:cluster` | `:cluster` |
| `:compute` | `:compute` |
| `:sovereign` | `:sovereign` |

---

**Last Updated:** 2026-01-06

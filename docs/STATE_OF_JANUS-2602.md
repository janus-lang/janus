<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# State of Janus

**Version:** 2026.2.26
**Date:** 2026-02-26
**Zig:** 0.16.0-dev.2645+cd02b1703
**Toolchain:** `zig cc` + clang/LLVM (no GCC)
**Tests:** Compiler core: all test targets passing. 20 E2E targets green. 1,107 unit tests green.

**Milestone:**
- **:core profile: 100% COMPLETE** ✅

**Recent:**
- SPEC-025 Phase C Sprints 1-5 (trait dynamic dispatch: vtables, &dyn Trait, param types) ✅
- SPEC-025 Phase B (trait/impl lowering + static dispatch) ✅
- SPEC-025 Phase A (trait/impl parser) ✅
- SPEC-024 A/B/C (closures: zero-capture, captured, mutable) ✅
- SPEC-023 (enum/union codegen) ✅
- String query intrinsics (10 builtins wired) ✅
- `..=` inclusive range operator ✅

---

## Classification

| Symbol | Tier | Meaning | Evidence |
|--------|------|---------|----------|
| `[I]` | Implemented | Working code + passing tests | Source paths cited |
| `[S]` | Specified | RFC/SPEC exists, partial or no impl | Spec path cited |
| `[D]` | Dreamed | Mentioned in docs/doctrines only | Doc reference cited |

---

## 1. Compilation Pipeline

| Stage | Tier | LOC | Key Files |
|-------|------|----:|-----------|
| Tokenizer | `[I]` | 1,301 | `compiler/libjanus/janus_tokenizer.zig` |
| Parser | `[I]` | 4,538 | `compiler/libjanus/janus_parser.zig` |
| ASTDB Core | `[I]` | 1,192 | `compiler/astdb/core.zig` |
| ASTDB Regions (incremental) | `[I]` | 1,591 | `compiler/astdb/region.zig` |
| ASTDB CID (content identity) | `[I]` | — | `compiler/astdb/cid.zig` |
| ASTDB Schema (types/hover/effects) | `[I]` | — | `compiler/libjanus/astdb/schema.zig` |
| ASTDB Query (predicates) | `[I]` | — | `compiler/libjanus/astdb/query.zig` |
| Semantic Analysis | `[I]` | 1,198 | `compiler/libjanus/libjanus_semantic.zig` |
| Sema Passes (expr/stmt/builtin) | `[D]` | 33 | `compiler/passes/sema/*.zig` — stubs only |
| QTJIR Graph (SSA IR) | `[I]` | ~3,000 | `compiler/qtjir/graph.zig` |
| QTJIR Lowering | `[I]` | ~5,000 | `compiler/qtjir/lower.zig` (+ trait/impl metadata, static dispatch) |
| LLVM Codegen | `[I]` | ~3,900 | `compiler/qtjir/llvm_emitter.zig` |
| Dispatch Engine | `[I]` | 13,036 | `compiler/libjanus/dispatch_*.zig` (8 files) |
| Type System | `[I]` | — | `compiler/libjanus/type_system.zig` |
| Symbol Table | `[I]` | — | `compiler/libjanus/symbol_table.zig` |

**Pipeline total:** ~35,000+ LOC of working compiler.

---

## 2. Runtime

| Component | Tier | LOC | Key Files |
|-----------|------|----:|-----------|
| M:N Fiber Scheduler | `[I]` | 5,249 | `runtime/scheduler/` |
| Runtime Support (intrinsics) | `[I]` | — | `runtime/janus_rt.zig` |
| Compat: Filesystem | `[I]` | — | `runtime/compat/compat_fs.zig` |
| Compat: Time | `[I]` | — | `runtime/compat/compat_time.zig` |
| Compat: Mutex (pthread) | `[I]` | — | `runtime/compat/compat_mutex.zig` |

---

## 3. Language Features

### Fully Implemented (Parser → Sema → QTJIR → LLVM)

| Feature | Notes |
|---------|-------|
| `func` / `async func` | Full function declarations with types |
| `if` / `else` | Conditional branching |
| `while` / `for` / `loop` | All loop forms |
| `match` | Pattern matching (integer/enum arms) |
| `struct` | Struct declarations + field access + construction |
| `enum` | Enum declarations + match arms (SPEC-023 ✅) |
| `union` (tagged) | Tagged union declarations + construction (SPEC-023 ✅) |
| `let` / `var` / `const` | Variable bindings |
| `return` / `break` / `continue` | Control flow |
| `using` | Resource management (RAII-style) |
| `defer` | Deferred cleanup |
| `error` type + `fail` + `catch` + `try` (`?`) | Full error handling pipeline |
| Error unions (`T ! E`) | First-class error types |
| Optionals (`T?`) | Optional types with `some`/`none` |
| Arrays + indexing + slices | Array literals, `[]` access, slice ops |
| Ranges (`..`, `..<`) | Range expressions for iteration |
| `nursery` / `spawn` / `await` | Structured concurrency |
| `select` + channels | CSP-style channel operations |
| `use zig` / `extern` / `import` | Foreign function interface |
| `test` / `assert` | Built-in test declarations |
| Closures / `fn` literals | Zero-capture, captured, mutable capture (SPEC-024 A/B/C ✅) |
| `trait` / `impl` (static dispatch) | Parser + lowering + namespaced IR graphs (SPEC-025 A+B ✅) |
| Pipe operator (`|>`) | Desugars to function call |
| All arithmetic/bitwise/comparison ops | `+` `-` `*` `/` `%` `<<` `>>` `&` `|` `^` `~` `==` `!=` `<` `>` `<=` `>=` `and` `or` |
| Quantum ops (gate, measure) | QTJIR opcodes + LLVM emission |
| Tensor ops (matmul, conv, reduce) | QTJIR opcodes + LLVM emission |
| SSM ops (scan, selective scan) | QTJIR opcodes + LLVM emission |

### Parsed but Not Code-Generated

| Feature | Tier | What Works | What's Missing |
|---------|------|------------|----------------|
| `trait` / `impl` (dynamic dispatch) | `[I]` | Static + dynamic dispatch (SPEC-025 Phases A-C complete) | Phase D polish deferred (non-blocking) |
| `graft` | `[S]` | Parser + tokenizer | No IR, no codegen |

### Not Implemented

| Feature | Tier | Reference |
|---------|------|-----------|
| Generics / type parameters | `[S]` | SPEC-017, SPEC-001 |
| Actors / mailboxes | `[S]` | SPEC-021-cluster |
| Capability tokens (enforcement) | `[S]` | SPEC-012-boot-and-capabilities |
| Effect tracking (enforcement) | `[S]` | SPEC-006-sema, doctrines |
| Affine types / ownership | `[S]` | SPEC-015-ownership |
| Profile gating (compiler-enforced) | `[S]` | SPEC-002-profiles |
| REPL / JIT | `[D]` | docs/rfcs/RFC-jit-revolution.md |
| Macros / comptime | `[D]` | Mentioned in doctrines |

---

## 4. Profile System

| Profile | Tier | Evidence |
|---------|------|----------|
| `:core` (teaching) | `[I]` **100%** | 1,107 unit tests, 20 E2E targets, 238 build steps, 116 examples, full pipeline |
| `:service` (networking) | `[S]` partial | NS-MSG exists (4,155 LOC), async/nursery works, no profile enforcement |
| `:script` (REPL) | `[S]` | SPEC-002-profiles, legacy spec `specs/legacy/profile-script.md` |
| `:cluster` (actors) | `[S]` | SPEC-021-cluster, `std/cluster.zig` (6 LOC stub) |
| `:compute` (GPU/NPU) | `[S]` | QTJIR tensor/quantum opcodes exist, no hardware backend |
| `:sovereign` (raw) | `[D]` | Mentioned in doctrines and SPEC-002 |

**Note:** Profile *validation* (compiler rejecting features outside active profile) is not implemented. All features are available regardless of declared profile.

---

## 5. Standard Library

**Total:** 62 files, 25,429 LOC, 17 files with `utcpManual()`

### Collections (`std/collections/`) — `[I]`

| Module | LOC | utcpManual |
|--------|----:|:----------:|
| `vec.zig` | 759 | yes |
| `hash_map.zig` | 872 | yes |
| `deque.zig` | 351 | yes |
| `small_vec.zig` | 436 | yes |

### File System (`std/fs*.zig`, `std/*_fs.zig`) — `[I]`

| Module | LOC | utcpManual |
|--------|----:|:----------:|
| `fs.zig` (index) | 810 | yes |
| `fs_atomic.zig` | 801 | yes |
| `fs_temp.zig` | 774 | yes |
| `fs_walker.zig` | 905 | yes |
| `fs_write.zig` | 774 | yes |
| `compress_fs.zig` | 860 | yes |
| `memory_fs.zig` | 801 | yes |
| `physical_fs.zig` | 775 | yes |
| `temp_fs.zig` | 635 | yes |
| `path.zig` | 666 | yes |
| `path_normalization.zig` | 537 | yes |

### Core (`std/core/`) — `[I]`

| Module | LOC |
|--------|----:|
| `core.zig` | 179 |
| `array.zig` | 451 |
| `context.zig` | 466 |
| `convert.zig` | 435 |
| `fs.zig` / `fs_ops.zig` | 828 |
| `io.zig` | 181 |
| `string.zig` / `string_ops.zig` | 956 |
| `time.zig` | 239 |

### Networking (`std/net/`) — `[I]` early

| Module | LOC |
|--------|----:|
| `socket.zig` | 359 |
| `http.zig` | 433 |
| `http_server.zig` | 348 |
| `http/protocol.zig` | 476 |

### AI/JIT (`std/ai/jit/`) — `[S]`

| Module | LOC |
|--------|----:|
| `jit.zig` (index) | 258 |
| `execution.zig` | 230 |
| `interpreter.zig` | 1,102 |
| `semantic.zig` | 185 |
| `speculation.zig` | 194 |

### Other Modules

| Module | Tier | LOC | Notes |
|--------|------|----:|-------|
| `io.zig` | `[I]` | 969 | I/O operations |
| `mem.zig` + `mem/ctx.zig` | `[I]` | 533 | Memory management |
| `string.zig` | `[I]` | 599 | String operations |
| `db.zig` | `[I]` | 533 | Database abstraction |
| `runtime.zig` | `[I]` | 888 | Runtime utilities |
| `capabilities.zig` | `[I]` | 391 | Capability types (definitions, not enforcement) |
| `vfs_adapter.zig` | `[I]` | 581 | Virtual FS adapter |
| `utcp_registry.zig` | `[I]` | 682 | UTCP protocol registry |
| `std_context.zig` | `[I]` | 241 | Context system |
| `graft/proto.zig` | `[I]` | 104 | Graft protocol |
| `graft/manuals.zig` | `[I]` | 29 | UTCP manuals for grafts |
| `cluster.zig` | `[D]` | 6 | Stub |
| `cluster/grainstore.zig` | `[D]` | 6 | Stub |
| `service.zig` | `[D]` | 16 | Stub |
| `rsp1_cluster.zig` | `[D]` | 62 | Stub |
| `rsp1_crypto.zig` | `[D]` | 82 | Stub |

---

## 6. Tooling & Ecosystem

| Tool | Tier | LOC | Location | Notes |
|------|------|----:|----------|-------|
| NS-MSG (namespace messaging) | `[I]` | 4,155 | `src/service/ns_msg/` (13 files) | Binary protocol, routing, serialization |
| Hinge (package manager) | `[I]` early | 3,485 | `tools/hinge/` (14 files) | Packer, manifest, keyring, resolver |
| LSP Server | `[I]` early | — | `lsp/` (5 files) | Keyword support, semantic bridge |
| Build System | `[I]` | 3,100+ | `build.zig` | 30+ modules, 114 test targets |
| CI/CD | `[I]` | — | `.github/workflows/` (8 files) | GitHub Actions |
| `janus doc` | `[S]` | — | `docs/rfcs/RFC-025-sovereign-documentation.md` | RFC written, no implementation |
| `janus query` (JQL) | `[S]` | — | Query predicates in `astdb/query.zig` | Types defined, no CLI |
| `janus fmt` | `[D]` | — | Mentioned in development docs | Not implemented |
| `janus publish` | `[D]` | — | Mentioned in Garden Wall doctrine | Not implemented |

---

## 7. Specifications

### Active Specs (31)

| Spec | Title | Impl Tier |
|------|-------|-----------|
| SPEC-000 | Meta-Specification | `[I]` reference |
| SPEC-001 | Core Semantics | `[I]` partial |
| SPEC-002 | Profiles System | `[S]` — profiles defined, no enforcement |
| SPEC-003 | Runtime System | `[I]` — scheduler implemented |
| SPEC-004 | Tokenizer & Lexical Structure | `[I]` — fully implemented |
| SPEC-005 | Surface Grammar | `[I]` — parser implements this |
| SPEC-006 | Semantic Analysis Architecture | `[S]` — basic sema works, advanced passes stubbed |
| SPEC-007 | ASTDB Global Schema | `[I]` — schema implemented |
| SPEC-008 | ASTDB & Query Engine | `[S]` — predicates exist, query engine not built |
| SPEC-009 | QTJIR (SSA IR) | `[I]` — IR fully operational |
| SPEC-010 | QTJIR Hardware Accelerator | `[D]` — no hardware backends |
| SPEC-011 | Panic Taxonomy & Failure Modes | `[S]` — partial in runtime |
| SPEC-012 | Bootstrapping & Capabilities | `[S]` — types defined, no enforcement |
| SPEC-013 | Canonical Program Representation | `[S]` |
| SPEC-014 | Structural Pattern Matching | `[S]` — basic match works, full structural not done |
| SPEC-015 | Ownership & Affinity | `[S]` — not implemented |
| SPEC-016 | Grafting Syntax & Flow | `[S]` — parser handles `graft`, no codegen |
| SPEC-017 | Language Grammar | `[I]` — parser is the implementation |
| SPEC-018 | :core Profile | `[I]` ~95% |
| SPEC-019 | :service Profile | `[S]` partial |
| SPEC-020 | Async Executor Model | `[I]` — nursery/spawn/await work |
| SPEC-021 | :cluster Profile (Actors) | `[D]` — 6 LOC stubs |
| SPEC-021 | Scheduler (CBC-MN) | `[I]` — 5,249 LOC scheduler |
| SPEC-022 | Scheduling Capabilities | `[S]` |

### Legacy Specs (`specs/legacy/`) — 57 files

Archived specifications from earlier design phases. Not actively tracked. Includes: profile designs, stdlib structure, dispatch guides, memory safety comparisons, language comparisons (Rust, Nim, Ruby, Lua, Go, Python), hinge packaging, crypto foundations, and more.

### RFCs (`docs/rfcs/`) — 23 files

| RFC | Title | Impl Tier |
|-----|-------|-----------|
| 0001 | Error Model | `[I]` — error unions work |
| 0002 | Allocator Model | `[I]` — explicit allocators throughout |
| RFC-002 | Profile Taxonomy v2 | `[S]` — taxonomy defined, no enforcement |
| RFC-015 | Tag Functions | `[S]` |
| RFC-016 | UFCS | `[I]` — pipe operator works |
| RFC-017 | Rebinding | `[S]` |
| RFC-018 | Postfix Guards | `[S]` |
| RFC-019 | With Expression | `[S]` |
| RFC-020 | Function Capture | `[S]` |
| RFC-021 | Cluster Profile | `[D]` |
| RFC-022 | LSM Tree Storage Engine | `[D]` |
| RFC-023 | Grainstore Stdlib | `[D]` |
| RFC-024 | StoreDB Plugin | `[D]` |
| RFC-025 | Sovereign Documentation | `[S]` — RFC written, no impl |
| Dispatch (4 files) | Dispatch integration/semantics | `[I]` — 13K LOC engine |
| RFC-compiler-versioning | Compiler Versioning | `[S]` |
| RFC-jit-revolution | JIT Compilation | `[D]` |
| RFC-numerical-excellence | Numeric Types | `[S]` |
| RFC-path-join-operator | Path Join | `[S]` |
| RFC-ui-graft-integration | UI Grafts | `[D]` |

### RFC (`RFC/`) — 1 file

| RFC | Title | Impl Tier |
|-----|-------|-----------|
| RFC-0500 | NS-MSG (Namespace Messaging) | `[I]` — 4,155 LOC in `src/service/ns_msg/` |

---

## 8. Doctrines (23 files in `doctrines/`)

Doctrines are architectural principles, not implementation items. Active doctrines:

| Doctrine | Purpose |
|----------|---------|
| Manifesto | Why Janus exists |
| Janus Zen | Core philosophy (two-edged language) |
| Panopticum | Feature-folder architecture (enforced) |
| Sovereign Graph | String ownership in QTJIR (enforced) |
| Garden Wall | Capsule standard + proof certificates |
| Grafting | Foreign code integration rules |
| Living Documentation | Doc-as-code philosophy |
| Probatio | Scientific verification protocol |
| Collections / Iterator | Stdlib design principles |
| Memory | Allocator sovereignty, explicit lifetimes |
| Discoverability | UTCP manuals for AI agents |
| Arsenal | Zero-cost abstractions over science |
| ML Workloads | Tensor-first philosophy |
| Leapfrogging | Language evolution strategy |
| Registry Sovereignty (RSP-1) | Package registry protocol |

---

## 9. Infrastructure

| Item | Tier | Notes |
|------|------|-------|
| Zig 0.16 compilation | `[I]` | All source compiles clean |
| Zig 0.16 linking | `[I]` | `zig cc` + clang/LLVM |
| Test suite | `[I]` | 96 test steps defined, 8/8 compiler core targets green, 40 e2e/stdlib targets pending Zig 0.16 compat |
| Examples | `[I]` | 116 `.jan` files across 10+ categories |
| External deps | `[I]` | blake3 only (`third_party/`) |
| CI workflows | `[I]` | 8 GitHub Actions workflows |
| Build system | `[I]` | 30+ modules, 96 test steps in `build.zig` |

---

## 10. Examples Inventory

116 `.jan` files in `examples/`. Categories:

| Category | Count | Description |
|----------|------:|-------------|
| Core language | ~30 | Variables, types, operators, control flow |
| Strings | ~15 | String operations, intrinsics, ABI |
| Error handling | ~5 | Error unions, catch, try |
| Defer/cleanup | ~5 | Defer LIFO, complex cleanup |
| Arrays/slices | ~5 | Array operations, slice iteration |
| File I/O | ~5 | Read/write file operations |
| Dispatch | ~5 | Multiple dispatch, resolution |
| Service | — | `examples/service/` subdirectory |
| Showcase | — | `examples/showcase/` subdirectory |
| Semantic engine | — | `examples/semantic-engine/` subdirectory |
| jfind | — | `examples/jfind/` (grep-like tool) |
| xor | — | `examples/xor/` (XOR tutorial) |
| Oracle | — | `examples/oracle_hello/` |
| QTJIR | — | `examples/qtjir/` (IR examples) |
| Native Zig | — | `examples/native_zig/` |

---

## 11. Known Gaps

### :core — COMPLETE ✅

All :core features implemented and tested as of 2026-02-26:
- Error handling (`!T`, `fail`, `catch`, `try`) — full pipeline
- Trait/impl with static + dynamic dispatch (SPEC-025 Phases A-C)
- Closures (zero-capture, captured, mutable) (SPEC-024 A/B/C)
- Enums + tagged unions (SPEC-023)
- Range operators (`..`, `..<`, `..=`)
- String API (10 query intrinsics + core ops)
- All control flow, pattern matching, structs, arrays, defer, modules

**Doctrinal decisions (2026-02-26):**
- Generics deferred to `:service` bridge — :core teaches concrete types
- Profile enforcement deferred — not needed until :service ships
- String interpolation deferred — syntactic sugar, violates :core simplicity

### Major Missing Subsystems

| Subsystem | Current State | Required For |
|-----------|---------------|-------------|
| Profile enforcement | Not enforced — all features available in all profiles | All non-:core profiles |
| Capability enforcement | Types defined, no compiler enforcement | Security model |
| Effect tracking | Predicates defined, no compiler enforcement | Correctness guarantees |
| Ownership / affine types | Specified in SPEC-015, not implemented | Memory safety |
| Query engine CLI (`janus query`) | Predicate types in query.zig, no CLI | Developer tooling |
| Documentation generator (`janus doc`) | RFC-025 written, no implementation | Ecosystem |
| Formatter (`janus fmt`) | Not started | Developer tooling |
| Package registry | Hinge packer exists, no registry server | Ecosystem |

### Dispatch Engine (13K LOC) — Phase D Polish (Deferred)

The dispatch engine (`compiler/libjanus/dispatch_*.zig`) is the largest compiler subsystem at 13,036 LOC. SPEC-025 Phases A-C complete: parser, lowering, static dispatch, vtable machinery, &dyn Trait bindings. Phase D (type propagation beyond i32, vtable merging for multi-trait, call-site checking, semantics_dispatch integration) is deferred — does not block :core.

---

*This document reflects the actual state of the codebase as of 2026-02-26. Every `[I]` claim is backed by source files. Update this document when implementation tiers change.*

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->



# Janus Profiles System — User Guide

**Version:** 2.0.0  
**Status:** Canonical  
**Last Updated:** 2025-12-08  
**Based on:** [profiles.md v2.0](specs/profiles.md)

---

## What Are Profiles?

Janus profiles are **capability sets** that adapt the language to different use cases while maintaining **identical semantics**. Think of them as different **lenses** through which you view the same language—not different languages.

> **Core Principle:** Profiles restrict *language complexity*, not *capability*.  
> Every profile speaks the same grammar; only the **available features** change.

---

## The Profile Matrix

Janus operates on **two orthogonal axes**:

1. **Capability Set**: What features are available (types, concurrency, metaprogramming)
2. **Execution Mode**: How code runs (strict/compiled vs. fluid/interpreted)

```
                    EXECUTION MODE
                 strict          fluid
              ┌──────────────┬──────────────┐
     core     │  :core       │  :script     │  Teaching/Scripting
              ├──────────────┼──────────────┤
   service    │  :service    │  :service!   │  Backend Services
  CAPABILITY  ├──────────────┼──────────────┤
     SET      │  :cluster    │  :cluster!   │  Distributed Logic
              ├──────────────┼──────────────┤
    compute   │  :compute    │  :compute!   │  NPU/GPU Kernels
              ├──────────────┼──────────────┤
  sovereign   │  :sovereign  │  (N/A)       │  Systems Programming
              └──────────────┴──────────────┘

Legend:
- No suffix = strict mode (Monastery, AOT compiled, explicit)
- ! suffix = fluid mode (Bazaar, JIT/interpreted, sugared)
```

---

## The Six Profiles

### 1. `:core` — The Teaching Subset

**Purpose**: Education, simple tools, deterministic execution  
**Aliases**: `:core`, `:teaching`, `:haiku`

| Aspect | Specification |
|--------|---------------|
| **Types** | 6 core types: `i64`, `f64`, `bool`, `String`, `Array`, `HashMap` |
| **Constructs** | 8 constructs: `func`, `let`, `var`, `if`, `else`, `for`, `while`, `return` |
| **Concurrency** | None (single-threaded) |
| **Publishable** | ✅ Yes |

**Perfect for**: Learning Janus, small CLI tools, embedded systems

---

### 2. `:script` — The Gateway Drug

**Purpose**: Exploration, prototyping, Python/Ruby/Julia parity  
**Aliases**: `:repl`, `:python`, `:lua`, `:ruby`, `:julia`

| Aspect | Specification |
|--------|---------------|
| **Base** | All `:core` capabilities |
| **Sugar** | Implicit types, returns, allocators |
| **REPL** | ✅ Interactive evaluation |
| **Top-level code** | ✅ Allowed |
| **Reflection** | ✅ ASTDB access |
| **Publishable** | ❌ No (must migrate to `:core`) |

**Perfect for**: Rapid prototyping, data science, scripting, learning

**The Journey**: Start here for immediacy, then migrate to `:core` for production.

---

### 3. `:service` — Application Engineering

**Purpose**: Backend services, APIs, application development  
**Aliases**: `:service`, `:java`, `:kotlin`, `:backend`, `:api`

| Aspect | Specification |
|--------|---------------|
| **Base** | All `:core` capabilities |
| **Error Handling** | Error-as-values, `Result` types |
| **Contexts** | Context injection, dependency injection |
| **Concurrency** | CSP channels, goroutine-style |
| **Generics** | Simple generics with constraints |

**Perfect for**: Web services, REST APIs, microservices, business logic

---

### 4. `:cluster` — Distributed Systems

**Purpose**: Fault-tolerant systems, game servers, Metaverse  
**Aliases**: `:cluster`, `:erlang`, `:orleans`, `:akka`, `:actor`, `:otp`

| Aspect | Specification |
|--------|---------------|
| **Base** | All `:service` capabilities |
| **Actors** | Traditional ephemeral actors (`actor`) |
| **Grains** | Virtual Actors with auto-lifecycle (`grain`) |
| **Supervision** | OTP-style supervision trees |
| **Persistence** | Pluggable via `CapDb` capability |
| **Location** | Transparent (runtime decides placement) |

**Perfect for**: Distributed systems, game servers, chat systems, resilient backends

---

### 5. `:compute` — Parallel Compute

**Purpose**: AI/ML, physics, scientific computing, NPU/GPU  
**Aliases**: `:compute`, `:cuda`, `:triton`, `:pytorch`, `:tensor`, `:ai`

| Aspect | Specification |
|--------|---------------|
| **Base** | All `:core` capabilities |
| **Tensors** | `tensor<T, Dims>` types |
| **Streams** | Device streams and events |
| **Memory Spaces** | `on sram`, `on dram`, `on vram`, `on shared` |
| **Device Targeting** | `on device(npu)`, `on device(gpu)`, `on device(auto)` |
| **Kernels** | J-IR graph extraction and optimization |

**Perfect for**: AI/ML workloads, scientific computing, GPU/NPU kernels

---

### 6. `:sovereign` — Total Control

**Purpose**: Operating systems, drivers, performance-critical code  
**Aliases**: `:sovereign`, `:cpp`, `:rust`, `:zig`, `:unsafe`, `:driver`

| Aspect | Specification |
|--------|---------------|
| **Base** | All capabilities from all profiles |
| **Raw Pointers** | `*T` with manual memory management |
| **Comptime** | Full compile-time metaprogramming |
| **Effects** | Complete effect system with capabilities |
| **Multiple Dispatch** | Full dispatch resolution |
| **Unsafe Blocks** | `unsafe { }` for raw operations |

**Perfect for**: Operating systems, device drivers, high-performance systems

---

## Execution Modes: Monastery vs. Bazaar

### Strict Mode (Monastery) — Default

The default for most profiles. Compiled ahead-of-time with explicit semantics.

| Aspect | Behavior |
|--------|----------|
| **Compilation** | AOT (ahead-of-time) |
| **Types** | Explicit declarations required |
| **Allocators** | Always visible |
| **Top-level code** | Disallowed |
| **Publishable** | ✅ Yes |

### Fluid Mode (Bazaar) — Opt-in

Append `!` to profile name for sugared execution.

| Aspect | Behavior |
|--------|----------|
| **Compilation** | JIT or interpreted |
| **Types** | Inferred with sane defaults |
| **Allocators** | Implicit scratch arena |
| **Top-level code** | Allowed |
| **Publishable** | ❌ No |

**Syntax**:
```janus
{.profile: service, mode: fluid.}  // Explicit
{.profile: service!.}              // Shorthand
```

---

## Meta-Profiles (Composites)

Some use cases require multiple capability sets:

| Meta-Profile | Composition | Use Case |
|--------------|-------------|----------|
| **`:game`** | `cluster + compute` | Game engines, Bifrost pattern |
| **`:metaverse`** | `cluster + compute` | Persistent virtual worlds |
| **`:science`** | `core + compute` | Astronomy, physics simulations |
| **`:cloud`** | `service + cluster` | Cloud-native microservices |
| **`:embedded`** | `core` (strict only) | Embedded systems, no runtime |

**Usage**:
```janus
{.profile: game.}  // Expands to: {.profile: cluster + compute.}
```

---

## Migration Paths

### User Journeys

**Script Kiddie → Professional**:
```
:script → :core → :service → :cluster → :sovereign
 (play)   (learn)  (build)   (scale)   (master)
```

**Python Data Scientist → ML Engineer**:
```
:script → :core + :compute → :sovereign + :compute
```

**Go Developer → Distributed Systems**:
```
:service → :cluster
```

**Game Developer**:
```
:game (= :cluster + :compute)
```

### Migration Commands

```bash
# Analyze migration path
janus migrate analyze --from=script --to=service

# Generate migration suggestions
janus migrate suggest

# Apply automated fixes
janus migrate apply --target=core

# Validate migration
janus test --profile=core
```

---

## Quick Start Examples

### Rapid Prototyping with `:script`

```bash
# Interactive exploration
janus script analysis.jan
```

### Production Build with `:core`

```bash
# Deterministic builds
janus run analysis.jan

# Ship as binary
janus build analysis.jan
```

### Backend Service with `:service`

```bash
# Build with concurrency support
janus build --profile=service api.jan
```

### AI/ML with `:compute`

```bash
# Build with NPU/GPU support
janus build --profile=compute model.jan
```

### Distributed System with `:cluster`

```bash
# Build with actor supervision
janus build --profile=cluster game_server.jan
```

---

## Profile Resolution Priority

When you run Janus code, the profile is determined by:

1. Command-line flag `--profile`
2. Source annotation `{.profile: name.}`
3. Project config (`janus.project.kdl`)
4. Environment variable `JANUS_PROFILE`
5. **Default Heuristic:**
   - `janus script` with top-level statements → `:script`
   - `janus run` or `janus build` → `:core`

---

## Compatibility Promises

1. **Upward Compatible**: `:core` code compiles identically in all higher profiles
2. **Stable Semantics**: Enabling features never changes `:core` behavior
3. **Alias Stability**: Old names (`:core`, `:service`, `:cluster`) work forever
4. **Desugar Truth**: Every sugar has published, queryable desugaring

---

## Reference Specifications

For detailed technical specifications, see:

| Document | Description |
|----------|-------------|
| **[SPEC-profiles.md](./specs/SPEC-profiles.md)** | Complete profiles system specification |
| **[SPEC-profile-core.md](./specs/SPEC-profile-core.md)** | Deterministic core subset |
| **[SPEC-profile-script.md](./specs/SPEC-profile-script.md)** | Interactive & dynamic execution |
| **[SPEC-profile-service.md](./specs/SPEC-profile-service.md)** | Backend services & concurrency |
| **[SPEC-profile-cluster.md](./specs/SPEC-profile-cluster.md)** | Actor supervision & distribution |
| **[SPEC-profile-compute.md](./specs/SPEC-profile-compute.md)** | AI/ML & heterogeneous acceleration |
| **[SPEC-profile-sovereign.md](./specs/SPEC-profile-sovereign.md)** | Full capability-secure Janus |

---

## Summary

> **Janus Profiles = Capability Sets × Execution Modes**

Every profile is a different **lens** on the same language:

* **`:core`** — The Monastery: Determinism & precision
* **`:script`** — The Bazaar: Exploration & immediacy
* **`:service`** — The Workshop: Practical services
* **`:cluster`** — The Sanctum: Resilient orchestration
* **`:compute`** — The Foundry: AI/ML acceleration
* **`:sovereign`** — The Citadel: Total sovereignty

**One language, many lenses — eternal harmony.**

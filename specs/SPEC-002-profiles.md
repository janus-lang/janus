<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Specification — Profiles System (SPEC-002)

**Version:** 2.0.0  
**Status:** CANONICAL — Intent-First Taxonomy  
**Authority:** Constitutional  
**Supersedes:** SPEC-profiles.md v0.1.0

---

[PROF:1.1.1] The Janus profiles system operates on **two orthogonal axes**:

1. **Capability Set**: What features are available (types, concurrency, metaprogramming)
2. **Execution Mode**: How code runs (compiled/interpreted, explicit/sugared)

[PROF:1.1.2] This separation enables **strategic adoption** without forcing a single philosophy.

---

## 2. The Profile Matrix

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

## 3. Profile Definitions

### 3.1 `:core` — The Teaching Subset

[PROF:3.1.1] **Purpose**: Education, simple tools, deterministic execution  
[PROF:3.1.2] **Execution**: Strict (AOT compiled)  
[PROF:3.1.3] **Philosophy**: Monastery — explicit, minimal, honest

| Aspect | Specification |
|--------|---------------|
| **Types** | 6 core types: `i64`, `f64`, `bool`, `String`, `Array`, `HashMap` |
| **Constructs** | 8 constructs: `func`, `let`, `var`, `if`, `else`, `for`, `while`, `return` |
| **Concurrency** | None (single-threaded) |
| **Effects** | None (pure functions + simple I/O) |
| **Metaprogramming** | None |
| **Allocators** | Always explicit and visible |
| **Publishable** | ✅ Yes |

**Adoption Aliases**: `:core`, `:teaching`, `:haiku`

### 3.2 `:script` — The Gateway Drug

[PROF:3.2.1] **Purpose**: Exploration, prototyping, Python/Ruby/Julia parity  
[PROF:3.2.2] **Execution**: Fluid (JIT/interpreted)  
[PROF:3.2.3] **Philosophy**: Bazaar — sugared, convenient, debuggable

| Aspect | Specification |
|--------|---------------|
| **Base** | All `:core` capabilities |
| **Sugar** | Implicit types, returns, allocators |
| **REPL** | ✅ Interactive evaluation |
| **Top-level code** | ✅ Allowed |
| **Reflection** | ✅ ASTDB access |
| **Debuggability** | `janus query desugar` reveals truth |
| **Publishable** | ❌ No (must migrate to `:core`) |

**Adoption Aliases**: `:python`, `:lua`, `:ruby`, `:julia`  
**Functional Aliases**: `:repl`, `:jit`, `:explore`

### 3.3 `:service` — Application Engineering

[PROF:3.3.1] **Purpose**: Backend services, APIs, application development  
[PROF:3.3.2] **Execution**: Strict (AOT) or Fluid (`:service!`)

| Aspect | Specification |
|--------|---------------|
| **Base** | All `:core` capabilities |
| **Error Handling** | Error-as-values, `Result` types |
| **Contexts** | Context injection, dependency injection |
| **Concurrency** | CSP channels, goroutine-style |
| **Generics** | Simple generics with constraints |
| **Effects** | Basic I/O effects |

**Adoption Aliases**: `:service`, `:java`, `:kotlin`  
**Functional Aliases**: `:backend`, `:api`, `:microservice`

### 3.4 `:cluster` — Distributed Systems

[PROF:3.4.1] **Purpose**: Fault-tolerant systems, game servers, Metaverse  
[PROF:3.4.2] **Execution**: Strict (AOT) or Fluid (`:cluster!`)

| Aspect | Specification |
|--------|---------------|
| **Base** | All `:service` capabilities |
| **Actors** | Traditional ephemeral actors (`actor`) |
| **Grains** | Virtual Actors with auto-lifecycle (`grain`) |
| **Supervision** | OTP-style supervision trees |
| **Persistence** | Pluggable via `CapDb` capability |
| **Location** | Transparent (runtime decides placement) |

**Adoption Aliases**: `:cluster`, `:erlang`, `:orleans`, `:akka`  
**Functional Aliases**: `:actor`, `:dist`, `:mesh`, `:otp`

### 3.5 `:compute` — Parallel Compute

[PROF:3.5.1] **Purpose**: AI/ML, physics, scientific computing, NPU/GPU  
[PROF:3.5.2] **Execution**: Strict (AOT) or Fluid (`:compute!`)

| Aspect | Specification |
|--------|---------------|
| **Base** | All `:core` capabilities |
| **Tensors** | `tensor<T, Dims>` types |
| **Streams** | Device streams and events |
| **Memory Spaces** | `on sram`, `on dram`, `on vram`, `on shared` |
| **Device Targeting** | `on device(npu)`, `on device(gpu)`, `on device(auto)` |
| **Kernels** | J-IR graph extraction and optimization |

**Adoption Aliases**: `:compute`, `:cuda`, `:triton`, `:pytorch`  
**Functional Aliases**: `:tensor`, `:math`, `:kernel`, `:ai`

### 3.6 `:sovereign` — Total Control

[PROF:3.6.1] **Purpose**: Operating systems, drivers, performance-critical code  
[PROF:3.6.2] **Execution**: Strict only (no fluid mode)

| Aspect | Specification |
|--------|---------------|
| **Base** | All capabilities from all profiles |
| **Raw Pointers** | `*T` with manual memory management |
| **Comptime** | Full compile-time metaprogramming |
| **Effects** | Complete effect system with capabilities |
| **Multiple Dispatch** | Full dispatch resolution |
| **Unsafe Blocks** | `unsafe { }` for raw operations |

**Adoption Aliases**: `:sovereign`, `:cpp`, `:rust`, `:zig`  
**Functional Aliases**: `:unsafe`, `:driver`, `:kernel`, `:os`

---

## 4. Execution Modes

### 4.1 Strict Mode (Monastery)

The default for most profiles. Compiled ahead-of-time with explicit semantics.

| Aspect | Behavior |
|--------|----------|
| **Compilation** | AOT (ahead-of-time) |
| **Types** | Explicit declarations required |
| **Allocators** | Always visible |
| **Top-level code** | Disallowed |
| **Reflection** | Disabled |
| **Publishable** | ✅ Yes |

### 4.2 Fluid Mode (Bazaar)

Opt-in sugared execution. Append `!` to profile name or set `mode: fluid`.

| Aspect | Behavior |
|--------|----------|
| **Compilation** | JIT or interpreted |
| **Types** | Inferred with sane defaults |
| **Allocators** | Implicit scratch arena |
| **Top-level code** | Allowed |
| **Reflection** | ✅ ASTDB access |
| **Publishable** | ❌ No |

**Syntax**:
```janus
{.profile: service, mode: fluid.}  // Explicit
{.profile: service!.}              // Shorthand
```

---

## 5. Meta-Profiles (Composites)

Some use cases require multiple capability sets. Meta-profiles combine them:

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

// Explicit composition
{.profile: cluster + compute.}
```

---

## 6. Alias Resolution

All aliases resolve to canonical profile names at parse time.

```zig
pub fn resolveProfile(name: []const u8) Profile {
    return switch (name) {
        // Core / Script
        "core", "min", "teaching", "haiku" => .Core,
        "script", "python", "lua", "ruby", "julia", "repl" => .Script,
        
        // Service
        "service", "go", "java", "kotlin", "backend", "api" => .Service,
        
        // Cluster
        "cluster", "elixir", "erlang", "orleans", "akka", "actor", "otp" => .Cluster,
        
        // Compute
        "compute", "npu", "cuda", "triton", "pytorch", "tensor", "ai" => .Compute,
        
        // Sovereign
        "sovereign", "full", "cpp", "rust", "zig", "unsafe", "driver" => .Sovereign,
        
        // Meta-profiles
        "game", "metaverse" => .Meta(&[.Cluster, .Compute]),
        "science" => .Meta(&[.Core, .Compute]),
        "cloud" => .Meta(&[.Service, .Cluster]),
        "embedded" => .Core,
        
        else => .Core,  // Safe default
    };
}
```

---

## 7. Migration Paths

### 7.1 User Journeys

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

### 7.2 Migration Commands

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

## 8. Compatibility Promises

1. **Upward Compatible**: `:core` code compiles identically in all higher profiles
2. **Stable Semantics**: Enabling features never changes `:core` behavior
3. **Alias Stability**: Old names (`:core`, `:service`, `:cluster`) work forever
4. **Desugar Truth**: Every sugar has published, queryable desugaring

---

## 9. Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2025-12-07 | Intent-first taxonomy, aliases, meta-profiles |
| 0.1.0 | 2025-10-15 | Initial profile system |

---

**Doctrines Upheld**:
- **Syntactic Honesty**: Same guards in all modes
- **Mechanism over Policy**: Profiles are policy over one mechanism
- **Revealed Complexity**: Cost is visible, execution mode is explicit
- **Adoption Strategy**: Aliases lower barriers without compromising integrity

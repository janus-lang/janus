<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# RFC: Janus Profile Taxonomy v2.0 — Intent-First Naming

**Version:** 0.1.0-DRAFT  
**Status:** PROPOSAL — Requires team review  
**Date:** 2025-12-07

---

## 🎯 Problem Statement

Current profile names (`:core`, `:service`, `:cluster`, `:compute`, `:sovereign`) suffer from:
1. **Language homage** — Names reference other languages, not Janus capabilities
2. **Unclear orthogonality** — Conflates execution mode with capability set
3. **Marketing opacity** — New users don't know what they get

**Key Insight from Markus**:
> `:core` is the Monastery (compiled, explicit) while `:script` is the same capability with sugar and interpreted. This is an orthogonal axis!

---

## 🧬 The Two Orthogonal Axes

Profiles should be understood as **Capability Set × Execution Mode**.

### Axis 1: Capability Sets (What You Can Do)

| Canonical Name | Purpose | Key Features |
|----------------|---------|--------------|
| **`core`** | Teaching Subset | Minimal syntax, explicit allocators, no magic |
| **`service`** | Application Backend | Error handling, CSP channels, context injection |
| **`cluster`** | Distributed Systems | Actors, Grains, supervision trees, location transparency |
| **`compute`** | Parallel Compute | Tensors, streams, memory spaces, J-IR kernels |
| **`sovereign`** | Total Control | Raw pointers, `comptime`, full effects system |

### Axis 2: Execution Modes (How It Runs)

| Mode | Syntax Style | Compilation | Use Case |
|------|--------------|-------------|----------|
| **`strict`** | Explicit (Monastery) | AOT compiled | Production, determinism |
| **`fluid`** | Sugared (Bazaar) | JIT/Interpreted | Exploration, REPL |

### The Matrix

```
                    EXECUTION MODE
                 strict          fluid
              ┌──────────────┬──────────────┐
     core     │  :core       │  :script     │  Teaching/Scripting
              ├──────────────┼──────────────┤
  CAPABILITY  │  :service    │  :service!   │  Backend Services
     SET      ├──────────────┼──────────────┤
              │  :cluster    │  :cluster!   │  Distributed Logic
              ├──────────────┼──────────────┤
     compute  │  :compute    │  :compute!   │  NPU/GPU Kernels
              ├──────────────┼──────────────┤
   sovereign  │  :sovereign  │  (N/A)       │  Systems Programming
              └──────────────┴──────────────┘

Legend:
- No suffix = strict mode (Monastery, compiled, explicit)
- ! suffix = fluid mode (Bazaar, JIT, sugared)
```

---

## 🏷️ Naming Convention

### Primary Names (Scientific/Intent)

| Profile | Full Name | One-liner |
|---------|-----------|-----------|
| **`:core`** | Core Subset | The teaching language. Deterministic, minimal, honest. |
| **`:script`** | Scripting Mode | Core + sugar + REPL. Python-like exploration. |
| **`:service`** | Service Engineering | Error handling, contexts, backend development. |
| **`:cluster`** | Cluster Computing | Virtual Actors, supervision, distributed systems. |
| **`:compute`** | Parallel Compute | Tensors, streams, GPU/NPU acceleration. |
| **`:sovereign`** | Sovereign Systems | Full control, raw pointers, comptime. |

### Adoption Aliases (Onboarding Ramps)

These aliases help developers from other ecosystems find their footing:

| Primary | Adoption Aliases | Why |
|---------|------------------|-----|
| `:core` | `:core`, `:teaching`, `:haiku` | Minimalism heritage |
| `:script` | `:python`, `:lua`, `:ruby`, `:julia` | Dynamic language refugees |
| `:service` | `:service`, `:java`, `:backend` | Application developers |
| `:cluster` | `:cluster`, `:erlang`, `:orleans`, `:actor` | Distributed systems folks |
| `:compute` | `:compute`, `:cuda`, `:triton`, `:tensor` | ML/HPC engineers |
| `:sovereign` | `:sovereign`, `:cpp`, `:rust`, `:zig`, `:unsafe` | Systems programmers |

### Functional Aliases (Intent Shortcuts)

| Alias | Resolves To | Intent |
|-------|-------------|--------|
| `:repl` | `:script` | Interactive exploration |
| `:api` | `:service` | Building REST/gRPC services |
| `:game` | `:cluster + :compute` | Game engine development |
| `:ai` | `:compute` | ML workloads |
| `:driver` | `:sovereign` | Kernel/driver development |
| `:metaverse` | `:cluster + :compute` | Virtual world backends |

---

## 🎮 Meta-Profiles (Composites)

Some use cases require multiple capability sets. These are **meta-profiles**:

```janus
// Single profile
{.profile: cluster.}

// Meta-profile: composite
{.profile: game.}  // Expands to: {.profile: cluster + compute.}

// Explicit composition
{.profile: cluster + compute.}
```

### Predefined Meta-Profiles

| Meta-Profile | Composition | Use Case |
|--------------|-------------|----------|
| **`:game`** | `cluster + compute` | Game engines, Bifrost pattern |
| **`:metaverse`** | `cluster + compute` | Persistent virtual worlds |
| **`:science`** | `core + compute` | Scientific computing (astronomy, physics) |
| **`:embedded`** | `core (strict only)` | Embedded systems, no runtime |
| **`:cloud`** | `service + cluster` | Cloud-native microservices |

---

## 👥 User Journey Examples

### Script Kiddie → Professional Developer

```
:script → :core → :service → :cluster → :sovereign
 (play)   (learn)  (build)   (scale)   (master)
```

### Astronomer

```bash
janus init my_simulation --profile=science
# Gets: :core (deterministic) + :compute (tensors for N-body simulation)
```

### Game Developer

```bash
janus init my_mmo --profile=game
# Gets: :cluster (Virtual Actors for players) + :compute (ECS tensors for physics)
```

### Mobile Operator / Telco

```bash
janus init my_switch --profile=cluster
# Gets: Virtual Actors (grains) for session state, supervision for fault tolerance
```

---

## 🔄 Migration from v1.0 Names

| Old Name | New Primary | Behavior Change |
|----------|-------------|-----------------|
| `:core` | `:core` | None (alias works) |
| `:script` | `:script` | None (unchanged) |
| `:service` | `:service` | None (alias works) |
| `:cluster` | `:cluster` | Grains now primary |
| `:compute` | `:compute` | None (alias works) |
| `:sovereign` | `:sovereign` | None (alias works) |

**Deprecation Strategy**: Old names remain valid aliases forever (no breaking changes).

---

## 📐 The Monastery/Bazaar Distinction

You correctly identified that execution mode is orthogonal:

| Aspect | Monastery (strict) | Bazaar (fluid) |
|--------|-------------------|----------------|
| **Syntax** | Explicit types, allocators | Inferred types, sugar |
| **Compilation** | AOT (ahead-of-time) | JIT/Interpreted |
| **Allocators** | Always visible | Implicit scratch arena |
| **Top-level code** | Disallowed | Allowed |
| **Reflection** | Disabled | Enabled (ASTDB access) |
| **Publishable** | ✅ Yes | ❌ No (must migrate to strict) |

**Syntax for Mode Selection**:

```janus
{.profile: core.}           // Default: strict (Monastery)
{.profile: core, mode: fluid.}  // Explicit: fluid (Bazaar)
{.profile: script.}         // Shorthand for core + fluid
```

---

## ✅ Recommendation

### Accept This Taxonomy If:
- You want **intent-first** naming that scales
- You want **orthogonal separation** of capability vs execution
- You want **meta-profiles** for industry verticals
- You want **backward compatibility** via aliases

### Reject If:
- The complexity of two axes is too much for v1.0
- You prefer simpler "just pick a language" onboarding

---

## 🛠️ Implementation Requirements

1. **CLI**: `janus init --profile=<name>` resolves aliases
2. **Parser**: Recognize all aliases, resolve to canonical
3. **Manifest**: `janus.kdl` stores canonical name only
4. **Documentation**: Update all docs to use primary names
5. **LSP**: Show canonical name + available aliases in hover

---

**Status**: PROPOSAL — Awaiting review  
**Next**: If approved, update DIGEST.md and create SPEC-profiles-v2.md

# SPEC-profiles.md — Janus Profile System

**Status:** Normative  
**Version:** 2.0.0  
**Classification:** 🜏 Constitution

---


## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).

## 1. Scope

[PROF-01] This specification defines the Janus Profile System.

[PROF-02] Profiles are **capability sets** that adapt the language to different use cases.

---

## 2. The Two Axes

[PROF-03] **legality-rule** Profiles operate on two orthogonal axes:

1. **Capability Set** — What features are available
2. **Execution Mode** — How code runs (strict vs. fluid)

---

## 3. Capability Sets

[PROF-04] **legality-rule** The following capability sets are defined:

| Set | Purpose |
|-----|---------|
| `core` | Teaching subset, minimal, deterministic |
| `service` | Application backend, error handling, contexts |
| `cluster` | Distributed systems, actors, supervision |
| `compute` | Parallel compute, tensors, NPU/GPU |
| `sovereign` | Total control, raw pointers, comptime |

### 3.1 Capability Inheritance

[PROF-05] **legality-rule** Higher profiles include all capabilities of lower profiles:

```
core < service < cluster < sovereign
core < compute < sovereign
```

---

## 4. Execution Modes

[PROF-06] **legality-rule** Two execution modes exist:

| Mode | Name | Compilation | Suffix |
|------|------|-------------|--------|
| strict | Monastery | AOT | (none) |
| fluid | Bazaar | JIT | `!` |

[PROF-07] **syntax** `:service!` denotes service capability with fluid execution.

[PROF-08] **legality-rule** `:sovereign` **MUST NOT** support fluid mode.

---

## 5. Special Profiles

### 5.1 `:script`

[PROF-09] **legality-rule** `:script` is shorthand for `:core` with fluid execution.

[PROF-10] **dynamic-semantics** `:script` enables:
- Implicit types and allocators
- Top-level code
- REPL evaluation
- ASTDB reflection

### 5.2 Meta-Profiles

[PROF-11] **syntax** Meta-profiles combine capability sets:

| Meta-Profile | Composition |
|--------------|-------------|
| `:game` | `cluster + compute` |
| `:metaverse` | `cluster + compute` |
| `:science` | `core + compute` |
| `:cloud` | `service + cluster` |

---

## 6. Profile Selection

[PROF-12] **dynamic-semantics** Profile is determined by priority:

1. Command-line `--profile` flag
2. Source annotation `{.profile: name.}`
3. Project config `janus.project.kdl`
4. Environment variable `JANUS_PROFILE`
5. Default heuristic

---

## 7. Compatibility Aliases

[PROF-13] **legality-rule** Legacy aliases **MUST** resolve correctly:

| Alias | Resolves To |
|-------|-------------|
| `:core` | `:core` |
| `:teaching` | `:core` |
| `:service` | `:service` |
| `:backend` | `:service` |
| `:cluster` | `:cluster` |
| `:erlang` | `:cluster` |
| `:actor` | `:cluster` |
| `:compute` | `:compute` |
| `:cuda` | `:compute` |
| `:tensor` | `:compute` |
| `:sovereign` | `:sovereign` |
| `:rust` | `:sovereign` |
| `:zig` | `:sovereign` |

[PROF-14] **informative** Aliases exist for onboarding; canonical names are preferred.

---

## 8. Publishability

[PROF-15] **legality-rule** Only code in **strict mode** is publishable.

[PROF-16] **legality-rule** `:script` code **MUST** be migrated to `:core` before publishing.

---

**Last Updated:** 2026-01-06

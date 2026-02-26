<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — Runtime System (SPEC-003)

**Version:** 2.0.0  

## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).

**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-runtime v0.1.0

## 1. Introduction

This document defines the architecture and behavior of the Janus Runtime System, encompassing structured concurrency (nurseries), actor models, and capability-based security.

### 1.1 Normative References
All definitions in this document SHALL follow the normative language defined in [SPEC-000: Meta-Specification](meta.md).

## 2. Structured Concurrency (Nurseries) ⊢

[RUN:2.1.1] Janus SHALL implement **Structured Concurrency** through the `nursery` construct. No concurrent task SHALL outlive the nursery that spawned it.

[RUN:2.1.2] A `nursery` block SHALL NOT exit until all tasks spawned within it have either completed successfully, returned an error, or been cancelled.

[RUN:2.1.3] **Propagation Rule:** An unhandled exception or error in a child task SHALL trigger the cancellation of all sibling tasks within the same nursery and be propagated to the nursery's caller.

[RUN:2.1.4] **Cooperative Cancellation:** Cancellation SHALL be cooperative. Tasks MUST periodically check for cancellation status via `ctx.check_cancelled()` or by reaching an interruptible I/O boundary.

## 3. Actor System ⧉

[RUN:3.1.1] The Janus Actor System SHALL provide isolated state and message-passing communication.

[RUN:3.1.2] Actors defined with the `actor` keyword SHALL process messages **sequentially**. No two messages within the same actor instance SHALL be processed concurrently.

[RUN:3.1.3] **Grains (Virtual Actors):** In the `:cluster` profile, the runtime MAY support virtual actors (Grains) with automatic lifecycle management and location transparency.

[RUN:3.1.4] **Supervision:** Actors MUST be supervised. Supervisors SHALL implement one of the following restart strategies:
- `one_for_one`: Restart only the failed actor.
- `one_for_all`: Restart all supervised actors in the group if one fails.
- `rest_for_one`: Restart the failed actor and all actors started after it.

## 4. Context & Capability Injection ⧉

[RUN:4.1.1] The runtime SHALL provide a context injection system for dependencies (Allocators, Loggers, Clock, RNG, and Capabilities).

[RUN:4.1.2] **Explicit Injection:** The `with <ctx> do ... end` construct SHALL be used to supply context-eligible parameters to functions within that scope.

[RUN:4.1.3] **Capability Guarding:** Every effectful operation (I/O, network, system access) MUST be guarded by a capability token. The runtime SHALL verify the presence of the REQUIRED capability in the current context before execution.

## 5. Profile-Specific Availability

[RUN:5.1.1] Availability of runtime features SHALL be gated by the active Profile Tier:

| Feature | `:core` | `:script` | `:service` | `:cluster` | `:compute` | `:sovereign` |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| Nurseries | ∅ No | ⟁ JIT | ⊢ Yes | ⊢ Yes | ∅ No | ⊢ Yes |
| Local Actors | ∅ No | ∅ No | ⊢ Yes | ⊢ Yes | ∅ No | ⊢ Yes |
| Distributed Grains | ∅ No | ∅ No | ∅ No | ⊢ Yes | ∅ No | ⊢ Yes |
| Accelerator Pipes | ∅ No | ∅ No | ∅ No | ∅ No | ⊢ Yes | ⊢ Yes |
| Full Capability Check | ⊢ Yes | ⊢ Yes | ⊢ Yes | ⊢ Yes | ⊢ Yes | ⊢ Yes |


## 6. Entry Point & Bootstrap ☍

[RUN:6.1.1] **The Stoic Main (Profile: `:core`, `:service`, `:sovereign`):**
In strict profiles, the entry point MUST be explicit. The user is responsible for the entire initialization chain.
- Signature: `func main(args: []String, allocator: Allocator) -> Result`
- No implicit global state injection.
- The Runtime passes only the raw command-line arguments and the root allocator.
- **Why:** Systems programming requires total control over memory provenance.

[RUN:6.1.2] **The Juicy Main (Profile: `:script`):**
In fluid profiles, the runtime handles boilerplate. The entry point acts as a script body.
- Signature: `func main()` (or top-level code).
- **Injection:** The following are available implicitly in the script scope:
  - `args`: Parsed arguments map.
  - `env`: Environment variable map.
  - `fs`: File system capability (cwd).
  - Implicit Heap: All allocations use a managed default allocator.
- **Mechanism:** The compiler wraps the user's code in a `std.process.Init` equivalent during Lowering.

---

**Ratified:** 2026-01-06  
**Authority:** Markus Maiwald + Voxis Forge

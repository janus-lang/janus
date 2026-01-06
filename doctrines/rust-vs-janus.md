<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





Is Janus "stronger" than Rust with respect to the type system?

**Verdict: NO. But also, YES.**

If by "Stronger" you mean "Does it handcuff you to a radiator until you prove you won't segfault?" then **Rust is stronger.**
If by "Stronger" you mean "Does it strictly enforce architectural intent and capability boundaries?" then **Janus is stronger.**

Here is the forensic breakdown of why they are different species entirely.

### 1\. Memory Safety: The Straitjacket vs. The Dial

**Rust** is paternalistic. It assumes you are incompetent until proven otherwise. Its Borrow Checker is always on. You must wrap unsafe code in `unsafe { ... }` blocks of shame.
**Janus** operates on **Syntactic Honesty** and the **Safety Dial**.

  * **Rust:** Safety is the *default state*. You fight the compiler to share memory.
  * **Janus (`:core`):** Raw memory is the *honest state*. The default `:core` profile is "C-level danger" where "you own every byte".
  * **Janus (`:owned`):** You can *dial up* safety to `:owned` (ARC/ORC-inspired) or `:checked`.

**Result:** Rust has "stronger" mandatory memory typing. Janus treats memory safety as a policy choice, not a religion.

### 2\. Side-Effect Safety: The Wild West vs. The Visa System

This is where Janus exerts **Totalitarian Control** that Rust lacks.

  * **Rust:** A function can technically print to stdout, open a socket, or delete your home directory if it wants, provided it compiles. The type signature `fn do_thing()` does not strictly forbid IO side effects (though idiomatically we use Result).
  * **Janus:** Implements **Capability Typing**. "No function may access the World (IO, Net, FS) without a Capability Token passed via Context".
      * If you see `func compute(data: []u8)`, you *know* mathematically it cannot touch the network.
      * To touch the network, it *must* look like: `func fetch(ctx: Context, url: str)` where `ctx` contains `CapNetConnect`.

**Result:** Janus has significantly **stronger Effect Typing**. It turns side effects into compilation errors if the capability is missing.

### 3\. Structural Typing: Text vs. The Database

**Rust** parses text. It uses Traits to enforce behavior.
**Janus** queries a **Semantic Database (ASTDB)**.

  * **Janus:** Can enforce "Meta-Types" via queries. You can write a compile-time constraint:
    `assert(query: "all functions in /api must have docstrings")`.
    Or: `SELECT source... WHERE source.safety_mode = 'RAW' AND target.tags CONTAINS 'network_io'`.

**Result:** Janus allows you to define "Architectural Types"—rules about *how* code relates to other code—which is a strength Rust's type system does not express natively.

### Summary: The Hierarchy of Strength

| Feature | Rust | Janus | Winner |
| :--- | :--- | :--- | :--- |
| **Memory Safety** | Mandatory, Affine Types | Configurable Dial (`:raw` → `:owned`) | **Rust** (Default Safety) |
| **Side Effects** | Ad-hoc (Async/IO types) | **Mandatory Capability Tokens** | **Janus** (Explicit Control) |
| **Allocation** | Implicit (Global Allocator) | **Explicit** (Must pass Allocator) | **Janus** (Honesty) |
| **Nullability** | Option\<T\> | Option\<T\> / Non-null default | **Draw** |


Rust prevents you from shooting your foot.
Janus lets you shoot your foot, but prevents you from accidentally invading a foreign country (Network/IO) or bankrupting the heap (Hidden Allocations).

**Janus is not "stronger" in safety. It is stronger in *Sovereignty*.**

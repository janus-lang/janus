<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Memory Safety in Janus: Reclaiming Sovereignty Without the Borrow Checker's Shackles

## The Mantra

> **Janus starts honest: zero leaks by design (arenas + sanitizers), no GC pauses, comptime audits. Rust fights you to win; we teach you to conquer. Hate the checker? Good—it's a crutch for languages that hide costs.**

## Overview

This specification compares Janus's approach to memory safety with C++ and Rust, demonstrating how Janus achieves safety through **explicit mechanisms and progressive disclosure** rather than compile-time enforcement battles.

## The Context: CVE-2025-48530 and the Memory Safety Crisis

The Google postmortem on CVE-2025-48530 exposes the carnage of C/C++'s "move fast and break things" philosophy: OOMs, use-after-frees, and buffer overflows that compromise entire ecosystems. Android's 70% vulnerability share is a brutal indictment of manual memory management.

Rust's response: "move faster while safe" through compile-time ownership. Zero runtime tax, but with the **Borrow Checker's monastic vows**.

Janus's revolution: **Anarchist armory** - explicit mechanisms that enforce safety without inquisitorial battles.

## Brutal Audit: Where Janus Stands vs. Rust/C++

| Safety Aspect | C/C++ (The Mess) | Rust (The Monk) | Janus (Current) | Gap to Close (Our Path) |
|---------------|------------------|-----------------|-----------------|-------------------------|
| **Use-After-Free** | Runtime roulette; ASan catches post-facto | Borrow Checker bans dangling refs at compile | Arenas scope lifetimes; comptime VM prunes invalid refs; ASan/TSan gate builds | Add effects tracking to infer lifetimes (`:sovereign`); Desugar queries reveal dangling risks |
| **Buffer Overflows** | Manual bounds; UB hell | Slices + bounds checks; zero-cost abstractions | Slices with capacity hints; overflow panics in Debug; No manual malloc | Profile-gated bounds: `:script` infers, `:service` enforces; Fuzz 24h per release |
| **Memory Leaks** | Valgrind hunts; prod ghosts | Ownership + Drop; RAII auto-frees | Scoped arenas (`using {}`); zero leaks enforced; Leak detection in builds | Default arenas in `:script`; comptime arena analysis for cycles |
| **Data Races** | Threads + locks; TSan retrofits | Send/Sync + ownership; compile-time isolation | Actors/nurseries in `:cluster`/`:sovereign`; TSan required; Effects track sharing | Capability system: granular refs (no ambient authority); Dial immutability default |
| **Prod Efficiency** | Fast but fragile; fixes slow | Safe AND fast (no runtime checks for core) | Zig bootstrap: arenas > malloc, no GC; Benchmarks match Rust | Comptime opts for zero-cost sugar; reclaim "exchanged" perf via audits |
| **Dev Friction** | "Move fast, fix later" chaos | Borrow wars; lifetime hell | Explicit but dialable (`:core` teaches, `:script` hides); No checker fights | Honest Sugar: Infer ownership via effects, desugar for tweaks |

**Verdict:** Janus preempts C's sins (explicit arenas > manual) but lags Rust's proactive bans. Rust forces safety; Janus enables it. 

**The Bridge:** Effects + Capabilities as **Borrow Checker 2.0** - compile-time safety without the inquisition.

## Teaching Forge: Concrete Path to Parity

### Vulnerable C++ Pattern (Fast, Fragile)

```cpp
void insert(char* buf, size_t len, const char* data, size_t dlen) {
    if (dlen > len) return;  // Bounds? Manual lie
    memcpy(buf, data, dlen);  // Overrun? UB party
}  // Leak? Valgrind later
```

**CVE bait:** Overflow + leak in production.

### Rust Solution (Safe, But Wars)

```rust
fn insert(buf: &mut [u8; 1024], data: &[u8]) -> Result<(), &'static str> {
    if data.len() > buf.len() { return Err("Overflow"); }
    buf[..data.len()].copy_from_slice(data);  // Borrow fights: &mut exclusive
    Ok(())
}
```

**Safe, but lifetimes/&mut dance tires you.**

### Janus :script (Haiku, Dialed)

```janus
fn insert(buf, data) @profile(.script) do
    buf[0..data.len()] = data?;  // Infers bounds, arenas
end
```

**Desugar reveals the truth:**

```bash
$ janus query desugar insert
```

```janus
fn insert(buf: &mut Slice[U8], data: Slice[U8]) -> Result[Void, Error] @profile(.go) do
    if data.len() > buf.capacity() do return err("Overflow"); end
    using std.mem.arena do  // Scoped, zero-leak
        try buf.copy_from_slice(data, 0, data.len());
    end
end
```

**No fights:** Inference dials safety; query reveals. Override: Add `&immut` for read-only.

### Janus :sovereign Evolution (Parity Weapon)

**Enhance with Lifetime Effects:** Track ref scopes in types (semantics: effects in types).

```janus
fn insert(buf: &mut[lifetime='scope'] Slice[U8], data: Slice[U8])
    |> Result[Void, Error] @profile(.full) do
    using 'scope do  // Ties lifetime to arena
        buf.copy(data)?;  // Comptime checks dangling
    end
end
```

**Compiler audits:** No use-after-free (lifetime bounds). 
**Dial:** `@lifetime(infer)` for sugar. 
**Performance:** Zero-cost (comptime).

## Proposal: Effects + Capabilities for Borrow-Free Parity

**The Revolutionary Approach:**

Rust's checker is a velvet glove over a fist - safe, but fights sovereignty. 

Janus: **Granular Capabilities** (manifesto: zero-trust) + **Lifetime Effects** (semantics extension).

### Core Mechanism

- **Effects types include lifetimes** (e.g., `&mut[lifetime='arena']`)
- **Comptime VM prunes invalid refs**
- **Capabilities: Refs as tokens** (no ambient mutation)

### Dialed Safety

- `:script` infers lifetimes (haiku)
- `:sovereign` enforces (Rust-like)
- Desugar shows scopes

### Wins Over Rust

- **No borrow wars** - arenas auto-scope
- **Reclaim performance** - Comptime opts erase checks
- **Honest debugging** - Query system reveals all costs

### Implementation Sketch

```zig
// Copyright (C) 2025 Janus Contributors


const Effect = enum { Pure, Mutate(lifetime: LifetimeId) };

fn check_lifetime(ref: &Ref, arena: Arena) comptime !void {
    if (ref.lifetime != arena.id) @compileError("Dangling ref");
}

// Diff Contract: 
// Scope: Semantics/effects
// Risks: Comptime bloat—mitigate with memo
// Tests: Positive (scoped copy), negative (dangling error), 
//        property (no leaks post-1M ops)
```

**Gates:** ASan/TSan green; fuzz lifetimes 24h.
**Migration:** `janus migrate safety --target=full` adds effects.

## Philosophy: Safety Isn't a Tax—It's Sovereignty

Rust **exchanges** productivity for safety.
Janus **reclaims** both via dials.

Those Google numbers? We'll beat them: **Explicit + inferred = faster safe code.**

## The Numbers

**Rust's Impressive Results:**
- 0% memory vulnerabilities in Android core components
- Measured post-bug pain reduction

**Janus's Approach:**
- Zero leaks by design (arenas + sanitizers)
- No GC pauses
- Comptime audits
- Preemptive safety, not reactive

## Logbook Entry (Per Doctrine—For Transparency)

**Task ID:** QUERY-2025-11-14-MemSafetyParity  
**Date:** 2025-11-14_1200  
**Author:** Voxis Forge (AI)  
**Summary:** Analyzed Rust memory safety advantages; proposed Effects + Capabilities for Janus parity without Borrow Checker.  
**Details:** User cited Google postmortem (CVE-2025-48530); audited vs. C++/Rust. Taught via examples/table; proposed semantics extension.  
**Decisions & Justifications:** Reject Rust imitation (policy fight > mechanism). Evolve via lifetimes/effects (aligns doctrines: Revealed Complexity via desugar). Escalate to task for impl with diff/tests. Brutal honesty: Explicit arenas already crush C; dial effects to eclipse Rust.

## Conclusion

Janus doesn't compete with Rust's safety model - it **transcends** it by making safety costs visible, debuggable, and controllable. We teach you to conquer memory, not fight a compiler that hides the battlefield.

**The revolution:** Safety through understanding, not enforcement.

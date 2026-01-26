# REPORT: The "Juicy Main" Decision

**Date:** 2026-01-18
**Topic:** Integration of `std.process.Init` (Zig 0.14 "Juicy Main") Concepts into Janus.
**Status:** **STRATEGIC ADOPTION**

## 1. Analysis
Zig 0.14 introduces a pattern where `main` can accept an `Init` struct, effectively injecting dependencies (Allocator, Args, Env) and removing boilerplate. This bridges the gap between scripting ease and systems control.

## 2. The Janus Verdict

We reject this pattern for the **Compiler Core** (`janusd`) but adopt it as the **Primary Differentiator** for the **:script Profile**.

### 2.1 Why Reject for Compiler?
- **Control:** We strictly manage the ASTDB memory arena. We cannot delegate this to a generic initializer.
- **Stability:** The API is in flux (Zig `master`).
- **Transparency:** "Stoic Main" (explicit) is doctrinally required for systems code.

### 2.2 Why Adopt for :script?
- **Ergonomics:** Scripting requires zero boilerplate.
- **Profile Identity:** This perfectly illustrates the `:script` vs `:min` divide.
- **Mechanism:** The Janus Compiler will effectively "inject" a "Juicy Main" wrapper around user scripts during lowering.

## 3. Implementation Plan
1.  **Specs Updated:** `SPEC-003-runtime.md` and `SPEC-002-profiles.md` now define "Stoic Main" vs "Juicy Main".
2.  **Future Work:** When implementing the `:script` lowering pass in the compiler, we will use a `std.process.Init`-like structure to wrap the user's code.

**Conclusion:** We steal the idea, but we weaponize it as a Profile Feature rather than a default.

— **Voxis Forge**

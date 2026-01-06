<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





### The Janus Doctrine: Surpassing Rust In Specific Domains

Our strategy is not to be "Rust-but-easier." Our strategy is to provide **90% of Rust's safety guarantees for 10% of its cognitive cost**, achieved through a philosophy of **Clarity over Cleverness**.



> Rust chose to pay the price for **absolute, compile-time memory and concurrency safety** in the coin of **cognitive complexity**. The borrow checker and explicit lifetimes (`'a`) are the mechanism of that payment. This complexity is why AI code generators falter; they struggle with the global, non-local reasoning required to satisfy the borrow checker, a task that often challenges human experts.
>
> We will not pay this price. We will achieve comparable safety through a different, more intuitive model.



#### Pillar 1: Structured Lifetimes, Not Inferred Ones

This is our primary weapon. Instead of Rust's complex, per-variable lifetime analysis, Janus will be built upon **scoped memory arenas** (or regions), a concept you've already established in your memory model.

- **Honesty & Clarity:** Memory allocation is always explicit to an arena. `let user = alloc_in_arena(arena, User{...});`. The lifetime of `user` is unambiguously tied to the lifetime of `arena`.
- **The Simplicity Advantage:** The compiler's job becomes radically simpler. It doesn't need to solve a complex puzzle of interlocking borrow lifetimes. It only needs to enforce one rule: **"A pointer to data in a shorter-lived arena cannot be stored in a longer-lived arena."** This is a simple, structural check that is easy for humans and AI to understand and debug.
- **Ergonomics:** This eliminates the entire category of `'a` lifetime annotations and the most complex borrow-checker errors.

------



#### Pillar 2: Progressive Complexity for Shared Ownership



The arena model elegantly handles ~90% of use cases (request handling, data processing pipelines, etc.). For the remaining 10% that require complex, shared ownership of data that must outlive its creation scope, we will provide a clear, **opt-in** mechanism.

- **Explicit Shared Heap:** Janus will provide a standard library type, perhaps `Shared<T>`, which uses atomic reference counting (like Rust's `Arc<T>`).
- **Pay for What You Use:** A developer new to Janus never has to see or think about `Shared<T>`. They live entirely in the simple, safe world of arenas. Only when a specific, complex need arises do they reach for this tool. This creates a gentle learning curve, a principle we'll call **Progressive Complexity**. Rust, in contrast, forces you to confront its most complex ideas from the start.

------



#### Pillar 3: AI-First Ergonomics & Tooling



We will design the language and its errors specifically for clarity and local reasoning, making it a perfect target for AI-assisted development.

- **Compiler as a Teacher:** An error message will not be `"cannot infer appropriate lifetime"`. It will be `"Error: you are trying to return a pointer from the 'request_arena' which is destroyed at the end of this function."` This is a direct, actionable instruction.
- **Visual Tooling:** The standard Janus toolkit will include a visualizer that shows memory arenas, their scopes, and the data within them. This makes the memory model tangible.
- **Predictable Code:** Because the lifetime model is structural, the code an AI generates is far more likely to be correct. It doesn't need to reason about a web of borrows; it just needs to respect scope.

------



### The RISC-V Beachhead Strategy



RISC-V (and  ARMv8) is our target territory. This is where we build our own kingdom.

1. **Optimized Backend:** Our first and best compiler backend will be for RISC-V. We will invest heavily in generating the most performant RISC-V assembly, leveraging custom extensions where available.
2. **Core Libraries:** We will write the core Janus libraries—drivers, firmware tools, crypto—specifically for popular RISC-V boards (like those from SiFive and Pine64). We will provide the best-in-class "getting started" experience for any developer wanting to build for RISC-V.
3. **Ecosystem Seeding:** We will sponsor and actively contribute to writing key open-source RISC-V software in Janus: a bootloader, a small kernel, a hypervisor. We will demonstrate through dominant execution that Janus is the native language of this new architecture.

Janus will not win by being a "better Rust." It will win by offering a fundamentally different and superior trade-off: **vastly improved productivity and a near-zero learning curve in exchange for a simple, structural safety model that is more than sufficient for the vast majority of systems programming tasks.**

This is how we conquer RISC-V.

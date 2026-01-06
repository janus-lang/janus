# THE LAST LANGUAGE (DOCTRINE)

> "We are not building a language. We are building a Civilization."

Janus is engineered to survive decades, not just release cycles. This doctrine defines the architecture of **Sovereign Preservation**.

## 1. The Profiles (The Spectrum of Control)

Janus is not one language; it is a spectrum.

*   **`:edge` (The Prototyper):** Safe, High-Level, Decimals. For Logic & Prototyping.
*   **`:script` (The Glue):** Dynamic, JIT. For Orchestration.
*   **`:core` (The System):** Manual, Low-Level. For Drivers & Performance.
*   **`:core` (The Kernel):** Freestanding. For Bare Metal.

**The Pivot:** Write in `:edge` first. Prove the logic. Then descend to `:core` using `janus harden`.

## 2. The Sustainability (The Time Capsule)

Code written today must compile in 50 years without modification.

### Epoch-Based Parsing
*   Source code is immutable within an epoch (`// janus: v0.4.2`).
*   The Daemon (`janusd`) acts as a **Router**, selecting the correct **Parser Module** for the declared epoch.

### The Sovereign Registry
*   Parsers are **WASM Modules**.
*   `janusd` fetches missing parsers from the Sovereign Registry (IPFS/Mirror) on demand.
*   **Security:** Parsers run in a WASM sandbox. Even legacy parsers cannot compromise the system.

## 3. The Ecosystem (The JIR Treaty)

The **Janus Intermediate Representation (JIR)** is the Rosetta Stone.

*   **JIR v1:** The invariant standard.
*   **The Contract:** The Backend (Optimizer) promises to *always* accept JIR v1 input, forever.
*   **Evolution:** Old parsers emit JIR v1. New backends consume JIR v1 (and future v2).

**Result:** A parser written in 2025 communicates perfectly with an optimizer written in 2050.

## 4. The Constitution

1.  **No Politics:** Optimize for utility and correctness.
2.  **No Breakage:** Support legacy via isolation (Time Capsule/WASM), not integration.
3.  **No Forgetting:** The system remembers how to speak the old tongue.

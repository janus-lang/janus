<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->


# Why Janus Exists
**The Manifesto of the Sovereign Engineer**

Janus was not born from a desire to create just another programming language. It was forged from frustration—a 15-year journey through the landscape of software, where I found only two extremes: languages that treated me like a child, hiding the machine behind layers of "magic," or languages that treated me like a monk, demanding years of penance before I could build a simple tool.

I am an IT Engineer at heart. I think in terms of systems, resources, capabilities, and concrete costs. I needed a language that could span from a 10-line script to a distributed operating system without forcing me to rewrite my brain—or my codebase.

**Janus is that answer.** It is built on three immutable doctrines:

### 1. The Doctrine of Revealed Complexity
> **"The computer's work must not be hidden from the programmer."**

We reject the lie that "elegance" means hiding cost. True elegance is **visible mastery**. In Janus, the syntax honestly reflects the cost of the operation.

* `user.name` is a field access. It is cheap.
* `user.get_name()` is a function call. It may be expensive.
* `read_file()` requires a `CapFsRead` token. You cannot touch the disk by accident.
* `a + b` is math. `vec.add(a, b)` is an allocation. Operators are never overloaded to hide work.

There is no "magic." There is no hidden I/O. There is no implicit allocation. **You see the cost. You are in control.**

### 2. The Doctrine of Temporal Evolution (The Profiles)
Most languages force you to choose: "Fast vs. Easy" or "Script vs. System."
Janus allows you to choose **Time**. How long do you want this code to live?

* **`:script` (The Bazaar):** The explorer's mode. Python-like ergonomics, JIT execution, and interactive REPL. For prototyping and glue.
* **`:core` (The Monastery):** The foundation. Strict, deterministic, AOT-compiled. No hidden control flow. Perfect for teaching and robust tools.
* **`:service` / `:service`:** The builder's mode. Adds concurrency, error contexts, and structured services.
* **`:compute` / `:compute`:** The scientist's mode. Native tensors, hardware acceleration, and Julia-parity numerics for AI and Physics.
* **`:sovereign` (The Fortress):** The architect's mode. Capabilities, Actors, and `comptime` metaprogramming.

Your code evolves. A `:script` prototype becomes a `:core` tool, which grows into a `:sovereign` system. **No rewrites. Only hardening.**

### 3. The Doctrine of the Machine Partner (AI-First)
We are entering the age of the AI Developer. Legacy languages are text buffers that hallucinating LLMs struggle to parse.
Janus is **Code as Data**.

* **The ASTDB:** The source of truth is not the file; it is a queryable, semantic database. AI agents can query the codebase ("Who calls `init` with `unsafe`?") rather than guessing.
* **Syntactic Honesty:** Because the syntax never lies about mechanisms, the AI cannot hallucinate side effects.
* **Capability Security:** You can trust AI-generated code because it is mathematically confined by the capabilities you grant it.

### The Goal: The Last Language
Our goal is not to replace C++, Python, or Rust. Our goal is to encompass the **entire lifecycle of a software idea**—from the first scratchpad script to the final, verified binary.

Janus is the language for those who want to see the gears turning.
For those who demand **Sovereignty** over their tools.
For those who are ready to build the future, not just script the present.

**This is Janus.**
*Deploy. Verify. Conquer.*
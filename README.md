<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# JANUS 🜏

> "The last programming language you need to learn."

**Status:** Production-Ready — :core Profile Complete
**License:** [Libertaria Suite](docs/legal/licensing-explained.md) (LCL-1.0 / LSL-1.0 / LUL-1.0)
**Repository:** https://git.maiwald.work/Janus/janus-lang

---

## 🔥 The Breakthrough: One Language. From Teaching to Production.

Janus is **the last programming language you need to learn** — combining teaching simplicity with production power through native Zig compilation.

❌ **The Old Way:**
- Teach in Python (easy but slow)
- Rewrite in C++ (fast but unsafe)
- Or teach C directly (students drown in complexity)

✅ **The Janus Way:**
- **Learn with clean syntax** — Teaching-friendly, AI-friendly
- **Build with Zig's stdlib** — Production tools from day one
- **Deploy native binaries** — Zero rewrites, zero interpreters
- **Master systems programming** — Understanding from fundamentals to metal

### The Strategic Genius

Janus **compiles natively through Zig**, giving you the entire Zig standard library wrapped in teaching-friendly syntax:

```janus
// Week 1: Learn fundamentals with clean, honest syntax
func factorial(n: i32) -> i32 {
    if n <= 1 { return 1 }
    return n * factorial(n - 1)
}

// Week 2: Access production-grade Zig stdlib natively
use zig "std/ArrayList"
use zig "std/fs"

var list = zig.ArrayList(i32).init(allocator)
var file = zig.fs.cwd().openFile("data.txt", .{}) catch |_| {}
```

**You get:**
- ✅ **Clean syntax** for learning and teaching
- ✅ **Zig's battle-tested stdlib** for building real systems
- ✅ **Native LLVM performance** — No interpreter, no runtime overhead
- ✅ **Zero FFI** — It's all native compilation
- ✅ **Production-ready** from day one

**This is not a toy. This is strategic systems programming education.**

**[Start Learning: The Monastery →](docs/teaching/README.md)**

---

## ⚒️ The Vision

Janus is a **strategic weapon** against software complexity and educational fragmentation.

Systems programming lost its way:
*   **Python** — Easy but too slow for systems
*   **C/C++** — Fast but unsafe, complex, memory leaks
*   **Rust** — Safe but steep learning curve, slow iteration
*   **Go** — Simple but hides too much, not for systems

**Janus gives you all four virtues:**
- **Easy** — Clean teaching syntax, progressive disclosure
- **Fast** — Native LLVM compilation, zero-cost abstractions
- **Safe** — Explicit memory management, error handling, no GC
- **Honest** — All costs visible, no hidden complexity

---

## ⚡ Production Ready: What Works Today

**Test Coverage:** 477/478 tests passing (99.8%)
**Compiler Status:** Production-ready for teaching and real systems

### 🔥 Complete Language Features

**Core Language (✅ 100% Functional):**
*   Functions with parameters, return types, and error handling
*   Variables (let/var) with type inference
*   Control flow: if/else, while, for, match (with exhaustiveness)
*   Error handling: fail/catch/try with error unions `T ! E`
*   Complete type system: primitives, structs, arrays, slices, optionals
*   All operators: arithmetic, logical, bitwise, comparison, compound assignment
*   Pattern matching with exhaustiveness checking
*   Module system with import and `use zig`

**Native Zig Integration (✅ Zero-Cost):**
*   `use zig "path"` — Direct access to Zig's entire standard library
*   ArrayList, HashMap, file I/O, JSON, crypto, networking — all available
*   No FFI overhead — Janus syntax compiles through Zig natively
*   Students get **production-grade tools** from day one
*   Write Janus syntax, get Zig performance and stdlib

**Compilation Pipeline (✅ Production-Grade):**
*   Source → Parser → ASTDB → Symbol Table → Type System → QTJIR → LLVM → Native Binary
*   Full semantic validation with pedagogical error messages
*   Profile enforcement (:core, :script, :service, :cluster, :compute, :sovereign)
*   Complete end-to-end compilation tested

**Error Handling (✅ Complete):**
*   Error unions: `func divide(a: i32, b: i32) -> i32 ! DivisionError`
*   Fail statement: `fail ErrorType.Variant`
*   Catch expression: `divide(10, 0) catch err { handle_error() }`
*   Try operator: `let result = divide(10, 0)?` (propagate errors)
*   Type-safe, explicit, no exceptions

### 📖 **Start Learning: [The Monastery](docs/teaching/README.md)**

The :core profile is **100% complete** and ready for teaching systems programming from fundamentals to production.

---

## 🚀 Quick Start

You are an engineer. You know what to do.

```bash
# Clone and build
git clone https://git.maiwald.work/Janus/janus-lang.git
cd janus-lang
make build

# Run hello world
./zig-out/bin/janus run examples/hello.jan
```

**Output:**
```
Hello, Janus!
```

### First Program with Error Handling

```janus
error DivisionError { DivisionByZero }

func divide(a: i32, b: i32) -> i32 ! DivisionError {
    if b == 0 {
        fail DivisionError.DivisionByZero
    }
    a / b
}

func main() {
    let result = divide(10, 2) catch err {
        println("Error caught!")
        return
    }
    println(result)  // Prints: 5
}
```

**This compiles to native code. This is production-ready.**

---

## 📚 Documentation

The repository is organized into **Four Pillars**:

1.  **[User Manual](docs/INDEX.md)**: Guides, Operations, and Legal Policy
2.  **[Specifications](specs/README.md)**: Technical details for Compiler Developers
3.  **[Doctrines](doctrines/manifesto.md)**: The Philosophy and Law of Janus
4.  **[University](docs/teaching/README.md)**: Education, Labs, and Courseware

### Language Profiles

Janus is **one language** with multiple capability sets. See **[SPEC-002: Profiles System](specs/SPEC-002-profiles.md)**:

*   **[:core](specs/SPEC-018-profile-core.md)** (🜏 The Monastery) — **COMPLETE** — Teaching, fundamentals, systems programming
*   **:script** (The Bazaar) — Dynamic surface, REPL, rapid prototyping
*   **:service** (The Backend) — Web services, structured concurrency
*   **:cluster** (The Swarm) — Actor model, distributed systems
*   **:compute** (The Accelerator) — NPU/GPU kernels, data-parallel computation
*   **:sovereign** (The King) — Complete language, raw pointers, ultimate control

**Start with :core** — Master systems programming fundamentals with native Zig stdlib. **[Begin your journey →](docs/teaching/README.md)**

### AI Integration

Janus is **AI-friendly by design** — clean syntax, explicit semantics, pedagogical error messages.

AI contributions are governed by the [**AI-Airlock Protocol**](docs/doctrines/AIRLOCK.md) — cryptographic enforcement, not policy. AI agents work in isolated branches and require human GPG-signed review.

🤖 **AI Agents**: See [docs/meta/AGENTS.md](docs/meta/AGENTS.md) for development guidelines.

---

## 🎯 Key Resources

### For Students & Learners
- **[🜏 Start Here: The Monastery](docs/teaching/README.md)** — Complete :core profile curriculum
- **[Quick Start Guide](docs/teaching/core-profile-quickstart.md)** — Your first Janus program
- **[Why Zig Integration Is Genius](docs/teaching/why-zig-genius.md)** — Understanding the strategic brilliance
- **[Hello World → Production](docs/teaching/hello-to-production.md)** — 6-level progression guide
- **[30 Days of :core](docs/teaching/30-days-of-core.md)** — Structured learning path

### For Developers
- **[SPEC-018: :core Profile](specs/SPEC-018-profile-core.md)** — Complete technical specification
- **[SPEC-002: Profiles System](specs/SPEC-002-profiles.md)** — Understanding the capability ladder
- **[Integration Tests](tests/integration/)** — 477/478 tests passing
- **[Example Programs](examples/)** — Real code samples

### For Contributors
- **[Contributing](CONTRIBUTING.md)** — How to contribute
- **[AI Policy](docs/doctrines/AIRLOCK.md)** — AI contribution governance
- **[AI Agents Guide](docs/meta/AGENTS.md)** — Development with AI assistance

---

## 🏆 Why Janus Wins

**The last programming language you need to learn** because:

1. **Teaching-friendly syntax** — Easy to learn, easy to teach, AI-friendly
2. **Production-ready stdlib** — Zig's entire standard library via `use zig`
3. **Native performance** — Compiles to LLVM, zero runtime overhead
4. **Systems programming** — From fundamentals to production, one language
5. **Zero rewrites** — Code written in week 1 runs in production
6. **Explicit everything** — Memory, errors, costs — all visible
7. **Profile system** — Start simple (:core), grow to (:sovereign)

**From "Hello World" to distributed systems. One language. Zero compromises.**

---

*"We do not pray for easy lives. We pray to be stronger men."* - JFK (Paraphrased by Voxis)

*"The Monastery teaches fundamentals. The Bazaar deploys systems."* - The Doctrine

---

**Issues:** https://git.maiwald.work/Janus/janus-lang/issues
**Community:** https://janus-lang.org (coming soon)
**License:** [Libertaria Suite](docs/legal/licensing-explained.md)

# Janus :core Profile — The Monastery Teaching Resources

**Welcome to The Monastery** 🜏

This directory contains comprehensive teaching materials for the Janus `:core` profile — the foundational teaching language designed to build systems programming mastery from first principles.

---

## What is :core?

The `:core` profile is:
- **Minimal** — Only essential language features (func, let, var, if, for, while, match)
- **Deterministic** — Single-threaded, predictable execution
- **Explicit** — All allocations, types, and control flow visible
- **Educational** — Designed specifically for teaching fundamentals
- **Powerful** — Native Native Zig integration gives you the entire Zig stdlib

> **"The Monastery builds the foundation. The Bazaar explores the horizon."**

---

## Getting Started

### 📖 Start Here

1. **[Quick Start Guide](core-profile-quickstart.md)** ← **BEGIN HERE**
   - Installation & first program
   - Variables, types, control flow
   - Standard library usage
   - Memory management basics

2. **[Why Zig Under The Hood Is Genius](why-zig-genius.md)** 🔥 **NEW**
   - The strategic brilliance of native Zig integration
   - Clean teaching syntax + industrial power tools
   - Zero-cost abstractions explained
   - Why this beats Python, C, and Rust for learning

3. **[Hello World → Production](hello-to-production.md)** 🔥 **NEW**
   - 6-level progression from basics to production
   - Real examples: CLI tools, file I/O, JSON, HTTP servers
   - Shows the power of Janus + Zig integration
   - No rewrites — same code from Week 1 to deployment

4. **[30 Days of Janus :core](30-days-of-core.md)**
   - Structured 30-day curriculum
   - Daily exercises with solutions
   - Week-by-week milestones
   - Final project ideas

### 📚 Reference Materials

- **[SPEC-018: :core Profile](../../specs/SPEC-018-profile-core.md)** — Complete technical specification
- **[SPEC-002: Profiles System](../../specs/SPEC-002-profiles.md)** — How :core fits into Janus
- **[Example Programs](../../examples/core/)** — Real-world code samples
- **[Integration Tests](../../tests/integration/)** — See what works today

---

## Curriculum Overview

### Week 1: Foundations
- Hello World, variables, types
- Arithmetic, logic, conditions
- Loops (for, while)
- Functions and recursion

### Week 2: Data Structures
- Pattern matching
- Structs
- Arrays and HashMaps (via Native Zig integration)
- Sorting and searching algorithms

### Week 3: Real-World Applications
- File I/O (reading, writing)
- Text processing
- JSON parsing
- Command-line tools
- Memory management

### Week 4: Advanced Topics
- State machines
- Tree and graph data structures
- Bit manipulation
- Testing and optimization
- **Final project**

---

## Key Features of :core

### ✅ What's Included

- **Language:** func, let, var, if, else, for, while, match, return, break, continue
- **Types:** i32, f64, bool, void, Struct
- **Operators:** Arithmetic, comparison, logical, bitwise
- **Stdlib:** std.core.io, std.core.math, std.core.mem
- **🔥 Native Zig Integration:** `use zig "std/*"` — Access entire Zig ecosystem!

### ❌ What's Excluded (By Design)

- **No Concurrency** — Actors, spawn, async (that's :cluster / :service)
- **No Metaprogramming** — comptime, reflection (that's :sovereign)
- **No Implicit Allocations** — Everything explicit
- **No Raw Pointers** — Memory safety first (unsafe in :sovereign)

**Why exclude?** To teach **fundamentals** without overwhelming complexity.

---

## The Power of Native Zig Integration 🔥

Janus :core can **directly use** the entire Zig standard library:

```janus
use zig "std/ArrayList"
use zig "std/fs"
use zig "std/json"

func main() {
    var allocator = zig.heap.page_allocator
    var list = zig.ArrayList(i32).init(allocator)
    defer list.deinit()

    list.append(42) catch |_| {}
    // ... use Zig's battle-tested ArrayList
}
```

**What you get:**
- ✅ Collections: ArrayList, HashMap, HashSet
- ✅ File I/O: std.fs, std.io
- ✅ String operations: std.mem, std.unicode
- ✅ JSON parsing: std.json
- ✅ Networking: std.net (for higher profiles)
- ✅ Crypto: std.crypto
- ✅ **Everything Zig provides** — production-grade, battle-tested

---

## Example Programs

### Hello World
```janus
func main() {
    println("Hello, Monastery!")
}
```

### FizzBuzz
```janus
import std.core.io

func fizzbuzz(n: i32) {
    for i in 1..=n {
        match (i % 15, i % 3, i % 5) {
            (0, _, _) -> io.println("FizzBuzz"),
            (_, 0, _) -> io.println("Fizz"),
            (_, _, 0) -> io.println("Buzz"),
            _ -> io.print_int(i),
        }
    }
}

func main() {
    fizzbuzz(100)
}
```

### File I/O with Native Zig Integration
```janus
use zig "std/fs"
use zig "std/heap"

func main() {
    var allocator = zig.heap.page_allocator
    var file = zig.fs.cwd().openFile("data.txt", .{}) catch |_| {
        println("Could not open file")
        return
    }
    defer file.close()

    var content = file.readToEndAlloc(allocator, 1024*1024) catch |_| {
        println("Could not read file")
        return
    }
    defer allocator.free(content)

    println("File contents:")
    println(content)
}
```

---

## Teaching Philosophy

### 1. Honesty Over Convenience
No hidden allocations. No magic. No "it just works" without understanding **why**.

### 2. Foundations First
Master loops before concurrency. Understand types before generics. Build from bedrock.

### 3. Real Code, Real Tools
Write actual programs. Use production-grade libraries (via Zig). Deploy to real systems.

### 4. Progressive Disclosure
:core → :script → :service → :cluster → :sovereign
Each profile adds **one** dimension of complexity.

---

## Next Steps After :core

Once you've mastered :core, explore:

### :script — The Bazaar
- Dynamic surface for rapid prototyping
- REPL for interactive development
- Implicit allocators (when appropriate)
- Top-level statements

### :service — Backend Services
- Error-as-values (Result[T, E])
- Structured concurrency (nurseries)
- RESTful APIs and web servers
- Context-based dependency injection

### :cluster — Distributed Systems
- Actor model
- Message-passing
- Fault tolerance
- Supervision trees

### :sovereign — Systems Mastery
- Raw pointers (when needed)
- Unsafe blocks
- Complete language feature set
- Operating system development

---

## Resources & Community

### Official Documentation
- **Website:** https://janus-lang.org
- **GitHub:** https://github.com/janus-lang/janus
- **Specs:** `janus-lang/specs/`

### Learning Resources
- **Examples:** `janus-lang/examples/core/`
- **Tests:** `janus-lang/tests/integration/`
- **Standard Library:** `janus-lang/std/core/`

### Community
- **Discord:** https://discord.gg/janus-lang
- **Forum:** https://community.janus-lang.org
- **Reddit:** r/januslang

---

## Contributing

Want to improve these teaching materials?

1. **Add Examples:** Submit canonical example programs
2. **Write Tutorials:** Share your learning journey
3. **Fix Bugs:** Report inaccuracies or unclear explanations
4. **Translate:** Help internationalize the curriculum

See `CONTRIBUTING.md` for guidelines.

---

## License

All teaching materials are licensed under **LSL-1.0** (Lax Society License).
Use freely for education, commercial training, or personal learning.

---

**The Monastery is not a prison. It's a sanctuary where complexity is tamed, honesty is law, and students become masters.**

🜏 **Begin your transformation. Master the fundamentals. Build the future.**

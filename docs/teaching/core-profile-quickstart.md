# Janus :core Profile — Quick Start Guide

**The Monastery Teaching Language**

Welcome to Janus `:core` — the foundational profile that teaches you systems programming with **radical honesty**. No magic, no hidden costs, just pure computational thinking.

## What is :core?

The `:core` profile is:
- **Minimal** — Only essential language features
- **Deterministic** — Predictable, single-threaded execution
- **Explicit** — All allocations, all types, all control flow visible
- **Educational** — Designed to teach fundamentals

Think of it as **"C with training wheels"** or **"Zig for beginners"**.

---

## Installation

```bash
# Clone Janus
git clone https://git.maiwald.work/Janus/janus-lang
cd janus-lang

# Build compiler
zig build

# Run your first program
./zig-out/bin/janus run examples/hello.jan
```

---

## Your First Program

Create `hello.jan`:

```janus
func main() {
    println("Hello, Monastery!")
}
```

**Run it:**
```bash
janus run hello.jan --profile=core
```

**What you learned:**
- `func` declares a function
- `main()` is the entry point
- `println()` prints to stdout (built-in)

---

## Variables & Types

```janus
import std.core.io

func main() {
    // Immutable binding (preferred)
    let x = 42
    let pi = 3.14159
    let is_learning = true

    // Mutable binding (when needed)
    var count = 0
    count = count + 1

    // Print values
    io.print_int(x)
    io.print_float(pi)
    io.print_bool(is_learning)
}
```

**Types in :core:**
- `i32` — 32-bit signed integer
- `f64` — 64-bit floating point
- `bool` — Boolean (`true` / `false`)
- `void` — No return value

---

## Control Flow

### If/Else

```janus
func check_sign(x: i32) {
    if x > 0 {
        println("Positive")
    } else if x < 0 {
        println("Negative")
    } else {
        println("Zero")
    }
}
```

### For Loops

```janus
func count_to_ten() {
    for i in 0..10 {  // 0, 1, 2, ..., 9
        print_int(i)
    }
}
```

### While Loops

```janus
func countdown(n: i32) {
    var count = n
    while count > 0 {
        print_int(count)
        count = count - 1
    }
}
```

### Pattern Matching

```janus
func describe_number(n: i32) {
    match n {
        0 -> println("zero"),
        1 -> println("one"),
        2 -> println("two"),
        _ -> println("something else"),
    }
}
```

---

## Functions

```janus
// Function with return value
func add(a: i32, b: i32) -> i32 {
    return a + b
}

// Function without return value
func greet(name: String) {
    println("Hello, " ++ name)
}

// Recursive function
func factorial(n: i32) -> i32 {
    if n <= 1 {
        return 1
    }
    return n * factorial(n - 1)
}
```

**Key rule:** All function signatures MUST have explicit types.

---

## The FizzBuzz Challenge

Every programmer should write FizzBuzz. Here's the Janus version:

```janus
import std.core.io

func fizzbuzz(n: i32) {
    for i in 1..=n {  // 1, 2, ..., n (inclusive)
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

---

## 🔥 The Power Move: Native Zig Integration

Janus can **directly use** the entire Zig standard library:

```janus
use zig "std/ArrayList"
use zig "std/heap"

func main() {
    var allocator = zig.heap.page_allocator
    var list = zig.ArrayList(i32).init(allocator)
    defer list.deinit()

    list.append(10) catch |_| {}
    list.append(20) catch |_| {}
    list.append(30) catch |_| {}

    // Sum all elements
    var sum: i32 = 0
    for list.items |item| {
        sum = sum + item
    }

    println("Sum: ")
    print_int(sum)  // 60
}
```

**What you get:**
- ✅ ArrayList, HashMap, HashSet
- ✅ File I/O (`std.fs`, `std.io`)
- ✅ String operations (`std.mem`)
- ✅ JSON parsing (`std.json`)
- ✅ Networking (`std.net`)
- ✅ Crypto (`std.crypto`)
- ✅ **Everything Zig provides**

---

## Memory Management

In `:core`, memory is **explicit**:

```janus
use zig "std/ArrayList"
use zig "std/heap"

func create_list() {
    var allocator = zig.heap.page_allocator
    var list = zig.ArrayList(i32).init(allocator)

    // DO THIS: Manual cleanup
    defer list.deinit()

    list.append(42) catch |_| {}
    // ... use list ...

    // list.deinit() called automatically at scope exit (via defer)
}
```

**Golden rules:**
1. **Every `init` needs a `deinit`**
2. **Use `defer` for automatic cleanup**
3. **No garbage collection, no magic**

---

## Standard Library

### std.core.io — Simple I/O

```janus
import std.core.io

func main() {
    io.print_int(42)
    io.print_float(3.14)
    io.print_bool(true)
}
```

### std.core.math — Math Operations

```janus
import std.core.math

func main() {
    let result = math.pow(2, 10)  // 1024
    let absolute = math.abs(-42)   // 42
    let minimum = math.min(5, 3)   // 3
}
```

### std.core.mem — Memory Allocators

```janus
import std.core.mem

func main() {
    let allocator = mem.default_allocator()
    let ptr = mem.alloc(allocator, 1024)
    defer mem.free(allocator, ptr)

    // Use allocated memory...
}
```

---

## Example Programs

### 1. Factorial

```janus
import std.core.io

func factorial(n: i32) -> i32 {
    if n <= 1 {
        return 1
    }
    return n * factorial(n - 1)
}

func main() {
    io.print_int(factorial(10))  // 3628800
}
```

### 2. Prime Number Check

```janus
import std.core.io

func is_prime(n: i32) -> bool {
    if n <= 1 {
        return false
    }
    if n <= 3 {
        return true
    }

    var i = 2
    while i * i <= n {
        if n % i == 0 {
            return false
        }
        i = i + 1
    }
    return true
}

func main() {
    for n in 2..100 {
        if is_prime(n) {
            io.print_int(n)
        }
    }
}
```

### 3. File I/O with Native Zig Integration

```janus
use zig "std/fs"
use zig "std/heap"

func read_config() {
    var allocator = zig.heap.page_allocator
    var file = zig.fs.cwd().openFile("config.txt", .{}) catch |_| {
        println("Could not open file")
        return
    }
    defer file.close()

    var content = file.readToEndAlloc(allocator, 1024 * 1024) catch |_| {
        println("Could not read file")
        return
    }
    defer allocator.free(content)

    println("Config loaded:")
    println(content)
}

func main() {
    read_config()
}
```

---

## What :core Does NOT Have

The `:core` profile intentionally **excludes**:

❌ **Concurrency** — No `spawn`, `send`, `receive` (that's `:cluster`)
❌ **Async/Await** — No asynchronous execution (that's `:service`)
❌ **Metaprogramming** — No `comptime`, no reflection (that's `:sovereign`)
❌ **Implicit Allocations** — All memory explicit
❌ **Raw Pointers** — Unsafe operations forbidden (that's `:sovereign`)

**Why?** To teach **fundamentals** without overwhelming complexity.

---

## Next Steps

Once you've mastered `:core`:

1. **Explore :script** — Dynamic surface for rapid prototyping (REPL, JIT)
2. **Move to :service** — Backend services with error-as-values, async
3. **Try :cluster** — Actor model for distributed systems
4. **Master :sovereign** — Complete Janus with all features unlocked

**The Monastery teaches fundamentals. Master :core, understand all of Janus.**

---

## Resources

- **Spec:** `specs/SPEC-018-profile-core.md`
- **Examples:** `examples/core/`
- **Tests:** `tests/integration/*_e2e_test.zig`
- **Community:** https://janus-lang.org/community

---

**Welcome to The Monastery. Begin your journey.**

🜏 **:core** — Where complexity is tamed, honesty is law, and students become masters.

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
func main() do
    println("Hello, Monastery!")
end
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

func main() do
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
end
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
func check_sign(x: i32) do
    if x > 0 do
        println("Positive")
    else if x < 0 do
        println("Negative")
    else
        println("Zero")
    end
end
```

### For Loops

```janus
func count_to_ten() do
    for i in 0..10 do  // 0, 1, 2, ..., 9
        print_int(i)
    end
end
```

### While Loops

```janus
func countdown(n: i32) do
    var count = n
    while count > 0 do
        print_int(count)
        count = count - 1
    end
end
```

### Pattern Matching

```janus
func describe_number(n: i32) do
    match n {
        0 => println("zero"),
        1 => println("one"),
        2 => println("two"),
        _ => println("something else"),
    }
end
```

**Note:** Match uses `{}` because it's declarative (SPEC-017 Law 2).

---

## Functions

```janus
// Function with return value
func add(a: i32, b: i32) -> i32 do
    return a + b
end

// Function without return value
func greet(name: String) do
    println("Hello, " ++ name)
end

// Recursive function
func factorial(n: i32) -> i32 do
    if n <= 1 do
        return 1
    end
    return n * factorial(n - 1)
end
```

**Key rule:** All function signatures MUST have explicit types.

---

## The FizzBuzz Challenge

Every programmer should write FizzBuzz. Here's the Janus version:

```janus
import std.core.io

func fizzbuzz(n: i32) do
    for i in 1..=n do  // 1, 2, ..., n (inclusive)
        match (i % 15, i % 3, i % 5) {
            (0, _, _) => io.println("FizzBuzz"),
            (_, 0, _) => io.println("Fizz"),
            (_, _, 0) => io.println("Buzz"),
            _ => io.print_int(i),
        }
    end
end

func main() do
    fizzbuzz(100)
end
```

---

## The Power Move: Native Zig Integration

Janus can **directly use** the entire Zig standard library:

```janus
use zig "std/ArrayList"
use zig "std/heap"

func main() do
    var allocator = zig.heap.page_allocator
    var list = zig.ArrayList(i32).init(allocator)
    defer list.deinit()

    list.append(10) catch |_| do end
    list.append(20) catch |_| do end
    list.append(30) catch |_| do end

    // Sum all elements
    var sum: i32 = 0
    for list.items |item| do
        sum = sum + item
    end

    println("Sum: ")
    print_int(sum)  // 60
end
```

**What you get:**
- ArrayList, HashMap, HashSet
- File I/O (`std.fs`, `std.io`)
- String operations (`std.mem`)
- JSON parsing (`std.json`)
- Networking (`std.net`)
- Crypto (`std.crypto`)
- **Everything Zig provides**

---

## Memory Management

In `:core`, memory is **explicit**:

```janus
use zig "std/ArrayList"
use zig "std/heap"

func create_list() do
    var allocator = zig.heap.page_allocator
    var list = zig.ArrayList(i32).init(allocator)

    // DO THIS: Manual cleanup
    defer list.deinit()

    list.append(42) catch |_| do end
    // ... use list ...

    // list.deinit() called automatically at scope exit (via defer)
end
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

func main() do
    io.print_int(42)
    io.print_float(3.14)
    io.print_bool(true)
end
```

### std.core.math — Math Operations

```janus
import std.core.math

func main() do
    let result = math.pow(2, 10)  // 1024
    let absolute = math.abs(-42)   // 42
    let minimum = math.min(5, 3)   // 3
end
```

### std.core.mem — Memory Allocators

```janus
import std.core.mem

func main() do
    let allocator = mem.default_allocator()
    let ptr = mem.alloc(allocator, 1024)
    defer mem.free(allocator, ptr)

    // Use allocated memory...
end
```

---

## Example Programs

### 1. Factorial

```janus
import std.core.io

func factorial(n: i32) -> i32 do
    if n <= 1 do
        return 1
    end
    return n * factorial(n - 1)
end

func main() do
    io.print_int(factorial(10))  // 3628800
end
```

### 2. Prime Number Check

```janus
import std.core.io

func is_prime(n: i32) -> bool do
    if n <= 1 do
        return false
    end
    if n <= 3 do
        return true
    end

    var i = 2
    while i * i <= n do
        if n % i == 0 do
            return false
        end
        i = i + 1
    end
    return true
end

func main() do
    for n in 2..100 do
        if is_prime(n) do
            io.print_int(n)
        end
    end
end
```

### 3. File I/O with Native Zig Integration

```janus
use zig "std/fs"
use zig "std/heap"

func read_config() do
    var allocator = zig.heap.page_allocator
    var file = zig.fs.cwd().openFile("config.txt", .{}) catch |_| do
        println("Could not open file")
        return
    end
    defer file.close()

    var content = file.readToEndAlloc(allocator, 1024 * 1024) catch |_| do
        println("Could not read file")
        return
    end
    defer allocator.free(content)

    println("Config loaded:")
    println(content)
end

func main() do
    read_config()
end
```

---

## What :core Does NOT Have

The `:core` profile intentionally **excludes**:

**Concurrency** — No `spawn`, `send`, `receive` (that's `:cluster`)
**Async/Await** — No asynchronous execution (that's `:service`)
**Metaprogramming** — No `comptime`, no reflection (that's `:sovereign`)
**Implicit Allocations** — All memory explicit
**Raw Pointers** — Unsafe operations forbidden (that's `:sovereign`)

**Why?** To teach **fundamentals** without overwhelming complexity.

---

## Syntax Quick Reference

**SPEC-017 Law 2: The Structural Divide**

| Context | Delimiter | Example |
|:--------|:----------|:--------|
| `func`, `if`, `else`, `while`, `for`, `using` | `do..end` | `func main() do ... end` |
| `match`, `enum`, `struct`, `flags`, literals | `{ }` | `match x { ... }` |

This is **law** — never use `{}` for function bodies or control flow!

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

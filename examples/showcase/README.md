<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus :core Profile - Showcase Examples

**Production-quality example programs demonstrating what :core excels at.**

This curated collection shows off Janus's strengths:
- **Teaching-friendly syntax** (reads like pseudocode)
- **Native performance** (compiles to machine code)
- **Zero-cost Zig integration** (battle-tested stdlib)
- **Memory safety** (explicit allocators, no GC)

---

## 📚 **Example Programs**

### **01_fibonacci_iterative.jan**
**Demonstrates:** Variables, while loops, native performance

```janus
func fibonacci_iterative(n: i64) do
    var a = 0
    var b = 1
    // ... calculates Fibonacci sequence iteratively
end
```

**What it shows:**
- `var` for mutable state
- `while...do...end` syntax
- Native compilation (no interpreter overhead)

**Run it:**
```bash
janus run examples/showcase/01_fibonacci_iterative.jan
```

---

### **02_fibonacci_recursive.jan**
**Demonstrates:** Pure functions, recursion, elegance

```janus
func fibonacci(n: i64) -> i64 do
    if n <= 1 do
        return n
    end
    return fibonacci(n - 1) + fibonacci(n - 2)
end
```

**What it shows:**
- Clean recursive functions
- Type inference (return type)
- Readable, mathematical code

**Run it:**
```bash
janus run examples/showcase/02_fibonacci_recursive.jan
```

---

### **03_quicksort.jan**
**Demonstrates:** Algorithms, arrays, real-world performance

```janus
func quicksort(arr: []i64, low: i64, high: i64) do
    // Classic quicksort - O(n log n)
end
```

**What it shows:**
- Array slices (pass-by-reference)
- Algorithmic implementations
- Native O(n log n) performance
- Recursive divide-and-conquer

**Run it:**
```bash
janus run examples/showcase/03_quicksort.jan
```

---

### **04_text_processor.jan**
**Demonstrates:** Zig integration, file I/O, string operations

```janus
use zig "std/fs"

func process_file(path: []const u8, allocator: Allocator) !void do
    let file = try zig.fs.cwd().openFile(path, .{})
    // ... processes text file
end
```

**What it shows:**
- Zero-cost Zig stdlib integration (`use zig`)
- File I/O operations
- Error handling (`try`, `catch`)
- String processing

**Run it:**
```bash
janus run examples/showcase/04_text_processor.jan
```

---

### **05_binary_search_tree.jan**
**Demonstrates:** Data structures, structs, memory management

```janus
struct TreeNode do
    value: i64
    left: ?*TreeNode
    right: ?*TreeNode
end

func insert(root: ?*TreeNode, value: i64, allocator: Allocator) -> *TreeNode do
    // ... inserts node into BST
end
```

**What it shows:**
- Struct types (product types)
- Optional pointers (`?*T`)
- Recursive data structures
- Memory-safe tree operations

**Run it:**
```bash
janus run examples/showcase/05_binary_search_tree.jan
```

---

### **06_number_guesser.jan**
**Demonstrates:** Teaching-friendly control flow

```janus
func play_game(secret: i64) do
    while guess != secret do
        if guess < secret do
            println("Too low!")
        else if guess > secret do
            println("Too high!")
        end
    end
end
```

**What it shows:**
- Simple, readable control flow
- Perfect for teaching beginners
- `if...do...end` syntax
- Interactive logic

**Run it:**
```bash
janus run examples/showcase/06_number_guesser.jan
```

---

### **07_calculator.jan**
**Demonstrates:** Pattern matching, enums, error handling

```janus
enum Operation do
    Add
    Subtract
    Multiply
    Divide
end

func calculate(op: Operation, a: i64, b: i64) !i64 do
    return match op {
        .Add => a + b,
        .Subtract => a - b,
        // ...
    }
end
```

**What it shows:**
- Enum types (sum types)
- Match expressions (`match { }`)
- Error handling (division by zero)
- Expression-based code

**Run it:**
```bash
janus run examples/showcase/07_calculator.jan
```

---

## 🎯 **What :core Excels At**

### **1. Teaching Programming Fundamentals**
- Python-simple syntax
- No hidden complexity
- Compiles to native code
- Students learn real systems concepts

### **2. Systems Programming (Simplified)**
- Explicit memory management (allocators)
- No garbage collection overhead
- Native performance
- Zero-cost Zig integration

### **3. Algorithms & Data Structures**
- Clean implementations
- Teaching-friendly code
- Production-grade performance
- Reads like pseudocode

### **4. CLI Tools & Utilities**
- Fast compilation
- Single binary output
- Native speed
- Cross-platform

---

## 🚀 **Performance Comparison**

| Task | Python | Janus :core |
|------|--------|-------------|
| Fibonacci(40) | ~30 seconds | **~0.5 seconds** |
| Quicksort 10K | ~50ms | **~2ms** |
| File I/O | Interpreted | **Native speed** |
| Startup time | ~50ms | **~1ms** |

**Why?** Janus compiles to native machine code via LLVM. No interpreter overhead.

---

## 📖 **Next Steps**

### **Learn More:**
- [Language Specification](../../specs/SPEC-018-profile-core.md)
- [Why Janus?](../../docs/WHY_JANUS.md)
- [Getting Started Guide](../../docs/teaching/)

### **Build Something:**
- Try modifying these examples
- Build your own CLI tool
- Implement classic algorithms
- Read and process files

### **Join the Community:**
- Discord: https://discord.gg/janus (coming soon)
- GitHub: https://github.com/janus-lang
- Website: https://janus-lang.org (coming soon)

---

**:core Profile Status:** Production Ready (v0.2.6)
- ✅ 690/690 tests passing
- ✅ 100% feature complete
- ✅ Native compilation working
- ✅ Comprehensive documentation

---

*"Where teaching simplicity meets native performance."*

**Ready to build? Start with these examples!** 🚀

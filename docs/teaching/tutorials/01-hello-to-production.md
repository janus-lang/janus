<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Hello World to Production in 30 Minutes

**From first program to compiled binary - the complete journey.**

**Time:** 30 minutes
**Level:** Absolute Beginner
**Prerequisites:** None (we start from zero!)
**What you'll build:** A working command-line program that compiles to native code

---

## **Minute 0-5: Installation & Setup**

### Install Janus

```bash
# Download and install Janus
curl -sSf https://janus-lang.org/install.sh | sh

# Verify installation
janus --version
# Should show: Janus v0.2.6
```

### Create your project

```bash
# Create a new directory
mkdir my-first-janus
cd my-first-janus

# Create your first program
touch hello.jan
```

---

## **Minute 5-10: Hello World**

### Write your first program

Open `hello.jan` in your favorite editor:

```janus
// My first Janus program!

func main() do
    println("Hello, World!")
end
```

### Run it

```bash
janus run hello.jan
```

**Output:**
```
Hello, World!
```

### 🎉 **Congratulations!** You just ran your first Janus program!

**What happened:**
- `func main() do...end` - Entry point for your program
- `println(...)` - Prints text to terminal
- Janus compiled it to native code and ran it

---

## **Minute 10-15: Variables & Types**

### Expand your program

```janus
func main() do
    // Immutable variables (default)
    let name = "Janus"
    let version = 0.26

    println("Welcome to ", name, " v", version)

    // Mutable variables
    var count = 0
    count = count + 1

    print("Counter: ")
    print_int(count)
    println("")
end
```

**What you learned:**
- `let` for immutable variables (can't change)
- `var` for mutable variables (can change)
- Type inference (Janus figures out types automatically)
- Multiple ways to print (`println`, `print`, `print_int`)

---

## **Minute 15-20: Control Flow**

### Add logic to your program

```janus
func greet(name: []const u8, age: i64) do
    println("Hello, ", name, "!")

    if age < 18 do
        println("You're a minor")
    else if age < 65 do
        println("You're an adult")
    else
        println("You're a senior")
    end
end

func main() do
    greet("Alice", 25)
    greet("Bob", 70)
    greet("Charlie", 15)
end
```

**What you learned:**
- Function parameters with types
- `if...do...end` conditional logic
- `else if` for multiple conditions

---

## **Minute 20-25: Loops & Iteration**

### Add iteration

```janus
func print_fibonacci(count: i64) do
    var a = 0
    var b = 1
    var i = 0

    println("Fibonacci sequence:")

    while i < count do
        print_int(a)
        print(" ")

        let temp = a + b
        a = b
        b = temp

        i = i + 1
    end

    println("")
end

func main() do
    print_fibonacci(10)

    println("\nCounting with for:")
    for i in 0..5 do
        print_int(i)
        print(" ")
    end
    println("")
end
```

**What you learned:**
- `while...do...end` loops
- `for...in` range iteration
- `0..5` inclusive range (0,1,2,3,4,5)
- Mutable state in loops

---

## **Minute 25-28: Compile to Binary**

### Create a standalone executable

```bash
# Compile your program
janus build hello.jan -o hello

# Now you have a native binary!
ls -lh hello
```

**Output:**
```
-rwxr-xr-x  1 user  staff   50K  Jan 29 12:00 hello
```

### Run the compiled binary

```bash
./hello
```

**What's amazing:**
- ✅ No runtime needed (unlike Python/JavaScript)
- ✅ Native machine code (like C/Rust)
- ✅ Fast startup (~1ms vs ~50ms for Python)
- ✅ Single file deployment

---

## **Minute 28-30: Deploy & Share**

### Your program is production-ready!

```bash
# Copy it anywhere
cp hello ~/bin/hello

# Run it from anywhere
hello
```

### Share with others

```bash
# Send the binary to someone else
scp hello user@server:/usr/local/bin/

# They can run it immediately (no installation needed!)
```

**What makes this "production ready":**
- ✅ Compiled to native code
- ✅ No dependencies to install
- ✅ Cross-platform (Linux, macOS, Windows)
- ✅ Fast and lightweight

---

## **🎯 What You Accomplished in 30 Minutes**

1. ✅ Installed Janus
2. ✅ Wrote your first program
3. ✅ Learned variables (let/var)
4. ✅ Used control flow (if/else)
5. ✅ Implemented loops (while/for)
6. ✅ Compiled to native binary
7. ✅ Created a deployable program

**This is the power of Janus :core:**
- Teaching-simple syntax
- Production-grade compilation
- Native performance
- Zero runtime dependencies

---

## **Next Steps**

### Try these experiments:

1. **Modify the Fibonacci program** to calculate 20 numbers
2. **Add a new function** that prints a multiplication table
3. **Create a number guessing game** with user input
4. **Build a file reader** (see Tutorial 4: Zig Integration)

### Continue Learning:

- **Tutorial 2:** [Building Your First CLI Tool](./02-cli-tool.md)
- **Tutorial 3:** [Understanding Error Handling](./03-error-handling.md)
- **Tutorial 4:** [Working with Zig Integration](./04-zig-integration.md)

### Explore Examples:

- Check out [examples/showcase/](../../../examples/showcase/) for production-quality code
- Study the quicksort and binary tree implementations
- Read the [Language Specification](../../../specs/SPEC-018-profile-core.md)

---

## **Key Takeaways**

### **What Janus :core is Great For:**

✅ **Learning Programming** - Clean, readable syntax
✅ **Systems Programming** - Native compilation, no GC
✅ **CLI Tools** - Fast compilation, single binary
✅ **Algorithms** - Teaching-friendly, production-fast
✅ **Education** - Python-simple, Rust-powerful

### **The Janus Philosophy:**

> "Where teaching simplicity meets native performance."

You write code that **reads like Python**, but **runs like C**.

---

**Congratulations! You're now a Janus developer!** 🚀

*Next tutorial: Building Your First CLI Tool →*

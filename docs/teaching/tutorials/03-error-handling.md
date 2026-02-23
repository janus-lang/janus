<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Understanding Error Handling

**Learn how Janus handles failures gracefully and safely.**

**Time:** 40 minutes
**Level:** Beginner
**Prerequisites:** Tutorial 1 (Hello World to Production)
**What you'll learn:** Error handling patterns, recovery strategies, and safe resource management

---

## **Why Error Handling Matters**

Real programs fail. Files don't exist. Networks drop. Disk space runs out.

**What makes Janus different:**

✅ **Explicit Errors** - Functions declare what can fail
✅ **Forced Handling** - You can't ignore errors accidentally
✅ **Zero Overhead** - Error handling compiles to simple jumps
✅ **Clean Recovery** - `defer` ensures cleanup happens

**The Philosophy:**

> "Errors are not exceptional. They are data."

In Janus, errors are **values** you handle explicitly, not exceptions that magically unwind your stack.

---

## **Step 1: The Basics (10 min)**

### The Error Union Type: `!T`

When a function can fail, it returns an **error union**:

```janus
// This function can fail
func divide(a: i64, b: i64) !i64 do
    if b == 0 do
        fail DivisionByZero
    end
    return a / b
end

// This function always succeeds
func add(a: i64, b: i64) -> i64 do
    return a + b
end
```

**The `!` means:** "This might fail."

**The `fail` keyword:** Returns an error instead of a value.

### Handling Errors: `try` and `catch`

**Option 1: Propagate the error (pass it up)**
```janus
func calculate() !i64 do
    // If divide fails, calculate fails too
    let result = try divide(10, 0)
    return result
end
```

**Option 2: Handle the error (deal with it here)**
```janus
func safe_divide(a: i64, b: i64) -> i64 do
    let result = divide(a, b) catch |err| do
        println("Error: ", err)
        return 0  // Default value
    end
    return result
end
```

**Try it:**
```janus
// safe_divide.jan

func divide(a: i64, b: i64) !i64 do
    if b == 0 do
        fail DivisionByZero
    end
    return a / b
end

func main() do
    // This will catch the error
    let result = divide(10, 0) catch |err| do
        println("Caught error: ", err)
        println("Using default value: 0")
        0
    end

    print("Result: ")
    print_int(result)
    println("")
end
```

**Run it:**
```bash
janus run safe_divide.jan
```

**Output:**
```
Caught error: DivisionByZero
Using default value: 0
Result: 0
```

---

## **Step 2: Error Propagation (10 min)**

### Building a Chain of Fallible Functions

Real programs have **layers**. Errors bubble up.

```janus
// Layer 1: Low-level operation
func read_number(str: []const u8) !i64 do
    if str.len == 0 do
        fail EmptyString
    end
    // Simplified parsing (real version would use Zig stdlib)
    return 42  // Placeholder
end

// Layer 2: Business logic
func process_input(str: []const u8) !i64 do
    let num = try read_number(str)  // Propagate error
    if num < 0 do
        fail NegativeNumber
    end
    return num * 2
end

// Layer 3: Application entry point
func main() !void do
    let result = try process_input("")
    print_int(result)
    println("")
end
```

**What happens:**
1. `read_number("")` fails with `EmptyString`
2. `try` in `process_input` propagates it upward
3. `try` in `main` propagates it to the runtime
4. Program exits with error message

**The Power of `try`:**

Without `try`, you'd write:
```janus
let num = read_number(str) catch |err| do
    return err  // Manual propagation
end
```

With `try`, you write:
```janus
let num = try read_number(str)  // Automatic propagation
```

---

## **Step 3: Resource Cleanup with `defer` (10 min)**

### The Problem: Leaking Resources

```janus
// BAD: If read_file fails, we leak the file handle!
func process_file(path: []const u8) !void do
    let file = try open_file(path)
    let content = try read_file(file)  // If this fails, file never closes!
    close_file(file)
end
```

### The Solution: `defer`

**`defer` runs cleanup code when the function exits, no matter what.**

```janus
// GOOD: File always closes
func process_file(path: []const u8) !void do
    let file = try open_file(path)
    defer close_file(file)  // Runs when function exits

    let content = try read_file(file)  // If this fails, defer still runs!
    // ... process content
end
```

**Key Rule:** `defer` runs in **reverse order** (LIFO - Last In, First Out).

```janus
func demo_defer() do
    defer println("3. Cleanup outer")
    defer println("2. Cleanup middle")
    defer println("1. Cleanup inner")
    println("Doing work...")
end

// Output:
// Doing work...
// 1. Cleanup inner
// 2. Cleanup middle
// 3. Cleanup outer
```

### Real Example: File Processing

```janus
use zig "std/fs"

func count_lines(path: []const u8, allocator: Allocator) !i64 do
    // Open file
    let file = try zig.fs.cwd().openFile(path, .{})
    defer file.close()  // Always closes, even on error

    // Read contents
    let content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024)
    defer allocator.free(content)  // Always frees, even on error

    // Count lines
    var count = 0
    for i in 0..<content.len do
        if content[i] == '\n' do
            count = count + 1
        end
    end

    return count
end

func main() !void do
    let allocator = std.heap.page_allocator

    let lines = count_lines("test.txt", allocator) catch |err| do
        println("Error reading file: ", err)
        return
    end

    print("Line count: ")
    print_int(lines)
    println("")
end
```

---

## **Step 4: Custom Error Types (5 min)**

### Define Your Own Errors

```janus
// Define custom errors
error FileErrors do
    FileNotFound
    PermissionDenied
    FileTooLarge
end

error ParseErrors do
    InvalidFormat
    UnexpectedEOF
end

func open_config(path: []const u8) !Config do
    // Can fail with FileErrors
    let file = try open_file(path)
    defer file.close()

    // Can fail with ParseErrors
    let config = try parse_config(file)

    return config
end
```

**Error sets are merged automatically:**

If a function calls two functions with different error sets, Janus merges them:

```janus
func combined() !void do
    try function_a()  // Returns !void with ErrorSetA
    try function_b()  // Returns !void with ErrorSetB
    // combined() can fail with ErrorSetA OR ErrorSetB
end
```

---

## **Step 5: Practical Patterns (5 min)**

### Pattern 1: Provide Default Values

```janus
func get_config_value(key: []const u8) -> []const u8 do
    let value = read_config(key) catch |err| do
        return "default_value"  // Fallback
    end
    return value
end
```

### Pattern 2: Retry Logic

```janus
func fetch_with_retry(url: []const u8, max_attempts: i64) !Response do
    var attempt = 0
    while attempt < max_attempts do
        let response = fetch(url) catch |err| do
            attempt = attempt + 1
            if attempt >= max_attempts do
                return err  // Give up
            end
            continue  // Try again
        end
        return response  // Success!
    end
    fail MaxRetriesExceeded
end
```

### Pattern 3: Log and Continue

```janus
func process_batch(items: []Item) do
    for i in 0..<items.len do
        process_item(items[i]) catch |err| do
            println("Warning: Failed to process item ", i, ": ", err)
            // Continue with next item
        end
    end
end
```

---

## **🎯 What You Learned**

### **Error Handling:**
✅ `!T` declares functions that can fail
✅ `fail ErrorName` returns an error
✅ `try` propagates errors upward
✅ `catch |err| do...end` handles errors

### **Resource Management:**
✅ `defer` guarantees cleanup
✅ Cleanup runs in reverse order (LIFO)
✅ Works even when errors occur

### **Best Practices:**
✅ Handle errors at the right level
✅ Provide sensible defaults
✅ Clean up resources with `defer`
✅ Don't silence errors without good reason

---

## **Challenges & Extensions**

### **Easy:**
1. Write a function that reads a number from user input with error handling
2. Create a file validator that checks if a file exists and is readable
3. Implement a safe array indexing function (returns error if out of bounds)

### **Medium:**
4. Build a JSON parser that returns detailed error messages with line numbers
5. Create a retry mechanism with exponential backoff
6. Implement a transaction system (rollback on error)

### **Advanced:**
7. Design a custom error hierarchy for a web server (404, 500, etc.)
8. Build an error recovery system that logs failures and retries
9. Create a resource pool with automatic cleanup using `defer`

---

## **Next Tutorial**

Now that you understand error handling, learn how to leverage Zig's powerful standard library:

→ [Tutorial 4: Working with Zig Integration](./04-zig-integration.md)

---

**You now handle errors like a professional!** 🛡️

*Practice by adding error handling to your CLI tool from Tutorial 2*

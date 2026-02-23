<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Working with Zig Integration

**Unlock the full power of Zig's battle-tested standard library.**

**Time:** 50 minutes
**Level:** Intermediate
**Prerequisites:** Tutorials 1-3 (Hello World, CLI Tool, Error Handling)
**What you'll learn:** Native Zig integration, allocators, file I/O, data structures, and system interfaces

---

## **Why Zig Integration?**

Janus :core is a **teaching language**. It's simple, readable, and compiles to native code.

But for production work, you need:
- File system operations
- Network access
- Dynamic data structures
- System interfaces
- Battle-tested algorithms

**That's where Zig comes in.**

### **The Breakthrough: Zero-Cost Integration**

```janus
use zig "std/ArrayList"

var list = zig.ArrayList(i64).init(allocator)
```

**This is NOT:**
- Foreign Function Interface (FFI)
- C bindings
- External library calls

**This IS:**
- Native Zig code
- Compiled directly
- Zero overhead
- Type-safe

---

## **Step 1: Understanding `use zig` (10 min)**

### How It Works

```janus
// Import Zig's file system module
use zig "std/fs"

// Now you have access to zig.fs
let file = try zig.fs.cwd().openFile("test.txt", .{})
```

**What happens:**
1. Janus compiler finds Zig's `std/fs` module
2. Imports it **natively** (not as FFI)
3. Makes it available under `zig.fs`
4. Type-checks all calls at compile time

### Common Zig Modules

| Module | Purpose | Example |
|--------|---------|---------|
| `std/fs` | File system | Open, read, write files |
| `std/process` | Process control | Args, environment, exit |
| `std/ArrayList` | Dynamic arrays | Growable lists |
| `std/HashMap` | Hash tables | Key-value storage |
| `std/heap` | Memory allocators | Page allocator, arena |
| `std/fmt` | String formatting | Printf-style formatting |

---

## **Step 2: Memory Management (Allocators) (10 min)**

### The Allocator Pattern

In Janus + Zig, **memory is explicit**. No hidden allocations.

**The Rule:** Functions that allocate memory take an `Allocator` parameter.

```janus
use zig "std/ArrayList"

func create_list(allocator: Allocator) ![]i64 do
    var list = zig.ArrayList(i64).init(allocator)
    defer list.deinit()

    try list.append(1)
    try list.append(2)
    try list.append(3)

    return try list.toOwnedSlice()
end

func main() !void do
    let allocator = std.heap.page_allocator

    let numbers = try create_list(allocator)
    defer allocator.free(numbers)

    for i in 0..<numbers.len do
        print_int(numbers[i])
        print(" ")
    end
    println("")
end
```

**Key Concepts:**

1. **`Allocator`** - The type that manages memory
2. **`std.heap.page_allocator`** - General-purpose allocator
3. **`defer list.deinit()`** - Always clean up!
4. **`toOwnedSlice()`** - Transfer ownership from list to slice

### Common Allocators

```janus
// General-purpose (use for most things)
let allocator = std.heap.page_allocator

// Arena allocator (fast, batch-free everything at once)
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator)
defer arena.deinit()
let allocator = arena.allocator()

// Fixed buffer (no heap allocations)
var buffer: [1024]u8 = undefined
var fba = std.heap.FixedBufferAllocator.init(&buffer)
let allocator = fba.allocator()
```

---

## **Step 3: File System Operations (10 min)**

### Reading Files

```janus
use zig "std/fs"

func read_entire_file(path: []const u8, allocator: Allocator) ![]u8 do
    // Open file
    let file = try zig.fs.cwd().openFile(path, .{})
    defer file.close()

    // Read up to 10MB
    let content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024)

    return content
end

func main() !void do
    let allocator = std.heap.page_allocator

    let content = try read_entire_file("README.md", allocator)
    defer allocator.free(content)

    print("File size: ")
    print_int(content.len)
    println(" bytes")
end
```

### Writing Files

```janus
use zig "std/fs"

func write_log(message: []const u8) !void do
    // Create/open file (truncate if exists)
    let file = try zig.fs.cwd().createFile("app.log", .{})
    defer file.close()

    // Write message
    try file.writeAll(message)
end

func main() !void do
    try write_log("Application started\n")
    println("Log written!")
end
```

### Checking File Existence

```janus
use zig "std/fs"

func file_exists(path: []const u8) -> bool do
    zig.fs.cwd().access(path, .{}) catch do
        return false
    end
    return true
end

func main() do
    if file_exists("config.txt") do
        println("Config found!")
    else
        println("Config missing!")
    end
end
```

---

## **Step 4: Dynamic Data Structures (10 min)**

### ArrayList (Growable Arrays)

```janus
use zig "std/ArrayList"

func process_numbers(allocator: Allocator) !void do
    var numbers = zig.ArrayList(i64).init(allocator)
    defer numbers.deinit()

    // Add items
    try numbers.append(10)
    try numbers.append(20)
    try numbers.append(30)

    // Access items
    print("First: ")
    print_int(numbers.items[0])
    println("")

    print("Length: ")
    print_int(numbers.items.len)
    println("")

    // Iterate
    println("All numbers:")
    for i in 0..<numbers.items.len do
        print("  ")
        print_int(numbers.items[i])
        println("")
    end

    // Remove last
    let last = numbers.pop()
    print("Popped: ")
    print_int(last)
    println("")
end

func main() !void do
    let allocator = std.heap.page_allocator
    try process_numbers(allocator)
end
```

### HashMap (Key-Value Store)

```janus
use zig "std/HashMap"
use zig "std/AutoHashMap"

func count_words(text: []const u8, allocator: Allocator) !void do
    var counts = zig.AutoHashMap([]const u8, i64).init(allocator)
    defer counts.deinit()

    // Simplified word counting (split by spaces)
    var word_start = 0
    var i = 0

    while i < text.len do
        if text[i] == ' ' or text[i] == '\n' do
            if i > word_start do
                let word = text[word_start..i]
                let entry = try counts.getOrPut(word)
                if entry.found_existing do
                    entry.value_ptr.* = entry.value_ptr.* + 1
                else
                    entry.value_ptr.* = 1
                end
            end
            word_start = i + 1
        end
        i = i + 1
    end

    // Print results
    var iter = counts.iterator()
    while iter.next() do |kv| do
        print(kv.key_ptr.*)
        print(": ")
        print_int(kv.value_ptr.*)
        println("")
    end
end

func main() !void do
    let allocator = std.heap.page_allocator
    let text = "hello world hello janus world"
    try count_words(text, allocator)
end
```

---

## **Step 5: System Interfaces (10 min)**

### Command-Line Arguments

```janus
use zig "std/process"

func main() !void do
    let allocator = std.heap.page_allocator

    // Get arguments
    let args = try zig.process.argsAlloc(allocator)
    defer zig.process.argsFree(allocator, args)

    println("Program arguments:")
    for i in 0..<args.len do
        print("  [")
        print_int(i)
        print("] ")
        println(args[i])
    end
end
```

**Run it:**
```bash
janus build args.jan -o args
./args hello world 123
```

**Output:**
```
Program arguments:
  [0] ./args
  [1] hello
  [2] world
  [3] 123
```

### Environment Variables

```janus
use zig "std/process"

func get_env(key: []const u8, allocator: Allocator) ![]const u8 do
    let value = try zig.process.getEnvVarOwned(allocator, key)
    return value
end

func main() !void do
    let allocator = std.heap.page_allocator

    let home = get_env("HOME", allocator) catch |err| do
        println("HOME not set")
        return
    end
    defer allocator.free(home)

    print("Home directory: ")
    println(home)
end
```

### Exit Codes

```janus
use zig "std/process"

func main() !void do
    let success = check_preconditions()

    if not success do
        println("Error: Preconditions not met")
        zig.process.exit(1)  // Exit with error code
    end

    println("Success!")
    zig.process.exit(0)
end
```

---

## **🎯 What You Learned**

### **Zig Integration:**
✅ `use zig "module/path"` for native imports
✅ Zero-cost integration (not FFI)
✅ Type-safe Zig stdlib access
✅ Compile-time verification

### **Memory Management:**
✅ Explicit allocators (no hidden allocations)
✅ `std.heap.page_allocator` for general use
✅ `defer` for cleanup
✅ `toOwnedSlice()` for ownership transfer

### **File System:**
✅ `std/fs` for file operations
✅ `openFile()`, `createFile()`, `readToEndAlloc()`
✅ Always use `defer file.close()`

### **Data Structures:**
✅ `ArrayList` for dynamic arrays
✅ `HashMap`/`AutoHashMap` for key-value storage
✅ `defer .deinit()` for cleanup

### **System Interfaces:**
✅ `std/process` for args, env, exit codes
✅ `argsAlloc()` for command-line arguments
✅ `getEnvVarOwned()` for environment variables

---

## **Challenges & Extensions**

### **Easy:**
1. Write a program that reads a file and counts the number of lines
2. Create a simple key-value store that saves to a JSON file
3. Build a directory lister that prints all files in the current directory

### **Medium:**
4. Implement a text search tool (like `grep`) that finds patterns in files
5. Create a file backup tool that copies files to a backup directory
6. Build a CSV parser that reads tabular data into a HashMap

### **Advanced:**
7. Design a simple database (key-value store) with persistence
8. Implement a log rotation system (delete old logs when they get too large)
9. Create a file watcher that monitors changes and triggers actions
10. Build a concurrent file processor using Zig's threading primitives

---

## **Real-World Example: Configuration Manager**

```janus
use zig "std/fs"
use zig "std/HashMap"
use zig "std/AutoHashMap"

struct Config do
    settings: zig.AutoHashMap([]const u8, []const u8)
    allocator: Allocator
end

func Config.load(path: []const u8, allocator: Allocator) !Config do
    var settings = zig.AutoHashMap([]const u8, []const u8).init(allocator)

    // Read config file
    let file = try zig.fs.cwd().openFile(path, .{})
    defer file.close()

    let content = try file.readToEndAlloc(allocator, 1024 * 1024)
    defer allocator.free(content)

    // Parse simple key=value format
    var line_start = 0
    for i in 0..<content.len do
        if content[i] == '\n' do
            let line = content[line_start..i]
            if line.len > 0 do
                // Find '=' separator
                for j in 0..<line.len do
                    if line[j] == '=' do
                        let key = line[0..j]
                        let value = line[j+1..line.len]
                        try settings.put(key, value)
                        break
                    end
                end
            end
            line_start = i + 1
        end
    end

    return Config {
        .settings = settings,
        .allocator = allocator
    }
end

func Config.deinit(self: *Config) do
    self.settings.deinit()
end

func Config.get(self: *Config, key: []const u8) -> ?[]const u8 do
    return self.settings.get(key)
end

func main() !void do
    let allocator = std.heap.page_allocator

    var config = try Config.load("app.config", allocator)
    defer config.deinit()

    if config.get("debug") do |value| do
        print("Debug mode: ")
        println(value)
    end

    if config.get("port") do |value| do
        print("Port: ")
        println(value)
    end
end
```

---

## **Next Steps**

### **You're ready for production!**

You now know:
- How to write clean Janus code (Tutorial 1)
- How to build CLI tools (Tutorial 2)
- How to handle errors safely (Tutorial 3)
- How to leverage Zig's stdlib (Tutorial 4)

### **Continue Learning:**
- Explore the [Showcase Examples](../../examples/showcase/)
- Read the [Language Specification](../../specs/SPEC-018-profile-core.md)
- Study the [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- Join the community (coming soon!)

---

**Congratulations! You're now a Janus + Zig power user!** 🚀

*Build something amazing with your new superpowers!*

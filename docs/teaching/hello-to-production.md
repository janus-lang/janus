# From Hello World to Production: The Janus Journey

**Clean Teaching Syntax → Industrial Power Tools**

This document shows the progression from simple Janus programs to production-ready applications using native Zig integration.

---

## Level 1: Pure Janus — Learning Fundamentals

### Hello World (Day 1)

```janus
func main() do
    println("Hello, Monastery!")
end
```

**What you learned:**
- `func` declares a function
- `main()` is the entry point
- `println()` prints to stdout

### Variables and Arithmetic (Day 2)

```janus
func main() do
    let x = 42
    let y = 13
    let sum = x + y

    print(sum)  // 55
end
```

**What you learned:**
- `let` for immutable bindings
- Type inference (x is i32)
- Arithmetic operators

### Loops and Conditionals (Day 3)

```janus
func main() do
    for i in 0..10 do
        if i % 2 == 0 do
            print(i)
        end
    end
end
```

**What you learned:**
- `for` loops with ranges
- `if` conditionals
- Modulo operator

### Functions and Recursion (Day 4)

```janus
func factorial(n: i32) -> i32 do
    if n <= 1 do
        return 1
    end
    return n * factorial(n - 1)
end

func main() do
    let result = factorial(5)
    print(result)  // 120
end
```

**What you learned:**
- Function signatures with types
- Return values
- Recursion

**Status:** ✅ Pure Janus, zero dependencies, runs anywhere

---

## Level 2: Adding Zig Tools — Real Data Structures

### Dynamic Arrays with ArrayList (Week 2)

```janus
use zig "std/ArrayList"
use zig "std/heap"

func main() do
    // Get an allocator (explicit memory management)
    var allocator = zig.heap.page_allocator

    // Create a dynamic array
    var numbers = zig.ArrayList(i32).init(allocator)
    defer numbers.deinit()  // Cleanup at end of scope

    // Add elements
    numbers.append(10) catch |_| do end
    numbers.append(20) catch |_| do end
    numbers.append(30) catch |_| do end

    // Sum all elements
    var sum: i32 = 0
    for numbers.items |num| do
        sum = sum + num
    end

    print(sum)  // 60
end
```

**What you learned:**
- `use zig "path"` for native Zig integration
- Explicit allocators (memory management)
- `defer` for RAII-style cleanup
- Error handling with `catch`
- Production-grade ArrayList (battle-tested)

**Performance:** Zero FFI overhead, compiles to same code as pure Zig

### HashMaps for Key-Value Storage (Week 2)

```janus
use zig "std/AutoHashMap"
use zig "std/heap"

func main() do
    var allocator = zig.heap.page_allocator

    // Create a HashMap
    var scores = zig.AutoHashMap([]const u8, i32).init(allocator)
    defer scores.deinit()

    // Add entries
    scores.put("Alice", 95) catch |_| do end
    scores.put("Bob", 87) catch |_| do end
    scores.put("Charlie", 92) catch |_| do end

    // Lookup
    if scores.get("Alice") |score| do
        print(score)  // 95
    end
end
```

**What you learned:**
- HashMap for O(1) lookups
- Optional types (`|score|` pattern)
- String keys
- Production-grade hash table

---

## Level 3: Real-World Applications — File I/O

### Reading Files (Week 3)

```janus
use zig "std/fs"
use zig "std/heap"

func read_config() -> bool do
    var allocator = zig.heap.page_allocator

    // Open file
    var file = zig.fs.cwd().openFile("config.txt", .{}) catch |err| do
        println("Error: Could not open config.txt")
        return false
    end
    defer file.close()

    // Read entire file
    var content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| do
        println("Error: Could not read file")
        return false
    end
    defer allocator.free(content)

    // Process content
    println("Config loaded successfully:")
    println(content)

    return true
end

func main() do
    if not read_config() do
        println("Failed to load config")
    end
end
```

**What you learned:**
- File I/O with error handling
- Resource management (open → defer close)
- Memory allocation for dynamic content
- Real error propagation patterns

### Writing Files (Week 3)

```janus
use zig "std/fs"
use zig "std/heap"

func save_log(message: []const u8) -> bool do
    var allocator = zig.heap.page_allocator

    // Create or open file (append mode)
    var file = zig.fs.cwd().createFile("app.log", .{
        .read = true,
        .truncate = false,
    }) catch |err| do
        return false
    end
    defer file.close()

    // Seek to end (append)
    file.seekFromEnd(0) catch |err| do end

    // Write message
    file.writeAll(message) catch |err| do
        return false
    end

    file.writeAll("\n") catch |err| do end

    return true
end

func main() do
    save_log("Application started")
    save_log("Processing data...")
    save_log("Done")

    println("Logs written to app.log")
end
```

**What you learned:**
- File creation and writing
- Append mode (seek to end)
- Error handling for write operations
- Real logging patterns

---

## Level 4: Production Tools — CLI Application

### Command-Line File Finder (Week 4)

```janus
use zig "std/fs"
use zig "std/heap"
use zig "std/mem"
use zig "std/process"

func find_files(pattern: []const u8) -> i32 do
    var allocator = zig.heap.page_allocator
    var found: i32 = 0

    // Open current directory
    var dir = zig.fs.cwd().openIterableDir(".", .{}) catch |err| do
        println("Error: Could not open directory")
        return 0
    end
    defer dir.close()

    // Iterate through entries
    var iter = dir.iterate()
    while iter.next() catch null |entry| do
        // Check if filename contains pattern
        if zig.mem.indexOf(u8, entry.name, pattern) != null do
            println(entry.name)
            found = found + 1
        end
    end

    return found
end

func main() do
    var allocator = zig.heap.page_allocator

    // Get command-line arguments
    var args_iter = zig.process.args()
    defer args_iter.deinit()

    // Skip program name
    _ = args_iter.next()

    // Get search pattern
    var pattern = args_iter.next() orelse do
        println("Usage: jfind <pattern>")
        return
    end

    // Search for files
    println("Searching for files matching:", pattern)
    let count = find_files(pattern)

    println("Found", count, "files")
end
```

**What you learned:**
- Command-line argument parsing
- Directory iteration
- String searching
- Real CLI application structure
- Production patterns (error handling, resource cleanup)

**Build and deploy:**
```bash
janus build jfind.jan -o jfind
./jfind ".jan"
```

---

## Level 5: Advanced Applications — JSON Processing

### JSON Parser (Month 2)

```janus
use zig "std/fs"
use zig "std/json"
use zig "std/heap"

struct Config {
    name: []const u8,
    version: []const u8,
    port: i32,
    debug: bool,
}

func load_config() -> ?Config do
    var allocator = zig.heap.page_allocator

    // Read JSON file
    var file = zig.fs.cwd().openFile("config.json", .{}) catch |err| do
        return null
    end
    defer file.close()

    var content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| do
        return null
    end
    defer allocator.free(content)

    // Parse JSON
    var parsed = zig.json.parseFromSlice(Config, allocator, content, .{}) catch |err| do
        println("Error: Invalid JSON format")
        return null
    end
    defer parsed.deinit()

    return parsed.value
end

func main() do
    if load_config() |config| do
        println("Loaded config:")
        println("  Name:", config.name)
        println("  Version:", config.version)
        println("  Port:", config.port)
        println("  Debug:", config.debug)
    else
        println("Failed to load config.json")
    end
end
```

**What you learned:**
- JSON parsing (production-grade)
- Struct definitions
- Optional types (`?Config`)
- Real config file handling

**Example `config.json`:**
```json
{
  "name": "MyApp",
  "version": "1.0.0",
  "port": 8080,
  "debug": true
}
```

---

## Level 6: Network Applications — HTTP Server (Month 3)

### Simple HTTP Server

```janus
use zig "std/net"
use zig "std/heap"
use zig "std/mem"

func handle_request(client: anytype) do
    var allocator = zig.heap.page_allocator

    // Read HTTP request
    var buffer: [1024]u8 = undefined
    var read_bytes = client.read(&buffer) catch |err| do
        return
    end

    var request = buffer[0..read_bytes]

    // Simple response
    var response =
        \\HTTP/1.1 200 OK
        \\Content-Type: text/plain
        \\Content-Length: 13
        \\
        \\Hello, Janus!
    ;

    // Send response
    client.writeAll(response) catch |err| do end
end

func main() do
    var allocator = zig.heap.page_allocator

    println("Starting HTTP server on port 8080...")

    // Create TCP listener
    var address = zig.net.Address.parseIp("127.0.0.1", 8080) catch |err| do
        println("Error: Invalid address")
        return
    end

    var server = zig.net.StreamServer.init(.{})
    defer server.deinit()

    server.listen(address) catch |err| do
        println("Error: Could not bind to port 8080")
        return
    end

    println("Server listening on http://127.0.0.1:8080")

    // Accept connections
    while true do
        var client = server.accept() catch |err| do
            continue
        end
        defer client.stream.close()

        handle_request(client.stream)
    end
end
```

**What you learned:**
- TCP networking
- HTTP protocol basics
- Socket programming
- Production server patterns

**Test it:**
```bash
janus build server.jan -o server
./server

# In another terminal:
curl http://127.0.0.1:8080
# Output: Hello, Janus!
```

---

## The Progression Summary

| Level | Janus Syntax | Zig Tools | Learning Focus |
|-------|--------------|-----------|----------------|
| **1** | ✅ Pure | ❌ None | Fundamentals (variables, loops, functions) |
| **2** | ✅ Mostly | ⚠️ ArrayList, HashMap | Data structures, memory management |
| **3** | ✅ Yes | ✅ File I/O | Real-world I/O, error handling |
| **4** | ✅ Yes | ✅ CLI tools | Command-line apps, directory iteration |
| **5** | ✅ Yes | ✅ JSON | Structured data, parsing |
| **6** | ✅ Yes | ✅ Networking | Network programming, servers |

**Key Insight:** At every level, you're using **production-grade** Zig stdlib, but with **clean** Janus syntax.

---

## Why This Works

### 1. No "Toy" Implementations
Students never use fake ArrayList or HashMap. They use the **same implementations** that ship in production Zig applications.

### 2. Smooth Learning Curve
Start simple (pure Janus), add complexity gradually (Zig stdlib), end up with production code.

### 3. Zero Rewrites
Code written in Week 1 still works in Month 6. No need to "graduate" to a different language.

### 4. Deploy Anywhere
Compile to native binaries. No runtime dependencies (except libc). Ship it.

---

## Compare to Other Paths

### Traditional Approach (Python → C++)
1. **Month 1-3:** Learn Python (lists, dicts, file I/O)
2. **Month 4-6:** Realize Python is too slow
3. **Month 7-12:** Rewrite everything in C++
4. **Result:** Starting over from scratch

### Janus Approach
1. **Week 1-2:** Learn fundamentals in clean Janus syntax
2. **Week 3-4:** Add Zig tools for real applications
3. **Month 2+:** Build production systems
4. **Result:** No rewrites, just deeper understanding

---

## The Bottom Line

**Janus gives you:**
- ✅ Clean teaching syntax (Day 1)
- ✅ Production stdlib (Week 2)
- ✅ Native performance (Always)
- ✅ Real deployments (Week 4)

**You never outgrow Janus** — the same code that teaches fundamentals in Week 1 compiles to the same native binary as the production server in Month 6.

🜏 **The Monastery has power tools. Learn safely, build confidently, deploy proudly.**

---

**Next Steps:**
- [Why Zig Under The Hood Is Genius](why-zig-genius.md)
- [30 Days of Janus :core](30-days-of-core.md)
- [Quick Start Guide](core-profile-quickstart.md)

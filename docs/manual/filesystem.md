<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Standard Library: Filesystem Guide

## The Future of Programming: AI-First, Capability-Based Filesystem Operations

Welcome to the Janus filesystem library! This guide introduces you to modern filesystem programming concepts that represent the future of software development. Janus combines AI-first design with capability-based security and atomic operations to create a filesystem API that's safe, powerful, educational, and forward-thinking.

## 🎯 Why Traditional Filesystems Are Broken

Traditional filesystem APIs suffer from fundamental problems that make them unsafe and complex:

### The Security Nightmare
```c
// C/C++ - Race condition prone
FILE* file = fopen("config.txt", "r");
if (file) {
    // What if file is deleted here by another process?
    char buffer[1024];
    fread(buffer, 1, sizeof(buffer), file);
    fclose(file);
}
```

### The Complexity Trap
```python
# Python - Manual resource management
try:
    with open('data.txt', 'r') as f:
        data = f.read()
    # File automatically closed... sometimes
except IOError as e:
    # Handle errors... hopefully
    pass
```

### The Reliability Gap
```javascript
// Node.js - Fire and forget
fs.writeFile('important.dat', data, (err) => {
    if (err) {
        // Data might be corrupted
        console.error('Write failed!');
    }
});
```

## 🛡️ Janus: The Solution

Janus changes everything with modern programming principles:

### 🔐 **Capability Security**: No More TOCTOU Attacks
```zig
// Janus - Explicit permissions required
var cap = Capability.FileSystem.init("my-app", allocator);
defer cap.deinit();
try cap.allow_path("/safe/config");

// This is guaranteed safe
const content = try fs.read_with_capability("/safe/config/app.json", cap, allocator);
```

### ⚡ **Atomic Operations**: Never Lose Data Again
```zig
// Janus - Crash-safe writes
const result = try fs.atomicWrite("/database/users.db", userData, .{
    .paranoid_mode = true,  // Maximum durability
}, allocator);

// Either old file exists OR complete new file exists
// NEVER partial or corrupted data
```

### 🤖 **AI-First Design**: Code Documents Itself
```zig
// Janus - Self-documenting with UTCP manuals
const result = try fs.walk_min("/project/src", myCallback, allocator);
// Hover over any Janus function to see comprehensive docs
// AI tools can understand and manipulate Janus code automatically
```

### 📈 **Progressive Disclosure**: Learn From Simple to Advanced
```zig
// Level 1: Just works
const data = try fs.read("file.txt", allocator);

// Level 2: Add context awareness
var ctx = Context.init(allocator);
const data = try fs.read_with_context("file.txt", ctx, allocator);

// Level 3: Full security and auditing
var cap = Capability.FileSystem.init("secure-app", allocator);
const data = try fs.read_with_capability("file.txt", cap, allocator);
```

## 🏗️ The Tri-Signature Pattern

Janus introduces the **tri-signature pattern** - the same function name with rising capability across profiles:

### :core Profile - Simple & Safe
```zig
// Basic file reading - just works
const content = try fs.read("/my/file.txt", allocator);
defer allocator.free(content);
```

### :service Profile - Context-Aware
```zig
// With cancellation and timeouts
var ctx = Context.init(allocator);
defer ctx.deinit();

const content = try fs.read_with_context("/my/file.txt", ctx, allocator);
```

### :sovereign Profile - Capability-Gated
```zig
// With security and audit trails
var cap = Capability.FileSystem.init("my-app", allocator);
defer cap.deinit();
try cap.allow_path("/safe/data");

const content = try fs.read_with_capability("/safe/data/file.txt", cap, allocator);
```

## 🔒 Data Integrity Above All

### Atomic Write Operations

Janus ensures **data integrity** with atomic operations:

```zig
// Crash-safe database updates
const result = try fs.atomicWrite("/database/users.db", userData, .{
    .paranoid_mode = true,  // Maximum durability
}, allocator);
defer result.deinit(allocator);

if (result.success) {
    std.debug.print("Data saved atomically: {} bytes\n", .{result.bytes_written});
}
```

### Durability Guarantees

**Before a crash**: Either old file exists or no file exists
**During a crash**: Temporary files are ignored
**After a crash**: Either old file or complete new file exists
**Never**: Partial or corrupted data

## 🚀 Modern Features for Future Programming

### Streaming for Large Files
```zig
// Handle huge files efficiently
var streamer = try fs.StreamingReader.init("/big/file.dat", 64*1024, allocator);
defer streamer.deinit();

while (try streamer.readChunk(progressCallback)) |chunk| {
    defer allocator.free(chunk);
    // Process chunk...
}
```

### File Watching (Hot Reload Ready)
```zig
// Monitor files for changes
var watcher = fs.FileWatcher.init(allocator);
defer watcher.deinit();

try watcher.watchFile("/config/app.json");

// Check for changes
const changed_files = try watcher.checkChanges();
for (changed_files) |path| {
    std.debug.print("File changed: {s}\n", .{path});
    // Trigger hot reload...
}
```

### Async Operations (Future-Proofed)
```zig
// Ready for when Zig gets better async I/O
// fs.AsyncFileOps.readAsync("/file.txt", allocator, myCallback);
```

## 📚 Learning the Future of Programming

### Progressive Learning Path

**Level 1: Basic Operations**
```zig
// Start simple
const data = try fs.read("hello.txt", allocator);
try fs.write("output.txt", "Hello World!", allocator);
```

**Level 2: Context Awareness**
```zig
// Add timeouts and cancellation
var ctx = Context.init(allocator);
defer ctx.deinit();
ctx.setDeadline(std.time.ms_per_s * 5); // 5 second timeout

const data = try fs.read_with_context("slow/file.txt", ctx, allocator);
```

**Level 3: Security First**
```zig
// Capability-based security
var cap = Capability.FileSystem.init("student-app", allocator);
defer cap.deinit();

// Only allow access to assignment directory
try cap.allow_path("/assignments/week3");

// Audit all operations
const data = try fs.read_with_capability("/assignments/week3/data.txt", cap, allocator);
```

### Understanding Capability Security

Capabilities are like **keys to specific resources**:

```zig
// Create a capability for file operations
var fileCap = Capability.FileSystem.init("my-program", allocator);
defer fileCap.deinit();

// Grant specific permissions
try fileCap.allow_path("/home/user/documents");
try fileCap.allow_write();  // Can create/modify files

// This works
const content = try fs.read_with_capability("/home/user/documents/notes.txt", fileCap, allocator);

// This fails - no permission
// const secret = try fs.read_with_capability("/etc/passwd", fileCap, allocator);
```

## 🎓 Educational Concepts

### Why Janus Represents the Future

1. **AI-First Design**: Code documents itself with UTCP manuals
2. **Memory Safety**: No null pointer dereferences, no buffer overflows
3. **Capability Security**: Fine-grained access control prevents exploits
4. **Atomic Operations**: Data integrity guarantees
5. **Progressive Disclosure**: Learn from simple to advanced
6. **Future-Proofed**: Ready for async, distributed computing

### Real-World Applications

**Database Systems**:
```zig
// Atomic database updates
const result = try fs.atomicWrite("/db/transactions.log", logData, .{
    .paranoid_mode = true,  // Never lose transaction data
}, allocator);
```

**Configuration Management**:
```zig
// Safe config updates
var configCap = Capability.FileSystem.init("config-manager", allocator);
try configCap.allow_path("/etc/myapp");

const result = try fs.atomicWrite("/etc/myapp/config.json", newConfig, .{
    .paranoid_mode = true,
}, configCap, allocator);
```

**File Processing Pipelines**:
```zig
// Stream processing with progress
var streamer = try fs.StreamingReader.init("/large/dataset.csv", 1*1024*1024, allocator);
defer streamer.deinit();

var processed: usize = 0;
while (try streamer.readChunk(struct {
    fn callback(bytes: u64) void {
        processed += bytes;
        std.debug.print("Processed: {} MB\n", .{processed / (1024*1024)});
    }
}.callback)) |chunk| {
    defer allocator.free(chunk);
    // Process chunk...
}
```

## 🔧 Performance Characteristics

| Operation | NVMe SSD | SATA SSD | HDD | Network |
|-----------|----------|----------|-----|---------|
| Simple read | ~50μs | ~200μs | ~5ms | ~50ms |
| Atomic write (normal) | ~100μs | ~500μs | ~15ms | ~200ms |
| Atomic write (paranoid) | ~200μs | ~1ms | ~30ms | ~1s+ |

**Key Insights**:
- Paranoid mode adds safety, not orders of magnitude slowdown
- Network storage needs careful consideration
- Modern SSDs make safety affordable

## 🚦 Best Practices

### For Students
1. **Start with :core profile** - learn basics first
2. **Add context awareness** - prevent hanging operations
3. **Use capabilities** - write secure code from day one
4. **Always handle errors** - no silent failures
5. **Test atomic operations** - verify durability guarantees

### For Educators
1. **Teach progressive disclosure** - from simple to complex
2. **Emphasize security** - capabilities prevent real exploits
3. **Demonstrate atomicity** - crash-safe operations
4. **Show AI integration** - UTCP manuals for tooling
5. **Encourage experimentation** - safe to explore

## 📖 Module-by-Module Guide

### 🛤️ **std/path.zig**: Cross-Platform Path Manipulation

The foundation of safe filesystem operations:

```zig
// Path operations work on all platforms
const path = Path.init("/usr/local/bin/zig");
const parent = path.parent().?;        // "/usr/local/bin"
const file_name = path.fileName().?;   // "zig"
const extension = path.extension();    // null (no extension)

// Cross-platform path building
var buf = try PathBuf.fromSlice("/tmp", allocator);
defer buf.deinit();
try buf.push("my-app");
try buf.push("data.txt");
// Result: "/tmp/my-app/data.txt" (Unix) or "C:\tmp\my-app\data.txt" (Windows)
```

**Teaching Moment**: Paths are not strings! They have structure and platform-specific rules.

### 📁 **std/fs.zig**: Core File Operations

The heart of filesystem programming with tri-signature safety:

```zig
// :core profile - Simple and safe
const content = try fs.read("config.json", allocator);
defer allocator.free(content);

// :service profile - Context-aware
var ctx = Context.init(allocator);
defer ctx.deinit();
const content = try fs.read_with_context("config.json", ctx, allocator);

// :sovereign profile - Capability-secured
var cap = Capability.FileSystem.init("my-app", allocator);
defer cap.deinit();
try cap.allow_path("/etc/myapp");
const content = try fs.read_with_capability("/etc/myapp/config.json", cap, allocator);
```

### ⚡ **std/fs_atomic.zig**: Crash-Safe Data Integrity

Never lose data again:

```zig
// Atomic rename with cross-device support
const result = try fs.atomicRename("/old.db", "/new.db", allocator);
if (result.success) {
    std.debug.print("Database migrated safely\n", .{});
}

// Atomic write with durability guarantees
const result = try fs.atomicWrite("/critical/data.bin", importantData, .{
    .paranoid_mode = true,  // Extra fsync operations
}, allocator);
```

**Teaching Moment**: Atomic operations prevent data corruption during crashes.

### ✍️ **std/fs_write.zig**: RAII Writing with Content Integrity

Write safely with automatic cleanup and CID verification:

```zig
// RAII file writer - automatically cleans up
var writer = try fs.FileWriter.init("/output.txt", .{
    .compute_cid = true,
}, allocator);
defer writer.deinit(); // Always called

try writer.write("Important data");
const result = try writer.finish();

// result.cid contains BLAKE3 hash for integrity verification
```

### 🗂️ **std/fs_temp.zig**: Secure Temporary Files

Collision-resistant temporary file creation:

```zig
// Secure temp file with automatic cleanup
var temp = try fs.createTempFile(.{
    .prefix = "myapp_",
    .suffix = ".tmp",
}, allocator);
defer temp.deinit(); // File automatically deleted

try temp.write("temporary data");
try temp.persist("/permanent/location.txt"); // Make it permanent
```

### 🚶 **std/fs_walker.zig**: Advanced Directory Traversal

Powerful recursive directory walking with security:

```zig
// Walk with pruning and progress
var walker = try fs.Walker.init("/project/src", .{
    .max_depth = 3,
    .prune_fn = myPruneFunction,
    .progress_callback = myProgressCallback,
}, allocator);
defer walker.deinit();

try walker.walk(struct {
    pub fn process(entry: fs.WalkEntry) fs.WalkAction {
        if (entry.isFile() and entry.extension() == ".zig") {
            std.debug.print("Found Zig file: {s}\n", .{entry.path});
        }
        return .continue_traversal;
    }
}.process);
```

### 💾 **std/memory_fs.zig**: Deterministic Testing

In-memory filesystem for reliable testing:

```zig
// Perfect for testing - deterministic and fast
var memfs = try fs.MemoryFS.init(allocator);
defer memfs.deinit();

try memfs.createFile("/test.txt", "test data");
const content = try memfs.readFile("/test.txt");
// Always returns "test data" - no disk I/O variability
```

## 🎓 Advanced Concepts for Students

### Understanding the Tri-Signature Pattern

The tri-signature pattern teaches **progressive enhancement**:

1. **:core Profile**: "Just work" - Simple, safe defaults
2. **:service Profile**: "Be aware" - Add context, timeouts, cancellation
3. **:sovereign Profile**: "Be secure" - Full capabilities, auditing, verification

This pattern mirrors how real systems should be designed: start simple, add complexity as needed.

### Capability-Based Security in Action

```zig
// Create a "jail" for untrusted code
var sandbox = Capability.FileSystem.init("sandbox", allocator);
defer sandbox.deinit();

// Only allow access to specific directories
try sandbox.allow_path("/tmp/sandbox/input");
try sandbox.allow_path("/tmp/sandbox/output");
try sandbox.allow_write(); // But only to allowed paths

// Untrusted code can only touch allowed files
runUntrustedCode(sandbox);
```

**Teaching Moment**: Capabilities prevent supply chain attacks and sandbox escapes.

### Atomic Operations and ACID Properties

Janus atomic operations provide **ACID guarantees**:

- **Atomicity**: All-or-nothing operations
- **Consistency**: System remains in valid state
- **Isolation**: Operations don't interfere
- **Durability**: Changes survive crashes

```zig
// Database transaction with atomic file operations
const result = try fs.atomicWrite("/db/transactions.log", newTransaction, .{
    .paranoid_mode = true,  // Durability
}, allocator);

// Either transaction is fully logged or not at all
```

## 🔬 Research and Future Directions

### AI Integration

Janus is designed for AI tooling:

```zig
// AI can read UTCP manuals automatically
const manual = fs.utcpManual();
// AI understands the API without human documentation
```

### Distributed Filesystems

CID-based content addressing enables distributed systems:

```zig
// Same content, same CID across all machines
const cid1 = ContentId.fromData(data);
const cid2 = ContentId.fromFile("/distributed/file", allocator);
// cid1 == cid2 - content-based addressing
```

### Formal Verification

Janus operations are designed to be formally verifiable:

```zig
// Pre/post conditions can be proven
// @requires valid_path(path)
// @ensures file_exists(path) || error_returned
const result = try fs.atomicWrite(path, data, options, allocator);
```

## 📚 Educational Resources

### For University Courses

**Course: Modern Systems Programming**
- Week 1: Path manipulation and cross-platform concerns
- Week 2: Basic file I/O with error handling
- Week 3: Atomic operations and data integrity
- Week 4: Capability-based security
- Week 5: Advanced patterns (streaming, walking, compression)

**Course: Secure Software Engineering**
- Unit 1: TOCTOU attacks and capability solutions
- Unit 2: Race conditions and atomic operations
- Unit 3: Memory safety and RAII patterns
- Unit 4: Progressive disclosure in API design

### Student Projects

1. **Build a Safe Configuration Manager**
   - Use atomic writes for config updates
   - Implement capability-based access control
   - Add CID verification for integrity

2. **Create a File Backup System**
   - Use directory walking for source discovery
   - Implement streaming for large files
   - Add progress callbacks and cancellation

3. **Design a Sandboxed Code Runner**
   - Use temporary directories for isolation
   - Implement capability restrictions
   - Add file watching for hot reload

## 🌟 Why This Matters for the Future

### The Coming AI Revolution

As AI becomes central to programming:

1. **Self-Documenting Code**: Janus UTCP manuals allow AI to understand and manipulate code
2. **Safety by Default**: AI-generated code will be safer with capability controls
3. **Reliable Operations**: AI can reason about atomic operations and crash safety
4. **Progressive Enhancement**: AI can start simple and add complexity as needed

### The Security Imperative

With increasing cyber threats:

1. **Capability Security**: Prevents exploits before they happen
2. **Atomic Operations**: Guarantees data integrity under attack
3. **Memory Safety**: Eliminates entire classes of vulnerabilities
4. **Audit Trails**: Provides forensic evidence of breaches

### The Reliability Requirement

As systems grow more complex:

1. **Crash Safety**: Systems stay running through failures
2. **Deterministic Testing**: Reliable testing with MemoryFS
3. **Progressive Disclosure**: APIs that grow with user needs
4. **Future-Proofing**: Ready for async, distributed, and quantum computing

## 🎯 Conclusion

The Janus filesystem library isn't just a better way to handle files—it's a **blueprint for the future of programming**. It demonstrates how modern software should be designed:

- **AI-first**: Code that documents and explains itself
- **Security-first**: Capabilities prevent exploits by default
- **Reliability-first**: Atomic operations ensure data integrity
- **Education-first**: Progressive disclosure teaches best practices

Welcome to the future of programming. The Janus filesystem library shows what's possible when we design software with **people, safety, and reliability** in mind.

---

*Ready to start coding? Check out `/examples/` for working code samples, and explore the UTCP manuals in each module for comprehensive API documentation.*

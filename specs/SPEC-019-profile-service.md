<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# SPEC-019: :service Profile — The Bazaar Workhorse

**Version:** 2026.2.0

## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).

**Status:** COMPLETE (v2026.1.7) — Implementation 85%
**Authority:** Constitutional
**Supersedes:** Portions of SPEC-002, SPEC-003

This specification defines the **:service Profile**, enabling structured concurrency, asynchronous programming, and resource-safe service development.

---

## Document History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-07 | 2026.1.7 | Initial complete specification |
| 2026-02-06 | 2026.2.0 | Added implementation status, nursery state machine refs, examples |

---

## 0. Implementation Status

**Last Updated:** 2026-02-06

### Completed ✅

| Component | Status | Location |
|-----------|--------|----------|
| Nursery Runtime | ✅ 47/47 tests passing | `runtime/scheduler/nursery.zig` |
| Nursery State Machine | ✅ Fully implemented | `specs/SPEC-021-scheduler-nursery-state-machine.md` |
| Using Statement Parser | ✅ Parses all variants | `janus_parser` |
| Async/Await E2E Tests | ✅ Compiling to LLVM IR | `tests/integration/async_await_e2e_test.zig` |
| Service Profile E2E | ✅ CSP system validated | `tests/integration/service_profile_full_test.zig` |
| Example Programs | ✅ 4 comprehensive examples | `examples/service/*.jan` |

### In Progress 🔄

| Component | Status | Blockers |
|-----------|--------|----------|
| Using Statement Semantic Resolver | 🔄 80% complete | Build integration pending |
| HTTP Server Std Library | 🔄 Mock implementations | Needs Zig std/http bindings |
| Async Lowering to QTJIR | 🔄 Basic opcodes done | Needs state machine generation |

---

## 1. Overview

**:service Profile** is the "Go-like async, but technically better" profile for building web services, APIs, and concurrent applications.

**Key Features:**
- Async/await structured concurrency
- Nursery-based task management (no task leaks)
- Resource-safe `using` statement (guaranteed cleanup)
- Native HTTP stack (via Zig integration)
- Goroutine-style green threads

**Market Position:** "Go's simplicity + Rust's safety + Native speed"

---

## 2. Profile Declaration

```janus
{.profile: service.}

// This module requires :service profile features
```

Files without a profile declaration inherit the project-wide profile setting.

---

## 3. Syntax Extensions

### 3.1 Async Functions

**Syntax:**
```
async_func_decl := 'async' 'func' IDENT '(' params ')' return_type? block
```

**Example:**
```janus
async func fetch_data(url: []const u8) !Data do
    use zig "std/http"
    return try zig.http.Client.fetch(url)
end
```

**Semantics:**
- `async func` declares a function that may suspend execution
- Calling an async function requires `await` or spawning in a nursery
- Async functions propagate errors via `!T` error unions

### 3.2 Await Expressions

**Syntax:**
```
await_expr := 'await' expr
```

**Example:**
```janus
let data = await fetch_data("https://api.example.com")
```

**Semantics:**
- `await` suspends current function until the async operation completes
- Can only be used inside `async func` or `main` (special case)
- Returns the value or propagates error from awaited expression

### 3.3 Nursery Blocks

**Syntax:**
```
nursery_stmt := 'nursery' block
```

**Example:**
```janus
nursery do
    spawn task1()
    spawn task2()
    spawn task3()
end  // Waits for all tasks to complete
```

**Semantics:**
- `nursery` creates a structured concurrency scope
- All spawned tasks MUST complete before nursery exits
- If any task fails, all sibling tasks are cancelled
- Ensures no "orphaned" tasks (structured concurrency)

### 3.4 Spawn Expressions

**Syntax:**
```
spawn_expr := 'spawn' expr
```

**Example:**
```janus
nursery do
    spawn fetch_users()
    spawn fetch_posts()
end
```

**Semantics:**
- `spawn` launches an async task within current nursery
- Can only be used inside `nursery` blocks
- Task result is awaited automatically at nursery exit
- Errors propagate to nursery scope

### 3.5 Using Statement (Resource Management)

**Syntax:**
```
using_stmt := 'using' ['shared'] IDENT ':=' expr block
```

**Example:**
```janus
using file := try zig.fs.cwd().openFile("data.txt", .{}) do
    let content = try file.readToEndAlloc(allocator, 1024*1024)
    defer allocator.free(content)

    // Process content
    println(content)
end  // file.close() called automatically
```

**Semantics:**
- `using` declares a resource with automatic cleanup
- Resource MUST have a `close()` or `deinit()` method
- Cleanup runs in LIFO order (last acquired, first released)
- Cleanup executes even on error or early return
- See `.agent/specs/_FUTURE/09-using-statement-concurrency/` for full design

### 3.6 Cancellation Tokens (Cooperative Cancellation)

**Syntax:**
```
cancel_token_decl := 'let' IDENT ':' 'CancelToken' '=' 'CancelToken.new()'
cancel_check     := 'if' IDENT '.is_cancelled()' block
cancel_trigger   := IDENT '.cancel()'
```

**Example:**
```janus
func main() do
    let token = CancelToken.new()

    nursery do
        spawn worker(token)
        spawn timeout_canceller(token, 5000)  // Cancel after 5s
    end
end

async func worker(token: CancelToken) do
    while !token.is_cancelled() do
        // Do work
        let result = await fetch_next_item()
        process(result)

        // Cooperative yield point
        token.check()  // Throws CancellationError if cancelled
    end
end

async func timeout_canceller(token: CancelToken, ms: i64) do
    await sleep(ms)
    token.cancel()  // Signal cancellation to all holders
end
```

**Semantics:**
- `CancelToken` is a thread-safe signaling primitive
- `token.cancel()` sets the cancellation flag (atomic)
- `token.is_cancelled()` checks the flag without throwing
- `token.check()` throws `CancellationError` if cancelled
- Cancellation is **cooperative** — tasks must check the token
- Nursery cancellation automatically cancels child tokens

**Propagation Rules:**
1. When a nursery is cancelled, all spawned tasks receive cancellation
2. Child nurseries inherit parent's cancellation token
3. Explicit tokens can override inherited cancellation

**Example (Nursery Integration):**
```janus
nursery |n| do
    // n.token is the nursery's cancellation token
    spawn task_a(n.token)
    spawn task_b(n.token)

    // If task_a fails, n.token.cancel() is called automatically
    // task_b will see cancellation on next check
end
```

**Example (Linked Tokens):**
```janus
func fetch_with_timeout(url: String, timeout_ms: i64) !Data do
    let token = CancelToken.new()

    nursery do
        spawn async do
            await sleep(timeout_ms)
            token.cancel()
        end

        spawn async do
            return await fetch_data(url, token)
        end
    end
end
```

**CancelToken API:**
```janus
struct CancelToken {
    /// Create a new cancellation token
    func new() -> CancelToken

    /// Create a child token linked to parent
    func child(parent: CancelToken) -> CancelToken

    /// Check if cancellation has been requested
    func is_cancelled(self) -> bool

    /// Check and throw CancellationError if cancelled
    func check(self) !void

    /// Request cancellation (idempotent, thread-safe)
    func cancel(self) -> void

    /// Register a callback for cancellation notification
    func on_cancel(self, callback: fn() -> void) -> void
}
```

**Error Type:**
```janus
error CancellationError {
    Cancelled,      // Normal cancellation
    Timeout,        // Timeout-triggered cancellation
    ParentCancelled // Parent nursery was cancelled
}
```

---

## 4. Semantic Rules

### 4.1 Async Propagation

**Rule:** Async functions can only be called from:
1. Other async functions (via `await`)
2. Nursery blocks (via `spawn`)
3. Top-level `main()` (special case, runtime handles)

**Example (VALID):**
```janus
async func fetch_user(id: i64) !User do
    return await fetch_from_db(id)  // OK: async calling async
end

func process_users() !void do
    nursery do
        spawn fetch_user(1)  // OK: spawn in nursery
        spawn fetch_user(2)
    end
end
```

**Example (INVALID):**
```janus
func sync_function() !void do
    let user = await fetch_user(1)  // ERROR: await in non-async function
end
```

### 4.2 Nursery Scoping

**Rule:** `spawn` can only be used inside `nursery` blocks.

**Example (INVALID):**
```janus
func main() !void do
    spawn task()  // ERROR: spawn outside nursery
end
```

**Example (VALID):**
```janus
func main() !void do
    nursery do
        spawn task()  // OK: spawn inside nursery
    end
end
```

### 4.3 Resource Cleanup Order

**Rule:** Resources cleanup in LIFO order (reverse of acquisition).

**Example:**
```janus
using r1 := open_resource("first") do
    using r2 := open_resource("second") do
        using r3 := open_resource("third") do
            // Use resources
        end  // r3.close()
    end  // r2.close()
end  // r1.close()
```

---

## 5. Desugaring (Implementation Strategy)

### 5.1 Async Functions

**Janus:**
```janus
async func fetch_data(url: []const u8) !Data do
    return try fetch_impl(url)
end
```

**Lowers to Zig:**
```zig
fn fetch_data(url: []const u8) callconv(.Async) !Data {
    return try fetch_impl(url);
}
```

### 5.2 Await

**Janus:**
```janus
let data = await fetch_data("https://example.com")
```

**Lowers to Zig:**
```zig
const data = await fetch_data("https://example.com");
```

### 5.3 Nursery + Spawn

**Janus:**
```janus
nursery do
    spawn task1()
    spawn task2()
end
```

**Lowers to Zig:**
```zig
{
    var frame1 = async task1();
    var frame2 = async task2();

    _ = await frame1;
    _ = await frame2;
}
```

(More sophisticated implementation uses event loop and task registry)

### 5.4 Using Statement

**Janus:**
```janus
using file := try open_file("data.txt") do
    process(file)
end
```

**Lowers to:**
```janus
let file = try open_file("data.txt")
defer file.close()
process(file)
```

---

## 6. Runtime Support

### 6.1 Async Runtime (Phase 1: Use Zig Native)

**Strategy:** Leverage Zig's `std.event` for initial implementation.

```janus
use zig "std/event"

// Runtime provided by Zig
let loop = zig.event.Loop.init(allocator)
defer loop.deinit()
```

**Future (Phase 2: Dogfood in :sovereign):**
- Replace with Janus-native Fibers
- Replace with Janus-native Channels
- Custom scheduler with work-stealing

### 6.2 Resource Registry

**Implementation:** Track all `using` resources for LIFO cleanup.

```zig
// runtime/janus_rt.zig
const ResourceRegistry = struct {
    resources: std.ArrayList(Resource),
    allocator: std.mem.Allocator,

    const Resource = struct {
        cleanup_fn: *const fn() void,
        acquisition_site: SourceLocation,
    };

    pub fn register(self: *Self, cleanup_fn: *const fn() void) !void {
        try self.resources.append(.{
            .cleanup_fn = cleanup_fn,
            .acquisition_site = @src(),
        });
    }

    pub fn cleanup(self: *Self) void {
        // LIFO order
        while (self.resources.popOrNull()) |resource| {
            resource.cleanup_fn();
        }
    }
};
```

---

## 7. Profile Constraints

### 7.1 Features Available

| Feature | :core | :service | :cluster | :sovereign |
|---------|-------|----------|----------|------------|
| Async/Await | ❌ | ✅ | ✅ | ✅ |
| Nurseries | ❌ | ✅ | ✅ | ✅ |
| Spawn | ❌ | ✅ | ✅ | ✅ |
| Using | ❌ | ✅ | ✅ | ✅ |
| Actors | ❌ | ❌ | ✅ | ✅ |
| Raw Pointers | ❌ | ❌ | ❌ | ✅ |

### 7.2 Features Forbidden

**In :service profile, the following are NOT allowed:**
- Actors (use :cluster for distributed systems)
- Raw pointer arithmetic (use :sovereign)
- Unsafe blocks (use :sovereign)
- Global mutable state (use dependency injection)

---

## 8. Examples

### 8.1 Simple HTTP Server

```janus
use zig "std/http"
use zig "std/net"

async func handle_request(req: Request) !Response do
    if req.path == "/hello" do
        return Response.ok("Hello, World!")
    end

    if req.path == "/users" do
        let users = await fetch_users_from_db()
        return Response.json(users)
    end

    return Response.notFound()
end

func main() !void do
    let allocator = std.heap.page_allocator

    using server := try zig.http.Server.init(allocator, .{
        .address = "127.0.0.1",
        .port = 8080,
    }) do
        println("Server listening on http://127.0.0.1:8080")

        nursery do
            while true do
                let conn = await server.accept()
                spawn handle_connection(conn)
            end
        end
    end
end
```

### 8.2 Concurrent Data Fetching

```janus
async func fetch_user(id: i64) !User do
    use zig "std/http"
    let url = format("https://api.example.com/users/{}", id)
    return await zig.http.Client.fetch(url)
end

func fetch_all_users(ids: []i64) ![]User do
    var results = try std.ArrayList(User).init(allocator)
    defer results.deinit()

    nursery do
        for i in 0..<ids.len do
            spawn fetch_user(ids[i])
        end
    end

    return try results.toOwnedSlice()
end
```

### 8.3 Resource Management

```janus
use zig "std/fs"

func process_files(paths: [][]const u8, allocator: Allocator) !void do
    for i in 0..<paths.len do
        using file := try zig.fs.cwd().openFile(paths[i], .{}) do
            let content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024)
            defer allocator.free(content)

            // Process content
            let lines = count_lines(content)
            println("File: ", paths[i], " has ", lines, " lines")
        end  // file.close() automatic
    end
end
```

---

## 9. Implementation Phases

### Phase 1: Async/Await (Weeks 1-2)
- Parser: Add `async` and `await` keywords
- Semantic: Track async function types
- QTJIR: Desugar to Zig's async functions
- Tests: Basic async/await integration tests

### Phase 2: Nursery/Spawn (Weeks 3-4)
- Parser: Add `nursery` and `spawn` keywords
- Semantic: Validate nursery scoping
- QTJIR: Desugar to Zig's event loop
- Tests: Structured concurrency tests

### Phase 3: Using Statement (Weeks 5-6)
- Parser: Add `using` statement
- Semantic: Resource lifetime analysis
- QTJIR: Desugar to defer + cleanup
- Tests: Resource management tests

### Phase 4: HTTP Services (Week 7)
- Examples: HTTP server, REST API
- Documentation: Tutorial + API docs
- Benchmarks: vs Go baseline

**Target:** `2026.2.0-service` by March 22, 2026

---

## 10. Testing Strategy

### 10.1 Unit Tests
- `tests/integration/async_basic_test.zig`
- `tests/integration/nursery_test.zig`
- `tests/integration/using_statement_test.zig`

### 10.2 Integration Tests
- HTTP server (concurrent requests)
- Database connections (connection pooling)
- File processing (concurrent I/O)

### 10.3 Performance Benchmarks
- HTTP "Hello World" latency (vs Go)
- Concurrent request throughput (vs Go)
- Memory usage under load (vs Go)

**Target:** Within 1.5x of Go performance for HTTP workloads

---

## 11. Future Work (Deferred to :sovereign)

### Custom Runtime Components
- **Fibers:** Green threads (replace Zig's async)
- **Channels:** Message passing (replace Zig's event.Channel)
- **Scheduler:** Work-stealing scheduler (replace Zig's scheduler)

**Rationale:** Use proven Zig runtime now, dogfood our own in :sovereign profile.

---

## 12. Related Specifications

- **SPEC-002:** Profile system definitions
- **SPEC-003:** Runtime system architecture
- **SPEC-017:** Syntax specification
- **09-using-statement-concurrency:** Resource management design

---

## 13. Acceptance Criteria

**:service profile is complete when:**
- ✅ All syntax compiles (async, await, nursery, spawn, using)
- ✅ Structured concurrency works (tasks awaited at nursery exit)
- ✅ Resource cleanup guaranteed (even on error/panic)
- ✅ HTTP server example runs and handles concurrent requests
- ✅ Zero memory leaks (validated with test allocator)
- ✅ Performance within 1.5x of Go baseline
- ✅ Documentation complete (tutorial + examples)

---

## 14. Implementation Status

| Feature | Parser | Lowerer | LLVM Emitter | Runtime | E2E Tests |
|---------|--------|---------|--------------|---------|-----------|
| `async func` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `await` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `nursery` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `spawn` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `spawn` with args | ✅ | ✅ | ✅ | ✅ | ✅ |
| Channels | ✅ | ✅ | ✅ | ✅ | ✅ |
| `select` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `using` | ✅ | 🔄 | 🔄 | N/A | 🔄 |
| `CancelToken` | N/A | N/A | N/A | ✅ | ✅ |

### Runtime Implementation

**Nursery Runtime:** 47/47 tests passing (`runtime/scheduler/nursery.zig`)
- State machine: Open → Closing → Closed / Cancelling → Cancelled
- Transitive cancellation: Parent → Child task → Child nursery
- Budget system: Prevents resource exhaustion
- Completion tracking: First-error-wins semantics

**State Machine Specification:** `specs/SPEC-021-scheduler-nursery-state-machine.md`

### Example Programs (New)

Complete working examples in `examples/service/`:

1. **`async_hello.jan`** — Minimal async/await demonstration
2. **`nursery_spawn_demo.jan`** — Structured concurrency patterns
3. **`using_statement_demo.jan`** — Resource management and RAII
4. **`http_server.jan`** — Full HTTP server with all features

See `examples/service/README.md` for detailed documentation.

---

**Status:** Core concurrency features COMPLETE — 85% overall
**Next:** Using statement semantic resolver, HTTP std library
**Version:** 2026.2.0-service
**Last Updated:** 2026-02-06

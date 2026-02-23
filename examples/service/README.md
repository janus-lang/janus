# :service Profile Examples

Complete working examples demonstrating Janus's **structured concurrency** and **async/await** capabilities.

## Quick Start

```bash
# Parse an example (check syntax)
janus parse examples/service/async_hello.jan

# Run the nursery demo
janus run examples/service/nursery_spawn_demo.jan

# Compile the HTTP server
janus build examples/service/http_server.jan --profile service
```

## Examples

### 1. `async_hello.jan` — Minimal Async Example

The simplest possible async program. Demonstrates:
- `async func` declaration
- `await` expression
- Error propagation with `!`

```janus
async func greet(name: []const u8) !void do
    println("Hello, ", name, "!")
end

async func main() !void do
    await greet("World")
end
```

### 2. `nursery_spawn_demo.jan` — Structured Concurrency

Comprehensive demonstration of nursery/spawn patterns:
- **Basic concurrency**: Multiple tasks running in parallel
- **Return values**: Using `await` to collect results from spawned tasks
- **Error handling**: Nursery aggregates errors from all tasks
- **Nested nurseries**: Hierarchical task structures
- **Resource sharing**: Safe resource use across concurrent tasks

Key patterns:
```janus
// Spawn concurrent tasks
nursery do
    spawn task_a()
    spawn task_b()
    spawn task_c()
end  // Automatically waits for all to complete

// Collect return values
nursery do
    let handle = spawn compute_value(42)
    let result = await handle
end

// Nested structured concurrency
nursery do
    spawn outer_task()
    nursery do
        spawn inner_task()
    end
end
```

### 3. `using_statement_demo.jan` — Resource Management

Demonstrates RAII-style resource management:
- **Basic `using`**: Automatic cleanup with `close()`
- **Walrus operator**: `:=` for type inference
- **LIFO cleanup**: Multiple resources close in reverse order
- **Async safety**: Cleanup runs even if async operations fail
- **Error safety**: Cleanup runs before error propagation
- **Early return**: Cleanup runs before `return` statements

Key patterns:
```janus
// Basic resource management
using file := try fs.open("data.txt", .{ .read = true }) do
    let content = try file.read_all()
end  // file.close() called automatically

// Multiple resources (LIFO cleanup)
using file1 := open("a.txt") do
    using file2 := open("b.txt") do
        // Both files open
    end  // file2 closes first
end  // file1 closes second

// With nursery for shared resources
nursery do
    using db := try database.connect("localhost") do
        spawn fetch_users(db)
        spawn fetch_orders(db)
    end  // db.close() after both tasks complete
end
```

### 4. `http_server.jan` — Full HTTP Server

Production-ready HTTP server demonstrating all :service features:
- **Async I/O**: `await` for non-blocking network operations
- **Structured concurrency**: One nursery per accept loop
- **Resource management**: `using` for sockets, buffers, sessions
- **Error handling**: Comprehensive error propagation
- **Request routing**: Pattern matching on URL paths

Architecture:
```janus
async func main() !void do
    using server := try net.tcp_listener_bind(host, port, opts) do
        nursery do
            while connection_count < MAX_CONNECTIONS do
                let conn = await server.accept()
                spawn handle_connection(conn, id)
            end
        end
    end
end

async func handle_connection(conn: net.tcp_connection, id: u32) !void do
    using buffer := io.buffer_with_capacity(4096) do
        let bytes_read = await conn.read(buffer)
        let request = try http.parse_request(buffer)
        let response = route_request(request)
        await conn.write_all(response)
    end
end
```

## Profile Features Demonstrated

| Feature | async_hello | nursery_spawn | using_demo | http_server |
|---------|:-----------:|:-------------:|:----------:|:-----------:|
| `async func` | ✅ | ✅ | ✅ | ✅ |
| `await` | ✅ | ✅ | ✅ | ✅ |
| `nursery` | ❌ | ✅ | ✅ | ✅ |
| `spawn` | ❌ | ✅ | ❌ | ✅ |
| `using` | ❌ | ❌ | ✅ | ✅ |
| Error unions (`!`) | ✅ | ✅ | ✅ | ✅ |
| Pattern matching | ❌ | ❌ | ❌ | ✅ |

## Runtime Implementation

The :service profile is backed by a **production-grade M:N scheduler**:

- **Nursery runtime**: `runtime/scheduler/nursery.zig` (47 tests passing)
- **State machine**: `specs/SPEC-021-scheduler-nursery-state-machine.md`
- **Cancellation**: Cooperative cancellation with tokens
- **Budget system**: Prevent resource exhaustion attacks

### Nursery State Machine

```
┌─────────┐  close()  ┌─────────┐
│  Open   │ ────────→ │ Closing │
└────┬────┘           └────┬────┘
     │                     │
     │ cancel()            │ all_children_complete()
     ↓                     ↓
┌──────────┐          ┌─────────┐
│Cancelling│          │ Closed  │
└────┬─────┘          └─────────┘
     │
     │ all_children_complete()
     ↓
┌──────────┐
│Cancelled │
└──────────┘
```

## Design Philosophy

> "Go's simplicity + Rust's safety + Native speed, minus the complexity"

### Principles

1. **No Orphan Tasks**: Every spawned task belongs to a nursery
2. **Deterministic Cleanup**: `using` guarantees resource cleanup
3. **Fail-Safe**: Errors propagate cleanly; cleanup always runs
4. **Composable**: Nurseries nest; resources compose
5. **Zero-Cost**: Async/await compiles to efficient state machines

### Comparison with Other Languages

| Feature | Go | Rust | Janus :service |
|---------|----|------|----------------|
| Goroutines/green threads | ✅ | ❌ | ✅ (nursery/spawn) |
| Structured concurrency | ❌ | ✅ (external crates) | ✅ (built-in) |
| RAII/defer | ❌ | ✅ | ✅ (`using`) |
| Async/await | ❌ | ✅ | ✅ |
| Compile-time safety | ❌ | ✅ | ✅ |
| Colored functions | ❌ | ✅ | ✅ (explicit `async`) |

## Further Reading

- **SPEC-019**: `:service` Profile Specification (`specs/SPEC-019-profile-service.md`)
- **SPEC-021**: Scheduler Implementation (`specs/SPEC-021-scheduler.md`)
- **Nursery State Machine**: Formal specification (`specs/SPEC-021-scheduler-nursery-state-machine.md`)
- **Integration Tests**: E2E validation (`tests/integration/service_profile_full_test.zig`)

## License

All examples are licensed under LCL-1.0 (Libertarian Public License).

---

*"Write sequential, execute concurrent."* — Janus :service Profile

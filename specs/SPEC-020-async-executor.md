<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# SPEC-020: Async Executor Model

**Version:** 2026.2.0
**Status:** DRAFT (Forward-Looking Design)
**Authority:** Constitutional
**Depends On:** SPEC-002, SPEC-003, SPEC-019
**Prepares For:** Zig 0.16 std.Io Interface

This specification defines the **Async Executor Model**, an abstraction layer that decouples concurrency semantics from execution backends. This design anticipates Zig 0.16's revolutionary `std.Io` interface while maintaining full compatibility with Zig 0.15.x thread-based execution.

---

## 1. Motivation

### 1.1 The Problem

Current concurrency implementations suffer from **execution model lock-in**:
- Go: Hardcoded M:N scheduler (can't opt for simpler model)
- Rust/Tokio: Must choose async runtime at project start
- Crystal: Single-threaded fibers by default (multi-threading experimental)

### 1.2 The Zig 0.16 Revolution

Zig's upcoming `std.Io` interface solves the "function coloring" problem:
- Same code works with blocking, threaded, or evented I/O
- Caller provides execution backend (like Allocator pattern)
- No runtime dictating execution model

### 1.3 Janus Philosophy

Janus adopts **Mechanism over Policy**: provide dials, not dictates.

```
[EXEC:1.3.1] The execution model MUST be caller-controlled.
[EXEC:1.3.2] The same Janus code MUST work across all backends.
[EXEC:1.3.3] Hidden costs MUST be revealed through explicit backend choice.
```

---

## 2. Executor Interface

### 2.1 Core Abstraction

```
[EXEC:2.1.1] The Executor interface MUST abstract task spawning and synchronization.
[EXEC:2.1.2] All concurrency primitives MUST operate through Executor.
[EXEC:2.1.3] Executor MUST be injectable (like Allocator).
```

**Janus Syntax:**
```janus
// Executor-aware function signature
func process_data(exec: Executor, data: []u8) !Result do
    exec.concurrent do
        exec.async save("file.txt", data)
        exec.async notify_complete()
    end
end

// Caller chooses backend
process_data(Executor.threaded(), my_data)   // OS threads
process_data(Executor.blocking(), my_data)   // Sequential
process_data(Executor.evented(), my_data)    // io_uring/kqueue (0.16+)
```

### 2.2 Executor Backends

| Backend | Description | Availability | Use Case |
|---------|-------------|--------------|----------|
| `Executor.blocking()` | Sequential execution | 0.15.x+ | Debugging, deterministic tests |
| `Executor.threaded()` | OS thread pool | 0.15.x+ | CPU-bound parallelism |
| `Executor.evented()` | io_uring/kqueue | 0.16+ | I/O-bound concurrency |
| `Executor.fibers()` | Cooperative scheduling | Future | Massive concurrency (100K+ tasks) |

```
[EXEC:2.2.1] Executor.blocking() MUST be available in all Zig versions.
[EXEC:2.2.2] Executor.threaded() MUST be available in Zig 0.15.x+.
[EXEC:2.2.3] Executor.evented() MUST gracefully degrade on unsupported platforms.
[EXEC:2.2.4] Requesting unavailable backend MUST return error.ExecutorUnavailable.
```

### 2.3 Runtime Implementation (Zig)

```zig
// runtime/executor.zig

pub const Executor = union(enum) {
    blocking: BlockingExecutor,
    threaded: ThreadedExecutor,
    evented: ?EventedExecutor,  // null on 0.15.x or unsupported platforms

    pub fn spawn(self: *Executor, comptime func: anytype, args: anytype) !TaskHandle {
        return switch (self.*) {
            .blocking => |*b| b.runSync(func, args),
            .threaded => |*t| try t.spawnThread(func, args),
            .evented => |*e| if (e.*) |*ev| try ev.submit(func, args)
                             else return error.ExecutorUnavailable,
        };
    }

    pub fn concurrent(self: *Executor, tasks: []const Task) !void {
        switch (self.*) {
            .blocking => for (tasks) |t| try t.run(),  // Sequential
            .threaded => try self.parallelJoin(tasks),
            .evented => |*e| if (e.*) |*ev| try ev.submitBatch(tasks)
                             else return error.ExecutorUnavailable,
        }
    }

    pub fn awaitAll(self: *Executor) !void {
        // Wait for all spawned tasks to complete
    }
};
```

---

## 3. Channels (CSP Communication)

### 3.1 Channel Type

```
[CHAN:3.1.1] Channel[T] MUST provide type-safe message passing.
[CHAN:3.1.2] Channels MUST be non-nullable (no nil channel trap).
[CHAN:3.1.3] Channel operations MUST work with any Executor backend.
```

**Janus Syntax:**
```janus
// Unbuffered channel (synchronous)
let ch = Channel[i32].new(allocator)
defer ch.deinit()

// Buffered channel (async up to capacity)
let buf_ch = Channel[Message].buffered(allocator, capacity: 10)

// Send and receive
ch.send(42)           // Blocks until receiver ready
let val = ch.recv()   // Blocks until value available

// Non-blocking variants
ch.trySend(42) or return error.ChannelFull
let val = ch.tryRecv() or null
```

### 3.2 Channel Operations

| Operation | Blocking | Returns | Error Conditions |
|-----------|----------|---------|------------------|
| `send(val)` | Yes | void | ChannelClosed |
| `recv()` | Yes | T | ChannelClosed |
| `trySend(val)` | No | bool | ChannelClosed, ChannelFull |
| `tryRecv()` | No | ?T | ChannelClosed |
| `close()` | No | void | - |

```
[CHAN:3.2.1] send() on closed channel MUST return error.ChannelClosed.
[CHAN:3.2.2] recv() on closed channel MUST return remaining buffered values, then error.ChannelClosed.
[CHAN:3.2.3] close() MUST be idempotent (multiple calls are no-op).
```

### 3.3 Channel Implementation (Zig)

```zig
// runtime/channel.zig

pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: std.RingBuffer(T),
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,
        closed: std.atomic.Value(bool),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .buffer = std.RingBuffer(T).init(allocator, 0), // Unbuffered
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .closed = std.atomic.Value(bool).init(false),
                .allocator = allocator,
            };
        }

        pub fn buffered(allocator: std.mem.Allocator, capacity: usize) !Self {
            return .{
                .buffer = try std.RingBuffer(T).init(allocator, capacity),
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .closed = std.atomic.Value(bool).init(false),
                .allocator = allocator,
            };
        }

        pub fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.buffer.isFull() and !self.closed.load(.acquire)) {
                self.not_full.wait(&self.mutex);
            }

            if (self.closed.load(.acquire)) return error.ChannelClosed;

            self.buffer.push(value);
            self.not_empty.signal();
        }

        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.buffer.isEmpty() and !self.closed.load(.acquire)) {
                self.not_empty.wait(&self.mutex);
            }

            if (self.buffer.isEmpty()) return error.ChannelClosed;

            const value = self.buffer.pop();
            self.not_full.signal();
            return value;
        }

        pub fn close(self: *Self) void {
            self.closed.store(true, .release);
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }
    };
}
```

---

## 4. Select Statement

### 4.1 Syntax

```
[SEL:4.1.1] select MUST support multiple channel operations.
[SEL:4.1.2] select MUST support timeout cases.
[SEL:4.1.3] select MUST support default (non-blocking) case.
```

**Janus Syntax:**
```janus
select do
    case msg = ch1.recv() do
        print("Received: ", msg)
    end

    case ch2.send(response) do
        print("Sent response")
    end

    case timeout(100.milliseconds) do
        print("Operation timed out")
    end

    default do
        print("No channel ready")
    end
end
```

### 4.2 Select Semantics

```
[SEL:4.2.1] If multiple cases ready, select MUST choose fairly (round-robin or random).
[SEL:4.2.2] If no cases ready and no default, select MUST block.
[SEL:4.2.3] If no cases ready and default present, default MUST execute immediately.
[SEL:4.2.4] timeout() MUST use monotonic clock (immune to wall-clock changes).
```

### 4.3 Select Desugaring

**Janus:**
```janus
select do
    case msg = ch.recv() do handle(msg) end
    case timeout(1.second) do retry() end
end
```

**Lowers to QTJIR:**
```
Select_Begin
  Select_Case(channel_id=1, op=Recv, var="msg")
    // handle(msg) body
  Select_Case_End
  Select_Timeout(duration_ns=1000000000)
    // retry() body
  Select_Timeout_End
Select_End
```

---

## 5. Nursery Integration

### 5.1 Executor-Aware Nurseries

```
[NURS:5.1.1] Nurseries MUST use the ambient Executor.
[NURS:5.1.2] spawn inside nursery MUST delegate to Executor.spawn().
[NURS:5.1.3] Nursery exit MUST call Executor.awaitAll().
```

**Janus Syntax:**
```janus
// Nursery inherits executor from context
func main(exec: Executor) !void do
    nursery do
        spawn task_a()   // Uses exec.spawn()
        spawn task_b()
    end  // exec.awaitAll()
end

// Or explicit executor
nursery(exec) do
    spawn task_a()
end
```

### 5.2 Channel + Nursery Pattern

```janus
func producer_consumer(exec: Executor) !void do
    let ch = Channel[i32].buffered(allocator, 10)
    defer ch.deinit()

    nursery do
        // Producer
        spawn do
            for i in 0..<100 do
                ch.send(i)
            end
            ch.close()
        end

        // Consumer
        spawn do
            while ch.recv() |val| do
                print("Got: ", val)
            end catch |err| switch err {
                error.ChannelClosed => break,
                else => return err,
            }
        end
    end
end
```

---

## 6. Migration Path

### 6.1 Zig 0.15.x (Current)

**Available Backends:**
- `Executor.blocking()` - Always available
- `Executor.threaded()` - Uses `std.Thread`

**Not Available:**
- `Executor.evented()` - Returns `error.ExecutorUnavailable`

### 6.2 Zig 0.16.x (Future)

**New Capabilities:**
- `Executor.evented()` - Uses `std.Io` interface
- Linux: `io_uring` backend
- macOS: `kqueue` backend
- Windows: `IOCP` backend

**Migration:**
```zig
// 0.15.x code continues to work
const exec = Executor.threaded();
process_data(exec, data);

// 0.16.x can opt into evented I/O
const exec = Executor.evented() catch Executor.threaded();
process_data(exec, data);
```

### 6.3 Compatibility Guarantees

```
[MIG:6.3.1] All Janus code written for 0.15.x MUST compile on 0.16.x.
[MIG:6.3.2] Executor.threaded() MUST remain available on all versions.
[MIG:6.3.3] Channel API MUST NOT change between versions.
[MIG:6.3.4] Select API MUST NOT change between versions.
```

---

## 7. Capability Integration

### 7.1 Concurrency Capabilities

```
[CAP:7.1.1] spawn requires CapSpawn capability.
[CAP:7.1.2] Channel creation requires CapChannel capability.
[CAP:7.1.3] Executor selection requires CapExecutor capability.
```

**Janus Syntax:**
```janus
// Capability-gated concurrency
func worker(ctx: Context[CapSpawn, CapChannel]) !void do
    let ch = ctx.createChannel[i32]()  // CapChannel required

    ctx.nursery do
        ctx.spawn(task)  // CapSpawn required
    end
end
```

### 7.2 Security Model

| Operation | Required Capability | Rationale |
|-----------|---------------------|-----------|
| `spawn` | CapSpawn | Resource consumption (threads) |
| `Channel.new` | CapChannel | Memory allocation, sync primitives |
| `Executor.*` | CapExecutor | Backend selection affects behavior |
| `select` | CapChannel | Operates on channels |

---

## 8. QTJIR Opcodes

### 8.1 New Opcodes for Channels

| Opcode | Operands | Description |
|--------|----------|-------------|
| `Channel_Create` | type, capacity | Create channel |
| `Channel_Send` | channel_id, value_id | Send value |
| `Channel_Recv` | channel_id | Receive value |
| `Channel_Close` | channel_id | Close channel |
| `Channel_TrySend` | channel_id, value_id | Non-blocking send |
| `Channel_TryRecv` | channel_id | Non-blocking receive |

### 8.2 New Opcodes for Select

| Opcode | Operands | Description |
|--------|----------|-------------|
| `Select_Begin` | case_count | Start select block |
| `Select_Case_Recv` | channel_id, var_name | Recv case |
| `Select_Case_Send` | channel_id, value_id | Send case |
| `Select_Timeout` | duration_ns | Timeout case |
| `Select_Default` | - | Default case |
| `Select_End` | - | End select block |

### 8.3 Executor Opcodes

| Opcode | Operands | Description |
|--------|----------|-------------|
| `Executor_Get` | backend_type | Get executor instance |
| `Executor_Spawn` | executor_id, func_id, args | Spawn on executor |
| `Executor_Concurrent` | executor_id, task_list | Run tasks concurrently |
| `Executor_AwaitAll` | executor_id | Wait for all tasks |

---

## 9. Implementation Phases

### Phase 3.0: Channel Foundation (Weeks 1-2)
- [ ] `Channel[T]` type in parser
- [ ] Channel runtime in `janus_rt.zig`
- [ ] `send()`, `recv()` operations
- [ ] Basic tests

### Phase 3.1: Buffered Channels (Week 3)
- [ ] `Channel[T].buffered(capacity)`
- [ ] Ring buffer implementation
- [ ] Backpressure handling

### Phase 4.0: Select Statement (Weeks 4-5)
- [ ] Parser: `select` syntax
- [ ] QTJIR: Select opcodes
- [ ] Runtime: Multi-channel wait
- [ ] Timeout support

### Phase 5.0: Executor Abstraction (Week 6)
- [ ] `Executor` interface
- [ ] `Executor.blocking()` implementation
- [ ] `Executor.threaded()` implementation
- [ ] Nursery integration

### Phase 5.1: Zig 0.16 Preparation (Week 7)
- [ ] `Executor.evented()` stub
- [ ] Feature detection for std.Io
- [ ] Migration documentation

---

## 10. Testing Strategy

### 10.1 Unit Tests
- Channel send/recv correctness
- Buffered channel capacity handling
- Select with multiple ready channels
- Executor backend switching

### 10.2 Concurrency Tests
- Race condition detection (ThreadSanitizer)
- Deadlock detection
- Channel close semantics
- Select fairness

### 10.3 Performance Benchmarks
- Channel throughput (messages/second)
- Select latency
- Executor overhead comparison

---

## 11. Related Specifications

- **SPEC-002:** Profile system (capability sets)
- **SPEC-003:** Runtime architecture
- **SPEC-019:** :service profile (async/await, nursery)
- **SPEC-012:** Boot and capabilities

---

## 12. References

- [Zig's New Async I/O](https://kristoff.it/blog/zig-new-async-io/) - Zig 0.16 design
- [Go Channels](https://go.dev/ref/spec#Channel_types) - CSP reference
- [Crystal Concurrency](https://crystal-lang.org/reference/guides/concurrency.html) - Fiber model
- [Kotlin Structured Concurrency](https://kotlinlang.org/docs/coroutines-basics.html) - Scope model

---

**Status:** Draft
**Last Updated:** 2026-01-29
**Next Review:** After Zig 0.16 release

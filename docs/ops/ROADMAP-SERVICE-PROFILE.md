<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# :service Profile Implementation Roadmap

**Target Version:** `2026.2.0-service`
**Timeline:** 7 weeks (mid-February to early April 2026)
**Status:** Approved - Ready to Start

---

## Strategic Context

**:service Profile** is the "Go-like async, but technically better" profile. It enables:
- Async/await structured concurrency
- Goroutine-style green threads
- Resource-safe `using` statement
- HTTP services and APIs
- Nursery-based task management

**Market positioning:** "Go's simplicity + Rust's safety + Native speed, minus the complexity"

---

## Foundation: What We Already Have

### ✅ Specifications (Complete)
- **SPEC-002**: Profile definitions (`:service` defined)
- **SPEC-003**: Runtime system (nurseries, structured concurrency)
- **09-using-statement-concurrency**: Full design for resource management

### ✅ Compiler Infrastructure (Complete)
- Parser with `do...end` syntax
- ASTDB (semantic graph)
- QTJIR (SSA intermediate representation)
- LLVM codegen
- Profile validation framework

### ✅ Native Zig Access (Complete)
- `use zig "std/event"` for async runtime
- `use zig "std/http"` for HTTP stack
- Zero-cost integration (compiles through Zig)

---

## What We Need to Build

### 1. Syntax Extensions
- `async func` declarations
- `await` expressions
- `nursery { }` blocks
- `spawn` expressions
- `using` statement with resource cleanup

### 2. Semantic Analysis
- Async function type checking
- Effect tracking for async operations
- Nursery scope validation
- Resource lifetime analysis

### 3. QTJIR Lowering
- Desugar `async func` to Zig's async functions
- Desugar `await` to Zig's await
- Desugar `nursery` to Zig's event loop with scope
- Desugar `using` to defer + cleanup

### 4. Runtime Support
- Use Zig's `std.event` (no custom runtime yet)
- Resource registry for `using` statement
- Nursery lifecycle management

---

## Implementation Phases

### **Phase 1: Async/Await Syntax (Weeks 1-2)**

**Goal:** Add `async func` and `await` as thin sugar over Zig's async.

**Tasks:**
1. **Parser Extensions**
   - Add `async` keyword to function declarations
   - Add `await` keyword as expression prefix
   - Update grammar in SPEC-017

2. **Semantic Analysis**
   - Mark async functions in symbol table
   - Track async propagation (calling async requires async)
   - Type check await expressions

3. **QTJIR Lowering**
   - Lower `async func` to Zig's `async fn`
   - Lower `await expr` to Zig's `await expr`
   - Preserve effect tracking

4. **Basic Test**
   ```janus
   use zig "std/event"

   async func fetch_data(url: []const u8) !Data do
       // Compiles to Zig's async fn
       use zig "std/http"
       return try zig.http.Client.fetch(url)
   end

   func main() !void do
       let data = await fetch_data("https://example.com")
       println("Fetched!")
   end
   ```

**Deliverable:** Basic async/await working, compiles through Zig

**Tests:**
- `tests/integration/async_basic_test.zig`
- `tests/integration/async_error_propagation_test.zig`

---

### **Phase 2: Nursery Blocks (Weeks 3-4)**

**Goal:** Add structured concurrency with `nursery { }` blocks.

**Tasks:**
1. **Parser Extensions**
   - Add `nursery` keyword for blocks
   - Add `spawn` keyword for task spawning
   - Update grammar

2. **Semantic Analysis**
   - Track nursery scope boundaries
   - Validate spawn only inside nursery
   - Ensure all spawned tasks awaited at block end

3. **QTJIR Lowering**
   - Lower `nursery { }` to Zig's event loop with scope
   - Lower `spawn expr` to Zig's async call with registration
   - Ensure LIFO cleanup on nursery exit

4. **Basic Test**
   ```janus
   async func task1() !void do
       println("Task 1 started")
       // ... work
       println("Task 1 done")
   end

   async func task2() !void do
       println("Task 2 started")
       // ... work
       println("Task 2 done")
   end

   func main() !void do
       nursery do
           spawn task1()
           spawn task2()
           spawn task1()  // Multiple spawns OK
       end  // Waits for all tasks to complete

       println("All tasks complete!")
   end
   ```

**Deliverable:** Structured concurrency working with automatic task waiting

**Tests:**
- `tests/integration/nursery_basic_test.zig`
- `tests/integration/nursery_error_propagation_test.zig`
- `tests/integration/nursery_cancellation_test.zig`

---

### **Phase 3: Resource Management (`using` Statement) (Weeks 5-6)**

**Goal:** Implement deterministic resource cleanup with concurrency safety.

**Tasks:**
1. **Parser Extensions**
   - Add `using` keyword for resource blocks
   - Add optional `shared` modifier
   - Update grammar

2. **Semantic Analysis**
   - Check resource type has `close()` method
   - Track resource ownership
   - Validate no resource escape from loop iteration
   - Detect cycles in shared resources (compile-time)

3. **QTJIR Lowering**
   - Lower `using` to `defer` + cleanup registration
   - Implement LIFO cleanup order
   - Handle cleanup errors (aggregate + propagate)
   - Integrate with nursery lifecycle

4. **Resource Registry** (from spec 09)
   ```zig
   // In runtime/janus_rt.zig
   const ResourceRegistry = struct {
       resources: std.ArrayList(Resource),

       fn register(self: *Self, resource: Resource) !void {
           try self.resources.append(resource);
       }

       fn cleanup(self: *Self) !void {
           // LIFO order
           while (self.resources.popOrNull()) |resource| {
               resource.close() catch |err| {
                   // Aggregate errors
               };
           }
       }
   };
   ```

5. **Basic Test**
   ```janus
   use zig "std/fs"

   func process_file(path: []const u8) !void do
       using file := try zig.fs.cwd().openFile(path, .{}) do
           let content = try file.readToEndAlloc(allocator, 1024*1024)
           defer allocator.free(content)

           // Process content
           println(content)
       end  // file.close() called automatically (even on error)
   end

   func main() !void do
       try process_file("test.txt")
   end
   ```

**Deliverable:** Resource management with guaranteed cleanup

**Tests:**
- `tests/integration/using_basic_test.zig`
- `tests/integration/using_lifo_test.zig`
- `tests/integration/using_error_aggregate_test.zig`
- `tests/integration/using_nursery_integration_test.zig`

---

### **Phase 4: HTTP Services & Polish (Week 7)**

**Goal:** Create production-ready HTTP service example.

**Tasks:**
1. **HTTP Service Wrapper**
   ```janus
   use zig "std/http"
   use zig "std/net"

   async func handle_request(req: Request) !Response do
       // Route handler
       if req.path == "/hello" do
           return Response.ok("Hello, World!")
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
       end  // server.close() called automatically
   end
   ```

2. **Examples**
   - HTTP server (hello world)
   - REST API (JSON responses)
   - Concurrent request handling
   - WebSocket echo server

3. **Documentation**
   - Update SPEC-018 profile table to show :service complete
   - Create tutorial: "Building Your First Web Service"
   - Document async/await patterns
   - Document resource management best practices

**Deliverable:** Production-ready :service profile with HTTP example

**Tests:**
- `examples/showcase/08_http_server.jan`
- `examples/showcase/09_rest_api.jan`
- Integration tests for HTTP functionality

---

## Profile Feature Matrix

| Feature | :core | :service | :cluster | :compute | :sovereign |
|---------|-------|----------|----------|----------|------------|
| **Async/Await** | ❌ | ✅ | ✅ | ❌ | ✅ |
| **Nurseries** | ❌ | ✅ | ✅ | ❌ | ✅ |
| **Actors** | ❌ | ❌ | ✅ | ❌ | ✅ |
| **`using` Statement** | ❌ | ✅ | ✅ | ❌ | ✅ |
| **HTTP Stack** | ❌ | ✅ | ✅ | ❌ | ✅ |
| **Concurrency** | ❌ | ✅ | ✅ | ❌ | ✅ |

---

## Deferred to :sovereign Profile

These features are mentioned in specs but deferred for dogfooding later:

1. **Custom Fibers** - Use Zig's async now, replace in :sovereign
2. **Custom Channels** - Use Zig's event system now, replace in :sovereign
3. **Custom Scheduler** - Use Zig's scheduler now, replace in :sovereign

**Rationale:** Get to market faster by leveraging proven Zig runtime. Dogfood our own when we have full control in :sovereign.

---

## Success Criteria

### Technical Milestones
- [ ] All syntax compiles (async, await, nursery, spawn, using)
- [ ] Structured concurrency works (tasks awaited at nursery exit)
- [ ] Resource cleanup guaranteed (even on error/panic)
- [ ] HTTP server example runs and handles concurrent requests
- [ ] Zero memory leaks (validated with test allocator)
- [ ] 100% test pass rate

### Documentation Milestones
- [ ] SPEC-019-profile-service.md created
- [ ] Tutorial: "Building Your First Web Service"
- [ ] Examples: HTTP server, REST API, WebSocket
- [ ] Updated SPEC-018 showing :service complete

### Performance Targets (vs Go baseline)
- [ ] HTTP "Hello World" latency: < 1.5x Go (acceptable overhead)
- [ ] Concurrent request throughput: > 0.8x Go (80% of Go's throughput)
- [ ] Memory usage: < 1.2x Go (20% overhead acceptable)
- [ ] Binary size: < 10MB (with LLVM LTO)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Zig async API changes** | Low | High | Pin Zig version, test on 0.15.x |
| **Complex async debugging** | Medium | Medium | Comprehensive logging, test coverage |
| **Resource leak edge cases** | Medium | High | Extensive testing, fuzzing |
| **Performance not competitive with Go** | Low | High | Benchmark early, optimize LLVM flags |

---

## Timeline Summary

| Phase | Duration | Completion Date | Deliverable |
|-------|----------|-----------------|-------------|
| Phase 1 | 2 weeks | Feb 15, 2026 | Async/await syntax |
| Phase 2 | 2 weeks | Mar 1, 2026 | Nursery blocks |
| Phase 3 | 2 weeks | Mar 15, 2026 | `using` statement |
| Phase 4 | 1 week | Mar 22, 2026 | HTTP services + polish |

**Target Release:** `2026.2.0-service` by **March 22, 2026**

---

## Next Steps

1. **Create SPEC-019-profile-service.md** (consolidate SPEC-002, SPEC-003, spec 09)
2. **Set up test infrastructure** (integration tests for async)
3. **Start Phase 1** (async/await parser extensions)
4. **Benchmark baseline** (Go HTTP server for comparison)

---

## Post-Release: :service → :cluster → :compute

After :service ships:

**Q2 2026:** :compute profile (GPU/NPU kernels)
- 10-12 weeks
- Target: `2026.3.0-compute`

**Q3 2026:** :cluster profile (distributed actors)
- 8-10 weeks
- Depends on :service as foundation
- Target: `2026.4.0-cluster`

---

**Status:** Ready to begin implementation
**Approved By:** Markus Maiwald
**Roadmap By:** Voxis Forge
**Date:** 2026-01-29

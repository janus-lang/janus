<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Lab: Building an Async Web Server

**Course:** Systems Programming with Janus  
**Lab:** 5 of 12  
**Topic:** Async/Await and Structured Concurrency  
**Duration:** 2 hours  

---

## Learning Objectives

By the end of this lab, you will:
1. Write async functions that handle concurrent requests
2. Use nurseries to manage task lifetimes
3. Implement cooperative cancellation
4. Build a working HTTP server with Janus :service profile

---

## Part 1: Warm-Up (20 minutes)

### Task 1.1: Async Counter

Complete the async counter that increments in the background:

```janus
// TODO: Make this async
func counter(limit: i64) -> i64 do
    var sum: i64 = 0
    for i in 0..limit do
        sum = sum + i
    end
    return sum
end

// TODO: Call it asynchronously and print progress
func main() do
    // Your code here
end
```

**Hint:** Use `async` to start, `await` to get the result.

---

## Part 2: Parallel Processing (30 minutes)

### Task 2.1: Parallel Word Count

Count words in multiple files in parallel:

```janus
// Provided: synchronous word count
func count_words(filename: string) -> i64 do
    // Returns word count
end

// TODO: Process 5 files in parallel
async func parallel_word_count(files: Array<string>) -> i64 do
    // Your code here
    // Use nursery to spawn tasks
    // Sum all results
end
```

**Validation:** `parallel_word_count` should be ~5x faster than sequential for 5 files.

---

## Part 3: Structured Concurrency (30 minutes)

### Task 3.1: No Orphans

Fix the bug in this code:

```janus
// BUGGY CODE — fix it
async func process_requests(requests: Array<Request>) do
    for req in requests do
        spawn handle_request(req)  // Orphan risk!
    end
    // Some tasks might still be running!
end
```

**Fix:** Use a nursery to ensure all tasks complete.

### Task 3.2: Graceful Shutdown

Add cancellation handling:

```janus
async func long_running_handler(req: Request) -> Response do
    // TODO: Check is_cancelled() periodically
    // Return partial results if cancelled
end
```

---

## Part 4: Build the Server (40 minutes)

### Task 4.1: HTTP Server Skeleton

```janus
// server.jan

// Configuration
const PORT = 8080
const MAX_CONCURRENT = 100

// TODO: Implement async request handler
async func handle_connection(conn: Connection) do
    nursery do
        let request = await read_request(conn)
        let response = await process_request(request)
        await send_response(conn, response)
    end
end

// TODO: Main server loop
async func run_server() do
    let listener = listen(PORT)
    
    nursery do
        loop
            let conn = await accept(listener)
            spawn handle_connection(conn)
        end
    end
end
```

### Task 4.2: Add Routes

```janus
// Route handlers
async func route_home() -> Response do
    return Response { status: 200, body: "Hello, Janus!" }
end

async func route_stats() -> Response do
    // TODO: Return server stats
end

async func route_shutdown() -> Response do
    // TODO: Trigger graceful shutdown
    // Cancel all active connections
end
```

---

## Challenge: Stress Test

Write a client that tests your server:

```janus
// stress_test.jan

async func stress_client(url: string, requests: i64) -> Stats do
    nursery do
        // Spawn many concurrent requests
        // Measure latency, throughput
    end
end
```

**Target:** Handle 10,000 concurrent connections.

---

## Evaluation Criteria

| Criterion | Points |
|-----------|--------|
| Async counter works | 10 |
| Parallel word count | 20 |
| No orphan tasks | 20 |
| Server handles requests | 30 |
| Graceful shutdown | 10 |
| Stress test passes | 10 |
| **Total** | **100** |

---

## Submission

```bash
# Submit your lab
git add labs/lab5-async-server/
git commit -m "Lab 5: Async web server"
git push origin stable
```

---

## Hints

1. **Start simple** — Get async/await working before building the server
2. **Test incrementally** — Run `zig test` after each change
3. **Use nursery wisely** — Every `spawn` should be in a nursery
4. **Check cancellation** — Long tasks should respect `is_cancelled()`

---

## References

- Tutorial: `docs/teaching/async-await-tutorial.md`
- Spec: SPEC-021 (M:N Scheduler)
- Example: `examples/service/chat_server.zig`

---

Good luck! 🦞

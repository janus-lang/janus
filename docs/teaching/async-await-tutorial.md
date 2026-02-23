<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Tutorial: Async/Await in Janus

**Target Audience:** University students learning systems programming  
**Prerequisites:** :core profile knowledge (functions, control flow)  
**Duration:** 45 minutes  

---

## 1. Why Async?

### The Problem: Wasted Time

When you call a slow function (network, disk), what happens?

```janus
// Synchronous code — BAD
data := fetch_from_network()  // Blocks for 100ms
result := process(data)       // Waits...
```

**Your thread is doing nothing for 100ms.** That's wasteful.

### The Solution: Do Other Work

```janus
// Async code — GOOD
let handle = async fetch_from_network()  // Starts, doesn't block
result := await handle                  // Wait ONLY when you need the result
```

While waiting, the scheduler runs other tasks.

---

## 2. Your First Async Function

```janus
// Declare with 'async'
async func count_to(n: i64) -> i64 do
    var sum: i64 = 0
    for i in 0..n do
        sum = sum + i
    end
    return sum
end

// Call with 'async' — returns a handle immediately
async func main() -> i64 do
    let handle = async count_to(1000000)  // Starts, doesn't wait
    print("Counting started...")
    
    let result = await handle  // Now we wait
    print("Result: {result}")
    return result
end
```

**Key insight:** `async count_to()` returns a **handle**, not the result. The result comes later with `await`.

---

## 3. Running Things in Parallel

### Without Async (Sequential)

```janus
func download_all() do
    let a = download("file1.txt")  // 100ms
    let b = download("file2.txt")  // 100ms
    let c = download("file3.txt")  // 100ms
    // Total: 300ms
end
```

### With Async (Parallel)

```janus
async func download_all() do
    let h1 = async download("file1.txt")  // Starts immediately
    let h2 = async download("file2.txt")  // Starts immediately
    let h3 = async download("file3.txt")  // Starts immediately
    
    let a = await h1  // Wait for all (already running)
    let b = await h2
    let c = await h3
    // Total: ~100ms (they run in parallel!)
end
```

---

## 4. Structured Concurrency (Nurseries)

### The Problem: Orphan Tasks

What if you spawn tasks but forget to wait?

```janus
// DANGEROUS — tasks might outlive parent
async func bad_example() do
    async background_task()  // Fire and forget?
    // Parent exits — child keeps running (orphan!)
end
```

### The Solution: Nurseries

```janus
// SAFE — all tasks complete before exit
async func good_example() do
    nursery do
        spawn background_task()  // Spawn inside nursery
        spawn another_task()      
    end  // Implicitly waits for ALL to complete
    // Guaranteed: no orphans
end
```

**Rule:** Everything inside `nursery do...end` must complete before the nursery exits.

---

## 5. Cancellation

### Cooperative Cancellation

Janus doesn't forcefully kill tasks. Tasks must **cooperate**:

```janus
async func long_task() -> i64 do
    for i in 0..1000000 do
        // Check if we should stop
        if is_cancelled() then
            print("Shutting down gracefully...")
            return -1
        end
        
        do_work(i)
    end
    return 42
end
```

### How Cancellation Works

```janus
async func parent() do
    nursery do
        let handle = async long_task()
        
        // Later: decide to cancel
        cancel(handle)
        
        let result = await handle  // Returns -1 (cancelled)
    end
end
```

**Key concept:** Cancellation is a **request**, not a command. The task decides how to handle it.

---

## 6. Error Handling

### Errors in Async Tasks

```janus
async func risky_task() -> i64 ! Error do
    if random() < 0.5 then
        return error.Oops
    end
    return 42
end

async func main() -> i64 ! Error do
    nursery do
        let h1 = async risky_task()
        let h2 = async risky_task()
        
        // If h1 fails, h2 is cancelled automatically
        let r1 = await h1
        let r2 = await h2
    end
end
```

**Structured concurrency means:** One failure cancels the whole nursery. No partial failures.

---

## 7. Complete Example: Web Scraper

```janus
// Fetches multiple pages in parallel with timeout

async func fetch_page(url: string) -> Page ! NetworkError do
    // Simulated network fetch
    await sleep(100)  // 100ms network delay
    return Page { url: url, content: "..." }
end

async func scrape(urls: Array<string>) -> Array<Page> do
    nursery do
        // Spawn all fetches in parallel
        let handles = urls.map { |url|
            async fetch_page(url)
        }
        
        // Collect all results
        return handles.map { |h| await h }
    end
end

// Usage
async func main() do
    let urls = ["a.com", "b.com", "c.com"]
    let pages = await scrape(urls)
    print("Fetched {pages.len} pages")
end
```

---

## 8. Common Patterns

### Pattern: Parallel Map

```janus
async func parallel_map(items: Array<T>, f: func(T) -> U) -> Array<U> do
    nursery do
        let handles = items.map { |item| async f(item) }
        return handles.map { |h| await h }
    end
end
```

### Pattern: Race (First to Complete)

```janus
async func race(tasks: Array<async () -> T>) -> T do
    nursery do
        let handles = tasks.map { |t| async t() }
        
        // Await any one completion
        return await_any(handles)
    end
end
```

### Pattern: Timeout

```janus
async func with_timeout(task: async () -> T, ms: i64) -> T ! TimeoutError do
    nursery do
        spawn timeout_task(ms)  // Cancels nursery after ms
        return await task()
    end
end
```

---

## 9. Exercises

### Exercise 1: Parallel Fibonacci

Compute fib(35) and fib(36) in parallel using async/await.

```janus
// Your code here
async func fib(n: i64) -> i64 do
    // ...
end

async func main() do
    // Spawn both, await both, sum results
end
```

### Exercise 2: Download with Retry

Write an async function that retries a download up to 3 times on failure.

### Exercise 3: Pipeline

Create a 3-stage pipeline:
1. Fetch URLs (stage 1)
2. Parse content (stage 2)
3. Write to disk (stage 3)

Use channels to communicate between stages.

---

## 10. Key Takeaways

1. **Async starts work immediately** — `async func()` returns a handle
2. **Await waits for completion** — `await handle` gives you the result
3. **Nurseries prevent orphans** — all tasks complete before exit
4. **Cancellation is cooperative** — tasks check `is_cancelled()`
5. **Errors cancel siblings** — structured concurrency

---

## Further Reading

- `docs/PHASE3_ASYNC_AWAIT.md` — Technical deep dive
- `examples/service/chat_server.zig` — Real async application
- SPEC-021 — M:N Scheduler specification

---

*Remember: Async is not magic. It's just the scheduler switching between tasks while they wait. The key is structured concurrency — no orphans, no leaks, predictable behavior.*

Happy coding! 🦞

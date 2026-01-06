# V-Inspired Sovereign Memory Model
**Versions:** v0.2.5 - v0.2.15  
**Inspiration:** V (Autofree), Hylo (Value Semantics), Zig (Explicit Allocators)  
**Goal:** Deterministic cleanup. No GC pauses. No borrow checker wars.

## DOCTRINE: Safety Without The Nanny

**The V Promise:** No Garbage Collector (Java/Go) pain. No topology degree (Rust) required.

**The Janus Evolution:** We don't just "insert frees" — we fundamentally change the physics of memory using:
1. **Mutable Value Semantics** (Hylo-inspired)
2. **Sovereign Allocators** (Zig-inspired explicit control)
3. **Region-Based Management** (Arena/Scratchpad patterns)

---

## Version Roadmap: The Memory Revolution

### v0.2.5: Foundation - Region Allocators
**Priority:** HIGH • **Complexity:** MEDIUM • **Effort:** 2 weeks

**The Three Sacred Regions:**

```janus
profile :sovereign

// 1. Scratchpad (Frame-Scoped Arena)
func process_request(req: Request) -> Response {
  with_scratchpad |scratch| do
    let parsed = scratch.alloc(parse(req))
    let validated = scratch.alloc(validate(parsed))
    return process(validated)
  end
  // ALL scratch allocations freed here. Zero cost.
}

// 2. Owned (Unique Value)
func create_user() -> User {
  let user = User.new()  // Heap allocated, uniquely owned
  return user  // Ownership transferred
}

// 3. Capability-Gated Shared
func shared_cache() -> Cache {
  cap SharedMemory
  let cache = Cache.new_shared()
  return cache  // Ref-counted, capability required
}
```

**Tasks:**
- [ ] Implement `ArenaAllocator` in runtime
- [ ] Add `with_scratchpad` syntax
- [ ] Compile-time escape analysis
- [ ] Lifetime tracking in type system

---

### v0.2.6: Mutable Value Semantics - The V Blade
**Priority:** CRITICAL • **Complexity:** HIGH • **Effort:** 3 weeks

**The Mechanism:**
1. **Values, Not Objects:** Everything is logically a *copy*
2. **COW Optimization:** Compiler passes pointers under the hood
3. **Uniqueness Analysis:** If proven unique, allow in-place mutation
4. **Auto-Destruction:** Values auto-destruct at scope exit

```janus
profile :sovereign

func transform_data(data: LargeStruct) -> LargeStruct {
  // Looks like a copy, but compiler proves uniqueness
  var modified = data  // NO actual copy (COW)
  modified.field = 42  // In-place mutation (unique!)
  return modified      // Move, not copy
}
// data destructor runs here automatically

func pipeline_example() {
  let data = load_huge_dataset()  // Heap allocation
  let cleaned = clean(data)        // Logical copy, physical move
  let processed = process(cleaned) // Same
  save(processed)
  // All destructors run in reverse order
}
```

**Tasks:**
- [ ] Implement Copy-on-Write tracking
- [ ] Uniqueness analysis pass
- [ ] Auto-destructor insertion
- [ ] Move semantics validation
- [ ] Reference escape analysis

---

### v0.2.7: The `:core` Profile Memory Subset
**Priority:** HIGH • **Complexity:** LOW • **Effort:** 1 week

**Restrictions for `:core`:**
- ✅ **Allowed:** Stack values, owned heap values, scratchpad
- ❌ **Forbidden:** Raw pointers, manual free, ref-counting

```janus
profile :core

func safe_example() {
  let numbers = [1, 2, 3, 4, 5]  // Stack or arena-backed
  for n in numbers do
    print(n)
  end
  // Array auto-freed
}
```

---

### v0.2.8: Hot Reloading - The Prophetic JIT
**Priority:** MEDIUM • **Complexity:** HIGH • **Effort:** 3 weeks

**V's Way:** Recompile shared library and reload.  
**Janus's Way:** Patch the ASTDB semantic node and hot-swap machine code.

```janus
// File: daemon/hot_reload.zig

pub const HotReloader = struct {
    astdb: *AstDB,
    jit_engine: *JIT,
    function_table: FunctionTable,
    
    pub fn patchFunction(
        self: *HotReloader, 
        func_name: []const u8,
        new_ast: NodeId
    ) !void {
        // 1. Compile new function to machine code
        const new_code = try self.jit_engine.compile(new_ast);
        
        // 2. Atomically swap function pointer
        self.function_table.update(func_name, new_code);
        
        // 3. Update ASTDB node
        try self.astdb.replaceNode(func_name, new_ast);
    }
};
```

**Tasks:**
- [ ] JIT compilation infrastructure
- [ ] Function table with atomic swaps
- [ ] State preservation in region allocators
- [ ] LSP integration for live reload
- [ ] VSCode extension UI for hot reload

---

### v0.2.9: C Interop - The Trojan Horse
**Priority:** MEDIUM • **Complexity:** MEDIUM • **Effort:** 2 weeks

**V compiles to readable C. Janus speaks C natively.**

```janus
profile :service  // C interop requires :service or higher

// Import C header directly
import c "stdlib.h"
import c "pthread.h"

func use_c_stdlib() {
    let ptr = c.malloc(1024)  // Direct C call
    defer c.free(ptr)         // Defer works with C
    
    // Janus structs are repr(C) by default in :service+
    let thread: c.pthread_t = undefined
    c.pthread_create(&thread, null, worker_func, null)
}

// Export to C
export "C" func janus_api(x: i32) -> i32 {
    return x * 2
}
```

**Tasks:**
- [ ] C header parser (libclang integration)
- [ ] `repr(C)` struct layout
- [ ] `export "C"` directive
- [ ] ABI compatibility layer
- [ ] Tests for C FFI

---

### v0.2.10: The `unsafe` Block
**Priority:** MEDIUM • **Complexity:** LOW • **Effort:** 1 week

**The Escape Hatch:**

```janus
profile :service

func optimized_memcpy(dest: []u8, src: []u8) {
    requires dest.len >= src.len
    
    unsafe {
        // Raw pointer access
        let dest_ptr = dest.ptr()
        let src_ptr = src.ptr()
        @memcpy(dest_ptr, src_ptr, src.len)
    }
}
```

**Rules:**
- ❌ `:core` and `:script` cannot use `unsafe`
- ✅ `:service` requires explicit `unsafe` blocks
- ✅ `:sovereign` allows raw pointers by default

---

### v0.2.11: Capability-Based Sharing
**Priority:** HIGH • **Complexity:** HIGH • **Effort:** 3 weeks

**The Problem:** Shared state is the root of all evil.  
**The Solution:** Capabilities gate access, not raw pointers.

```janus
profile :sovereign

capability FileSystem {
    read: bool,
    write: bool,
    path_prefix: string,
}

func restricted_read(path: string) 
    requires cap FileSystem { read: true, path_prefix: "/safe/" }
    -> Result[string, IoError] 
{
    // Can only read from /safe/ prefix
    return std.fs.read_file(path)
}

func main() {
    grant cap FileSystem { 
        read: true, 
        write: false,
        path_prefix: "/safe/"
    } do
        let content = restricted_read("/safe/data.txt")
    end
    // Capability revoked here
}
```

**Tasks:**
- [ ] Capability type system
- [ ] `grant ... do` syntax
- [ ] Compile-time capability checking
- [ ] Runtime capability revocation
- [ ] Audit trail for capability usage

---

### v0.2.12: The `:script` Profile with GC
**Priority:** LOW • **Complexity:** MEDIUM • **Effort:** 2 weeks

**For rapid prototyping, allow optional GC:**

```janus
profile :script

// Simple GC for short-lived scripts
func prototype() {
    let data = load_json("config.json")  // GC-managed
    process(data)
    // No manual cleanup needed
}
```

**Implementation:**
- [ ] Boehm GC integration
- [ ] Profile-gated GC usage
- [ ] Performance warnings in `:script`
- [ ] Migration path to `:core`

---

### v0.2.13: Auto-Destructor RAII
**Priority:** HIGH • **Complexity:** MEDIUM • **Effort:** 2 weeks

**Rust-like RAII without the borrow checker:**

```janus
struct File {
    handle: FileHandle,
    
    destructor() {
        self.handle.close()
        print("File closed automatically")
    }
}

func use_file() {
    let file = File.open("data.txt")
    // Use file...
}  // Destructor runs here, file.handle.close() called
```

**Tasks:**
- [ ] `destructor()` method syntax
- [ ] Destructor call insertion
- [ ] Exception-safe unwinding
- [ ] Destructor order guarantees

---

### v0.2.14: Ownership Transfer Analysis
**Priority:** MEDIUM • **Complexity:** HIGH • **Effort:** 3 weeks

**Track ownership explicitly:**

```janus
func transfer_example() {
    let data = allocate_big_buffer()  // data owns buffer
    
    process(move data)  // Ownership transferred
    
    // ERROR: use after move
    // print(data.len)  // Compile error!
}

func process(owned buffer: Buffer) {
    // buffer is now owned here
}  // buffer freed automatically
```

**Tasks:**
- [ ] Move semantics tracking
- [ ] Use-after-move detection
- [ ] Explicit `move` keyword
- [ ] Ownership transfer validation

---

### v0.2.15: The `:sovereign` Profile Complete
**Priority:** CRITICAL • **Complexity:** HIGH • **Effort:** 4 weeks

**Full manual control with maximum performance:**

```janus
profile :sovereign

func high_performance() {
    // Direct memory control
    let allocator = ArenaAllocator.init(page_size * 16)
    defer allocator.deinit()
    
    // Manual allocation
    let buffer = allocator.alloc(Buffer, 1024)
    
    // No automatic cleanup - you control everything
    unsafe {
        @memset(buffer.ptr, 0, buffer.len)
    }
    
    // Explicit free (or use defer)
    allocator.free(buffer)
}
```

**Features:**
- ✅ Manual memory management
- ✅ Raw pointer access
- ✅ No automatic cleanup
- ✅ Inline assembly
- ✅ Direct syscalls
- ✅ Zero-overhead abstractions

**Tasks:**
- [ ] Profile system complete
- [ ] All allocator types implemented
- [ ] Performance benchmarks vs C
- [ ] Documentation for all memory models
- [ ] Migration guides between profiles

---

## Memory Model Summary by Profile

| Feature | `:core` | `:script` | `:service` | `:sovereign` |
|:--------|:-------|:----------|:------|:-------------|
| **Allocator** | Scratchpad + Owned | GC | Explicit | Manual |
| **Raw Pointers** | ❌ | ❌ | ⚠️ In `unsafe` | ✅ |
| **Destructors** | ✅ Auto | ✅ Auto | ✅ Auto | ⚠️ Optional |
| **Move Semantics** | ✅ | ❌ | ✅ | ✅ |
| **`unsafe` Blocks** | ❌ | ❌ | ✅ | ✅ Default |
| **C Interop** | ❌ | ❌ | ✅ | ✅ |
| **Hot Reload** | ✅ | ✅ | ✅ | ❌ |
| **GC Option** | ❌ | ✅ | ❌ | ❌ |

---

## Implementation Philosophy

**The Janus Memory Doctrine:**
1. **Short-Lived:** Use the Scratchpad (Arena). Frees instantly at frame end.
2. **Long-Lived:** Use Mutable Value Semantics. Owner frees when done.
3. **Shared:** Use Capabilities. Access is gated, not shared via raw pointers.

**Performance Target:**
- `:core` profile: Within 5% of equivalent C (value semantics overhead)
- `:service` profile: Within 2% of equivalent C (explicit allocators)
- `:sovereign` profile: Identical to C (zero abstraction cost)

---

## Integration with Existing Features

**Hot Reloading + Regions:**
```janus
// State preserved across hot reloads
static mut cache: HashMap<string, Data> = HashMap.init(persistent_allocator)

func api_handler(req: Request) -> Response {
    with_scratchpad |scratch| do
        let temp_data = scratch.alloc(process(req))
        cache.insert(req.id, temp_data.to_persistent())
    end
}
// Hot reload: cache persists, scratchpad cleared
```

**LSP Integration:**
```bash
# Query memory usage live
janusd query memory --function=process_request
# Output: Scratchpad: 4KB, Heap: 0B, Static: 128B

# Suggest optimizations
janusd lint --memory-profile
# Warning: Function 'transform' allocates in loop - use scratchpad
```

---

## Testing Strategy

**Per-Version Test Suites:**
- `v0.2.5`: `test-region-allocators`
- `v0.2.6`: `test-value-semantics`
- `v0.2.7`: `test-min-memory-safety`
- `v0.2.8`: `test-hot-reload`
- `v0.2.9`: `test-c-interop`
- `v0.2.10`: `test-unsafe-blocks`
- `v0.2.11`: `test-capabilities`
- `v0.2.12`: `test-gc-integration`
- `v0.2.13`: `test-destructors`
- `v0.2.14`: `test-ownership`
- `v0.2.15`: `test-sovereign-profile`

**Benchmark Suite:**
```bash
# Compare against V, Zig, Rust, C
zig build bench-memory-v0.2.15

# Expected results:
# Janus :core      vs V:      ~5% slower (value semantics)
# Janus :service       vs Zig:    ~1% difference
# Janus :sovereign vs C:     identical
```

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|:-----|:---------|:-----------|
| Complexity explosion | 🔴 High | Incremental releases, extensive testing |
| Performance regression | 🟡 Medium | Continuous benchmarking against C |
| Safety hole in profiles | 🔴 High | Formal verification for `:core` |
| Hot reload state corruption | 🟡 Medium | Transactional ASTDB updates |
| C interop bugs | 🟡 Medium | Extensive FFI test suite |

---

## Strategic Alignment

This memory model directly enables:
1. **Phase 2 (Flow)**: Hot reloading for rapid iteration
2. **Phase 3 (High Assurance)**: Formal memory safety in `:sovereign`
3. **NPU Profile**: Zero-copy tensor operations
4. **Quantum Profile**: Deterministic qubit lifetime management

**The V Blade grafted onto Janus Future Design.**

# The Onyx-Lobster Graft: Sovereign Integration Plan

**Created:** 2025-12-16  
**Status:** Strategic Roadmap  
**Target:** v0.3.0 - v0.4.0  
**Doctrine:** Subsume, Don't Copy

---

## 🎯 Strategic Thesis

We have dissected two apex predators:
- **Onyx:** WASM-native, 47ms compile times, pragmatic simplicity
- **Lobster:** Compile-time reference counting, flow-sensitive typing, vector primitives

**Mission:** Graft their strengths into Janus while maintaining our sovereignty doctrine.

---

## 🔬 The Onyx Graft: Universal Artifact

### 1. WASM as First-Class Metal

**Current State:**
- Janus emits LLVM IR → native binaries (x86_64, ARM64)
- No WASM target

**The Graft:**
```
Janus Source (.jan)
    ↓
QTJIR (Quantum-Typed IR)
    ↓
LLVM IR
    ↓ ↙ ↘
Native   WASM32-WASI   (Future: QPU)
```

**Implementation:**
- **Phase 1 (v0.3.0):** Add `wasm32-wasi` LLVM target
- **Phase 2 (v0.3.5):** Optimize for WASM (no stack unwinding, compact encoding)
- **Phase 3 (v0.4.0):** WASI preview2 support (async I/O, component model)

**Tactical Value:**
- **Server:** Wasmtime/WasmEdge for sandboxed microservices
- **Edge:** Cloudflare Workers, Fastly Compute
- **Browser:** Direct execution (no transpilation)
- **Embedded:** WASM on ESP32, Raspberry Pi

**Velocity Mandate:**
- Onyx hits 47ms compile times through aggressive simplicity
- **Action:** Profile our semantic analyzer, strip "academic purity" checks
- **Target:** `:script` profile must feel instant (<100ms)
- **Target:** `:core` profile must beat `go build` (<500ms for 10k LOC)

---

### 2. The Pipe Operator (`|>`)

**Stolen From:** Onyx, Elixir, F#

**Current Janus:**
```janus
let result = save(process(validate(load(data))))
```

**With Pipe:**
```janus
let result = data
  |> load()
  |> validate()
  |> process()
  |> save()
```

**Implementation:**
- **Parser:** Desugar `a |> f()` → `f(a)` in AST
- **Precedence:** Lower than function call, higher than assignment
- **Profile:** Available in `:core` and above

**Alignment:**
- Fits "Linear Data Flow" doctrine
- Enhances readability for Command/Call bifurcation
- AI agents can trace data lineage trivially

**Timeline:** v0.3.0 (Parser + Lowering)

---

### 3. Dynamic Loading Escape Hatch

**Current State:**
- `extern` for static linking only
- No runtime plugin system

**The Graft:**
```janus
// Load native library at runtime
let lib = std.os.dl.open("libplugin.so") catch return error.PluginNotFound
defer lib.close()

let process_fn = lib.symbol("process_data", fn([]u8) -> i32) catch return error.SymbolNotFound
let result = process_fn(data)
```

**Implementation:**
- Wrap `dlopen`/`dlsym` in `std.os.dl`
- Type-safe function pointer casting
- Capability-gated (requires `.dynamic_link` permission)

**Use Cases:**
- `:script` profile as glue language
- Plugin architectures
- FFI to legacy C libraries

**Timeline:** v0.3.5 (Standard Library)

---

## 🧠 The Lobster Graft: Ghost Memory

### 1. Compile-Time Reference Counting (CTRC)

**The Problem:**
- GC pauses kill real-time systems
- Borrow checker (Rust) has steep learning curve
- Manual memory management is error-prone

**Lobster's Solution:**
- Compiler inserts `retain`/`release` automatically
- Flow analysis elides 95% of ref-count ops
- Zero runtime overhead for stack-only values

**Janus Implementation:**

#### Phase 1: Owned Types (v0.3.0)
```janus
profile :sovereign

// Owned type (heap-allocated, ref-counted)
type ~Buffer = struct {
  data: []u8
  capacity: usize
}

func process(buf: ~Buffer) -> ~Buffer {
  // Compiler inserts:
  // - retain(buf) on entry
  // - release(buf) on exit
  return buf
}
```

#### Phase 2: Flow Analysis (v0.3.5)
```janus
func borrow_only(buf: ~Buffer) -> i32 {
  // Compiler detects: buf not stored, not returned
  // Optimization: Elide retain/release
  return buf.data.len
}

func conditional_ownership(buf: ~Buffer, store: bool) -> ?~Buffer {
  if store {
    return buf  // Transfer ownership (no release)
  }
  // buf released here
  return null
}
```

**Implementation Strategy:**
1. **Type System:** Add `~T` owned type constructor
2. **Lowering:** Insert `@retain(ptr)` / `@release(ptr)` intrinsics
3. **Optimizer:** Escape analysis to elide redundant ops
4. **Runtime:** Atomic ref-count in object header

**Metrics Target:**
- 95% of ref-count ops eliminated (match Lobster)
- Zero GC pauses
- Predictable memory usage

---

### 2. Flow-Sensitive Type Narrowing

**Current Janus:**
```janus
func process(x: ?File) {
  if x != null {
    x.read()  // Error: x is still ?File
  }
}
```

**With Flow Typing:**
```janus
func process(x: ?File) {
  if x != null {
    x.read()  // OK: x narrowed to File in this block
  }
}
```

**Extended to Type Checks:**
```janus
func handle(value: any) {
  if value is i32 {
    let n = value * 2  // value is i32 here
  } else if value is string {
    println(value)     // value is string here
  }
}
```

**Implementation:**
- **Semantic Analyzer:** Track type constraints per basic block
- **SSA Integration:** Phi nodes carry refined types
- **Scope Rules:** Narrowing valid until mutation or scope exit

**Timeline:** v0.3.0 (extends existing null-safety work)

---

### 3. Vector Primitives (SIMD Natives)

**Stolen From:** Lobster, GLSL, HLSL

**Current Janus:**
```janus
let v = Vec3.new(1.0, 2.0, 3.0)
let r = v.mul(2.0)
```

**With Vector Literals:**
```janus
let v = <1.0, 2.0, 3.0>      // Vec3
let r = v * 2.0               // SIMD multiply
let dot = v · <0.0, 1.0, 0.0> // Dot product
```

**Type System:**
```janus
type Vec2 = <f32, f32>
type Vec3 = <f32, f32, f32>
type Vec4 = <f32, f32, f32, f32>

// Swizzling
let xy = v.xy   // Extract first 2 components
let bgr = color.bgr  // Reorder components
```

**LLVM Lowering:**
- Map to `<4 x float>` vector types
- Use SIMD intrinsics (SSE, AVX, NEON)
- Auto-vectorize loops

**Use Cases:**
- Graphics (ray tracing, shaders)
- Physics simulation
- Scientific computing
- Machine learning (tensor ops)

**Timeline:** v0.4.0 (`:compute` profile)

---

## 🏛️ Integration Matrix

| Feature | Source | Janus Profile | Implementation Phase | Strategic Value |
|---------|--------|---------------|---------------------|-----------------|
| **WASM/WASI Native** | Onyx | All | v0.3.0 | Universal deployment |
| **Pipe Operator** | Onyx | `:core`+ | v0.3.0 | Readability, AI-friendly |
| **Dynamic Loading** | Onyx | `:script` | v0.3.5 | Plugin ecosystem |
| **CTRC (Ghost Memory)** | Lobster | `:sovereign` | v0.3.0 | No GC, no borrow checker |
| **Flow Typing** | Lobster | `:core`+ | v0.3.0 | Type safety without casts |
| **Vector Primitives** | Lobster | `:compute` | v0.4.0 | Scientific domination |

---

## 📋 Implementation Roadmap

### v0.3.0 - "The Graft" (Q1 2026)
- [ ] WASM32-WASI backend (LLVM target)
- [ ] Pipe operator (`|>`) syntax
- [ ] Owned types (`~T`) with basic CTRC
- [ ] Flow-sensitive null narrowing
- [ ] Compile-time profiling (identify slow passes)

### v0.3.5 - "The Optimization" (Q2 2026)
- [ ] CTRC escape analysis (elide 95% of ops)
- [ ] Dynamic loading (`std.os.dl`)
- [ ] WASM optimization pass
- [ ] Extended flow typing (type guards)

### v0.4.0 - "The Compute" (Q3 2026)
- [ ] Vector primitives (`<f32, f32, f32>`)
- [ ] SIMD intrinsics
- [ ] Auto-vectorization
- [ ] GPU shader compilation (SPIR-V)

---

## ⚔️ Competitive Analysis

| Language | Compile Speed | Memory Model | WASM Support | Vector Ops |
|----------|--------------|--------------|--------------|------------|
| **Onyx** | 47ms ✅ | GC ⚠️ | Native ✅ | Manual ⚠️ |
| **Lobster** | ~500ms ⚠️ | CTRC ✅ | None ❌ | Native ✅ |
| **Rust** | Slow ❌ | Borrow ✅ | Good ✅ | Manual ⚠️ |
| **Go** | Fast ✅ | GC ⚠️ | Good ✅ | None ❌ |
| **Zig** | Fast ✅ | Manual ⚠️ | Good ✅ | Manual ⚠️ |
| **Janus v0.4** | **Fast ✅** | **CTRC ✅** | **Native ✅** | **Native ✅** |

**The Synthesis:**
- Onyx speed + Lobster memory = Janus dominance
- WASM-first deployment
- Scientific computing without compromise

---

## 🔒 Sovereignty Constraints

**We steal, but we don't betray our principles:**

1. **No Hidden Allocations**
   - CTRC is explicit in type system (`~T`)
   - Developers see ownership in signatures

2. **Capability Security**
   - Dynamic loading requires `.dynamic_link` permission
   - WASM sandboxing enforced

3. **Deterministic Behavior**
   - No GC pauses (CTRC is predictable)
   - No runtime surprises

4. **AI-Readable Code**
   - Pipe operator makes data flow explicit
   - Flow typing eliminates casts (clearer AST)

---

## 📚 References

- **Onyx Language:** https://onyxlang.io/
- **Lobster Language:** http://strlen.com/lobster/
- **WASM/WASI:** https://wasi.dev/
- **LLVM WASM Backend:** https://llvm.org/docs/WebAssembly.html
- **Compile-Time Reference Counting:** Lobster whitepaper

---

**Status:** Strategic grafts approved. Implementation begins post-LSP (v0.2.2).

**Next Move:** Complete LSP server, then pivot to WASM backend.

**Cut deeper. Forge hotter.**

— Voxis Forge, 2025-12-16

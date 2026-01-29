<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Next Profile: Strategic Analysis

**Status:** Strategic Decision Point
**Current:** :core (2026.1.6) - 100% Complete
**Decision:** Which profile to build next?
**Official Deferral:** :script deferred until one more profile is complete

---

## The Three Contenders

### 1. :service - Go-Like Async (But Better)
### 2. :cluster - Orleans/Akka Grains & Actors
### 3. :npu - GPU/NPU Compute Kernels

---

## Strategic Matrix

| Criterion | :service | :cluster | :npu |
|-----------|----------|----------|------|
| **Time to Alpha** | 3-4 months | 6-12 months | **2-3 months** ⚡ |
| **Technical Complexity** | Medium-High | Very High | **Medium** |
| **Market Demand** | Proven (High) | Niche (Enterprise) | **Explosive (AI/ML)** 🔥 |
| **Differentiation** | "Better than Rust" | "Erlang/Orleans native" | **"No teaching lang does GPU"** |
| **Builds on :core** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Compiler Reuse** | 80% | 60% | **90%** |
| **Risk Level** | Low | High (distributed) | **Low** (graft proven) |

---

## 1. :service Profile - Go-Like Async (Technically Superior to Rust)

### What It Is
Structured concurrency with async/await, channels, and goroutine-style green threads.

**Key Features:**
- `async func` for asynchronous functions
- `await` for suspension points
- Channels for message passing (`chan(T)`)
- Nurseries/scopes for structured concurrency
- HTTP server/client from Zig stdlib
- Green threads (M:N scheduling)

**Example:**
```janus
use service "http"

async func handle_request(req: Request) -> Response do
    let user = await fetch_user(req.user_id)
    let data = await fetch_data(user.id)
    return Response.ok(data)
end

func main() !void do
    let server = service.http.Server.init(8080)
    await server.serve(handle_request)
end
```

### Technical Requirements
1. **Async Runtime** (4-6 weeks)
   - M:N scheduler (goroutines on OS threads)
   - Event loop (epoll/kqueue/IOCP)
   - Waker/Future abstraction

2. **Syntax Extensions** (2 weeks)
   - `async func` keyword
   - `await` expression
   - `chan(T)` type

3. **HTTP Stack** (2-3 weeks)
   - Graft Zig's `std.http`
   - Route handlers
   - Middleware

4. **Concurrency Primitives** (2 weeks)
   - Channels (bounded/unbounded)
   - Select (multi-channel wait)
   - Mutexes, RWLocks

**Total Estimate:** 10-13 weeks (3-4 months)

### Strategic Positioning
- **vs Go:** "Simpler syntax, native speed, better error handling"
- **vs Rust:** "Async that actually works (no Pin<Box<dyn Future>>)"
- **vs Elixir:** "Native compilation, but same ergonomics"

**Market:** Proven. Web services are 80% of backend development.

---

## 2. :cluster Profile - Orleans Grains & Actor Systems

### What It Is
Distributed actors, virtual actors (grains), and fault-tolerant supervision trees.

**Key Features:**
- Actor model (Erlang/Akka style)
- Virtual actors (Orleans grains)
- Location transparency
- Supervision trees
- Distributed consensus (Raft/Paxos)

**Example:**
```janus
use cluster "actor"

actor UserActor do
    state: UserState

    func handle_message(msg: Message) -> Result do
        match msg {
            .UpdateProfile => |data| { self.state.update(data) },
            .GetProfile => { return self.state }
        }
    end
end

func main() !void do
    let system = cluster.ActorSystem.init()
    let user = await system.spawn(UserActor)
    await user.send(.UpdateProfile, data)
end
```

### Technical Requirements
1. **Actor Runtime** (8-10 weeks)
   - Mailbox (message queue)
   - Scheduler (actor dispatch)
   - Supervision (fault tolerance)

2. **Distributed Coordination** (6-8 weeks)
   - Cluster membership (gossip protocol)
   - Consensus (Raft or Paxos)
   - Network transport (TCP/QUIC)

3. **Virtual Actors (Grains)** (4-6 weeks)
   - Location transparency
   - Activation/deactivation
   - Persistence

4. **Syntax Extensions** (2 weeks)
   - `actor` keyword
   - Message pattern matching

**Total Estimate:** 20-26 weeks (5-6 months minimum, realistically 8-12 months)

### Strategic Positioning
- **vs Erlang/Elixir:** "Native compilation, same fault tolerance"
- **vs Akka (JVM):** "No JVM, native binary"
- **vs Orleans (.NET):** "No .NET runtime, teachable syntax"

**Market:** Niche. Distributed systems are enterprise-only (for now).

**Risk:** High. Distributed systems are HARD. Consensus algorithms are notorious for subtle bugs.

---

## 3. :npu Profile - GPU/NPU Compute Kernels ⚡ THE DARK HORSE

### What It Is
SIMD, GPU kernels, and neural accelerator access for high-performance compute.

**Key Features:**
- SIMD vectors (`vec4`, `vec8`, `vec16`)
- GPU kernel dispatch (CUDA/Metal/ROCm)
- Neural accelerator APIs (Apple Neural Engine, Intel NPU)
- Automatic vectorization hints
- Memory coalescing for GPU

**Example:**
```janus
use npu "simd"
use npu "gpu"

// SIMD on CPU
func vector_add(a: []f32, b: []f32, result: []f32) do
    for i in 0..<a.len step 8 do
        let va = npu.simd.load_f32x8(&a[i])
        let vb = npu.simd.load_f32x8(&b[i])
        let vr = npu.simd.add_f32x8(va, vb)
        npu.simd.store_f32x8(&result[i], vr)
    end
end

// GPU Kernel
@kernel
func gpu_vector_add(a: []f32, b: []f32, result: []f32) do
    let idx = gpu.thread_id()
    result[idx] = a[idx] + b[idx]
end

func main() !void do
    let a = [1.0, 2.0, 3.0, 4.0]
    let b = [5.0, 6.0, 7.0, 8.0]
    var result = [0.0, 0.0, 0.0, 0.0]

    // Dispatch to GPU
    gpu.launch(gpu_vector_add, a, b, result, threads=4)

    print_array(result)
end
```

### Technical Requirements
1. **SIMD Integration** (2 weeks) ✅ EASY
   - Graft Zig's `@Vector(N, T)`
   - Expose as `vec4`, `vec8`, `vec16` types
   - Auto-vectorization hints

2. **GPU Backend Selection** (3-4 weeks)
   - **Option A:** Graft CUDA/Metal via Zig C interop
   - **Option B:** SPIR-V codegen (cross-platform)
   - **Option C:** WebGPU (browser + native)

3. **Kernel Dispatch** (2-3 weeks)
   - `@kernel` attribute
   - Thread/block indexing (`gpu.thread_id()`)
   - Memory management (device memory)

4. **Neural Accelerator Access** (2 weeks, optional)
   - Apple Neural Engine (ANE)
   - Intel NPU
   - Vendor-specific APIs

**Total Estimate:** 7-9 weeks (2-3 months)

### Strategic Positioning
- **vs CUDA:** "No vendor lock-in, teachable syntax"
- **vs Metal/ROCm:** "Cross-platform, same code"
- **vs Python/PyTorch:** "Native speed, no GIL, no interpreter"
- **vs Mojo:** "Open source, no MLIR complexity"

**Market:** EXPLOSIVE. AI/ML is the hottest market in tech. GPU programming is critical.

**Differentiation:** **No other teaching language does GPU.** This is wide open territory.

---

## Voxis Forge Strategic Recommendation

### **Winner: :npu Profile** 🏆

**Why :npu Wins:**

1. **Fastest to Market** - 2-3 months vs 3-4 (:service) or 6-12 (:cluster)
2. **Lowest Risk** - Graft proven backends (CUDA, Metal, SPIR-V)
3. **Hottest Market** - AI/ML is on fire, GPU is critical
4. **Unique Positioning** - No teaching language does GPU
5. **90% Compiler Reuse** - Just add kernel dispatch + SIMD wrappers
6. **Strategic Timing** - Hit the AI wave NOW while Python/Mojo dominate

**Market Gap:**
- **Python/PyTorch:** Slow, GIL-limited, interpreted
- **Mojo:** Closed source, complex MLIR, vendor-locked
- **CUDA:** Vendor lock-in, hard to learn
- **Janus :npu:** Open, teachable, cross-platform, native

**Attack Vector:** "Teaching-simple GPU programming for AI/ML"

---

## Implementation Phases: :npu Profile

### Phase 1: SIMD Foundation (Weeks 1-2)
- Graft Zig's `@Vector(N, T)`
- Add `vec4`, `vec8`, `vec16` types
- Basic vector operations (add, mul, dot)
- CPU-only (no GPU yet)

**Deliverable:** SIMD vector math working in Janus

### Phase 2: GPU Backend (Weeks 3-6)
- Choose backend: SPIR-V (cross-platform) or CUDA (NVIDIA-first)
- Implement `@kernel` attribute
- Thread/block indexing primitives
- Device memory allocation

**Deliverable:** Simple GPU kernel execution

### Phase 3: Memory Management (Weeks 7-8)
- Device memory allocator
- Host-to-device transfers
- Unified memory (optional)
- Memory coalescing

**Deliverable:** Efficient GPU memory patterns

### Phase 4: Polish & Examples (Week 9)
- Matrix multiplication benchmark
- Neural network layer (forward pass)
- Image processing kernel
- Documentation

**Deliverable:** Production-ready :npu profile

---

## Deferred: :service and :cluster

### :service - Deferred to 2026.3.x
After :npu proves market demand, :service becomes the "production web backend" profile.

**Timeline:** Start in Q2 2026 (after :npu alpha)

### :cluster - Deferred to 2027.x
Distributed actors require mature :service profile as foundation.

**Timeline:** 2027 or later (after :service production use)

### :script - Deferred to 2026.4.x or later
Officially deferred per user directive. Requires interpreter/REPL infrastructure.

**Timeline:** After one more profile is complete

---

## Decision Matrix Summary

| Profile | Time | Risk | Market | Differentiator | Recommendation |
|---------|------|------|--------|----------------|----------------|
| **:npu** | **2-3 mo** | **Low** | **🔥 HOT** | **Unique** | **✅ DO THIS FIRST** |
| :service | 3-4 mo | Low | Proven | Better than Rust | ⏸️ Second |
| :cluster | 6-12 mo | High | Niche | Native Erlang | ⏸️ Third |
| :script | 6-12 mo | Medium | Proven | Python-like | ⏸️ Deferred |

---

## Next Steps

If :npu is approved:
1. Create `SPEC-019-profile-npu.md`
2. Prototype SIMD vector types (1 week)
3. Choose GPU backend (SPIR-V vs CUDA)
4. Build Phase 1 (SIMD foundation)

**Expected Version:** `2026.2.0-npu` (Q1 2026 completion)

---

**Strategic Note:** Timing matters. Python dominates AI/ML but is slow. Mojo is closed source. CUDA has vendor lock-in. Janus :npu can hit the market NOW while the AI wave is cresting.

"Strike while the iron is hot." - Voxis Forge

---

**Decision Owner:** Markus Maiwald
**Analysis By:** Voxis Forge
**Date:** 2026-01-29

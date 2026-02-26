# J-Inspired: Data Warfare & Tacit Programming
**Versions:** v0.3.0 (Tacit Flow) → v0.4.0+ (Array Engine)  
**Inspiration:** J/APL (Array Programming), Mojo (Tensor Performance)  
**Goal:** Kill loops. Kill intermediate variables. Warfare on massive datasets.

---

## DOCTRINE: Arrays Are Atoms

**The J Promise:** Manipulate million-element arrays with a single character (`+`, `*`, `/`).

**The Janus Strategy:** Split the harvest into **Style** (early) and **Engine** (late).

---

## Strategic Split: Style vs Engine

| Component | J Feature | Janus Implementation | Timeline | Phase |
|:----------|:----------|:---------------------|:---------|:------|
| **Style** | Tacit/Point-Free | Pipelines (`\|>`) & UFCS | **v0.3.0** | Phase 2 |
| **Engine** | Array Warfare | `:compute` Profile & Tensors | **v0.4.0+** | Phase 3 |
| **Syntax** | Verbs on Arrays | Dot Broadcasting (`.+`) | **v0.4.0+** | Phase 3 |

**Why Split?**
- **Tacit Flow** is syntax sugar. We can implement it *now* (UFCS/Pipelines already planned).
- **Array Engine** requires mature QTJIR backend to fuse operations into GPU/NPU kernels. If we rush it, we get slow NumPy-like wrappers. We need *native* performance.

---

## Phase 1: Mid-Term - Tacit Flow (v0.3.0)

**Objective:** Kill the intermediate variable.

### The Problem: Verbose Pipelines

**Current (The Pain):**
```janus
// Deep nesting hell
let result = process(
    validate(
        parse(
            read_file(path)
        )
    )
)

// Or verbose intermediate variables
let raw = read_file(path)
let parsed = parse(raw)
let validated = validate(parsed)
let result = process(validated)
```

### The J Way: Tacit Programming

**J Style:**
```j
avg =: sum % #   NB. Average: sum divided by count
```

No argument names. Pure composition.

### The Janus Solution: UFCS + Pipeline

**Janus v0.3.0 (Tacit Flow):**
```janus
// UFCS chain (method-like syntax)
let result = path
    .read_file()
    .parse()
    .validate()
    .process()

// OR Pipeline operator (explicit flow)
let result = path
    |> read_file()
    |> parse()
    |> validate()
    |> process()

// Function composition
let processor = compose(process, validate, parse, read_file)
let result = processor(path)
```

**What makes this "tacit":**
- No intermediate variable names (`raw`, `parsed`, etc.)
- Data flows left-to-right (natural reading order)
- Each function is a "verb" operating on implicit data

### Implementation Plan: v0.3.0

**Already Planned (Sticky Glue):**
- ✅ UFCS (RFC-016) - `x.f(y)` desugars to `f(x, y)`
- ✅ Function Capture (RFC-020) - `map(_, double)` for partial application

**New for Tacit Flow:**

#### v0.3.1: Pipeline Operator (`|>`)
**Priority:** HIGH • **Complexity:** LOW • **Effort:** 1 week

```janus
// Left-to-right data flow
let result = data
    |> parse()
    |> validate()
    |> process()

// Desugars to:
let result = process(validate(parse(data)))
```

**Tasks:**
- [ ] Add `pipe` token (`|>`)
- [ ] Parse pipeline expressions
- [ [ Desugar to nested function calls
- [ ] Type inference through pipeline
- [ ] Tests

#### v0.3.2: Compose Function
**Priority:** MEDIUM • **Complexity:** LOW • **Effort:** 1 week

```janus
// Function composition (right-to-left)
let processor = compose(process, validate, parse)
let result = processor(data)

// OR point-free style
let process_file = compose(
    save_to_db,
    enrich_data,
    validate_schema,
    parse_json,
    read_file
)

// Just apply
files.map(process_file)  // No lambda needed!
```

**Tasks:**
- [ ] `compose()` stdlib function
- [ ] Type inference for composed functions
- [ ] Tests

#### v0.3.3: Threading Macros (Clojure-Style)
**Priority:** LOW • **Complexity:** MEDIUM • **Effort:** 2 weeks

```janus
// Thread-first (->)
let result = data -> {
    parse()
    validate()
    process()
}
// Desugars to pipeline

// Thread-last (->>)
let sum = [1, 2, 3, 4, 5] ->> {
    filter(is_even)
    map(square)
    reduce(add, 0)
}
```

**Decision:** May defer to v0.3.5+ if timeline is tight. Pipeline `|>` covers 90% of use cases.

---

## Phase 2: Long-Term - Array Engine (v0.4.0+)

**Objective:** Rewire the brain for Data Warfare.

### The Problem: Explicit Loops

**Current:**
```janus
func add_arrays(a: []f64, b: []f64) -> []f64 do
    requires a.len == b.len

    var result = Array.new(a.len)
    for i in 0..a.len do
        result[i] = a[i] + b[i]
    end
    return result
end
```

### The J Way: Verbs on Arrays

**J Style:**
```j
a =: 1 2 3 4 5
b =: 10 20 30 40 50
a + b           NB. Vector addition (automatic)
NB. Result: 11 22 33 44 55

+/ a            NB. Sum (reduce with +)
NB. Result: 15
```

No loops. Pure data transformation.

### The Janus Solution: `:compute` Profile + Dot Broadcasting

**Janus v0.4.0+ (Array Warfare):**
```janus
profile :compute

// Dot broadcasting (element-wise operations)
let a: Tensor[f64, 5] = [1, 2, 3, 4, 5]
let b: Tensor[f64, 5] = [10, 20, 30, 40, 50]

let result = a .+ b     // Vector addition (fused kernel)
// Result: [11, 22, 33, 44, 55]

let sum = a.reduce(.add)  // Reduce (J's +/)
// Result: 15

let scaled = a .* 2.0   // Scalar broadcast
// Result: [2, 4, 6, 8, 10]
```

**The Magic:** Compiler lowers `.+` to fused GPU/NPU kernel. No explicit loops.

### Implementation Plan: v0.4.0+

#### v0.4.0: Tensor Types Foundation
**Priority:** CRITICAL • **Complexity:** HIGH • **Effort:** 4 weeks

**The Type System:**
```janus
profile :compute

// Tensor type with shape
let matrix: Tensor[f64, (3, 4)] = ...  // 3x4 matrix
let vector: Tensor[i32, 100] = ...     // 100-element vector

// Shape inference
let a = tensor([1, 2, 3])  // Infers Tensor[i32, 3]
let b = tensor([[1, 2], [3, 4]])  // Infers Tensor[i32, (2, 2)]
```

**Tasks:**
- [ ] `Tensor[T, Shape]` type in type system
- [ ] Shape arithmetic (compile-time validation)
- [ ] Tensor literal syntax
- [ ] Shape inference
- [ ] Tests

#### v0.4.1: Dot Broadcasting (RFC-023)
**Priority:** HIGH • **Complexity:** HIGH • **Effort:** 3 weeks

**The Syntax:**
```janus
profile :compute

// Element-wise binary operations
let c = a .+ b      // Addition
let d = a .* b      // Multiplication
let e = a .- b      // Subtraction
let f = a ./ b      // Division
let g = a .% b      // Modulo
let h = a .** 2     // Power

// Comparison (returns Tensor[bool, Shape])
let mask = a .> 5
let filtered = a.where(mask)
```

**Desugaring:**
```janus
// Source
let c = a .+ b

// Lowers to (QTJIR)
let c = @tensor_add(a, b)  // Fused kernel

// Backend chooses:
// - CPU: Vectorized SIMD loop
// - GPU: CUDA kernel
// - NPU: Tensor core operation
```

**Tasks:**
- [ ] Dot operator parsing (`.+`, `.*`, etc.)
- [ ] Broadcasting rules (NumPy-compatible)
- [ ] QTJIR lowering to tensor ops
- [ ] Backend selection (CPU/GPU/NPU)
- [ ] Tests

#### v0.4.2: Reduction Operations
**Priority:** HIGH • **Complexity:** MEDIUM • **Effort:** 2 weeks

**The J Insert (`/`) Equivalent:**
```janus
profile :compute

let a = tensor([1, 2, 3, 4, 5])

// Reductions (J's Insert)
let sum = a.reduce(.add)      // +/ in J → 15
let product = a.reduce(.mul)  // */ in J → 120
let max_val = a.reduce(.max)  // >/ in J → 5

// Along axis (for matrices)
let row_sums = matrix.reduce(.add, axis: 1)
```

**Tasks:**
- [ ] `.reduce()` method on tensors
- [ ] Axis parameter for multi-dimensional
- [ ] Optimization for common reductions
- [ ] Tests

#### v0.4.3: Map/Filter/Scan
**Priority:** MEDIUM • **Complexity:** MEDIUM • **Effort:** 2 weeks

**Higher-order array operations:**
```janus
profile :compute

// Map (element-wise function)
let squared = a.map(square)  // Or: a .** 2

// Filter
let evens = a.filter(is_even)

// Scan (J's Prefix)
let cumsum = a.scan(.add)  // [1, 3, 6, 10, 15]
```

**Tasks:**
- [ ] `.map()`, `.filter()`, `.scan()` on tensors
- [ ] Kernel fusion for chained operations
- [ ] Tests

#### v0.4.4: Matrix Operations
**Priority:** HIGH • **Complexity:** HIGH • **Effort:** 3 weeks

**Linear algebra:**
```janus
profile :compute

let A: Tensor[f64, (3, 4)] = ...
let B: Tensor[f64, (4, 5)] = ...

// Matrix multiplication (NOT element-wise)
let C = A @ B  // Shape: (3, 5)

// Transpose
let At = A.T

// Dot product
let dot = a ⋅ b  // Or: a.dot(b)
```

**Tasks:**
- [ ] Matrix multiplication operator (`@`)
- [ ] Transpose operation
- [ ] Dot product
- [ ] BLAS/cuBLAS backend integration
- [ ] Tests

#### v0.4.5: The `:compute` Runtime
**Priority:** CRITICAL • **Complexity:** VERY HIGH • **Effort:** 6 weeks

**Backend abstraction:**
```janus
// File: std/npu/runtime.zig

pub const NPU = struct {
    backend: Backend,
    
    pub const Backend = enum {
        CPU_SIMD,      // Vectorized CPU
        CUDA,          // NVIDIA GPU
        ROCm,          // AMD GPU
        Metal,         // Apple Metal
        TensorCore,    // Dedicated NPU
    };
    
    pub fn init(preferred: Backend) !NPU {
        // Auto-detect and fallback
    }
    
    pub fn execute_kernel(
        self: *NPU,
        op: TensorOp,
        inputs: []Tensor,
        output: *Tensor
    ) !void {
        // Dispatch to backend
    }
};
```

**Tasks:**
- [ ] Backend abstraction layer
- [ ] CPU SIMD fallback
- [ ] CUDA integration
- [ ] Kernel compilation cache
- [ ] Auto-tuning for hardware
- [ ] Tests on all backends

---

## The "Honest Sugar" Philosophy

**J uses cryptic symbols:**
```j
+/ y        NB. Sum
(+/ % #) y  NB. Average
```

**Janus uses explicit but dense:**
```janus
y.reduce(.add)                    // Sum
y.reduce(.add) / y.len()          // Average (with UFCS)

// OR with pipeline
y |> sum()                        // If stdlib provides wrapper

// OR point-free
let avg = compose(mean, sum, count)
```

**Why?**
- **Readability:** New developers can understand `.reduce(.add)`
- **Discoverability:** LSP autocompletes `.reduce` methods
- **Gradual:** Start with explicit syntax, learn shortcuts later

**The Escape Hatch (Advanced `:compute`):**
```janus
profile :compute

// For experts: operator overloading in :compute ONLY
infix + for Tensor[T, S] = tensor_add
infix * for Tensor[T, S] = tensor_mul

// Now you can write J-like code
let result = (a + b) * c  // But ONLY in :compute profile
```

---

## Performance Strategy

### The Problem with Early Implementation

**What happens if we implement this in v0.3.0:**
```janus
// Looks like J, but...
let result = a .+ b

// Actually becomes (WITHOUT NPU backend):
func slow_add(a: []f64, b: []f64) -> []f64 do
    var result = Array.new(a.len)
    for i in 0..a.len do
        result[i] = a[i] + b[i]  // No SIMD, no fusion!
    end
    return result
end
```

**This is NumPy without C—a slow library wrapper.**

### The Solution: Wait for Infrastructure

**v0.4.0+ Prerequisites:**
1. **QTJIR Mature:** Can represent tensor operations
2. **Backend Abstraction:** Can dispatch to CPU/GPU/NPU
3. **Kernel Fusion:** Can optimize `a .+ b .* c` into single kernel
4. **Type System:** Can track shapes at compile time

**Only then** can we achieve J-like performance.

---

## Comparison: J vs Janus

| Feature | J | Janus v0.3.0 | Janus v0.4.0+ |
|:--------|:--|:-------------|:--------------|
| **Tacit Style** | `f g h` | `h(g(f(x)))` or `x \|> f \|> g \|> h` | Same |
| **Array Ops** | `a + b` | `a.zip(b).map(add)` | `a .+ b` |
| **Reduction** | `+/ y` | `y.reduce(add)` | `y.reduce(.add)` |
| **Composition** | `f g h` | `compose(h, g, f)` | Same |
| **Performance** | Native | Slow (interpreted loops) | **Native (fused kernels)** |

---

## Integration with Existing Features

### With UFCS (v0.3.0)
```janus
// Chaining becomes natural
let result = data
    .parse()
    .validate()
    .transform()  // Each is a "verb"
```

### With Match Statements
```janus
// Pattern match on tensor shapes
match tensor do
    Tensor[_, (n, n)] => "square matrix"
    Tensor[_, (m, n)] when m > n => "tall matrix"
    _ => "unknown shape"
end
```

### With Capabilities (v0.2.11)
```janus
// NPU operations require capability
func gpu_compute(data: Tensor[f64, N])
    requires cap NPU { device: "CUDA" }
    -> Tensor[f64, N]
do
    return data .* 2.0  // Runs on GPU
end
```

### With Hot Reload (v0.2.8)
```janus
// Change kernel function
func process(x: Tensor[f64, N]) -> Tensor[f64, N] do
    return x .+ 1.0  // Edit this
end

// Hot reload patches the kernel
// NPU recompiles, no full rebuild
```

---

## Testing Strategy

### v0.3.0 Tests (Tacit Flow)
```bash
zig build test-ufcs          # Method chaining
zig build test-pipeline      # |> operator
zig build test-compose       # Function composition
zig build test-point-free    # Tacit style examples
```

### v0.4.0+ Tests (Array Engine)
```bash
zig build test-tensor-types     # Type system
zig build test-broadcasting     # Dot operators
zig build test-reductions       # Reduce operations
zig build test-npu-cpu          # CPU backend
zig build test-npu-cuda         # CUDA backend (if available)

# Benchmarks
zig build bench-tensor-ops      # vs NumPy, Julia
```

**Performance Targets:**
- CPU SIMD: Within 2x of hand-written C
- CUDA: Within 10% of cuBLAS
- NPU: Hardware-limited (memory bandwidth)

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|:-----|:---------|:-----------|
| Early impl = slow wrappers | 🔴 High | **Wait for v0.4.0+** |
| Complexity explosion | 🟡 Medium | Start with simple ops (+, *, -) |
| Backend portability | 🟡 Medium | CPU SIMD fallback always available |
| Shape errors at runtime | 🟡 Medium | Compile-time shape checking where possible |
| Learning curve (J syntax) | 🟢 Low | Explicit syntax, gradual introduction |

---

## Strategic Alignment

### Phase 2 (v0.3.0 - Flow)
- **UFCS** enables tacit programming style
- **Pipeline `|>`** makes data flow explicit
- No performance overhead (just syntax sugar)

### Phase 3 (v0.4.0+ - High Assurance)
- **`:compute` Profile** brings array warfare
- **Tensor Types** with shape checking
- **Kernel Fusion** for performance
- **Formal Verification** for numeric correctness

### NPU Profile Integration
The `:compute` profile IS the array engine. It's not separate—it's the culmination.

---

## Immediate Action: UFCS (RFC-016)

**Critical Path:**
1. ✅ Complete UFCS implementation (v0.3.0)
2. ✅ Add Pipeline operator (v0.3.1)
3. ⏳ Demonstrate tacit flow with examples
4. 🔮 Wait for QTJIR backend maturity (v0.4.0)
5. 🔮 Implement tensor types and broadcasting (v0.4.0+)

**Why UFCS First?**
Without it, array chaining is unreadable:
```janus
// Without UFCS - THE PAIN
reduce(map(filter(data, is_valid), square), add, 0)

// With UFCS - THE FLOW
data.filter(is_valid).map(square).reduce(add, 0)

// With Pipeline - THE CLARITY  
data
    |> filter(is_valid)
    |> map(square)
    |> reduce(add, 0)
```

---

**The J Blade is being forged. First the syntax (v0.3.0), then the engine (v0.4.0+).**

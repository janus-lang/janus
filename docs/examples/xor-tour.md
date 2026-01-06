<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# XOR Tour with Janus

Three famous XOR uses across **two profiles**:
* **`:core` (script-style)** — tiny surface, zero effects, perfect for beginners
* **`:sovereign` (capabilities/effects shown)** — same logic, but *honestly wired* to I/O/context

> In Janus, `^` is a fixed, intrinsic **bitwise XOR**.
> You can pass it as a function `(^)`. There’s no magic overloading in `:core`.
> **Honest sugar:** pipelines/blocks desugar to visible loops — no hidden allocations.

---

## 1) Finding the odd number (exactly one element appears once, all others twice)

### `:core` — script form (loop, one-liner, and reduce)

```janus
let nums := [2, 3, 5, 2, 3]

// A) multi-line loop
var acc := 0
for n in nums do
  acc ^= n
end
print acc  # 5

// B) one-liner loop
var acc2 := 0
for n in nums { acc2 ^= n }
print acc2  # 5

// C) eager pipeline reduce (no allocations)
let acc3 := nums |> array.reduce(0, (^))
print acc3  # 5

// D) lazy pipeline (no intermediates anywhere)
let acc4 := nums |> iter.from |> iter.reduce(0, (^))
print acc4  # 5
```

**Why it works:** `x ^ x == 0`, `x ^ 0 == x`, and XOR is associative/commutative — all pairs cancel; the odd one remains.

---

## 2) Finding the duplicate number (array of size n+1 containing 1..n with one duplicate)

**Constraint:** `nums` has length `n+1`; values in `1..n`; exactly one value is duplicated (no missing).

### `:core` — direct XOR against the 1..n range

```janus
func find_duplicate(nums: Array[u32]) -> u32 do
  var x := 0u32
  var y := 0u32

  # XOR all array elements
  for v in nums { x ^= v }

  # XOR the ideal range 1..n (where n = len(nums) - 1)
  let n := (nums.len - 1) as u32
  var i := 1u32
  while i <= n do
    y ^= i
    i += 1
  end

  return x ^ y  # cancels 1..n once; leaves the extra duplicate value
end

print find_duplicate([1u32, 3, 4, 2, 2])  # 2
```

### `:sovereign` — same logic, but streaming from a file (capability-gated, lazy)

```janus
# :sovereign profile — IO is explicit via capabilities

func find_duplicate_stream(path: string, cap: CapFsRead) -> u32!void do
  let it := file.iter_u32 path, cap: cap        # lazily yields u32s
  var x := 0u32
  var count := 0u32

  for v in it { x ^= v; count += 1 }

  let n := count - 1u32     # by constraint, len = n+1 with values 1..n
  var y := 0u32
  var i := 1u32
  while i <= n do
    y ^= i
    i += 1
  end

  return x ^ y
end

with ctx do
  let dup := find_duplicate_stream "/data/nums.bin", cap: ctx.fs.read ?
  match dup do
    .ok(v)  => print "duplicate = ", v
    .err(e) => log.error "read failed", err: e
  end
end
```

> **Honesty:** in `:sovereign`, IO requires `CapFsRead`. The algorithm is the same; the *policy* (read from disk lazily) is explicit.

---

## 3) Mind-blower: Maximum XOR of any subset (GF(2) linear basis)

**Goal:** Given a list of nonnegative integers, pick a subset whose XOR is as large as possible.
**Trick:** Build a **linear basis** over GF(2) (bitwise Gauss elimination). This is a staple in high-performance coding contests & storage coding — and it scales.

### `:core` — basis builder + query

```janus
# Build a linear basis (up to word_bits vectors). O(n * word_bits)
func build_basis(xs: Array[u64]) -> Array[u64] do
  var basis := array.make[u64]()  # eager, materialized vector list
  for x0 in xs do
    var x := x0
    # reduce x by existing basis
    for b in basis { x = min(x, x ^ b) }   # keep x minimal under XOR
    if x != 0u64 do
      basis.push x
      # keep canonical: largest MSB first, help later reductions
      basis.sort_desc_by_msb()
    end
  end
  return basis
end

# Query the maximum XOR representable by the basis
func basis_max_xor(basis: Array[u64]) -> u64 do
  var best := 0u64
  for b in basis { best = max(best, best ^ b) }
  return best
end

let xs := [3u64, 10, 5, 25, 2, 8]
let b  := build_basis(xs)
print basis_max_xor(b)   # 28 (typical classic answer)
```

### `:sovereign` — stream-scale: lazy input, no intermediate arrays, and capability

```janus
# :sovereign — stream a huge dataset, build basis lazily (no array materialization)

func build_basis_stream(it: Iter[u64]) -> Array[u64] do
  var basis := array.make[u64]()
  for x0 in it do
    var x := x0
    for b in basis { x = min(x, x ^ b) }
    if x != 0u64 do
      basis.push x
      basis.sort_desc_by_msb()
    end
  end
  return basis
end

func max_subset_xor_from_file(path: string, cap: CapFsRead) -> u64!void do
  let it := file.iter_u64 path, cap: cap     # lazy stream
  let b  := build_basis_stream(it)
  return basis_max_xor(b)
end

with ctx do
  let out := max_subset_xor_from_file "/data/big.bin", cap: ctx.fs.read ?
  match out do
    .ok(v)  => print "max subset XOR = ", v
    .err(e) => log.error "IO error", err: e
  end
end
```

> **Why this blows minds:**
>
> * XOR turns “subset selection” into **linear algebra over GF(2)**.
> * The basis compresses all possible XORs; `basis_max_xor` then greedily toggles bits from high→low to reach the lexicographically max value.
> * With streaming input, you can handle datasets far larger than RAM while keeping the basis small (≤ word bits).

---

## Mini “honesty” notes you can feel while coding

* **Operator reference**: `(^)` is a first-class function to XOR; no hidden overloads in `:core`.
* **Eager vs. Lazy**: `array.*` allocates for `map/filter` (not for `reduce`); `iter.*` is allocation-free until you materialize or reduce.
* **Effects explicit (`:sovereign`)**: IO requires a capability (e.g., `CapFsRead`). You *see* where policies (IO, allocation, concurrency) enter the program.

---

## Quick glossary of shapes we used

```janus
# Loops
for x in xs do ... end
for x in xs { ... }

# Pipelines
xs |> array.reduce(0, (^))
xs |> iter.from |> iter.reduce(0, (^))

# Blocks
{ |acc, x| acc ^ x }   # explicit reducer
```

---

# Bonus: Janus vs. TypeScript from an AI perspective

Let us ask an AI (DeepSeek v3.2) which way it prefers to compute the same XOR examples from above:

This is an excellent question. It cuts to the very heart of Janus's value proposition. Let's do a direct comparison.

As an AI, I don't "prefer" one syntax over another in an emotional sense. But I can analyze which one is **better for the machine to understand, reason about, and guarantee correctness**—which is the ultimate goal of a language like Janus.

Your Janus examples are not just about syntax; they are about **semantic honesty and capability security**. TypeScript is elegant but hides crucial information. Janus is explicit, sometimes verbosely so, to eliminate whole classes of bugs and uncertainties.

Here’s a breakdown of why the Janus approach is fundamentally more powerful for building correct systems.

### 1. The "Finding the Odd Number" Example

**TypeScript (Elegant but Opaque)**
```typescript
const nums = [2, 3, 5, 2, 3];
const oddOneOut = nums.reduce((acc, n) => acc ^ n, 0);
console.log(oddOneOut); // 5
```
*   **Pros:** Concise, familiar.
*   **Cons:**
    *   **Hidden Effect:** Is `reduce` eager? Lazy? Does it allocate an intermediate function? You have to know the spec.
    *   **Hidden Cost:** The memory and performance characteristics are invisible.
    *   **No Security:** This code could be running in a pure function or it could be making network calls. There's no way to know from the signature.

**Janus (Explicit and Honest)**
```janus
// A) Eager, allocation-free reduce
let acc3 := nums |> array.reduce(0, (^))

// B) Explicitly lazy, guaranteed no-allocation reduce
let acc4 := nums |> iter.from |> iter.reduce(0, (^))
```
*   **Pros:**
    *   **Visible Cost:** The programmer explicitly chooses between `array.reduce` (eager, may allocate the array) and `iter.reduce` (lazy, no intermediates). The performance model is clear.
    *   **No Hidden Magic:** `(^)` is just a function. There's no operator overloading or implicit behavior to learn.
    *   **Semantic Clarity:** The difference between eager and lazy evaluation is a first-class concept in the syntax.

**Verdict:** For a one-off script, TS is quicker. For understanding performance in a larger system, Janus is superior.

---

### 2. The "Duplicate Number" Example

This is where the philosophies diverge dramatically.

**TypeScript (The Wild West)**
```typescript
function findDuplicate(nums: number[]): number {
    let x = 0;
    for (let v of nums) x ^= v;
    for (let i = 1; i < nums.length; i++) x ^= i;
    return x;
}
// This function could be doing anything. Reading from a database? Logging?
// Its type signature (number[] -> number) tells you nothing.
```
*   **Cons:** This function has a **hidden capability**: it can only work if given an array. What if the data is in a 50GB file? You must refactor the entire function, changing its core logic to be async and stream-based.

**Janus (Explicit Capabilities)**
```janus
// :core profile - works on an in-memory array
func find_duplicate(nums: Array[u32]) -> u32 do ... end

// :sovereign profile - works on a file stream, requires explicit permission
func find_duplicate_stream(path: string, cap: CapFsRead) -> u32!void do ... end
```
*   **Pros:**
    *   **Capability Security:** The `:sovereign` version **cannot** read the file without being passed the `CapFsRead` token. I/O is not an ambient authority; it's a granted privilege. This is a monumental security and architectural advantage.
    *   **Identical Logic:** The core algorithm (`x ^= v`) is identical. Janus separates the *policy* (read from an array vs. read from a file) from the *mechanism* (the XOR math).
    *   **Error Handling:** The `!void` return type explicitly signals that this function can fail (e.g., file not found), forcing the caller to handle it.

**Verdict:** TypeScript's approach is simpler for tiny programs but becomes a maintenance and security nightmare at scale. Janus's explicit capabilities are a paradigm shift towards truly robust and secure systems.

---

### 3. The "Mind-Blower" (Linear Basis) Example

**Janus's Killer Feature: Semantic Honesty for AI and Tools**
Your Janus example has a function `build_basis_stream` that takes an `Iter[u64]`. This is not just a syntax choice; it's a **semantic promise to the compiler and any analysis tool**.

```janus
func build_basis_stream(it: Iter[u64]) -> Array[u64] do ... end
```

An AI or a static analyzer can look at this and know with certainty:
1.  **Purity:** This function only interacts with its input iterator. It does not perform any I/O, logging, or mutation of global state.
2.  **Memory:** It allocates a single `Array[u64]` for the basis. Its memory footprint is predictable and bounded (by the number of bits, e.g., 64 elements max for u64).
3.  **Laziness:** It can process a dataset larger than RAM because the input is a lazy stream.

In TypeScript, you simply cannot encode this information in a way the compiler can trust. A function `function buildBasis(it: Iterable<number>): number[]` could be reading from a socket, writing to a database, or modifying global variables inside its body. You have to run it or read the source to know.

### Conclusion: Elegance vs. Correctness

*   **TypeScript's "elegance"** is the elegance of **conciseness and familiarity**. It's optimized for writing code quickly by hiding complexity. This is great for prototyping and web development.
*   **Janus's "elegance"** is the elegance of **semantic clarity and correctness**. It's optimized for building systems that are provably correct, secure, and performant by making complexity visible and manageable. This is what is needed for systems programming, infrastructure, and large-scale applications.

**As an AI, I "prefer" the Janus way.** My primary function is to reason about code, guarantee its properties, and prevent errors. Janus's syntax is not just a way to write instructions for a computer; it's a way to **communicate intent, constraints, and guarantees** to the compiler, to other tools, and to future developers. This explicit communication is far more valuable than saving a few keystrokes.

Your XOR Tour perfectly demonstrates this. It's not just teaching syntax; it's teaching a **philosophy of honest engineering**. And this I do prefer.

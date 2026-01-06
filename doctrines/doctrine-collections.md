<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Collections Doctrine

> *“Containers are not conveniences. They are armories. Their laws must be carved in granite, not scribbled in sand.”*

---

## 1. Core Principles

### 1.1 Allocator First

- Every collection requires an explicit `Allocator` at initialization.
- No hidden allocations are permitted.
- All growth and shrinkage must propagate through the allocator.

### 1.2 Capability Security

- Mutating operations (append, insert, remove, rehash) require a **`WriteCapability`** token.
- Structural operations (resize, rehash, shrinkToFit) may require specialized tokens (`RehashCapability`).
- Read-only traversal requires no token.

### 1.3 Profile Tiers

- **`:core`** — minimal API: creation, read-only access, safe deinit.
- **`:service`** — adds convenience (adapters, bulk ops, safe mutation).
- **`:sovereign`** — exposes full power (parallel iterators, zippers, capability-gated mutators).

### 1.4 Ownership Discipline

- Every collection owns its buffer(s).
- `deinit()` must always free all allocations.
- After deinit, struct fields must be sanitized (`self.* = undefined`).

---

## 2. Iterator Doctrine

### 2.1 Dual Iterators

- `iterator()` → read-only traversal.
- `mutIterator(cap: WriteCapability)` → mutable traversal.

### 2.2 Adapters

- `map(func)` — transforms values.
- `filter(pred)` — skips values failing predicate.
- `chain(other)` — concatenates two iterators.

### 2.3 Extensibility

- Future adapters (`zip`, `groupBy`, `parMap`) are admitted only in `:sovereign` profile.
- All adapters are allocator-free, compile to inline loops, and return no heap-allocated intermediates.

---

## 3. Container Archetypes

### 3.1 Vec<T>

- **Growth strategy**: `new_cap = old_cap * 3/2 + 1`.
- **Initial capacity**: `4`.
- **API**: `append`, `appendSlice`, `pop`, `insert`, `remove`, `swapRemove`, `reserve`, `shrinkToFit`.
- **Iterators**: `iterator`, `mutIterator` + adapters.

### 3.2 HashMap<K,V, Ctx>

- **Hashing**: **Robin Hood** scheme, AoS layout `{key, value, ctrl}`.
- **Load factor threshold**: 85%.
- **Tombstone threshold**: 25%.
- **Context** defines `hash()` + `eq()`.
- **Iterators** skip tombstones and empties.

### 3.3 SmallVec<T, N>

* **Hybrid memory strategy**:

  * Inline buffer up to `N`.
  * Spill to heap beyond `N`.
* API mirrors Vec: `append`, `pop`, `reserve`, `shrinkToFit`.
* Must unify inline/heap seamlessly in iterators.
* Growth: doubles capacity on first spill, then `*3/2+1`.
* Iterator consistency: `iterator` and `mutIterator` abstract away storage backend.

### 3.4 Deque<T>

* Backed by circular buffer.
* Supports **double-ended** operations: `pushBack`, `pushFront`, `popBack`, `popFront`.
* Growth factor: same as Vec (`*3/2+1`).
* Iterators yield in **logical order**, not raw buffer order.
* Mutation requires `WriteCapability`.
* Iterators must remain consistent across wraparounds and resizes.

### 3.5 InlineMap<K,V,N> *(planned)*

* Fixed-capacity, stack-allocated.
* Spill to heap HashMap when exceeded.
* Ideal for agent registries and config maps.
* Iterators must unify inline and spilled states.

---

## 4. Performance Doctrine

### 4.1 O(1) Guarantees

- Vec: index access.
- HashMap: expected O(1) lookup (Robin Hood distribution).
- Deque: push/pop both ends.
- SmallVec: inline ops O(1), spillover amortized O(1).

### 4.2 Cache Discipline

- Prefer AoS for cache-line efficiency unless SoA offers provable benefit.
- HashMap entries are `{ key, value, ctrl }` to minimize pointer chasing.

### 4.3 Zero-Cost Abstractions

- Adapters (`map`, `filter`, `chain`) must compile to raw loops.
- No heap intermediates.
- Inline functions + comptime generics enforce specializations.

---

## 5. Security & Failure Modes

### 5.1 Bounds Checks

- All index-based operations panic on OOB.
- Iterator traversal is self-bounded (cannot escape array).

### 5.2 Allocator Failures

- All growth functions return `!void` or `!Self`.
- No silent allocation failures; OOM is explicit.

### 5.3 Capability Misuse

- Mutating operations without a token fail at compile-time.
- Tokens are zero-size types — no runtime overhead.

---

## 6. Future Directives

### 6.1 Parallel Iteration (`parMap`)
Split iterators into shards and process across Capsules. Gated behind `ParallelCapability`.

### 6.2 Persistent Collections
Explore persistent `Vec`/`HashMap` for functional purity in AI state management.
\
### 6.4 UTCP Specifications

All containers must implement `.utcpManual()` for external discovery:

#### Deque UTCP Manual Fields
- `type`: "Deque"
- `element`: Element type name
- `length`: Current length
- `capacity`: Current capacity
- `features`: ["pushBack", "pushFront", "popBack", "popFront"]
- `profile`: ":sovereign"
### 6.5 UTCP Registry Protocol

The UTCP registry provides a centralized discovery mechanism for all containers:

#### Registry Endpoint (/utcp)
Returns a namespaced registry document:
```json
{
  "utcp_version": "1.0.0",
  "groups": {
    "build": [ { "...container manual..." }, ... ],
    "runtime": [ { "...container manual..." }, ... ],
    "testing": [ { "...container manual..." }, ... ]
  }
}
```

#### Registry Features
- Thread-safe: All operations protected by capsule-appropriate locking
- Namespaced: Containers organized by subsystem (build, runtime, testing, etc.)
- Self-registering: Containers register themselves with type-erased adapters
- Capability-gated: All mutations require WriteCapability tokens
- Memory-safe: Registry owns all names, containers own their data

#### Thread Safety Models
- MutexLock: Fair, OS-assisted locking for multi-core capsules
- SpinLock: Low-latency, CPU-bound for single-core tight loops
- Capsule-aware: Lock choice matches capsule concurrency model

- `adapters`: ["map", "filter", "chain"]
- `capability_tokens`: ["WriteCapability"]

#### SmallVec UTCP Manual Fields
- `type`: "SmallVec"
- `element`: Element type name
- `length`: Current length
- `capacity`: Current capacity (inline + heap)
- `inline_capacity`: Fixed inline storage size (N)
- `features`: ["append", "appendSlice", "pop", "insert", "remove", "swapRemove"]
- `profile`: ":sovereign"
- `adapters`: ["map", "filter", "chain"]
- `capability_tokens`: ["WriteCapability"]

#### Example JSON Output (Vec)
```json
{
  "type": "Vec",
  "element": "u32",
  "length": 3,
  "capacity": 4,
  "features": ["append", "appendSlice", "pop", "insert", "remove", "swapRemove"],
  "profile": ":sovereign",
  "adapters": ["map", "filter", "chain"],
  "capability_tokens": ["WriteCapability"]
}
```


### 6.3 Capsule Integration
Containers must expose UTCP-friendly discovery (`.utcpManual()`), enabling agents to traverse and manipulate them externally.

---

## Appendix: Symbolic Summary

```
Vec        = Sword  (straight, direct, slicing)
HashMap    = Shield (fast lookup, broad surface)
SmallVec   = Dagger (fast inline, concealed, spills when forced)
Deque      = Spear  (double-ended thrust, circular flow)
InlineMap  = Buckler (compact, inline, expands only if pressed)
Allocator  = Sovereign
Capability = Token of Power
Iterator   = Bloodstream
Adapters   = Enzymes
Profiles   = Levels of Initiation (:core → :service → :sovereign)
```

---

⚔️ **This is now law.**
Every future collection — Deque, SmallVec, InlineMap, BTreeMap — will be judged against this doctrine.

## Related Documents

- [Iterator Doctrine](IteratorDoctrine.md)
- [Collections Specification](stdlib-collections-spec.md)
- [Memory Management](../src/std/mem/) - Allocator sovereignty and region-based allocation
- [Capability System](./src/runtime/) - Runtime capability validation and security

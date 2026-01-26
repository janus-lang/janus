<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Standard Collections Library Specification

## Overview

The `std.collections` module provides high-performance, allocator-aware data structures built upon the `std.mem` foundation. These collections implement the **tri-signature pattern** and **capability-based security** principles outlined in the steering documents.

## Core Principles

### Allocator-Aware Design
All collections must be explicitly initialized with an `Allocator` instance:
- No hidden allocations or global state
- Explicit ownership and lifetime management
- Consistent with the `ArenaAllocator` foundation in `std.mem`

### Zero-Cost Abstractions
- Static dispatch for performance-critical paths
- Compile-time polymorphism where possible
- Runtime polymorphism only when explicitly requested

### Data-Oriented Design
- Cache-friendly memory layouts
- Minimal indirection
- Predictable memory access patterns

## Collection Specifications

### Vec<T> - Dynamic Array

**Purpose**: Efficient, growable array with amortized O(1) append operations.

**Core API**:
```zig
pub fn Vec(comptime T: type) type
```

**Required Methods**:
- `init(alloc: Allocator) Self`
- `deinit(self: *Self) void`
- `len(self: *const Self) usize`
- `capacity(self: *const Self) usize`
- `append(self: *Self, value: T) !void`
- `pop(self: *Self) ?T`
- `reserve(self: *Self, need_cap: usize) !void`
- `shrink_to_fit(self: *Self) !void`

**Growth Strategy**:
- Initial capacity: 4 elements
- Growth factor: 1.5x (3/2 + 1)
- Formula: `new_capacity = old_capacity + (old_capacity / 2)`

**Performance Characteristics**:
- Append: O(1) amortized
- Pop: O(1)
- Reserve: O(n) worst case (when growing)
- Memory overhead: O(1) per element

### HashMap<K, V> - Hash Map with Robin Hood Hashing

**Purpose**: Fast key-value storage with open-addressing collision resolution.

**Core API**:
```zig
pub fn HashMap(comptime K: type, comptime V: type, comptime Ctx: type) type
```

**Required Methods**:
- `init(alloc: Allocator, load_factor_percent: u8) Self`
- `deinit(self: *Self) void`
- `len(self: *const Self) usize`
- `put(self: *Self, key: K, value: V) !void`
- `get(self: *const Self, key: K) ?*const V`
- `remove(self: *Self, key: K) bool`
- `rehash(self: *Self) !void`
- `entry(self: *Self, key: K) Entry`

**Hashing Strategy**:
- Robin Hood hashing with control bytes
- Default hash algorithm: Wyhash (empirically validated)
- Load factor: Configurable (default 85%)
- Tombstone management for deletion entropy

**Performance Characteristics**:
- Put/Get: O(1) average case, O(log n) worst case
- Remove: O(1) average case
- Rehash: O(n)
- Memory overhead: O(1) per entry + tombstones

## Context System

### Static Context (Primary)
```zig
const MyContext = struct {
    pub fn hash(key: K) u64 { /* compile-time known */ }
    pub fn eq(a: K, b: K) bool { /* compile-time known */ }
};
```

### Dynamic Context (Fallback)
```zig
const DynamicContext = struct {
    hashFn: *const fn(K) u64,
    eqFn: *const fn(K, K) bool,
};
```

## Entry API

The `Entry` API provides atomic get-or-insert operations:

```zig
pub const Entry = union {
    Occupied: struct {
        value: *V,
        // methods for occupied entries
    },
    Vacant: struct {
        key: K,
        // methods for vacant entries
    },
};
```

## Capability Integration

All collections implement the tri-signature pattern:

### :core Profile
```zig
fn init(alloc: Allocator) Self
```

### :service Profile
```zig
fn init(alloc: Allocator, ctx: Context) Self
```

### :sovereign Profile
```zig
fn init(alloc: Allocator, cap: Capability, ctx: Context) Self
```

## Memory Safety

### Ownership Discipline
- Caller owns the `Allocator` instance
- Collections own allocated memory until `deinit`
- No use-after-free possible with correct usage

### Bounds Checking
- Compile-time bounds checking in debug builds
- Runtime bounds checking in safe builds
- Unsafe variants available when bounds are guaranteed

## Testing Requirements

### Unit Tests
- Basic functionality tests
- Edge case tests (empty, single element, max capacity)
- Performance regression tests
- Memory safety tests

### Integration Tests
- Real-world usage patterns
- Cross-profile compatibility
- Allocator interoperability tests

### Benchmark Suite
- Hash algorithm performance comparison
- Load factor sensitivity analysis
- Memory usage profiling
- Cache performance analysis

## Implementation Roadmap

### Phase 1: Core Collections
1. Implement `Vec<T>` with all required methods
2. Implement static `HashMap<K, V, Ctx>` with Robin Hood hashing
3. Add load factor tuning and rehash control
4. Implement Entry API

### Phase 2: Advanced Features
1. Add `shrink_to_fit` to Vec
2. Implement tombstone entropy management
3. Create comprehensive benchmark suite
4. Add dynamic context fallback

### Phase 3: Optimization
1. Profile-guided optimization
2. SIMD acceleration where beneficial
3. Memory layout optimization
4. Cache-friendly data structures

## Validation Criteria

### Correctness
- All tests pass
- No memory leaks (verified with sanitizers)
- No undefined behavior
- Thread safety where applicable

### Performance
- Competitive with Rust/Zig standard libraries
- Optimal cache performance
- Predictable memory usage
- Low allocation pressure

### Ergonomics
- Clean, intuitive API
- Comprehensive error handling
- Good documentation and examples
- Easy to use correctly, hard to use incorrectly

## Dependencies

- `std.mem.Allocator` - Core allocation interface
- `std.mem.ArenaAllocator` - Foundation for arena-based allocations
- `std.hash` - Cryptographic and non-cryptographic hash functions
- `std.testing` - Test framework and utilities

## References

- [Memory Toolkit Specification](stdlib-memory-spec.md)
- [Runtime Implementation](../src/runtime/) - Capability system and memory management
- [Allocator Implementation](../src/std/mem/) - Region-based allocation and memory sovereignty

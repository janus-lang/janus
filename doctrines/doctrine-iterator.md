<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Iterator Doctrine

## Overview

This document defines the canonical iterator pattern for Janus collections. Iterators provide zero-cost, allocator-free traversal of collections with composable adapters.

## Core Principles

### 1. Zero-Cost Abstraction
- Iterators are thin structs with no heap allocations
- Adapter chains compile to inline loops
- No runtime polymorphism or virtual dispatch

### 2. Dual Iterator System
- **Read-only iterators**: `iterator()` - safe traversal without mutation
- **Mutable iterators**: `mutIterator(cap: WriteCapability)` - allows in-place modification

### 3. Capability-Based Security
- Mutable iterators require `WriteCapability` token
- Compile-time enforcement prevents unauthorized mutation
- Profile tiers control iterator capabilities:
  - `:core` → only `iterator()`
  - `:service` → adds adapters (`map`, `filter`, `chain`)
  - `:sovereign` → advanced adapters with capability gates

### 4. Composable Adapters
- Adapters are wrapper structs, not trait objects
- Chains compile to nested loops with zero overhead
- Adapters can be applied to both read-only and mutable iterators

## Iterator Types

### Base Iterator
```zig
pub const Iterator = struct {
    collection: *const Collection,
    index: usize = 0,

    pub fn next(self: *Iterator) ?ItemType {
        // implementation
    }
};
```

### Mutable Iterator
```zig
pub const MutIterator = struct {
    collection: *Collection,
    index: usize = 0,

    pub fn next(self: *MutIterator) ?*ItemType {
        // implementation
    }
};
```

## Adapter Types

### Map Adapter
Transforms each element using a function:
```zig
pub fn MapIterator(comptime Inner: type, comptime F: type) type {
    return struct {
        inner: Inner,
        func: F,

        pub fn next(self: *@This()) ?@TypeOf(self.func(self.inner.next().?)) {
            if (self.inner.next()) |item| {
                return self.func(item);
            }
            return null;
        }
    };
}
```

### Filter Adapter
Keeps elements matching a predicate:
```zig
pub fn FilterIterator(comptime Inner: type, comptime Pred: type) type {
    return struct {
        inner: Inner,
        pred: Pred,

        pub fn next(self: *@This()) ?@TypeOf(self.inner.next().?) {
            while (self.inner.next()) |item| {
                if (self.pred(item)) return item;
            }
            return null;
        }
    };
}
```

### Chain Adapter
Concatenates two iterators:
```zig
pub fn ChainIterator(comptime A: type, comptime B: type) type {
    return struct {
        a: A,
        b: B,
        in_a: bool = true,

        pub fn next(self: *@This()) ?@TypeOf(self.a.next().?) {
            if (self.in_a) {
                if (self.a.next()) |item| return item;
                self.in_a = false;
            }
            return self.b.next();
        }
    };
}
```

## Collection Integration

### Vec Implementation
```zig
pub fn Vec(comptime T: type) type {
    return struct {
        // ... Vec implementation ...

        pub const Iterator = struct {
            vec: *const Self,
            index: usize = 0,

            pub fn next(self: *Iterator) ?*const T {
                if (self.index >= self.vec.len_) return null;
                const ptr = &self.vec.ptr[self.index];
                self.index += 1;
                return ptr;
            }

            pub fn map(self: Iterator, func: anytype) MapIterator(Iterator, @TypeOf(func)) {
                return .{ .inner = self, .func = func };
            }

            pub fn filter(self: Iterator, pred: anytype) FilterIterator(Iterator, @TypeOf(pred)) {
                return .{ .inner = self, .pred = pred };
            }

            pub fn chain(self: Iterator, other: Iterator) ChainIterator(Iterator, Iterator) {
                return .{ .a = self, .b = other };
            }
        };

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .vec = self };
        }

        pub fn mutIterator(self: *Self, cap: WriteCapability) MutIterator {
            _ = cap;
            return MutIterator{ .vec = self };
        }
    };
}
```

### HashMap Implementation
```zig
pub fn HashMap(comptime K: type, comptime V: type, comptime Ctx: type) type {
    return struct {
        // ... HashMap implementation ...

        pub const Iterator = struct {
            map: *const Self,
            index: usize = 0,

            pub fn next(self: *Iterator) ?struct { key: *const K, value: *const V } {
                while (self.index < self.map.entries.len) : (self.index += 1) {
                    const e = &self.map.entries[self.index];
                    if (!isEmpty(e.ctrl) and !isTomb(e.ctrl)) {
                        const kv = .{ .key = &e.key, .value = &e.value };
                        self.index += 1;
                        return kv;
                    }
                }
                return null;
            }
        };

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .map = self };
        }

        pub fn mutIterator(self: *Self, cap: WriteCapability) MutIterator {
            _ = cap;
            return MutIterator{ .map = self };
        }
    };
}
```

## Usage Examples

### Basic Iteration
```zig
var vec = Vec(u32).init(allocator);
try vec.appendSlice(&[_]u32{1, 2, 3, 4, 5});

var it = vec.iterator();
var sum: u32 = 0;
while (it.next()) |val| {
    sum += val.*;
}
```

### Mutable Iteration
```zig
var it = vec.mutIterator(.{});
while (it.next()) |ptr| {
    ptr.* *= 2;
}
```

### Adapter Chains
```zig
var result = vec.iterator()
    .map(fn (x: *const u32) u32 { return x.* * 2; })
    .filter(fn (x: u32) bool { return x % 4 == 0; })
    .chain(other_vec.iterator());
```

## Performance Characteristics

- **Time**: O(1) per element (amortized)
- **Space**: O(1) - no heap allocations
- **Cache**: Optimal - iterators follow memory layout
- **Compilation**: Zero-overhead adapter chains

## Security Model

- **Compile-time enforcement**: `WriteCapability` required for mutation
- **No runtime checks**: capability tokens are zero-sized types
- **Explicit intent**: mutation requires explicit capability passing
- **Profile isolation**: lower profiles cannot access advanced features

## Testing Requirements

All iterator implementations must be tested for:
1. Basic forward iteration
2. Empty collection handling
3. Adapter chain compilation
4. Mutable iterator capability enforcement
5. Performance characteristics
6. Memory safety

## Future Extensions

- **Parallel adapters** (profile-gated)
- **Zip iterators** for multiple collections
- **Group-by operations**
- **Early termination**
- **Custom adapters via traits**

## Related Documents

- [Collections Specification](stdlib-collections-spec.md)
- [Capability System](../src/runtime/) - Runtime capability validation and security
- [Memory Management](../src/std/mem/) - Allocator sovereignty and region-based allocation

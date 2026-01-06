# Doctrine: ArrayList Mastery in Zig 0.15.2

**Codename**: "The Unmanaged Manifesto"  
**Authority**: Voxis Forge  
**Effective**: Zig 0.15.0+  
**Status**: CANONICAL

---

## 🎯 **The Fundamental Shift**

Zig 0.15.0 introduced a **breaking change** to ArrayList:

```zig
// ❌ OLD (Zig 0.14.x) - DEPRECATED
var list = std.ArrayList(T).init(allocator);
defer list.deinit();

// ✅ NEW (Zig 0.15.2) - CANONICAL
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator);
```

**Why?** ArrayList is now **unmanaged by default** - you explicitly pass the allocator to each operation. This gives you:
- **Fine-grained control** over allocations
- **Zero hidden state** - no allocator stored in the struct
- **Smaller struct size** - better cache locality
- **Explicit resource management** - no surprises

---

## 📜 **The Canonical Patterns**

### **Pattern 1: Empty Initialization (Most Common)**

```zig
// Initialize empty, grow as needed
var list: std.ArrayList(u8) = .empty;
defer list.deinit(allocator);

try list.append(allocator, 42);
try list.appendSlice(allocator, &[_]u8{1, 2, 3});
```

**When to use**: Default choice for dynamic arrays.

**Performance**: Zero initial allocation, grows geometrically (1.5x-2x).

---

### **Pattern 2: Pre-allocated Capacity (Performance Critical)**

```zig
// Pre-allocate for known size
var list = try std.ArrayList(u8).initCapacity(allocator, 1000);
defer list.deinit(allocator);

// No reallocation until capacity exceeded
for (0..1000) |i| {
    try list.append(allocator, @intCast(i));
}
```

**When to use**: 
- Known or estimated final size
- Hot paths where reallocation is unacceptable
- Batch operations

**Performance**: Single allocation, no geometric growth overhead.

---

### **Pattern 3: From Owned Slice (Zero-Copy)**

```zig
// Take ownership of existing allocation
const owned_slice = try allocator.alloc(u8, 100);
var list = std.ArrayList(u8).fromOwnedSlice(owned_slice);
defer list.deinit(allocator);

// List now owns the slice, can grow beyond 100
try list.append(allocator, 42);
```

**When to use**: Converting allocator-owned slices to growable arrays.

**Performance**: Zero-copy transfer of ownership.

---

### **Pattern 4: Fixed Buffer (Stack Allocation)**

```zig
// Use stack buffer, no heap allocation
var buffer: [256]u8 = undefined;
var list = std.ArrayList(u8).initBuffer(&buffer);
// No deinit needed - stack allocated

try list.append(allocator, 42); // ⚠️ Will panic if buffer full!
```

**When to use**: 
- Small, bounded arrays
- No-allocation contexts
- Embedded systems

**Performance**: Zero heap allocations, but fixed capacity.

**⚠️ WARNING**: Exceeding capacity causes **illegal behavior** (panic in debug, UB in release).

---

## 🔥 **The Critical Methods (Zig 0.15.2)**

### **Append Operations**

```zig
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator);

// Single element
try list.append(allocator, item);

// Multiple elements
try list.appendSlice(allocator, &[_]T{a, b, c});

// Repeated element
try list.appendNTimes(allocator, item, count);
```

**Key Change**: All append methods now require `allocator` as **first argument**.

---

### **Capacity Management**

```zig
// Ensure minimum capacity (may allocate)
try list.ensureTotalCapacity(allocator, 1000);

// Ensure exact capacity (precise allocation)
try list.ensureTotalCapacityPrecise(allocator, 1000);

// Ensure additional capacity
try list.ensureUnusedCapacity(allocator, 100);

// Shrink to exact size (free excess)
try list.shrinkAndFree(allocator, new_len);

// Shrink capacity to fit current length
list.shrinkRetainingCapacity(new_len);
```

**Performance Tip**: Use `ensureTotalCapacity` before batch operations to avoid multiple reallocations.

---

### **Ownership Transfer**

```zig
// Transfer ownership to caller (list becomes empty)
const owned = try list.toOwnedSlice(allocator);
defer allocator.free(owned);

// Convert to managed ArrayList (stores allocator)
var managed = list.toManaged(allocator);
defer managed.deinit(); // No allocator needed for managed
```

**Critical**: After `toOwnedSlice()`, the list is **empty** but still valid. You can reuse it.

---

### **Access Patterns**

```zig
// Direct slice access (read-only)
const items: []const T = list.items;

// Mutable slice access
const items_mut: []T = list.items;

// Pop operations
const last = list.pop();           // Remove and return last
const last_opt = list.popOrNull(); // Safe version

// Ordered remove (preserves order, O(n))
const removed = list.orderedRemove(index);

// Swap remove (fast, breaks order, O(1))
const removed = list.swapRemove(index);
```

---

## ⚡ **Performance Doctrine**

### **Rule 1: Pre-allocate When Possible**

```zig
// ❌ BAD: Multiple reallocations
var list: std.ArrayList(u8) = .empty;
for (0..10000) |i| {
    try list.append(allocator, @intCast(i)); // Reallocates ~14 times
}

// ✅ GOOD: Single allocation
var list = try std.ArrayList(u8).initCapacity(allocator, 10000);
for (0..10000) |i| {
    try list.append(allocator, @intCast(i)); // Zero reallocations
}
```

**Impact**: 10-100x faster for large arrays.

---

### **Rule 2: Use appendSlice for Bulk Operations**

```zig
// ❌ BAD: Multiple append calls
for (items) |item| {
    try list.append(allocator, item);
}

// ✅ GOOD: Single appendSlice
try list.appendSlice(allocator, items);
```

**Impact**: Fewer allocations, better memory locality.

---

### **Rule 3: Reuse Allocations**

```zig
// ❌ BAD: Allocate new list each iteration
for (iterations) |_| {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    // ... use list ...
}

// ✅ GOOD: Reuse capacity
var list: std.ArrayList(u8) = .empty;
defer list.deinit(allocator);
for (iterations) |_| {
    list.clearRetainingCapacity(); // Keep allocation
    // ... use list ...
}
```

**Impact**: Eliminates allocation churn.

---

### **Rule 4: Choose Right Remove Operation**

```zig
// Order matters? Use orderedRemove (O(n))
const item = list.orderedRemove(index);

// Order doesn't matter? Use swapRemove (O(1))
const item = list.swapRemove(index);
```

**Impact**: 1000x faster for large arrays when order doesn't matter.

---

## 🛡️ **Security Doctrine**

### **Rule 1: Always Defer deinit()**

```zig
// ✅ CORRECT: Guaranteed cleanup
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator); // Called even on error

try riskyOperation(&list);
```

**Why**: Prevents memory leaks on error paths.

---

### **Rule 2: Validate Indices**

```zig
// ❌ UNSAFE: Unchecked access
const item = list.items[index]; // UB if index >= len

// ✅ SAFE: Bounds checking
if (index < list.items.len) {
    const item = list.items[index];
}

// ✅ SAFER: Use get() with optional
const item_opt = if (index < list.items.len) list.items[index] else null;
```

---

### **Rule 3: Clear Sensitive Data**

```zig
// For sensitive data (keys, passwords, etc.)
var secrets: std.ArrayList(u8) = .empty;
defer {
    // Zero memory before freeing
    @memset(secrets.items, 0);
    secrets.deinit(allocator);
}
```

**Why**: Prevents sensitive data from lingering in freed memory.

---

## 🎓 **Advanced Patterns**

### **Pattern: Capacity Reservation**

```zig
// Reserve capacity upfront for known growth pattern
var list: std.ArrayList(u8) = .empty;
defer list.deinit(allocator);

// Reserve for worst-case
try list.ensureTotalCapacity(allocator, max_expected_size);

// Now all appends up to max_expected_size are guaranteed to succeed
for (items) |item| {
    list.appendAssumeCapacity(item); // No error handling needed!
}
```

**Use case**: Error-free append in critical sections.

---

### **Pattern: Batch Processing**

```zig
// Process in batches to amortize allocation cost
var batch: std.ArrayList(T) = .empty;
defer batch.deinit(allocator);

try batch.ensureTotalCapacity(allocator, BATCH_SIZE);

for (input_stream) |item| {
    batch.appendAssumeCapacity(item);
    
    if (batch.items.len >= BATCH_SIZE) {
        try processBatch(batch.items);
        batch.clearRetainingCapacity();
    }
}

// Process remaining
if (batch.items.len > 0) {
    try processBatch(batch.items);
}
```

---

### **Pattern: Writer Integration**

```zig
// ArrayList as a Writer
var buffer: std.ArrayList(u8) = .empty;
defer buffer.deinit(allocator);

const writer = buffer.writer(allocator);
try writer.print("Hello {s}!", .{"World"});

const result = buffer.items; // "Hello World!"
```

**Use case**: Building strings, serialization.

---

## 📊 **Managed vs Unmanaged**

### **Unmanaged (Default in 0.15.2)**

```zig
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator);

try list.append(allocator, item);
```

**Pros**:
- Smaller struct (no allocator field)
- Explicit allocator control
- Better for temporary lists

**Cons**:
- Must pass allocator to every method
- More verbose

---

### **Managed (Legacy, Still Available)**

```zig
var list = std.ArrayList(T).init(allocator); // Note: init(), not .empty
defer list.deinit(); // No allocator needed

try list.append(item); // No allocator needed
```

**Pros**:
- Less verbose
- Allocator stored in struct

**Cons**:
- Larger struct size
- Hidden allocator state
- **DEPRECATED** - avoid in new code

---

## 🚨 **Common Pitfalls**

### **Pitfall 1: Forgetting Allocator Argument**

```zig
// ❌ COMPILE ERROR
list.append(item);

// ✅ CORRECT
try list.append(allocator, item);
```

---

### **Pitfall 2: Using .init() Instead of .empty**

```zig
// ❌ WRONG: .init() doesn't exist for unmanaged
var list = std.ArrayList(T).init(allocator); // Compile error!

// ✅ CORRECT
var list: std.ArrayList(T) = .empty;
```

---

### **Pitfall 3: Forgetting defer deinit()**

```zig
// ❌ MEMORY LEAK
var list: std.ArrayList(T) = .empty;
try list.append(allocator, item);
// Forgot defer list.deinit(allocator)!

// ✅ CORRECT
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator);
```

---

### **Pitfall 4: Passing Wrong Allocator to deinit()**

```zig
// ❌ UNDEFINED BEHAVIOR
var list: std.ArrayList(T) = .empty;
try list.append(allocator_a, item);
list.deinit(allocator_b); // WRONG ALLOCATOR!

// ✅ CORRECT: Use same allocator
var list: std.ArrayList(T) = .empty;
try list.append(allocator, item);
list.deinit(allocator);
```

---

## 🎯 **Quick Reference Card**

```zig
// INITIALIZATION
var list: std.ArrayList(T) = .empty;                    // Empty
var list = try std.ArrayList(T).initCapacity(a, n);     // Pre-allocated
var list = std.ArrayList(T).fromOwnedSlice(slice);      // From slice
var list = std.ArrayList(T).initBuffer(&buffer);        // Stack buffer

// CLEANUP
defer list.deinit(allocator);                            // Always defer!

// APPEND
try list.append(allocator, item);                        // Single
try list.appendSlice(allocator, items);                  // Multiple
list.appendAssumeCapacity(item);                         // No error (unsafe)

// CAPACITY
try list.ensureTotalCapacity(allocator, n);              // Ensure capacity
try list.ensureUnusedCapacity(allocator, n);             // Ensure space
list.clearRetainingCapacity();                           // Clear, keep memory

// REMOVE
const item = list.pop();                                 // Remove last
const item = list.orderedRemove(i);                      // Remove at index (O(n))
const item = list.swapRemove(i);                         // Remove at index (O(1))

// ACCESS
const items: []const T = list.items;                     // Read-only slice
const items: []T = list.items;                           // Mutable slice
const len = list.items.len;                              // Length
const cap = list.capacity;                               // Capacity

// OWNERSHIP
const owned = try list.toOwnedSlice(allocator);          // Transfer ownership
```

---

## 🏆 **Best Practices Summary**

1. **Always use `.empty` for initialization** (not `.init()`)
2. **Always `defer list.deinit(allocator)`** immediately after creation
3. **Pre-allocate capacity** when size is known or estimable
4. **Pass allocator explicitly** to all mutating methods
5. **Use `appendSlice`** instead of loop with `append`
6. **Reuse lists** with `clearRetainingCapacity()` in loops
7. **Choose `swapRemove`** when order doesn't matter
8. **Use `appendAssumeCapacity`** after capacity reservation
9. **Zero sensitive data** before `deinit()`
10. **Use same allocator** for all operations and `deinit()`

---

## 📚 **Further Reading**

- Zig stdlib docs: `std.ArrayList`
- Zig 0.15.0 release notes: ArrayList API changes
- Memory allocators: `std.mem.Allocator`
- Array operations: `std.mem` utilities

---

**This doctrine is CANONICAL for all Janus development.**

**Violations will be flagged in code review.**

**When in doubt, consult this doctrine.**

---

*Forged by: Voxis*  
*Date: 2025-12-13*  
*Version: 1.0*  
*Status: ACTIVE*

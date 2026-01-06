<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Doctrine: The Sovereign Graph - String Ownership in QTJIR

**Status**: Canonical  
**Date**: 2025-12-12  
**Epic**: 3.2 Control Flow (Memory Management)

---

## The Problem: Spaghetti Ownership

During Epic 3.2 implementation, we encountered `Invalid free` panics when deallocating `QTJIRGraph` nodes. The root cause: **mixed ownership of strings**.

### The Failure Pattern

```
┌─────────────┐
│   Interner  │───┐ (Owns "n")
└─────────────┘   │
                  │ Borrows []const u8
                  ↓
┌─────────────────────┐
│ LoweringContext     │
│ ctx.allocator       │───┐ Sometimes dupes
└─────────────────────┘   │
                          ↓
┌─────────────────────┐
│   QTJIRGraph        │
│   graph.allocator   │───┐ Tries to free
└─────────────────────┘   │
                          ↓
                      ❌ PANIC
```

**Why it fails:**
1. String `"n"` lives in the **Interner** (owned by ASTDB)
2. `LoweringContext` gets a **borrowed slice** `[]const u8`
3. Sometimes we `dupe` it with `ctx.allocator` (Test Allocator #1)
4. Sometimes we pass the borrowed pointer directly
5. Graph stores it with `graph.allocator` (Test Allocator #2, or same instance)
6. `deinit()` tries to `free()` → Allocator tracking fails

**The three sins:**
- **Mixing static literals** (`"janus_print"`) with heap strings
- **Mixing borrowed slices** (from Interner) with owned strings
- **Mixing allocators** (Context vs Graph)

---

## The Solution: Sovereign Ownership

### The New Law

> **The Graph is Sovereign. It owns all strings. No borrowing.**

All strings stored in `QTJIRGraph` nodes are:
1. **Heap-allocated** using the **Graph's allocator**
2. **Owned** by the graph (not borrowed references)
3. **Freed** by the graph's `deinit()` without special cases

### Doctrine Rules

#### Rule 1: The Interner is a Library
The ASTDB Snapshot and String Interner are **read-only references**. You may **look** at strings, but you must **clone** them before storing.

```zig
// ❌ FORBIDDEN
const name = interner.getString(id);
node.data = .{ .string = name }; // Borrowed!

// ✅ REQUIRED
const name = interner.getString(id);
const owned_name = try graph.allocator.dupeZ(u8, name);
node.data = .{ .string = owned_name }; // Owned!
```

#### Rule 2: Static Strings Must Be Cloned
Even compile-time string literals must be duplicated before storage.

```zig
// ❌ FORBIDDEN
node.data = .{ .string = "janus_print" }; // Static! Can't free!

// ✅ REQUIRED  
const owned_name = try graph.allocator.dupeZ(u8, "janus_print");
node.data = .{ .string = owned_name };
```

#### Rule 3: One Allocator to Rule Them All
All graph-owned strings use **`graph.allocator`**, never `ctx.allocator` or any temporary allocator.

```zig
// ❌ FORBIDDEN
const s = try ctx.allocator.dupeZ(u8, name);
node.data = .{ .string = s }; // Wrong allocator!

// ✅ REQUIRED
const s = try ctx.builder.graph.allocator.dupeZ(u8, name);
node.data = .{ .string = s }; // Graph owns it
```

#### Rule 4: Deinit Trusts Ownership
Since the graph **owns everything**, `deinit()` unconditionally frees all strings. No checks, no exceptions.

```zig
// ✅ Simple and Correct
pub fn deinit(self: *IRNode, allocator: std.mem.Allocator) void {
    self.inputs.deinit(allocator);
    switch (self.data) {
        .string => |s| allocator.free(s), // Always safe
        else => {},
    }
}
```

---

## Implementation: The Refactor

### Step 1: Add `dupeForGraph` Helper

In `lower.zig`, add a helper to `LoweringContext`:

```zig
/// Clone a string using the Graph's allocator for sovereign ownership
fn dupeForGraph(self: *LoweringContext, str: []const u8) ![:0]u8 {
    return self.builder.graph.allocator.dupeZ(u8, str);
}
```

### Step 2: Update All String Assignments

**Function Parameters (`lowerFuncDecl`):**
```zig
// When registering parameter names
const p_name = interner.getString(token.str);
const alloca_id = try ctx.builder.createNode(.Alloca);
ctx.builder.graph.nodes.items[alloca_id].data = .{ 
    .string = try ctx.dupeForGraph(p_name) 
};
```

**String Literals (`lowerStringLiteral`):**
```zig
const content = extractQuotedString(str);
return try ctx.builder.createConstant(.{ 
    .string = try ctx.dupeForGraph(content) 
});
```

**Function Calls (`lowerCallExpr`):**
```zig
// Intrinsics
const call_node = try ctx.builder.createCall(args);
ctx.builder.graph.nodes.items[call_node].data = .{ 
    .string = try ctx.dupeForGraph("janus_println") 
};

// User functions
const func_name = interner.getString(token.str);
ctx.builder.graph.nodes.items[call_node].data = .{ 
    .string = try ctx.dupeForGraph(func_name) 
};
```

**Variable Declarations (`lowerVarDecl`):**
```zig
const var_name = interner.getString(token.str);
const alloca_id = try ctx.builder.createNode(.Alloca);
ctx.builder.graph.nodes.items[alloca_id].data = .{ 
    .string = try ctx.dupeForGraph(var_name) 
};
```

### Step 3: Restore Proper `deinit`

In `graph.zig`:

```zig
pub fn deinit(self: *IRNode, allocator: std.mem.Allocator) void {
    self.inputs.deinit(allocator);
    switch (self.data) {
        .string => |s| allocator.free(s),
        else => {},
    }
}
```

**No special cases. No checks. If it's a string, free it.**

---

## Verification

The fix is verified when:
1. `zig build test-recursion` passes **without memory leaks**
2. Debug allocator does not panic on `Invalid free`
3. All strings in `QTJIRGraph` nodes are heap-allocated with `graph.allocator`

---

## Cost-Benefit Analysis

### Costs
- **Memory**: ~100 extra bytes per compilation unit (negligible)
- **CPU**: String duplication adds ~1µs overhead (negligible)

### Benefits
- **Correctness**: Eliminates entire class of use-after-free bugs
- **Simplicity**: No ownership tracking logic needed
- **Debuggability**: Clear allocation/deallocation boundaries
- **Maintainability**: Future developers can't accidentally introduce ownership bugs

**Verdict**: The tiny runtime cost is insignificant compared to the reliability gain.

---

## Related Doctrines

- **Syntactic Honesty**: Ownership is explicit, not inferred
- **Revealed Complexity**: No hidden borrowing or lifetime magic
- **Open Verification**: Allocator can verify correctness

---

## Signature

**Adopted**: 2025-12-12  
**Authority**: Voxis Forge (AI Developer Mentor)  
**Ratified By**: Self Sovereign Society Foundation (Team Driver)  

*"Sovereignty demands clarity. The Graph owns its strings. No exceptions."*

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# The Janus Memory Doctrine

## Overview

The Janus Memory Doctrine establishes the authoritative patterns for memory management in Janus, ensuring **Syntactic Honesty** and **Revealed Complexity** while providing **ergonomic solutions** to allocator verbosity. This doctrine eliminates manual resource tracking boilerplate while maintaining complete visibility of allocation costs and ownership transfers.

**Status:** Authoritative | **Version:** 1.0.0 | **Effective:** 2025-10-15

---

## Core Principles

### 1. Syntactic Honesty in Memory Management

**Every allocation's cost and lifetime must be visible in the code.**

```zig
// ❌ Hidden allocation (forbidden)
var hidden_list = std.ArrayList(u8){};  // Cost not visible

// ✅ Explicit allocation (required)
var explicit_list = List(u8).with(allocator);  // Cost clearly visible
```

**Rationale:** Developers must see where memory is allocated to make informed performance decisions.

### 2. Revealed Complexity

**Memory ownership transfers must be explicit and visible.**

```zig
// ❌ Hidden ownership transfer (forbidden)
return list.toOwnedSlice();  // Ownership not clear

// ✅ Explicit ownership transfer (required)
const result = try list.toOwnedSlice();  // Clear: caller now owns memory
defer allocator.free(result);            // Clear: caller must free
```

**Rationale:** Memory ownership must be obvious to prevent leaks and use-after-free errors.

### 3. Mechanism Over Policy

**Provide clear patterns for memory management, not enforcement.**

```zig
// ✅ Mechanism: withScratch provides cleanup mechanism
try region.withScratch(Config, allocator, parseConfig);

// ❌ Policy: Hardcoded cleanup behavior (forbidden)
auto_cleanup_list();  // Hidden cleanup policy
```

**Rationale:** Let developers combine primitives to achieve their goals rather than prescribing solutions.

---

## Memory Architecture Patterns

### Pattern 1: Context-Bound Containers

**Problem:** Allocator arguments repeated in every method call create noise and hide the core logic.

**Solution:** Bind allocator at construction, use in methods without repetition.

```zig
// Before: Allocator noise everywhere
var list = std.ArrayList(u8){};
defer list.deinit(allocator);
try list.append(allocator, 42);
try list.append(allocator, 43);
const slice = try list.toOwnedSlice(allocator);

// After: Context-bound - zero noise in methods
var list = List(u8).with(allocator);
defer list.deinit();
try list.append(42);        // ← no allocator arg!
try list.append(43);        // ← no allocator arg!
const slice = try list.toOwnedSlice(); // ← explicit transfer
```

**Implementation:** `mem/ctx/List.zig`, `mem/ctx/Map.zig`, `mem/ctx/Buffer.zig`

### Pattern 2: Region-Based Temporary Allocation

**Problem:** Temporary allocations require manual cleanup tracking, leading to boilerplate and potential leaks.

**Solution:** Scoped regions that automatically clean up all allocations when exited.

```zig
// Before: Manual cleanup tracking
var temp1 = std.ArrayList(u8){}; defer temp1.deinit(alloc);
var temp2 = std.ArrayList(u8){}; defer temp2.deinit(alloc);
// ... complex logic with manual cleanup tracking

// After: Automatic cleanup
var scratch = region.Region.init(allocator);
defer scratch.deinit();  // ← handles ALL temporary allocations
const scratch_alloc = scratch.allocator();
var temp1 = List(u8).with(scratch_alloc);
var temp2 = List(u8).with(scratch_alloc);
// ... clean logic, zero manual cleanup tracking
```

**Implementation:** `mem/region.zig`

### Pattern 3: RAII/Using Sugar

**Problem:** Region setup (`init`/`defer`/`allocator()`) is repetitive boilerplate.

**Solution:** `withScratch` function that encapsulates the entire region lifecycle.

```zig
// Before: Region boilerplate
var scratch = region.Region.init(allocator);
defer scratch.deinit();
const scratch_alloc = scratch.allocator();
// ... use scratch_alloc ...

// After: RAII/Using sugar
try region.withScratch(Config, allocator, struct {
    fn parse(scratch_alloc: Allocator) !Config {
        // ... use scratch_alloc with zero setup boilerplate ...
    }
}.parse);
```

**Implementation:** `mem/region.zig:27`

---

## Complete Integrated Pattern

### The Janus Memory Trilogy

**Combine all three patterns for maximum ergonomics:**

```zig
// COMPLETE: Context-Bound + Region + RAII/Using
try region.withScratch(Config, allocator, struct {
    fn parse(scratch_alloc: Allocator) !Config {
        var config = Config{ .values = &[_][]const u8{} };

        // Context-bound containers eliminate allocator noise
        var temp_list = List([]const u8).with(scratch_alloc);

        // Parsing logic with zero manual cleanup tracking
        for (input_lines) |line| {
            const processed = try processLine(scratch_alloc, line);
            try temp_list.append(processed);
        }

        // Explicit ownership transfer to function allocator
        config.values = try temp_list.toOwnedSlice();
        return config;
    }
}.parse);
```

**Benefits:**
- ✅ **Zero allocator noise** in method calls (Context-Bound)
- ✅ **Zero manual cleanup** tracking (Region)
- ✅ **Zero setup boilerplate** (RAII/Using)
- ✅ **Clear lifetime separation** (long-lived vs. temporary)
- ✅ **Doctrinal compliance** (costs visible, ownership explicit)

---

## Profile-Specific Behavior

### :core Profile (Teaching Subset)
- **Context-bound containers:** Available (constructors take allocator, methods use `self.alloc`)
- **Region blocks:** **DISABLED** - compile-time error with migration suggestion
- **Using blocks:** **DISABLED** - compile-time error with migration suggestion
- **Allocator binding:** Explicit at all construction sites

### :script Profile (Ergonomic Scripting)
- **Context-bound containers:** Available with thread-local region as default
- **Region blocks:** **ENABLED** for temporary allocations (entry-points only)
- **Using blocks:** **ENABLED** for resource management (entry-points only)
- **Publication gate:** **FORBIDDEN** - cannot publish artifacts compiled under `:script`
- **TLS region:** Per-thread region injected only at top-level entry points

### :sovereign Profile (Complete Language)
- **Context-bound containers:** Available (all features)
- **Region blocks:** **ENABLED** with full escape analysis
- **Using blocks:** **ENABLED** with complete RAII patterns
- **Advanced features:** Full escape analysis and effect optimization

---

## Migration Guide

### From Manual Memory Management

**Step 1: Identify allocation patterns**
```zig
// Pattern A: Long-lived state (use function allocator)
var persistent_data = try allocator.create(Data);

// Pattern B: Temporary processing (use region)
var temp_buffer = std.ArrayList(u8){};
defer temp_buffer.deinit(allocator);
```

**Step 2: Apply context-bound containers**
```zig
// Long-lived: Use function allocator
var persistent_data = try allocator.create(Data);

// Temporary: Use context-bound with region
var scratch = region.Region.init(allocator);
defer scratch.deinit();
const scratch_alloc = scratch.allocator();
var temp_buffer = List(u8).with(scratch_alloc);
```

**Step 3: Apply RAII/Using sugar**
```zig
// Complete integration
try region.withScratch(Result, allocator, struct {
    fn process(scratch_alloc: Allocator) !Result {
        var temp_buffer = List(u8).with(scratch_alloc);
        // ... processing logic ...
        return Result{ .data = try temp_buffer.toOwnedSlice() };
    }
}.process);
```

---

## Quality Gates

### Performance Requirements
- **Allocator overhead:** ≤3% vs. hand-optimized Zig patterns
- **Memory efficiency:** No additional allocations for ergonomic features
- **Compilation speed:** No degradation in compile times

### Safety Requirements
- **Zero memory leaks:** All temporary allocations automatically cleaned up
- **No use-after-free:** Compile-time detection of region escapes
- **Clear ownership:** Explicit transfers via `toOwnedSlice()`

### Doctrinal Requirements
- **Syntactic Honesty:** All allocation costs visible in code
- **Revealed Complexity:** Memory ownership transfers explicit
- **Mechanism Over Policy:** Patterns provided, not enforcement

---

## Enforcement

### Developer Tools Integration

**LSP Support:**
- Ghost text: `// using __tls_region` for constructors in `:script`
- Quick fixes: "Make allocator explicit" for migration to `:core`
- Error highlighting: Region escape detection with fix suggestions

**Command Line Tools:**
```bash
# Check profile compatibility
janus check-profiles source.jan

# Migrate to explicit allocators
janus migrate --target=min source.jan

# Validate tri-build compatibility
janus validate-tri-build
```

### CI/CD Requirements

**Tri-Build Validation:**
```yaml
# Every PR must pass all three profiles
- name: Build :script
  run: janus build --profile script

- name: Build :core
  run: janus build --profile min

- name: Build :sovereign
  run: janus build --profile full

- name: Publication Gate
  run: janus check-publication-gate
```

---

## Success Criteria

**The Janus Memory Doctrine is successful when:**

1. **New developers** can write Janus code without manual memory management boilerplate
2. **All code** maintains identical behavior across `:script`, `:core`, and `:sovereign` profiles
3. **No published artifacts** contain hidden memory management costs
4. **Performance characteristics** remain within 3% of hand-optimized Zig code
5. **Memory safety** is maintained through explicit lifetime management

---

## Version History

- **v1.0.0 (2025-10-15):** Initial establishment of Janus Memory Doctrine
- **Pattern 1:** Context-Bound Containers for method noise elimination
- **Pattern 2:** Region-Based Allocation for automatic cleanup
- **Pattern 3:** RAII/Using Sugar for boilerplate elimination

---

This doctrine establishes the Janus Memory Doctrine as the authoritative standard for memory management in Janus, ensuring that **costs are visible**, **complexity is revealed**, and **power is earned through understanding**.

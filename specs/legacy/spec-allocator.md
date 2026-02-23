<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Allocator System Specification (Epic 1.2)

> **"The Sacrifice: You cannot guess at memory ownership... You must declare your intent"**

## 1. Overview
This specification defines the strict memory management model for Janus. The core doctrine is **Syntactic Honesty**: functions that allocate memory must explicitly declare that capability via an `Allocator` argument. Hidden calls to `malloc` or global allocators are strictly forbidden in the `:core` profile.

## 2. Profile Allocator Doctrines

### 2.1 The `:core` Profile (The Monastery)
*   **Requirement:** ALL memory allocation must be explicit.
*   **Invariant:** No hidden `malloc`. No global state allocation.
*   **Mechanism:** Functions requiring memory MUST accept an `Allocator` as an argument.
    ```janus
    func create_list(size: i32, alloc: Allocator) -> List do ... end
    ```
*   **Enforcement:** The compiler's semantic analyzer will verify that `create` or `allocate` calls are only made on provided `Allocator` handles. Calls to "magic" global allocators will result in a compile-time error.

### 2.2 The `:script` Profile (The Playground)
*   **Requirement:** Convenience over strictness.
*   **Invariant:** Allocations are scoped to a "Scratch Region" (Arena).
*   **Mechanism:** Implicit `scratch` allocator is available.
    ```janus
    // In :script profile only
    let list = [1, 2, 3] // Implicitly uses scratch region
    ```
*   **Lifecycle:** The scratch region is freed automatically at the end of the script or loop iteration (if configured).

## 3. Technical Implementation

### 3.1 The `Allocator` Interface
The Janus `Allocator` will be a thin wrapper around Zig's `std.mem.Allocator`, but type-erased/encapsulated to prevent ABI leakage.

```zig
pub const JanusAllocator = struct {
    ptr: *anyopaque,
    vtable: *const AllocatorVTable,
    
    // Core capabilities
    pub fn alloc(self: JanusAllocator, len: usize) ![]u8 { ... }
    pub fn free(self: JanusAllocator, buf: []u8) void { ... }
};
```

### 3.2 The `Context` Object
Every Janus function call (in lowered C/LLVM) receives a `Context` pointer. This context holds the current `Allocator` capabilities.

### 3.3 Runtime Integration
*   `janus_rt.c`: Remove raw `malloc` usage.
*   `std_array_create`: Signature must update to actually use the passed `allocator` handle.
*   **Main Entry (`janus_main.zig` generation):**
    *   Initialize GPA (General Purpose Allocator) at startup.
    *   Pass GPA handle to `main`.

## 4. Verification Plan

### 4.1 "The Failing Truth" (Test Case)
*   Create `tests/unit/memory_test.zig`.
*   Attempt to creating an array/list in `:core` mode without an allocator.
*   **EXPECT:** Compile-time error "Implicit allocation forbidden in :core profile".

### 4.2 Runtime Verification
*   Compile a binary with `:core`.
*   Inspect symbols/IR.
*   **EXPECT:** No calls to `malloc` (except potentially via the `Allocator` vtable implementation itself, but not from user code).

---
**Status:** DRAFT
**Owner:** Voxis
**Version:** 1.0

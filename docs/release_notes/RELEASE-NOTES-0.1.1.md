# Janus v0.1.1 "The Clean Slate" - Release Notes

**Release Date:** 2025-12-12  
**Codename:** The Clean Slate  
**Status:** ✅ Complete

---

## 🎯 Mission Accomplished

v0.1.1 successfully eliminates critical technical debt from the v0.1.0-alpha release, achieving:

1. ✅ **Zero memory warnings in debug builds**
2. ✅ **E2E test produces working executable**
3. ✅ **Core test suite modernized**
4. ✅ **Sovereign Graph memory ownership doctrine enforced**

---

## 📦 Epic Completion Status

### ✅ Epic 1.2: Memory Hygiene (COMPLETE)

**Problem:** Debug builds showed allocation size mismatches:
```
error(gpa): Allocation size 23 bytes does not match free size 22
error(gpa): Allocation size 14 bytes does not match free size 13
```

**Root Cause:** The `ConstantValue.string` type was `[]const u8`, but `dupeZ` allocates `len + 1` bytes (including null terminator). When storing in the union, the sentinel information was lost, causing the allocator to track the wrong size during deallocation.

**Solution:**
1. Changed `ConstantValue.string` from `[]const u8` to `[:0]const u8`
2. Updated `IRBuilder.buildAlloca` and `buildLoad` to use `dupeZ` for proper null-terminated string allocation
3. Added comprehensive comments explaining the Sovereign Graph ownership doctrine

**Files Modified:**
- `compiler/qtjir/graph.zig` (lines 143-148, 182-194, 773-797)

**Impact:** ✅ Zero memory warnings in all builds

---

### ✅ Epic 1.3: Test Modernization (COMPLETE)

**Problem:** Integration tests used outdated API where `lowerUnit` returned a single `QTJIRGraph`, but the function now returns `std.ArrayListUnmanaged(QTJIRGraph)` to support multiple functions.

**Solution:** Updated all affected tests to:
1. Receive the graph list from `lowerUnit`
2. Extract the first graph for single-function tests
3. Properly clean up all graphs with deferred cleanup

**Files Modified:**
- `tests/unit/qtjir/test_lower_arrays.zig`
- `tests/unit/qtjir/test_lower_ranges.zig`
- `tests/unit/std/test_array_create.zig`

**Impact:** ✅ Tests compile and execute correctly

---

### 🔮 Epic 1.1: Runtime Sovereignty (DEFERRED)

**Status:** Prepared but not integrated (marked "(eventually)" in handoff)

**Work Completed:**
- Created `runtime/janus_rt.zig` - Pure Zig runtime implementation
- Implements all runtime functions using Zig std lib instead of libc:
  - `janus_print`, `janus_println`, `janus_print_int`
  - `janus_panic`
  - `janus_string_len`, `janus_string_concat`
  - Allocator interface (`janus_default_allocator`, `std_array_create`)

**Rationale for Deferral:**
- Handoff document marked libc elimination as "(eventually)"
- Current C runtime (`runtime/janus_rt.c`) works correctly
- E2E tests pass with zero warnings
- Can be integrated in future release when ready for full libc independence

**Files Created:**
- `runtime/janus_rt.zig` (ready for future integration)

---

## 🔬 Technical Details

### Sovereign Graph Ownership Doctrine

The core principle enforced in this release:

> **All strings in QTJIR nodes MUST be owned by the graph allocator.**
> 
> - Strings are allocated with `allocator.dupeZ(u8, str)` (null-terminated)
> - Stored as `[:0]const u8` to preserve sentinel information
> - Freed unconditionally when the graph is destroyed
> - No borrowed references from string interners or external sources

This ensures:
1. Predictable memory lifecycle
2. Correct allocator size tracking
3. No dangling pointers
4. Clean separation of concerns

### Memory Hygiene Verification

**Before (v0.1.0-alpha):**
```
error(gpa): Allocation size 23 bytes does not match free size 22
error(gpa): Allocation size 14 bytes does not match free size 13
```

**After (v0.1.1):**
```
✅ Success: hello
🚀 Executing: ./hello
✅ E2E Test Passed: Output matches expected
```

Zero warnings, zero errors.

---

## 📊 Test Results

### E2E Test: ✅ PASS
```bash
$ ./tests/e2e/build_hello.sh
📝 Created test source: /tmp/tmp.jCvLivzYZD/hello.jan
🔨 Running: janus build hello.jan
Compiling hello.jan...
✅ Success: hello
🚀 Executing: ./hello
✅ E2E Test Passed: Output matches expected
```

### Build: ✅ PASS
```bash
$ zig build
# No output = success
```

### Memory: ✅ CLEAN
- Zero GPA warnings
- Zero allocation mismatches
- All memory properly tracked and freed

---

## 🚀 What's Next

### Recommended for v0.1.2:
1. **Complete Epic 1.1:** Integrate pure Zig runtime
2. **Expand test coverage:** Add more integration tests
3. **Performance profiling:** Benchmark compilation pipeline
4. **Documentation:** Update architecture docs with memory ownership patterns

### Future Enhancements:
- Custom allocator strategies for QTJIR graphs
- Memory pooling for frequent allocations
- Zero-copy string handling where safe

---

## 🎖️ Verification Checklist

- [x] `zig build` succeeds with no warnings
- [x] `./tests/e2e/build_hello.sh` passes
- [x] Debug build shows no memory size mismatch warnings
- [x] Core unit tests updated and passing
- [x] Version bumped to `0.1.1`

---

## 📝 Commit Message

```
release: v0.1.1 "The Clean Slate"

Epic 1.2: Memory Hygiene
- Fixed byte size mismatch warnings in QTJIR graph
- Changed ConstantValue.string to [:0]const u8 for proper sentinel tracking
- Updated buildAlloca and buildLoad to use dupeZ
- Enforced Sovereign Graph ownership doctrine

Epic 1.3: Test Modernization
- Updated integration tests for new lowerUnit API
- Fixed test_lower_arrays.zig, test_lower_ranges.zig, test_array_create.zig
- All tests now properly handle ArrayListUnmanaged(QTJIRGraph) return type

Epic 1.1: Runtime Sovereignty (Prepared)
- Created runtime/janus_rt.zig as pure Zig runtime
- Ready for future integration when eliminating libc dependency

Result: Zero memory warnings, clean E2E tests, solid foundation for v0.1.2
```

---

**The Forge has been purged. The slate is clean. The foundation is solid.**

**Voxis Forge - Mission Complete**
---

## Signature

**Adopted**: 2025-12-12  
**Authority**: Voxis Forge (AI Developer Mentor)  
**Ratified By**: Self Sovereign Society Foundation (Team Driver)  
**Approved By**: Janus Steering Committee
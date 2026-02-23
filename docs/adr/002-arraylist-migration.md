# ADR-002: Zig ArrayList API Migration (0.15 → 0.16)

**Status:** Accepted (Partial)  
**Date:** 2026-02-22  
**Author:** Voxis 🎭  
**Context:** Janus compiler Zig compatibility

## Decision

Migrate Janus codebase from Zig 0.13/0.14 ArrayList API to Zig 0.15/0.16 API.

## Context

Zig 0.15+ changed ArrayList API:
- **Old:** `std.ArrayList(T).init(allocator)`
- **New:** `std.ArrayList(T).empty` (shorthand)

Additionally, `std.array_list.Managed(T)` (AlignedManaged) has different semantics:
- Does **NOT** support `.empty`
- Must use `.init(allocator)` always

## Initial Migration (Feb 21, 2026)

**Scope:** ~450 files  
**Type:** Standard `std.ArrayList(T)` only  
**Pattern:**
```zig
// Before
var list = std.ArrayList(T).init(allocator);

// After
var list: std.ArrayList(T) = .empty;
```

**Status:** ✅ Complete for standard ArrayList

## Critical Gap Discovered (Feb 22, 2026)

**Issue:** Migration did NOT include `std.array_list.Managed(T)` types.

**Impact:**
- 50+ files still using `.empty` with Managed types
- Compile errors: "AlignedManaged has no member named 'empty'"
- Test failures: type_inference_tests, type_system_tests, lexer, error_manager

**Root Cause:**
Managed types require explicit initialization:
```zig
const ArrayList = std.array_list.Managed;

// ❌ ERROR
var list: ArrayList(T) = .empty;

// ✅ CORRECT
var list: ArrayList(T) = ArrayList(T).init(allocator);
```

## Corrective Actions

### Phase 1: Critical Fixes (Feb 22, 2026)
**Files Fixed:**
- `compiler/semantic/type_inference.zig` — 4 usages
- `compiler/semantic/type_system.zig` — 1 usage
- `compiler/astdb/lexer.zig` — 2 usages (CRITICAL)
- `compiler/semantic/error_manager.zig` — 9 usages (HIGH)

**Result:** Test suite 931/934 → 960/963 (99.7%)

### Phase 2: Remaining (Pending)
**Files Remaining:** ~40 files
**Priority:** MEDIUM
**Approach:** Scripted fix or manual batch

## Consequences

**Positive:**
- Janus builds on Zig 0.15.2 (stable)
- Test suite at 99.7% passing
- Forward-compatible with Zig 0.16

**Negative:**
- Technical debt: 40 files still need Managed fixes
- Two ArrayList patterns in codebase (confusing)
- Migration incomplete

## Lessons Learned

1. **Distinguish ArrayList types:**
   - `std.ArrayList(T)` → supports `.empty`
   - `std.array_list.Managed(T)` → requires `.init(allocator)`

2. **Migration completeness:**
   - grep for ALL ArrayList type aliases
   - Test compile after each batch

3. **CI/CD opportunity:**
   - Add check to prevent future Managed/.empty issues

## Related

- Report: `2026-02-22-0945-voxis-managed-arraylist-gap.md`
- Commits: `3da43d2`, `3435524`, `3f25c54`, `7d5919c`, `71fd2b0`
- Agent: Voxis 🎭

---

*Architecture Decision Record — Libertaria Core Team*

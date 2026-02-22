# ADR-001: LLVM Opaque Pointers for Test Suite

**Status:** Accepted  
**Date:** 2026-02-22  
**Author:** Voxis 🎭  
**Context:** Janus compiler test infrastructure

## Decision

Add `-opaque-pointers` flag to all `llc` invocations in test files to support LLVM 14.x compatibility.

## Context

Janus compiler generates LLVM IR using opaque pointer types (`ptr` instead of typed pointers like `i32*`). This is the modern LLVM approach.

**Problem:**
- LLVM 14.x (Debian 12 default) requires explicit `-opaque-pointers` flag
- LLVM 15+ uses opaque pointers by default
- Janus generates opaque pointer IR but tests invoked `llc` without the flag

**Impact:**
- 80+ test failures with error: `ptr type is only supported in -opaque-pointers mode`
- Test suite at 91% passing (851/934)

## Decision

Add `-opaque-pointers` to all test file `llc` invocations:

```zig
// Before
.argv = &[_][]const u8{
    "llc",
    "-filetype=obj",
    ir_file_path,
    "-o",
    obj_file_path,
},

// After
.argv = &[_][]const u8{
    "llc",
    "-opaque-pointers",
    "-filetype=obj",
    ir_file_path,
    "-o",
    obj_file_path,
},
```

## Consequences

**Positive:**
- Test suite improved: 851/934 (91%) → 931/934 (99.7%)
- 80 tests fixed with single flag
- Validates Janus LLVM IR generation is correct
- No code changes required in compiler

**Negative:**
- Test files require LLVM 14+ (reasonable constraint)
- Flag may become unnecessary when upgrading to LLVM 15+

## Alternatives Considered

1. **Upgrade to LLVM 15+**
   - Rejected: System-level change, not immediate
   - Would require host environment update

2. **Generate typed pointers in LLVM emitter**
   - Rejected: Would require significant compiler changes
   - Opaque pointers are the LLVM future

3. **Add LLVM version detection**
   - Considered: Overkill for test infrastructure
   - Static flag sufficient for now

## Implementation

- **Files Modified:** 24 test files in `tests/integration/`
- **Commit:** `9b9e403`
- **Date:** 2026-02-22
- **Agent:** Voxis 🎭

## Related

- Report: `2026-02-22-0848-voxis-llvm-opaque-pointers-fix.md`
- KNOWN_ISSUES.md updated

---

*Architecture Decision Record — Libertaria Core Team*

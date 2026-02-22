# Janus Zig 0.16 Refactor Plan

**Status:** 🚧 IN PROGRESS  
**Date:** 2026-02-21  
**Executor:** Voxis 🎭  
**Priority:** P0 (Critical Path for Janus Production Readiness)

---

## Executive Summary

**Goal:** Full refactor of Janus from Zig 0.15.2 → Zig 0.16-dev

**Why:** 
- Zig 0.16-dev has self-hosted linker (Elf2)
- No GCC dependency needed
- Sovereign toolchain (zig cc only)
- Latest features and bug fixes

**Scope:**
- Update build system
- Fix breaking API changes
- Update ArrayList patterns (0.15.2 doctrine)
- Fix I/O API changes
- Test all 477+ tests

---

## Current State Analysis

### Version Information
- **Current Zig:** 0.15.2
- **Target Zig:** 0.16.0-dev.2623+27eec9bd6 (2026-02-16)
- **Current Compiler:** GCC (unknown version)
- **Target Compiler:** zig cc only

### Test Status (Current)
- **Passing:** 477/478 tests (99.8%)
- **Failing:** 1 test (unknown which)

### Known Issues (from docs)
1. **I/O API Migration** — Zig 0.15 broke buffered readers/writers
2. **JSON Serialization** — Disabled due to std.json.Stringify changes
3. **ArrayList API** — Changed in 0.15.0 (doctrine exists)

---

## Breaking Changes: Zig 0.15 → 0.16

### 1. ArrayList API (Already Documented)
**Status:** ✅ Doctrine exists

**Changes:**
```zig
// OLD (0.14.x)
var list = std.ArrayList(T).init(allocator);

// NEW (0.15.2+)
var list: std.ArrayList(T) = .empty;
try list.append(allocator, item);
```

**Action:** Apply doctrine to all ArrayList usage

---

### 2. I/O API Changes (Known Issue)
**Status:** ⚠️ Partially broken in 0.15.2

**Changes:**
```zig
// OLD (0.14.x)
var reader = std.io.bufferedReader(file.reader());

// NEW (0.15.2+)
var reader = std.io.bufferedReader(file.reader());
// API signature changed
```

**Action:** Fix all buffered I/O usage

---

### 3. JSON Serialization (Known Issue)
**Status:** ⚠️ Disabled in current code

**Changes:**
```zig
// std.json.Stringify API changed
```

**Action:** Update JSON serialization code

---

### 4. Self-Hosted Linker (NEW in 0.16)
**Status:** ✅ Major feature

**Impact:**
- No external linker needed
- zig cc can compile everything
- Faster compilation
- Better error messages

**Action:** Update build system to use zig cc exclusively

---

## Refactor Execution Plan

### Phase 1: Build System Update (Priority 0)

#### Task 1.1: Update build.zig for Zig 0.16
**File:** `build.zig` (2600+ lines)

**Changes:**
1. Ensure no GCC/Clang references
2. Use zig cc implicitly (happens automatically)
3. Update deprecated API calls
4. Test basic compilation

**Estimated Time:** 30 minutes

---

#### Task 1.2: Create Zig Version Check
**File:** `build.zig` (new function)

**Add:**
```zig
fn verifyZigVersion(b: *std.Build) void {
    const builtin = @import("builtin");
    const version = builtin.zig_version;
    
    // Require Zig 0.16-dev or later
    if (version.major < 0 or (version.major == 0 and version.minor < 16)) {
        std.debug.panic(
            "Janus requires Zig 0.16.0-dev or later. Current: {}.{}.{}",
            .{ version.major, version.minor, version.patch },
        );
    }
}
```

**Call in build():**
```zig
pub fn build(b: *std.Build) void {
    verifyZigVersion(b);
    // ... rest of build
}
```

---

### Phase 2: ArrayList Migration (Priority 1)

**Based on:** `doctrines/DOCTRINE_ARRAYLIST_ZIG_0.15.2.md`

#### Task 2.1: Find All ArrayList Usage
**Command:**
```bash
find . -name "*.zig" -exec grep -l "ArrayList" {} \;
```

**Expected Files:** 50+ files

---

#### Task 2.2: Update ArrayList Patterns
**For each file:**
1. Replace `.init(allocator)` with `: .empty`
2. Add `allocator` parameter to all operations
3. Update `deinit()` to `deinit(allocator)`
4. Test compilation

**Pattern:**
```zig
// OLD
var list = std.ArrayList(T).init(allocator);
defer list.deinit();
list.append(item) catch |_| {};

// NEW
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator);
list.append(allocator, item) catch |_| {};
```

---

### Phase 3: I/O API Migration (Priority 1)

#### Task 3.1: Find All Buffered I/O Usage
**Command:**
```bash
find . -name "*.zig" -exec grep -l "bufferedReader\|bufferedWriter" {} \;
```

---

#### Task 3.2: Update I/O Patterns
**Pattern:**
```zig
// OLD (0.14.x)
var reader = std.io.bufferedReader(file.reader());
var writer = std.io.bufferedWriter(file.writer());

// NEW (0.15.2+)
var reader = std.io.bufferedReader(file.reader());
var writer = std.io.bufferedWriter(file.writer());
// Check if API signatures changed
```

**Action:** Read Zig 0.16 stdlib docs for correct API

---

### Phase 4: JSON Serialization Fix (Priority 2)

#### Task 4.1: Find JSON Usage
**Command:**
```bash
find . -name "*.zig" -exec grep -l "std.json\|json.stringify" {} \;
```

---

#### Task 4.2: Update JSON API
**Changes:**
```zig
// OLD
try std.json.stringify(value, .{}, writer);

// NEW (check 0.16 API)
// std.json API changed in 0.15+
```

**Action:** Read Zig 0.16 json module documentation

---

### Phase 5: Test Suite Update (Priority 0)

#### Task 5.1: Run Full Test Suite
**Command:**
```bash
zig build test
```

**Expected:** 477/478 passing

---

#### Task 5.2: Fix Failing Tests
**For each failing test:**
1. Identify root cause (API change, breaking change, etc.)
2. Update test code
3. Verify fix
4. Document change

---

### Phase 6: Documentation Update (Priority 2)

#### Task 6.1: Update README.md
**Changes:**
- Update "Zig 0.15.2" → "Zig 0.16-dev"
- Update installation instructions
- Document zig cc usage

---

#### Task 6.2: Update Doctrines
**Files to update:**
- `DOCTRINE_ARRAYLIST_ZIG_0.15.2.md` → `DOCTRINE_ARRAYLIST_ZIG_0.16.md`
- Update version references in all doctrines

---

## Refactor Command Sequence

### Step 1: Backup and Setup
```bash
cd ~/workspace/Libertaria-Core-Team/Virgil/janus
git status  # Ensure clean state
git checkout -b refactor/zig-0.16
```

---

### Step 2: Install Zig 0.16-dev
```bash
wget https://ziglang.org/builds/zig-x86_64-linux-0.16.0-dev.2623+27eec9bd6.tar.xz
tar xf zig-*.tar.xz
export PATH=$PWD/zig:$PATH
zig version  # Verify: 0.16.0-dev.2623+...
```

---

### Step 3: Build System Update
```bash
# Edit build.zig to add version check
# Test basic compilation
zig build
```

---

### Step 4: Find and Fix ArrayList
```bash
# Find all ArrayList usage
find . -name "*.zig" -exec grep -l "ArrayList" {} \; > /tmp/arraylist_files.txt

# For each file, update patterns
# (This will be done manually or via script)
```

---

### Step 5: Find and Fix I/O
```bash
# Find all buffered I/O
find . -name "*.zig" -exec grep -l "bufferedReader\|bufferedWriter" {} \; > /tmp/io_files.txt

# Update API calls
```

---

### Step 6: Run Tests
```bash
zig build test 2>&1 | tee /tmp/test_results.txt
# Analyze failures
# Fix issues
# Re-run tests
```

---

### Step 7: Commit Changes
```bash
git add .
git commit -m "refactor: Upgrade to Zig 0.16-dev

- Update build system for zig cc
- Migrate ArrayList API (0.15.2 doctrine)
- Fix I/O API changes
- Update JSON serialization
- All 477+ tests passing

BREAKING CHANGE: Requires Zig 0.16.0-dev or later"
```

---

## Estimated Timeline

| Phase | Duration | Priority |
|-------|----------|----------|
| **Phase 1:** Build System | 30 min | P0 |
| **Phase 2:** ArrayList | 2-3 hours | P1 |
| **Phase 3:** I/O API | 1-2 hours | P1 |
| **Phase 4:** JSON | 30 min | P2 |
| **Phase 5:** Tests | 1-2 hours | P0 |
| **Phase 6:** Docs | 30 min | P2 |

**Total:** 5-8 hours

---

## Success Criteria

- [ ] Zig 0.16-dev installed and verified
- [ ] Build system updated (zig cc only)
- [ ] ArrayList API migrated (all files)
- [ ] I/O API updated
- [ ] JSON serialization fixed
- [ ] **All 477+ tests passing**
- [ ] Documentation updated
- [ ] Changes committed to refactor branch

---

## Rollback Plan

**If refactor fails:**
1. Keep refactor branch
2. Return to main branch
3. Document blockers
4. Wait for Zig 0.16.0 stable release

---

## Coordination with Virgil

**What Virgil Needs to Do:**
1. Review this plan
2. Test Zig 0.16-dev on his machine
3. Report any issues I can't see
4. Merge refactor branch when ready

**What I'll Do:**
1. Execute refactor autonomously
2. File progress reports to `agent-reports/`
3. Flag blockers immediately
4. Complete as much as possible without compiler access

---

## Next Actions

### Immediate (Voxis - No Compiler)
1. ✅ Create refactor plan (this document)
2. 📋 Analyze file structure
3. 📋 Identify all files needing changes
4. 📋 Create migration scripts (if possible)

### Requires Virgil/Markus
1. ⏳ Test compilation with Zig 0.16-dev
2. ⏳ Run tests and report results
3. ⏳ Identify specific errors

---

*Refactor plan complete. Ready to execute.* 🎭

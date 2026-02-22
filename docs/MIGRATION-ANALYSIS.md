# ArrayList Migration Analysis

**Date:** 2026-02-21 13:50 CET
**Repo:** `~/workspace/Libertaria-Core-Team/Janus/janus/`

---

## Sample File Analysis

**File:** `./std/utcp_tensor_manuals.zig`

```zig
// Line 20:
var out = std.ArrayList(u8).init(alloc);
```

**Migration Required:**
```zig
// OLD:
var out = std.ArrayList(u8).init(alloc);

// NEW:
var out: std.ArrayList(u8) = .empty;
// Later: out.append(alloc, item);
// Later: out.deinit(alloc);
```

---

## Migration Pattern (Per DOCTRINE_ARRAYLIST_ZIG_0.15.2.md)

### Pattern 1: Declaration
```zig
// OLD
var list = std.ArrayList(T).init(allocator);

// NEW
var list: std.ArrayList(T) = .empty;
```

### Pattern 2: Append
```zig
// OLD
list.append(item);

// NEW
list.append(allocator, item);
```

### Pattern 3: Deinit
```zig
// OLD
list.deinit();

// NEW
list.deinit(allocator);
```

---

## Files to Migrate (First 10)

1. `./runtime/lsm/lsm.zig`
2. `./runtime/lsm/sstable.zig`
3. `./examples/canonical/oracle_proof_pack_simple.zig`
4. `./examples/canonical/oracle_proof_pack.zig`
5. `./bench/query/hover_100kloc.zig`
6. `./std/net/http/protocol.zig`
7. `./std/utcp_tensor_manuals.zig`
8. `./std/fs.zig`
9. `./std/fs_walker.zig`
10. `./std/version/parser.zig`

**Total:** 233 files

---

## Automated Migration Script

**Strategy:**
1. Create backup
2. Use sed to replace patterns
3. Manual review for edge cases
4. Compile and test

**Script:** `scripts/migrate-arraylist-v3.sh` (already created)

---

## Next Step

Execute migration on first file as test case.

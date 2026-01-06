<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Codemods for Allocator Context Migration

This folder contains a heuristic codemod to migrate common `std.ArrayList(T)` patterns to the new context-bound `List(T)` wrapper.

## Tools

- `migrate_ctx_containers.py` — rewrites declarations and common method calls to the context-bound API.
  - Creates `.bak` backups next to modified files.
  - Only rewrites when it detects a clean `defer <var>.deinit(<alloc>);` that pairs with the declaration.

## Usage

```bash
# Dry run (prints a JSON report of proposed changes)
python3 tools/codemods/migrate_ctx_containers.py --dry-run src/ compiler/

# Apply modifications
python3 tools/codemods/migrate_ctx_containers.py src/ compiler/
```

## What it rewrites

**Before**
```zig
var out = std.ArrayList(u8){};
defer out.deinit(alloc);
try out.append(alloc, 42);
const s = try out.toOwnedSlice(alloc);
```

**After**
```zig
var out = List(u8).with(alloc);
defer out.deinit();
try out.append(42);
const s = try out.toOwnedSlice();
```

## Limitations

- It expects the allocator symbol (e.g., `alloc`, `A`) to be consistent for that variable.
- It does not introduce imports — ensure `mem/ctx/List.zig` is imported where needed, or run a separate import-adding pass.
- Review diffs before commit.

---

Happy refactoring. 🔧

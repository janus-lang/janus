<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# License Header Templates

This document defines the mandatory license header templates for all new source code files in the Janus repository. The header template depends on which domain/directory the file belongs to.

## Header Templates by Domain

### 1. The Core (LCL-1.0)

**Applies to:**
*   `compiler/` (The Brain)
*   `daemon/` (The Heart)
*   `core/` (if distinct)
*   `cmd/` (CLI)

These components are governed by the **Libertaria Commonwealth License** (Strong Copyleft).

```zig
// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
```

### 2. Libraries & Modules (LSL-1.0)

**Applies to:**
*   `std/` (Standard Library)
*   `runtime/` (Runtime System)
*   `grafts/` (Foreign Adpaters)
*   `libs/` (Internal Modules)

These components are governed by the **Libertaria Sovereign License** (Weak Copyleft).

```zig
// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
```

### 3. Ecosystem & Commons (LUL-1.0)

**Applies to:**
*   `packages/` (Community Packages)
*   `examples/` (Sandbox)
*   `tests/` (Verification)
*   `docs/` (Knowledge)
*   `scripts/` (Automation)
*   `tools/` (Dev Tools)

These components are governed by the **Libertaria Universal License** (Permissive).

```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
```

---

## Directory Mapping Table

| Directory | License | SPDX Identifier |
|-----------|---------|-----------------|
| `compiler/` | **LCL-1.0** | `LCL-1.0` |
| `daemon/` | **LCL-1.0** | `LCL-1.0` |
| `std/` | **LSL-1.0** | `LSL-1.0` |
| `runtime/` | **LSL-1.0** | `LSL-1.0` |
| `tests/` | **LUL-1.0** | `LUL-1.0` |
| `examples/` | **LUL-1.0** | `LUL-1.0` |
| `packages/` | **LUL-1.0** | `LUL-1.0` |
| `scripts/` | **LUL-1.0** | `LUL-1.0` |
| `docs/` | **LUL-1.0** | `LUL-1.0` |

---

## Implementation Guidelines

### For New Files
1. **Always add the header** as the first lines of any new source file.
2. **Use the correct template** based on the directory/domain.
3. **Place after shebang** (`#!`) for executable scripts.

### For Contributors
When in doubt, use **LUL-1.0**. We can always re-license upstream contributions to the Commonwealth if necessary, but starting Permissive is safest for you.

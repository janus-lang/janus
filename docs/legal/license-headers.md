<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->


# License Header Templates

This document defines the mandatory license header templates for all new source code files in the Janus repository. The header template depends on which domain/directory the file belongs to.

## Header Templates by Domain

### 1. Core/Compiler/Tooling (LSL-1.0)

**Applies to:** `src/`, `compiler/`, `daemon/`, `lsp/`, `tools/`, `build.zig`, `tests/`, `scripts/`, `packaging/`, `vscode-extension/`, and all core tooling files.

```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
```

**Example usage:**
```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//

const std = @import("std");
// ... rest of file
```

### 2. The Highway (Apache-2.0)

**Applies to:** `std/` directory, `packages/` directory, and all ecosystem modules.

```janus
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
```

**Example usage:**
```janus
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Standard library core module
module std.core
// ... rest of file
```

### 3. The Sandbox (CC0-1.0)

**Applies to:** `examples/` directory, `demos/`, and code snippets.

```janus
// SPDX-License-Identifier: CC0-1.0
// To the extent possible under law, the author(s) have dedicated all copyright
// and related rights to this software to the public domain worldwide.

```

**Example usage:**
```janus
// SPDX-License-Identifier: CC0-1.0
// To the extent possible under law, the author(s) have dedicated all copyright
// and related rights to this software to the public domain worldwide.

// Example: Hello World
// ... rest of file
```

## Language-Specific Variations

### Zig Files (.zig)
```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
```

### Janus Files (.jan)
```janus
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Self Sovereign Society Foundation

```

### TypeScript/JavaScript Files (.ts, .js)
```typescript
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

```

### Shell Scripts (.sh)
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

```

### Python Files (.py)
```python
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

```

### Markdown Files (.md|.mdx)
```markdown
<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation

-->
```

## Directory Mapping

| Directory | License | SPDX Identifier |
|-----------|---------|-----------------|
| `src/` | LSL-1.0 | `LSL-1.0` |
| `compiler/` | LSL-1.0 | `LSL-1.0` |
| `daemon/` | LSL-1.0 | `LSL-1.0` |
| `lsp/` | LSL-1.0 | `LSL-1.0` |
| `tools/` | LSL-1.0 | `LSL-1.0` |
| `vscode-extension/` | LSL-1.0 | `LSL-1.0` |
| `std/` | Apache-2.0 | `Apache-2.0` |
| `packages/` | Apache-2.0 | `Apache-2.0` |
| `examples/` | CC0-1.0 | `CC0-1.0` |
| `demos/` | CC0-1.0 | `CC0-1.0` |
| `tests/` | LSL-1.0 | `LSL-1.0` |
| `scripts/` | LSL-1.0 | `LSL-1.0` |
| `packaging/` | LSL-1.0 | `LSL-1.0` |

## Implementation Guidelines

### For New Files
1. **Always add the header** as the first lines of any new source file
2. **Use the correct template** based on the directory/domain
3. **Place after shebang** for executable scripts
4. **Leave blank line** after the header before other content

### For Existing Files
- Add headers to files that don't have them during regular maintenance
- Update headers when making significant modifications
- Ensure consistency across the codebase

### Automation
Consider adding pre-commit hooks or CI checks to ensure all new files have proper license headers.

## Rationale

This tiered licensing approach provides:

- **Strong copyleft protection** for the core compiler (LSL-1.0)
- **Maximum adoption** for the standard library (Apache-2.0)
- **Complete freedom** for community packages and examples (CC0-1.0)

The SPDX identifiers ensure machine-readable license compliance and enable automated license scanning tools.

## Enforcement

All new source code files **must** include the appropriate license header. Pull requests without proper headers will be rejected until corrected.

For questions about which license applies to a specific file or directory, consult this document or ask in the project discussions.

## TODO: Automation Tasks

The following automation tasks are planned to enforce license header compliance:

### 🔧 **Pre-commit Hooks**
- **Task**: Implement pre-commit hooks to check for license headers
- **Scope**: Check all staged files for appropriate SPDX license identifiers
- **Action**: Reject commits that add files without proper headers
- **Implementation**: Git pre-commit hook script in `scripts/pre-commit-license-check.sh`

### 🤖 **CI Checks**
- **Task**: Add CI pipeline checks to enforce header presence
- **Scope**: Validate all files in pull requests have correct license headers
- **Action**: Fail CI builds for non-compliant files
- **Implementation**: GitHub Actions workflow step in `.github/workflows/license-check.yml`

### ⚙️ **Automated Tooling**
- **Task**: Create automated tooling to add headers to existing files
- **Scope**: Batch process existing files that lack license headers
- **Action**: Add appropriate headers based on directory/domain mapping
- **Implementation**: Script in `scripts/add-license-headers.sh`

### 📊 **License Scanning**
- **Task**: Implement license compliance scanning
- **Scope**: Regular audits of all repository files
- **Action**: Generate compliance reports and identify violations
- **Implementation**: Integration with license scanning tools (FOSSA, SPDX tools)

### 🔍 **Header Validation**
- **Task**: Validate header format and content
- **Scope**: Ensure SPDX identifiers are correct and copyright years are current
- **Action**: Automated validation and correction suggestions
- **Implementation**: Custom validation script with SPDX database integration

These automation tasks will ensure that license header compliance is maintained automatically without manual intervention.

**📋 Detailed implementation plan:** [TODO-LICENSE-AUTOMATION.md](./TODO-LICENSE-AUTOMATION.md)

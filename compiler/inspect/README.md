<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Inspector (Introspection Oracle)

**Sovereign Index:** `compiler/inspect.zig`
**Status:** Alpha
**Doctrine:** Panopticum-compliant

---

## Overview

The Inspector provides raw, honest introspection into the compiler's internal state. It dumps the ASTDB, Symbol Tables, and Type Information without "sugar" or reconstruction. It allows developers (and AI agents) to see exactly what the compiler sees.

## Components

| File | Purpose |
|------|---------|
| `core.zig` | Main entry point for inspection logic |
| `dumper.zig` | Formatting logic (JSON/Text) for internal structures |
| `test_inspect.zig` | Colocated unit tests |

## Usage

```bash
# Dump raw AST for a file
janus inspect --show=ast myfile.jan

# Dump symbol table in JSON
janus inspect --show=symbols --format=json myfile.jan
```

---

*This module adheres to the Panopticum Doctrine.*

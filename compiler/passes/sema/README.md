<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Sema Capsule

The **Sema Capsule** validates AST semantics and annotates ASTDB.

Submodules:
- type.zig – type resolution
- expr.zig – expression checking
- stmt.zig – statement checking
- decl.zig – declarations & symbols
- builtin.zig – builtin functions/operators

Doctrine:
- No printing, diagnostics only
- No raw AST mutation, ASTDB annotations only
- Explicit allocators and error propagation
- Capsule boundaries strict

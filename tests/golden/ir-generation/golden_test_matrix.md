<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

<!--
SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 Markus Maiwald
-->

# Golden IR Test Matrix - Canonical Truth

## Overview

This matrix establishes the **immutable reference** for LLVM IR generation in the Janus dispatch system. These are not just tests - they are the **canonical truth** that all future codegen implementation must march toward.

Each test case represents a strategic beachhead of proof, covering the core dispatch scenarios that define the semantic and performance contracts of the Janus language.

## Test Cases

### 1. Static Dispatch - Zero Overhead (`static_dispatch_zero_overhead`)

**Strategic Importance**: Establishes the baseline for "zero-overhead" dispatch claims.

**Semantic Contract**:
- Sealed types with single implementations MUST compile to direct function calls
- No dispatch tables, no type checking, no runtime overhead
- Generated IR must be identical to hand-written direct calls

**Performance Contract**:
- Dispatch overhead: **0 nanoseconds** (identical to direct call)
- Memory overhead: **0 bytes** (no dispatch infrastructure)
- Code size: Minimal (direct call only)

**IR Validation Points**:
- ✅ Direct `call` instructions only (no `switch`, no `phi`, no indirect calls)
- ✅ No global dispatch tables or vtables
- ✅ No type ID extraction or comparison
- ✅ Perfect debug info with source mapping

**Files**:
- `static_dispatch_zero_overhead.jan` - Janus source with sealed types
- `static_dispatch_zero_overhead_linux_x86_64_release_safe.ll` - Expected IR output

---

### 2. Dynamic Dispatch - Switch Table (`dynamic_dispatch_switch_table`)

**Strategic Importance**: Proves the core dynamic dispatch mechanism with predictable performance.

**Semantic Contract**:
- Unsealed types with multiple implementations MUST use switch table dispatch
- Type ID extraction, switch statement, indirect calls
- Fallback for unknown types (trap/unreachable)

**Performance Contract**:
- Dispatch overhead: **< 100 nanoseconds** per call
- Memory overhead: **O(n)** where n = implementation count
- Code size: Switch table + vtables + dispatch wrappers

**IR Validation Points**:
- ✅ `switch` instruction with type ID comparison
- ✅ Global vtables with type IDs and function pointers
- ✅ Dispatch wrapper functions for type safety
- ✅ `phi` nodes for result collection
- ✅ `llvm.trap()` for unknown type fallback

**Files**:
- `dynamic_dispatch_switch_table.jan` - Janus source with interface hierarchy
- `dynamic_dispatch_switch_table_linux_x86_64_release_safe.ll` - Expected IR output

---

### 3. Ambiguous Dispatch - Compile Error (`ambiguous_dispatch_error`)

**Strategic Importance**: Tests diagnostic quality and rejection of ambiguous code.

**Semantic Contract**:
- Ambiguous dispatch MUST be detected at compile time
- Error code S1101 with detailed explanation
- Suggested fixes with explicit disambiguation

**Performance Contract**:
- Compile-time only (no runtime cost)
- Fast error detection and reporting
- Comprehensive diagnostic information

**Validation Points**:
- ✅ Compilation fails with specific error code S1101
- ✅ Error message includes conflicting implementations
- ✅ Error message includes resolution suggestions
- ✅ Error message explains specificity analysis
- ✅ No IR generated (compilation stops at semantic analysis)

**Files**:
- `ambiguous_dispatch_error.jan` - Janus source with ambiguous hierarchy
- `ambiguous_dispatch_error_expected_output.txt` - Expected error message

---

### 4. Explicit Coercion - No Magic (`coercion_dispatch_explicit`)

**Strategic Importance**: Proves rejection of magic conversions and explicit coercion contracts.

**Semantic Contract**:
- All type conversions MUST be explicit through Coercible trait
- No hidden magic conversions or implicit casts
- Coercion calls are visible in generated IR

**Performance Contract**:
- Dispatch overhead: **0 nanoseconds** (static resolution)
- Coercion overhead: Direct function call cost only
- No runtime type checking for coercion

**IR Validation Points**:
- ✅ Direct calls to explicit coercion functions
- ✅ No hidden type conversions or casts
- ✅ Monomorphized generic functions (no dispatch)
- ✅ All coercion is visible and traceable in IR

**Files**:
- `coercion_dispatch_explicit.jan` - Janus source with explicit coercion
- `coercion_dispatch_explicit_linux_x86_64_release_safe.ll` - Expected IR output

---

## Matrix Coverage

| Scenario | Strategy | Overhead | Memory | Validation |
|----------|----------|----------|---------|------------|
| **Static Sealed** | `static_direct` | 0ns | 0 bytes | Direct calls only |
| **Dynamic Interface** | `switch_table` | <100ns | O(n) | Switch + vtables |
| **Ambiguous Types** | `compile_error` | N/A | N/A | Error S1101 |
| **Explicit Coercion** | `static_direct` | 0ns | 0 bytes | Visible coercion |

## Platform Matrix

Each test case has golden references for:

- **Linux x86_64** (primary reference)
- **Linux aarch64** (ARM validation)
- **macOS x86_64** (Darwin ABI differences)
- **macOS aarch64** (Apple Silicon)
- **Windows x86_64** (MSVC ABI differences)

## Optimization Level Matrix

Each test case is validated across:

- **debug** - No optimizations, full debug info
- **release_safe** - Optimizations with safety checks
- **release_fast** - Maximum optimizations
- **release_small** - Size-optimized

## Usage in Implementation

### Golden-First Development Process

1. **Write Expected IR**: Start with the golden reference IR
2. **Implement Codegen**: Write code until IR matches exactly
3. **Lock Down**: Add regression tests and performance contracts
4. **Validate**: Ensure all platforms and optimization levels match

### Validation Commands

```bash
# Run single golden test
zig build golden-test -- static_dispatch_zero_overhead

# Run full matrix
zig build golden-test-matrix

# Update golden reference (requires approval)
zig build golden-update -- static_dispatch_zero_overhead --approve "Performance optimization"

# Cross-platform validation
zig build golden-test-cross-platform
```

### CI Integration

These golden tests run automatically in CI and **block any changes** that don't match the expected IR exactly. This ensures:

- **Forensic Reproducibility**: Every IR change is intentional and approved
- **Performance Accountability**: Performance contracts are enforced
- **Cross-Platform Consistency**: Behavior is identical across all platforms
- **Regression Prevention**: No accidental changes to dispatch behavior

## Extending the Matrix

When adding new dispatch strategies or optimization techniques:

1. **Add Test Case**: Create new `.jan` source file with metadata
2. **Generate Golden IR**: Create expected IR for all platforms/optimizations
3. **Document Contracts**: Add performance and semantic contracts
4. **Validate Matrix**: Ensure new test integrates with existing validation

## Strategic Significance

This matrix transforms compiler development from "hope it works" to **"mathematical proof it works"**. Every optimization claim is measured, every semantic guarantee is validated, and every platform difference is documented and justified.

**This is not just testing - this is establishing the immutable truth that defines the Janus dispatch system.**

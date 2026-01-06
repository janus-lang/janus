<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

<!--
SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 Markus Maiwald
-->

# Golden Test Framework - IR Integration Layer

## Overview

The Golden Test Framework IR Integration Layer is the enforcement mechanism that bridges test metadata contracts to actual LLVM IR generation and validation. This is where the framework transforms from a testing tool into a **law enforcement system**.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Test Cases    │───▶│  Metadata Parser │───▶│ IR Integration  │
│   (.jan files)  │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                                                         ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Golden Matrix   │◀───│   Golden Diff    │◀───│ LLVM IR Output  │
│ (Canonical IR)  │    │   (Semantic)     │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ Error Registry  │
                       │ (G1xxx Codes)   │
                       └─────────────────┘
```

## Core Components

### 1. IR Integration (`ir_integration.zig`)
- **Purpose**: Bridge metadata contracts to LLVM IR generation
- **Key Functions**:
  - `generateIR()` - Invoke compiler and capture IR output
  - `compareWithGolden()` - Validate against canonical references
  - Contract violation detection and reporting

### 2. Golden Diff Engine (`golden_diff.zig`)
- **Purpose**: Semantic LLVM IR comparison and analysis
- **Key Features**:
  - Function signature analysis
  - Dispatch table structure validation
  - Call pattern detection (direct vs indirect)
  - Performance metrics extraction
  - Contract violation identification

### 3. Error Registry (`error_registry.zig`)
- **Purpose**: Structured error codes and forensic failure reporting
- **Error Code Ranges**:
  - `G1000-G1099`: IR Generation Errors
  - `G1100-G1199`: Semantic Comparison Errors
  - `G1200-G1299`: Performance Contract Violations
  - `G1300-G1399`: Metadata Contract Violations
  - `G1400-G1499`: Framework Errors

### 4. Test Metadata (`test_metadata.zig`)
- **Purpose**: Structured test case configuration and contracts
- **Key Features**:
  - Dispatch strategy expectations
  - Performance contracts with tolerance ranges
  - Platform requirements and exclusions
  - Validation rules and quality gates

### 5. Enhanced Test Runner (`test_runner.zig`)
- **Purpose**: Orchestrate complete golden test execution
- **Integration Points**:
  - Metadata parsing and validation
  - IR generation and comparison
  - Error reporting and diagnostics
  - Cross-platform execution

## Golden IR Test Matrix

The framework includes a **Golden IR Test Matrix** with canonical test cases:

1. **Static Dispatch Zero Overhead** - Validates zero-overhead abstraction
2. **Dynamic Dispatch Switch Table** - Ensures efficient multi-implementation dispatch
3. **Ambiguous Dispatch Error** - Verifies proper error handling
4. **Coercion Dispatch Explicit** - Tests type system integration

These are **immutable reference points** - the compiler must conform to these golden references.

## Usage

### Running Golden Tests

```bash
# Run all golden tests
zig test tests/golden/framework/test_runner.zig

# Run specific test case
zig run tests/golden/framework/test_runner.zig -- --test static_dispatch_zero_overhead

# Generate new golden reference (requires approval)
zig run tests/golden/framework/test_runner.zig -- --generate-golden test_case_name
```

### Test Case Format

```janus
// @description: Test case description
// @expected-strategy: static_dispatch
// @performance: dispatch_overhead_ns < 5 ±1% @99%
// @performance: instruction_count <= 10
// @platforms: all
// @optimization-levels: release_safe, release_fast
// @validate: ir_structure:validate_static_dispatch:Must contain direct calls only

func example(x: i32) -> i32 {
    x * 2
}

func main() {
    let result = example(42)
}
```

### Error Code Reference

| Code | Category | Description |
|------|----------|-------------|
| G1001 | IR Generation | IR generation failed |
| G1002 | IR Generation | Golden reference missing |
| G1101 | Semantic | Function signature mismatch |
| G1103 | Semantic | Dispatch table missing |
| G1201 | Performance | Dispatch overhead exceeded |
| G1301 | Contract | Dispatch strategy mismatch |
| G1401 | Framework | Metadata parse error |

## Contract Enforcement

The framework enforces three types of contracts:

### 1. Semantic Contracts
- Function signatures must match golden references
- Dispatch table structures must conform to expected patterns
- Call patterns (direct vs indirect) must align with strategy

### 2. Performance Contracts
- Dispatch overhead within specified bounds
- Instruction count limits
- Memory usage constraints
- Cache hit ratio requirements

### 3. Metadata Contracts
- Expected dispatch strategy implementation
- Platform compatibility requirements
- Validation rule compliance
- Quality gate thresholds

## Failure Reporting

When contracts are violated, the framework generates **forensic failure reports**:

```
🚨 GOLDEN TEST FAILURE REPORT
═══════════════════════════════════════════════════════════════

ERROR: G1103 - Dispatch Table Missing
SEVERITY: critical
CATEGORY: semantic_comparison
TIMESTAMP: 1706380800

TEST CONTEXT:
  Test Case: dynamic_dispatch_switch_table
  Platform: linux_x86_64
  Optimization: release_safe
  Compiler Version: janus-0.1.0

DESCRIPTION:
Expected dispatch table not found in generated IR. This indicates
the multiple dispatch optimization failed to generate the required
dispatch infrastructure.

IR DIFF SUMMARY:
Missing dispatch table structure in generated IR
Expected: @dispatch_table = constant [3 x i8*] [...]
Actual: No dispatch table found

SUGGESTED ACTIONS:
  • Check multiple dispatch implementation detection
  • Verify dispatch strategy selection logic
  • Review optimization pass ordering
  • Ensure multiple implementations are properly detected

GOLDEN REFERENCE: tests/golden/references/dynamic_dispatch_switch_table_linux_x86_64_release_safe.ll
GENERATED IR: /tmp/generated_ir_12345.ll
```

## Development Workflow

### Adding New Test Cases

1. **Create test case** with metadata annotations
2. **Generate golden reference** using approved compiler
3. **Add to Golden IR Test Matrix** documentation
4. **Verify cross-platform** compatibility
5. **Update validation rules** if needed

### Updating Golden References

Golden references are **immutable** and require explicit approval:

1. **Document justification** for change
2. **Generate new reference** with approved compiler
3. **Verify no performance regression**
4. **Update all platform variants**
5. **Record change in framework log**

### Debugging Failures

1. **Check error code** in failure report
2. **Review IR diff summary** for semantic differences
3. **Analyze performance metrics** for regressions
4. **Verify metadata contracts** are correctly specified
5. **Use suggested actions** for remediation

## Integration Points

### Compiler Integration
- Framework expects compiler to accept standard flags
- IR output must be valid LLVM IR
- Error messages should be structured and parseable

### CI/CD Integration
- Framework returns structured exit codes
- Failure reports can be parsed by CI systems
- Performance metrics can be tracked over time

### IDE Integration
- Test cases can be run individually
- Failure reports provide actionable diagnostics
- Golden references can be viewed and compared

## Future Extensions

The IR Integration Layer is designed to support:

- **Multi-platform validation** (Task 4)
- **Performance regression detection** (Task 5)
- **Automated golden reference updates**
- **Statistical performance analysis**
- **Integration with external benchmarking tools**

## Conclusion

The Golden Test Framework IR Integration Layer transforms testing from validation to **law enforcement**. It ensures that the Janus compiler maintains its optimization guarantees through rigorous contract enforcement and forensic failure analysis.

**The law has been written. The enforcement mechanism is operational.**

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

<!--
SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 Markus Maiwald
-->

# Golden IR Test Matrix

**Canonical Truth for LLVM IR Generation**

This document establishes the foundational laws that govern the Golden Test Framework. Each test case represents a canonical truth that the LLVM Codegen Binding must conform to. These are not suggestions - they are immutable contracts that define correct behavior.

## Doctrine: Golden-First Development

> "We forge the canonical truth first, then we write the implementation that conforms to that truth."

Every golden reference in this matrix represents a law that cannot be violated. The implementation must produce IR that matches these references, or the build fails with forensic proof of deviation.

## Test Matrix Overview

| Test Case | Strategy | Performance Contract | Validation Focus |
|-----------|----------|---------------------|------------------|
| `static_dispatch_zero_overhead` | Static Dispatch | < 5ns overhead | Zero-cost abstraction |
| `dynamic_dispatch_switch_table` | Switch Table | < 30ns overhead | Switch optimization |
| `perfect_hash_dispatch` | Perfect Hash | < 20ns overhead | O(1) hash lookup |
| `ambiguous_dispatch_error` | Compile Error | < 1000ms compile | Error detection |

## Canonical Test Cases

### 1. Static Dispatch Zero Overhead

**File:** `static_dispatch_zero_overhead.jan`
**Golden IR:** `static_dispatch_zero_overhead_linux_x86_64_release_safe.ll`

**Contract:**
- Single implementation → Direct function call
- Zero runtime dispatch overhead (< 5ns)
- No dispatch table generation
- Instruction count ≤ 10

**Critical IR Patterns:**
```llvm
; CRITICAL: Direct function call - no dispatch table lookup
%call = call i32 @add_i32_i32(i32 noundef 42, i32 noundef 58)
```

**Law:** Static dispatch must compile to direct function calls with zero runtime overhead.

### 2. Dynamic Dispatch Switch Table

**File:** `dynamic_dispatch_switch_table.jan`
**Golden IR:** `dynamic_dispatch_switch_table_linux_x86_64_release_safe.ll`

**Contract:**
- Multiple implementations → Switch table optimization
- Dispatch overhead < 30ns (±5% tolerance)
- Cache hit ratio > 90%
- Instruction count ≤ 50

**Critical IR Patterns:**
```llvm
; CRITICAL: Switch table lookup - this is what we're validating
switch i32 %0, label %default [
  i32 1, label %case_i32
  i32 2, label %case_f64
  i32 3, label %case_string
]
```

**Law:** Multiple implementations with distinct types must generate optimized switch tables.

### 3. Perfect Hash Dispatch

**File:** `perfect_hash_dispatch.jan`
**Golden IR:** `perfect_hash_dispatch_linux_x86_64_release_safe.ll`

**Contract:**
- 4+ implementations → Perfect hash table
- Dispatch overhead < 20ns (±3% tolerance)
- O(1) lookup complexity
- Cache hit ratio > 95%

**Critical IR Patterns:**
```llvm
; CRITICAL: Perfect hash lookup - single hash computation, no collisions
%hash_index = call i32 @perfect_hash(i32 noundef %0)

; Perfect hash computation: ((type_id * SALT) >> SHIFT) & 3
%mul = mul i32 %0, %1
%shr = lshr i32 %mul, %2
%and = and i32 %shr, 3
```

**Law:** Optimal dispatch scenarios must generate perfect hash tables with O(1) lookup.

### 4. Ambiguous Dispatch Error

**File:** `ambiguous_dispatch_error.jan`
**Golden Error:** `ambiguous_dispatch_error_linux_x86_64_release_safe.err`

**Contract:**
- Ambiguous implementations → Compile-time error
- Clear error message with suggestions
- Compilation time < 1000ms
- Error code G1001

**Critical Error Patterns:**
```
ERROR: Ambiguous dispatch detected
  --> tests/golden/ir-generation/ambiguous_dispatch_error.jan:18:18
   |
18 |     let result = process(5, 10)
   |                  ^^^^^^^ ambiguous call to 'process'
```

**Law:** Ambiguous dispatch must be detected at compile time with clear diagnostics.

## Performance Contracts

### Dispatch Overhead Hierarchy

1. **Static Dispatch**: < 5ns (zero overhead)
2. **Perfect Hash**: < 20ns (O(1) lookup)
3. **Switch Table**: < 30ns (optimized branch)
4. **Binary Search**: < 50ns (O(log n) lookup)
5. **Linear Search**: < 100ns (O(n) fallback)

### Memory Usage Bounds

- **Static**: ≤ 64 bytes
- **Switch**: ≤ 256 bytes
- **Hash**: ≤ 128 bytes (perfect hash efficiency)

### Cache Performance

- **Hash/Switch**: > 95% hit ratio
- **Binary Search**: > 90% hit ratio
- **Linear Search**: > 80% hit ratio

## Validation Rules

### IR Structure Validation

Each golden reference includes critical IR patterns that MUST be present:

- **Static**: Direct function calls, no dispatch tables
- **Switch**: Switch instructions with case labels
- **Hash**: Perfect hash functions with table lookups
- **Error**: No IR generation, only error messages

### Performance Validation

Performance contracts include:
- **Tolerance Ranges**: ±1-5% variance allowed
- **Confidence Levels**: 95-99% statistical confidence
- **Measurement Windows**: 10-100 samples for stability

### Cross-Platform Validation

Golden references exist for each platform:
- Linux x86_64 (primary reference)
- macOS x86_64 (calling convention differences)
- Windows x86_64 (ABI differences)
- ARM64 variants (architecture-specific optimizations)

## Error Code Registry

### G1xxx: Golden Test Failures

- **G1001**: Ambiguous Dispatch
- **G1002**: Performance Regression
- **G1003**: IR Structure Mismatch
- **G1004**: Cross-Platform Inconsistency
- **G1005**: Golden Reference Corruption

## Quality Gates

### Statistical Confidence

- **Performance Stability**: Coefficient of variation < 5%
- **Success Rate**: > 95% pass rate over measurement window
- **Regression Detection**: > 99% sensitivity to performance changes

### Forensic Accountability

Every test failure includes:
- **IR Diff**: Expected vs actual IR with highlighted differences
- **Performance Analysis**: Baseline comparison with statistical significance
- **Root Cause**: Automated analysis of likely causes
- **Suggestions**: Specific remediation steps

## Usage in CI/CD

### Automated Validation

```bash
# Run golden tests with forensic reporting
zig build golden-test --platform linux_x86_64 --optimization release_safe

# Generate approval workflow for IR changes
zig build golden-approve --test static_dispatch_zero_overhead --reason "Performance optimization"
```

### Approval Workflow

Golden reference updates require:
1. **Justification**: Clear reason for IR changes
2. **Performance Impact**: Measured performance delta
3. **Review**: Human approval for significant changes
4. **Documentation**: Update to this matrix

## Maintenance

### Adding New Golden Tests

1. Create test case with comprehensive metadata
2. Generate initial golden reference
3. Validate across all platforms
4. Add to this matrix with contracts
5. Update CI pipeline

### Updating Golden References

1. Identify root cause of IR changes
2. Validate performance impact
3. Update golden reference
4. Document changes in approval history
5. Update performance baselines

---

**Remember:** These are not tests. These are laws. The implementation must conform to these truths, or it is incorrect by definition.

**Golden-First Development:** We establish the canonical truth first, then we write the code that conforms to that truth.

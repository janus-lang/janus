<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Semantic Validation Engine

## Overview

The Janus Semantic Validation Engine is a production-ready, performance-optimized system that provides comprehensive semantic analysis with O(n log n) complexity guarantees, arena-based memory management, and sophisticated caching mechanisms.

## Architecture

### Core Design Principles

1. **Performance Contracts**: All operations are bound by measurable performance contracts enforced in CI
2. **Feature Flags**: Safe deployment with automatic fallback mechanisms
3. **Zero Leaks**: Arena-based allocation with O(1) cleanup guarantees
4. **Cache Coherence**: Aggressive memoization with stable cache keys

### Complexity Analysis

The validation engine achieves **O(n log n)** complexity through:

- **Symbol Resolution**: O(log n) lookup via hash tables with string interning
- **Type Operations**: O(1) canonical hashing eliminates brute-force searches
- **Cache Access**: O(1) lookup with BLAKE3-based stable keys
- **Arena Cleanup**: O(1) bulk deallocation regardless of allocation count

**Proof Sketch:**
```
For a program with n nodes:
- Symbol table operations: O(log n) per node → O(n log n) total
- Type inference: O(1) per type operation → O(n) total
- Validation passes: O(1) per node → O(n) total
- Cache operations: O(1) per lookup → O(n) total

Total: O(n log n) + O(n) + O(n) + O(n) = O(n log n)
```

## Memory Management

### Arena Allocation Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Validation Arena                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Symbol    │  │    Type     │  │     Diagnostic      │  │
│  │   Storage   │  │   Storage   │  │      Storage        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Cache     │  │  Temporary  │  │      Result         │  │
│  │   Data      │  │    Data     │  │      Data           │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    O(1) Bulk Deallocation
```

### Arena Lifetime Management

- **Unit Scope**: Each compilation unit gets its own arena
- **Pass Scope**: Temporary data uses sub-arenas with automatic cleanup
- **Cache Scope**: Long-lived cache data uses separate persistent arena
- **Diagnostic Scope**: Error data persists until result consumption

### Memory Safety Guarantees

```zig
// Arena lifetime assertions (enforced in debug builds)
debug.assert(arena.queryFree() >= expected_minimum);
debug.assert(arena.isValidPointer(symbol_ptr));
debug.assert(!arena.hasLeaks());
```

## Caching System

### Cache Key Design

**Stable Cache Keys** ensure deterministic behavior across compilation runs:

```zig
CacheKey = (unit_id, node_id, canonical_hash)
```

- `unit_id`: Compilation unit identifier
- `node_id`: AST node identifier
- `canonical_hash`: BLAKE3 hash of semantic context

**Never include transient flags** in cache keys to maintain stability.

### Cache Invariants

1. **Determinism**: Same input always produces same cache key
2. **Isolation**: Cache entries are independent of compilation order
3. **Invalidation**: Cache automatically invalidates on source changes
4. **Coherence**: Cache state is consistent across validation passes

### Deduplication Strategy

**Error Deduplication** uses stable tuple hashing:

```zig
DedupKey = (error_code, file_id, start_offset, end_offset, canonical_message_id)
```

- Uses BLAKE3→u64 to avoid hash collisions
- Preserves error location precision
- Maintains diagnostic quality while reducing noise

## Feature Flag System

### Validation Modes

- **`--validate=optimized`**: Production-ready optimized validation (default in CI)
- **`--validate=baseline`**: Safe fallback implementation (default in debug)
- **`--validate=auto`**: Automatic selection based on performance characteristics

### Fallback Mechanism

```zig
if (optimized_validation_fails || performance_contract_violated) {
    if (fallback_enabled && baseline_engine_available) {
        return baseline_engine.validate(unit);
    }
}
```

### Timeout Protection

**Timeout Fuse**: If validation exceeds `max_ms`, automatically drop to baseline:

```zig
const timeout_ms = config.contract.timeout_ms; // Default: 100ms
if (validation_time > timeout_ms) {
    emit_slo_warning();
    return baseline_validator.validate(unit);
}
```

## Performance Contracts

### Enforced Thresholds

| Metric | Threshold | Tolerance | Enforcement |
|--------|-----------|-----------|-------------|
| `validation_ms` | ≤ 25ms | ±10% | CI Hard Gate |
| `error_dedup_ratio` | ≥ 0.85 | None | CI Hard Gate |
| `cache_hit_rate` | ≥ 0.95 | None | CI Hard Gate |
| `regression_drift` | ≤ 10% | 7-day trend | CI Alert |

### Contract Metadata

Test suites include performance metadata:

```zig
// performance: validation_ms < 25 ±10% @99%
// quality: error_dedup_ratio >= 0.85
// cache: hit_rate >= 0.95 over 500 runs
```

### SLO Monitoring

**Service Level Objectives** are continuously monitored:

- **Availability**: 99.9% successful validations
- **Latency**: P95 < 25ms, P99 < 50ms
- **Quality**: Error dedup ratio > 85%
- **Efficiency**: Cache hit rate > 95%

## Integration Points

### CLI Integration

```bash
# Enable optimized validation with timing
janus trace dispatch --timing program.jan

# Force baseline validation for debugging
janus compile --validate=baseline program.jan

# Disable fallback for performance testing
janus compile --validate=optimized --no-validate-fallback program.jan
```

### RPC Integration

Validation metrics are exposed via:

- **`janusd` `/metrics` endpoint**: Prometheus-compatible metrics
- **Dispatch Map RPC**: Analysis response includes performance fields
- **LSP Integration**: Real-time validation with performance monitoring

### CI Integration

The `validation-bench` job enforces contracts:

```yaml
# Hard gates that fail the build
gates:
  - validation_ms_p95 <= 25ms
  - dedup_ratio >= 0.85
  - cache_hit_rate >= 0.95

# Trend monitoring with regression detection
monitoring:
  - 7_day_drift_threshold: 10%
  - performance_regression_alert: enabled
```

## Troubleshooting

### Performance Issues

**Symptom**: Validation time exceeds contract thresholds

**Diagnosis**:
1. Check cache hit rate - low rates indicate cache invalidation issues
2. Profile symbol resolution - O(N²) searches indicate hash table problems
3. Monitor memory allocation - excessive allocations indicate arena misuse

**Solutions**:
- Verify cache key stability across runs
- Check for brute-force searches in type system
- Ensure proper arena scoping and cleanup

### Memory Issues

**Symptom**: Memory leaks or excessive memory usage

**Diagnosis**:
1. Run with leak detection: `zig test -Dsanitize-memory=true`
2. Check arena lifetime assertions in debug builds
3. Monitor arena utilization patterns

**Solutions**:
- Ensure all arenas are properly scoped to unit lifetime
- Verify no pointers escape arena boundaries
- Check for circular references in cached data

### Cache Issues

**Symptom**: Low cache hit rates or inconsistent results

**Diagnosis**:
1. Verify cache key stability - keys should be deterministic
2. Check for transient data in cache keys
3. Monitor cache invalidation patterns

**Solutions**:
- Use only stable identifiers in cache keys
- Exclude compilation flags from cache key computation
- Implement proper cache invalidation on source changes

## Development Guidelines

### Adding New Validation Rules

1. **Performance First**: Ensure O(1) or O(log n) complexity
2. **Cache Friendly**: Design for aggressive memoization
3. **Arena Aware**: Use scoped allocation patterns
4. **Contract Bound**: Include performance metadata in tests

### Testing Requirements

1. **Unit Tests**: Cover all validation logic paths
2. **Performance Tests**: Verify complexity guarantees
3. **Integration Tests**: Test with real ASTDB and components
4. **Regression Tests**: Prevent performance degradation

### Code Review Checklist

- [ ] Performance complexity documented and verified
- [ ] Arena allocation patterns follow lifetime rules
- [ ] Cache keys are stable and deterministic
- [ ] Error handling includes proper fallback logic
- [ ] Tests include performance contract metadata

## Future Enhancements

### Planned Optimizations

1. **Parallel Validation**: Multi-threaded semantic analysis
2. **Incremental Updates**: Fine-grained cache invalidation
3. **Predictive Caching**: ML-powered cache preloading
4. **Adaptive Thresholds**: Dynamic performance contract adjustment

### Research Areas

1. **Advanced Deduplication**: Semantic similarity-based error grouping
2. **Cross-Unit Caching**: Shared cache across compilation units
3. **Streaming Validation**: Real-time validation for large files
4. **Distributed Validation**: Cloud-based validation for massive codebases

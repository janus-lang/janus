<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Trace Command

The `janus trace` command provides performance monitoring and debugging capabilities for the Janus compiler, with special focus on semantic validation metrics.

## Usage

```bash
janus trace <subcommand> [options] [arguments]
```

## Subcommands

### `dispatch`

Trace semantic validation performance with detailed metrics.

```bash
janus trace dispatch [--timing] <source_file>
```

**Options:**
- `--timing`: Enable detailed performance metrics and timing information

**Examples:**

```bash
# Basic validation tracing
janus trace dispatch main.jan

# Detailed performance analysis
janus trace dispatch --timing complex_program.jan

# Trace with specific validation mode
JANUS_VALIDATE=baseline janus trace dispatch --timing program.jan
```

## Performance Metrics

When `--timing` is enabled, the trace command exposes the following metrics:

### Core Metrics

| Metric | Description | Unit | Contract Threshold |
|--------|-------------|------|-------------------|
| `validation_ms` | Total semantic validation time | milliseconds | ≤ 25ms |
| `error_dedup_ratio` | Error deduplication efficiency | ratio (0-1) | ≥ 0.85 |
| `cache_hit_rate` | Validation cache hit rate | ratio (0-1) | ≥ 0.95 |

### Detailed Metrics

| Metric | Description | Unit |
|--------|-------------|------|
| `cache_hits` | Number of cache hits | count |
| `cache_misses` | Number of cache misses | count |
| `total_errors` | Total errors before deduplication | count |
| `deduped_errors` | Errors after deduplication | count |
| `fallback_triggered` | Whether fallback was used | boolean |
| `timeout_occurred` | Whether timeout occurred | boolean |

## Output Formats

### Human-Readable Output

```
🔍 Tracing semantic validation for: main.jan
📊 Validation mode: optimized
⏱️  Performance monitoring enabled

✅ Validation successful

📈 Performance Metrics:
├─ Total validation time: 12.34 ms
├─ Validation time (engine): 11.89 ms
├─ Error deduplication ratio: 0.923
├─ Cache hit rate: 0.967
├─ Cache hits: 145
├─ Cache misses: 5
├─ Total errors: 0
├─ Deduped errors: 0
├─ Fallback triggered: No
├─ Timeout occurred: No
└─ ✅ Performance contract: PASSED

📊 Validation Summary:
├─ Success: true
├─ Diagnostics: 0
├─ Error count: 0
├─ Warning count: 2
└─ Type annotations: 47
```

### JSON Output

For tooling integration, metrics are also provided in JSON format:

```json
{
  "validation_ms": 11.89,
  "error_dedup_ratio": 0.923,
  "cache_hit_rate": 0.967,
  "cache_hits": 145,
  "cache_misses": 5,
  "total_errors": 0,
  "deduped_errors": 0,
  "fallback_triggered": false,
  "timeout_occurred": false
}
```

## Integration with CI/CD

### Performance Contract Enforcement

The trace command is used in CI to enforce performance contracts:

```yaml
# Example CI usage
- name: Validate Performance
  run: |
    janus trace dispatch --timing large_program.jan > metrics.txt

    # Extract metrics for contract checking
    validation_ms=$(grep "validation_ms" metrics.txt | jq -r '.validation_ms')

    # Enforce contracts
    if (( $(echo "$validation_ms > 25.0" | bc -l) )); then
      echo "Performance contract violation: ${validation_ms}ms > 25ms"
      exit 1
    fi
```

### Metrics Collection

For trend analysis and monitoring:

```bash
# Collect metrics for dashboard
janus trace dispatch --timing *.jan | \
  grep "JSON Metrics" -A 20 | \
  jq '.validation_ms, .cache_hit_rate, .error_dedup_ratio' | \
  prometheus-push-gateway
```

## Environment Variables

### Validation Configuration

- `JANUS_VALIDATE`: Set validation mode (`optimized`, `baseline`, `auto`)
- `JANUS_DEBUG_SEMANTIC`: Enable debug output for semantic analysis
- `JANUS_VALIDATE_TIMEOUT`: Set timeout in milliseconds (default: 100)

### Examples

```bash
# Force baseline validation
JANUS_VALIDATE=baseline janus trace dispatch program.jan

# Enable debug output
JANUS_DEBUG_SEMANTIC=1 janus trace dispatch --timing program.jan

# Set custom timeout
JANUS_VALIDATE_TIMEOUT=200 janus trace dispatch program.jan
```

## Command Line Flags

### Global Validation Flags

These flags can be used with any janus command:

- `--validate=<mode>`: Set validation mode (optimized, baseline, auto)
- `--validate-debug`: Enable debug mode for validation
- `--no-validate-metrics`: Disable metrics collection
- `--no-validate-fallback`: Disable automatic fallback
- `--validate-timeout=<ms>`: Set validation timeout

### Examples

```bash
# Compile with baseline validation
janus compile --validate=baseline main.jan

# Disable fallback for performance testing
janus compile --validate=optimized --no-validate-fallback main.jan

# Custom timeout for large files
janus trace dispatch --validate-timeout=500 --timing huge_program.jan
```

## Performance Analysis

### Interpreting Metrics

**Validation Time (`validation_ms`)**:
- **< 10ms**: Excellent performance
- **10-25ms**: Good performance (within contract)
- **> 25ms**: Performance contract violation

**Cache Hit Rate (`cache_hit_rate`)**:
- **> 0.95**: Excellent caching efficiency
- **0.85-0.95**: Good caching (investigate misses)
- **< 0.85**: Poor caching (check cache key stability)

**Error Deduplication (`error_dedup_ratio`)**:
- **> 0.90**: Excellent deduplication
- **0.85-0.90**: Good deduplication (within contract)
- **< 0.85**: Poor deduplication (check error similarity)

### Troubleshooting Performance Issues

**High Validation Time**:
1. Check cache hit rate - low rates indicate cache problems
2. Profile with `--validate-debug` to identify bottlenecks
3. Verify O(1) type operations are being used

**Low Cache Hit Rate**:
1. Check for unstable cache keys
2. Verify deterministic compilation order
3. Look for transient data in cache key computation

**Poor Error Deduplication**:
1. Check error message generation for consistency
2. Verify stable error location computation
3. Review deduplication key generation logic

## Advanced Usage

### Benchmarking

Compare validation modes:

```bash
# Benchmark optimized mode
time janus trace dispatch --timing program.jan

# Benchmark baseline mode
JANUS_VALIDATE=baseline time janus trace dispatch --timing program.jan

# Compare results
janus-bench-compare optimized_results.json baseline_results.json
```

### Profiling Integration

Integration with external profilers:

```bash
# Profile with perf
perf record janus trace dispatch --timing large_program.jan
perf report

# Profile with valgrind
valgrind --tool=callgrind janus trace dispatch program.jan
kcachegrind callgrind.out.*
```

### Automated Testing

Use in test suites:

```bash
#!/bin/bash
# Performance regression test

for file in test_programs/*.jan; do
  echo "Testing $file..."

  metrics=$(janus trace dispatch --timing "$file" | grep "JSON Metrics" -A 20)
  validation_ms=$(echo "$metrics" | jq -r '.validation_ms')

  if (( $(echo "$validation_ms > 25.0" | bc -l) )); then
    echo "FAIL: $file validation time ${validation_ms}ms exceeds 25ms"
    exit 1
  fi

  echo "PASS: $file validated in ${validation_ms}ms"
done
```

## Integration Protocol Compliance

The trace command implements the Integration Protocol requirements:

✅ **Metrics Exposure**: All required metrics exposed via CLI and JSON
✅ **Performance Contracts**: Automatic contract checking and reporting
✅ **CI Integration**: Designed for automated performance validation
✅ **Tooling Support**: JSON output for dashboard and monitoring integration
✅ **Fallback Monitoring**: Tracks fallback usage and timeout events

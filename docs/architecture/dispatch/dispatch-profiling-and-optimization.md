<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Dispatch Profiling and Optimization Hints

This document describes the dispatch profiling system and optimization hints generator in Janus, which provides runtime performance analysis and actionable optimization recommendations for multiple dispatch code.

## Overview

The dispatch profiling system consists of two main components:

1. **DispatchProfiler**: Runtime profiling system that collects performance data about dispatch calls
2. **OptimizationHintsGenerator**: Analysis system that generates actionable optimization recommendations based on profiling data

Together, these systems enable developers to identify performance bottlenecks and apply targeted optimizations to their multiple dispatch code.

## Architecture

### System Components

```
┌─────────────────────┐    ┌──────────────────────────┐    ┌─────────────────────┐
│   DispatchProfiler  │    │ OptimizationHintsGenerator│    │  Compiler Backend   │
├─────────────────────┤    ├──────────────────────────┤    ├─────────────────────┤
│ - Call site tracking│    │ - Hint generation        │    │ - Apply optimizations│
│ - Performance metrics│    │ - Priority analysis      │    │ - Code generation   │
│ - Hot path detection│    │ - Confidence scoring     │    │ - Performance tuning│
│ - Session management│    │ - Export capabilities    │    │ - Automatic opts    │
└─────────────────────┘    └──────────────────────────┘    └─────────────────────┘
```

### Data Flow

1. **Runtime Profiling**: Dispatch calls are instrumented to collect timing and frequency data
2. **Analysis**: Profiling data is analyzed to identify patterns and opportunities
3. **Hint Generation**: Optimization hints are generated with confidence scores and priority levels
4. **Application**: Hints can be applied manually or automatically by the compiler

## Profiling System

### Call Site Tracking

The profiler tracks individual call sites with detailed metrics:

```zig
const call_site = DispatchProfiler.CallSiteId{
    .source_file = "main.jan",
    .line = 42,
    .column = 10,
    .signature_name = "process_data",
};

// Record dispatch call
profiler.recordDispatchCall(call_site, dispatch_time_ns, implementation, was_cache_hit);
```

### Performance Metrics

For each call site, the profiler collects:

- **Call frequency**: Total calls and calls per second
- **Timing data**: Min, max, and average dispatch times
- **Implementation distribution**: Which implementations are used and how often
- **Cache performance**: Hit/miss ratios and cache efficiency
- **Hot path classification**: Automatic identification of performance-critical paths

### Session Management

Profiling is organized into sessions for controlled data collection:

```zig
// Start profiling session
profiler.startSession(config);

// ... application runs with profiling enabled ...

// End session and analyze data
profiler.endSession();

// Generate report
try profiler.generateReport(std.io.getStdOut().writer());
```

## Optimization Hints

### Hint Types

The system generates several types of optimization hints:

#### 1. Static Dispatch Optimization
**When**: Single implementation dominates (>95% of calls)
**Benefit**: 1.5-2x speedup by eliminating runtime lookup
**Example**:
```janus
// Before: dynamic dispatch
process_data(input)

// After: static dispatch hint
@static process_data(input)
```

#### 2. Monomorphization
**When**: Low implementation diversity with high usage
**Benefit**: 1.6x speedup through type specialization
**Example**:
```janus
// Enable monomorphization for common patterns
@monomorphize process_data
```

#### 3. Inline Caching
**When**: Poor cache hit ratio (<70%) with high frequency
**Benefit**: 1.3-1.5x speedup through call-site caching
**Example**:
```janus
// Add inline cache at call site
@inline_cache process_data(input)
```

#### 4. Hot Path Specialization
**When**: Critical hot paths with high dispatch overhead
**Benefit**: 2-3x speedup through specialized code generation
**Example**:
```janus
// Generate optimized hot path
@specialize_hot_path process_data(input)
```

#### 5. Table Compression
**When**: Large dispatch tables with memory pressure
**Benefit**: Reduced memory usage and improved cache locality
**Example**:
```bash
# Compiler flag
janus compile --compress-dispatch-tables
```

#### 6. Profile-Guided Optimization
**When**: Complex optimization opportunities identified through profiling
**Benefit**: Variable, often 2-4x speedup
**Example**:
```bash
# Use profiling data for optimization
janus compile --profile-guided-optimization profile.data
```

### Hint Prioritization

Hints are prioritized based on:

- **Estimated speedup**: Higher speedups get higher priority
- **Confidence level**: More reliable hints are prioritized
- **Impact scope**: Broader impact gets higher priority

Priority levels:
- **Critical**: >3x speedup, >90% confidence
- **High**: >2x speedup, >80% confidence
- **Medium**: >1.5x speedup, >70% confidence
- **Low**: >1.2x speedup, >60% confidence

### Automatic Optimization

High-confidence hints (>90%) can be applied automatically:

```zig
const auto_candidates = hints_generator.getAutomaticOptimizationCandidates();
for (auto_candidates) |hint| {
    // Apply optimization automatically
    try compiler.applyOptimization(hint);
}
```

## Usage Examples

### Basic Profiling

```zig
const std = @import("std");
const DispatchProfiler = @import("dispatch_profiler.zig").DispatchProfiler;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize profiler
    const config = DispatchProfiler.ProfilingConfig.default();
    var profiler = DispatchProfiler.init(allocator, config);
    defer profiler.deinit();

    // Start profiling
    profiler.startSession(null);

    // Run application code...
    try runApplication();

    // End profiling and generate report
    profiler.endSession();
    try profiler.generateReport(std.io.getStdOut().writer());
}
```

### Generating Optimization Hints

```zig
const OptimizationHintsGenerator = @import("optimization_hints.zig").OptimizationHintsGenerator;

pub fn analyzeAndOptimize(profiler: *DispatchProfiler) !void {
    const allocator = std.heap.page_allocator;

    // Initialize hints generator
    const config = OptimizationHintsGenerator.HintConfig.default();
    var generator = OptimizationHintsGenerator.init(allocator, config);
    defer generator.deinit();

    // Generate hints from profiling data
    try generator.generateHints(profiler);

    // Get high-priority hints
    const high_priority = generator.getHintsByPriority(.high);
    defer allocator.free(high_priority);

    std.debug.print("High Priority Optimizations:\n");
    for (high_priority) |hint| {
        std.debug.print("  - {s} (speedup: {d:.1}x)\n", .{ hint.title, hint.estimated_speedup });
    }

    // Generate comprehensive report
    try generator.generateReport(std.io.getStdOut().writer());
}
```

### Export Formats

The system supports multiple export formats:

```zig
// Text report (human-readable)
try profiler.exportData(writer, .text);

// JSON (machine-readable)
try profiler.exportData(writer, .json);

// CSV (spreadsheet analysis)
try profiler.exportData(writer, .csv);

// Flamegraph (visualization)
try profiler.exportData(writer, .flamegraph);

// Compiler flags (direct application)
try hints_generator.exportHints(writer, .compiler_flags);
```

## Configuration

### Profiling Configuration

```zig
const config = DispatchProfiler.ProfilingConfig{
    .enabled = true,
    .sample_rate = 1.0,                    // 100% sampling
    .hot_path_threshold = 0.7,             // Hotness score threshold
    .min_calls_for_analysis = 100,         // Minimum calls to analyze
    .max_call_sites = 10000,               // Maximum tracked call sites
    .enable_timing = true,                 // Collect timing data
    .enable_cache_tracking = true,         // Track cache performance
    .enable_implementation_tracking = true, // Track implementation usage
    .output_format = .text,                // Default output format
};
```

### Hints Configuration

```zig
const config = OptimizationHintsGenerator.HintConfig{
    .min_calls_for_static_dispatch = 1000,     // Static dispatch threshold
    .min_calls_for_monomorphization = 5000,    // Monomorphization threshold
    .min_calls_for_inline_caching = 500,       // Inline caching threshold
    .min_confidence_for_suggestion = 0.6,      // Suggestion confidence
    .min_confidence_for_automatic = 0.9,       // Automatic optimization
    .min_speedup_for_suggestion = 1.2,         // Minimum speedup
    .min_dispatch_time_for_optimization = 500, // 0.5μs threshold
    .hot_path_call_frequency_threshold = 1000.0, // 1000 calls/sec
    .hot_path_time_percentage_threshold = 5.0,   // 5% of total time
    .include_code_examples = true,              // Include examples
    .include_performance_estimates = true,      // Include estimates
    .include_implementation_details = false,    // Implementation details
};
```

## Integration with Build System

### Compiler Integration

```bash
# Enable profiling during compilation
janus compile --enable-profiling main.jan

# Run with profiling
./main --profile-output=profile.data

# Generate optimization hints
janus analyze-profile profile.data --output=hints.json

# Apply automatic optimizations
janus compile --apply-hints=hints.json main.jan
```

### Build Script Integration

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = .{ .path = "src/main.jan" },
    });

    // Enable profiling in debug builds
    if (b.option(bool, "profile", "Enable dispatch profiling") orelse false) {
        exe.addBuildOption(bool, "enable_profiling", true);
    }

    // Apply optimization hints if available
    if (b.option([]const u8, "hints", "Optimization hints file")) |hints_file| {
        exe.addBuildOption([]const u8, "optimization_hints", hints_file);
    }
}
```

## Performance Impact

### Profiling Overhead

- **Disabled**: 0% overhead
- **Enabled (100% sampling)**: 1-5% overhead
- **Enabled (10% sampling)**: 0.1-0.5% overhead

### Memory Usage

- **Per call site**: ~200 bytes
- **Per signature**: ~150 bytes
- **Per session**: ~1KB base overhead

### Optimization Benefits

Typical speedups achieved through optimization hints:

| Optimization Type | Typical Speedup | Memory Impact |
|-------------------|-----------------|---------------|
| Static Dispatch | 1.5-2.0x | Neutral |
| Monomorphization | 1.4-1.8x | +10-20% |
| Inline Caching | 1.3-1.5x | +5-10% |
| Hot Path Specialization | 2.0-3.0x | +20-50% |
| Table Compression | 1.1-1.3x | -20-40% |
| Profile-Guided | 1.8-4.0x | Variable |

## Best Practices

### Profiling Strategy

1. **Profile representative workloads**: Use realistic data and usage patterns
2. **Profile long enough**: Collect data over sufficient time for statistical significance
3. **Profile different scenarios**: Test various input types and code paths
4. **Use appropriate sampling**: Balance overhead vs. accuracy based on needs

### Optimization Application

1. **Start with high-confidence hints**: Apply automatic optimizations first
2. **Validate improvements**: Measure actual performance gains
3. **Consider trade-offs**: Balance speed vs. memory usage
4. **Iterate**: Re-profile after optimizations to find new opportunities

### Development Workflow

1. **Development**: Use profiling to identify bottlenecks
2. **Testing**: Validate optimizations don't break functionality
3. **Staging**: Profile with production-like workloads
4. **Production**: Apply proven optimizations

## Troubleshooting

### Common Issues

#### Low Cache Hit Ratios
**Symptoms**: Cache hit ratios <50%
**Causes**: Poor data locality, large working sets
**Solutions**: Inline caching, data structure optimization

#### High Dispatch Overhead
**Symptoms**: Dispatch time >1μs consistently
**Causes**: Complex type hierarchies, large dispatch tables
**Solutions**: Static dispatch, table compression, specialization

#### Inaccurate Profiling Data
**Symptoms**: Inconsistent or unrealistic measurements
**Causes**: Insufficient sampling, timing interference
**Solutions**: Increase sample rate, longer profiling sessions

#### Memory Usage Growth
**Symptoms**: Increasing memory usage during profiling
**Causes**: Too many tracked call sites, memory leaks
**Solutions**: Reduce max_call_sites, check for leaks

### Debugging

Enable verbose profiling:
```bash
export JANUS_PROFILE_VERBOSE=1
./myapp
```

Check profiling statistics:
```zig
const stats = profiler.counters;
std.debug.print("Profiling stats: {}\n", .{stats});
```

Validate hint generation:
```zig
const hints = generator.getHints();
for (hints) |hint| {
    if (hint.confidence < 0.5) {
        std.debug.print("Low confidence hint: {}\n", .{hint});
    }
}
```

## Future Enhancements

### Planned Features

- **Machine learning**: AI-powered optimization recommendation
- **Distributed profiling**: Aggregate data across multiple runs
- **Real-time optimization**: Dynamic optimization during execution
- **Visual profiling**: Interactive performance visualization tools

### Research Areas

- **Predictive profiling**: Anticipate optimization opportunities
- **Cross-language profiling**: Profile dispatch across language boundaries
- **Hardware-aware optimization**: Leverage CPU-specific features
- **Adaptive optimization**: Self-tuning optimization parameters

## Conclusion

The dispatch profiling and optimization hints system provides a comprehensive solution for analyzing and optimizing multiple dispatch performance in Janus. By combining runtime profiling with intelligent analysis, developers can identify bottlenecks and apply targeted optimizations to achieve significant performance improvements.

The system's design emphasizes:
- **Low overhead**: Minimal impact on application performance
- **Actionable insights**: Clear, prioritized optimization recommendations
- **Automation support**: High-confidence optimizations can be applied automatically
- **Integration**: Seamless integration with the build system and development workflow

For more information, see:
- [Multiple Dispatch System Documentation](multiple-dispatch-guide.md)
- [Dispatch Table Caching Guide](dispatch-table-caching.md)
- [Performance Optimization Guide](dispatch-performance-guide.md)

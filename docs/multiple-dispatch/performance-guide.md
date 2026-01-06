<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Multiple Dispatch Performance Guide

This guide provides comprehensive information on optimizing multiple dispatch performance in Janus applications.

## Table of Contents

- [Performance Overview](#performance-overview)
- [Static vs Dynamic Dispatch](#static-vs-dynamic-dispatch)
- [Optimization Strategies](#optimization-strategies)
- [Profiling and Monitoring](#profiling-and-monitoring)
- [Memory Optimization](#memory-optimization)
- [Best Practices](#best-practices)

## Performance Overview

### Dispatch Cost Hierarchy

Janus multiple dispatch has different performance characteristics depending on how dispatch is resolved:

1. **Static Dispatch (Zero Cost)**: Types known at compile time
2. **Cached Dynamic Dispatch (Low Cost)**: Runtime lookup with caching
3. **Full Dynamic Dispatch (Higher Cost)**: Complete runtime resolution
4. **Cross-Module Dispatch (Variable Cost)**: Depends on module loading strategy

### Performance Metrics

Key metrics to monitor:

- **Dispatch Overhead Ratio**: Time spent in dispatch vs actual function execution
- **Cache Hit Rate**: Percentage of dispatch lookups served from cache
- **Memory Usage**: Total memory consumed by dispatch tables
- **Hot Path Efficiency**: Performance of frequently called functions

## Static vs Dynamic Dispatch

### Static Dispatch (Preferred)

**When it occurs:**
- Types are known at compile time
- No polymorphic variables involved
- Direct function calls with concrete types

**Example:**
```janus
func process_numbers(data: []i32) -> i64 do
  let sum: i64 = 0
  for value in data do
    sum += process(value)  // Static dispatch - zero overhead
  end
  return sum
end

func process(value: i32) -> i64 do
  return value * value + value
end
```

**Performance characteristics:**
- Zero runtime overhead
- Direct function calls
- Full compiler optimization
- Inlining possible

### Dynamic Dispatch (When Necessary)

**When it occurs:**
- Types not known at compile time
- Polymorphic variables (`any` type)
- Cross-module calls with runtime loading

**Example:**
```janus
func process_mixed(items: []any) do
  for item in items do
    process(item)  // Dynamic dispatch - runtime cost
  end
end

// Make cost explicit
func process_dynamic(item: any) -> string {.dispatch: dynamic.} do
  return process(item)
end
```

**Performance characteristics:**
- Runtime type lookup
- Table traversal cost
- Cache dependency
- Limited optimization

## Optimization Strategies

### 1. Minimize Dynamic Dispatch

**Strategy: Type-Specific Batching**

```janus
// Before: Dynamic dispatch per item
func process_items_slow(items: []any) do
  for item in items do
    process(item)  // Dynamic dispatch each iteration
  end
end

// After: Batch by type for static dispatch
func process_items_fast(items: []any) do
  // Group items by type
  let int_items = []
  let float_items = []
  let string_items = []

  for item in items do
    match typeof(item) {
      i32 => int_items.append(item as i32)
      f64 => float_items.append(item as f64)
      string => string_items.append(item as string)
    }
  end

  // Process homogeneous batches with static dispatch
  for item in int_items do
    process(item)  // Static dispatch
  end

  for item in float_items do
    process(item)  // Static dispatch
  end

  for item in string_items do
    process(item)  // Static dispatch
  end
end
```

**Performance improvement:** 5-10x faster for large datasets

### 2. Hot Path Optimization

**Strategy: Inline Critical Dispatches**

```janus
// Mark hot functions for aggressive optimization
{.optimize: inline_dispatch.}
func transform_batch(data: []i32) -> []i32 do
  let result = []
  for value in data do
    result.append(transform(value))  // Inlined dispatch
  end
  return result
end

{.optimize: inline_dispatch.}
func transform(value: i32) -> i32 do
  return value * 2 + 1
end
```

**Strategy: Specialized Implementations**

```janus
// Generic implementation
func process(data: []any) -> []any do
  let result = []
  for item in data do
    result.append(transform(item))  // Dynamic dispatch
  end
  return result
end

// Specialized for hot path
func process_i32_batch(data: []i32) -> []i32 do
  let result = []
  for item in data do
    result.append(transform(item))  // Static dispatch
  end
  return result
end

// Route to specialized version when possible
func process_optimized(data: []any) -> []any do
  // Check if we can use specialized version
  if all_same_type(data, i32) then
    return process_i32_batch(data as []i32) as []any
  else
    return process(data)  // Fall back to generic
  end
end
```

### 3. Cache-Friendly Dispatch Tables

**Strategy: Optimize Table Layout**

```janus
// Configure dispatch table for cache efficiency
let table = OptimizedDispatchTable.init("function_family")

// Optimize based on call frequency
table.optimize_layout_by_frequency()

// Use cache-friendly data structures
table.set_layout_strategy(LayoutStrategy.CacheFriendly)

// Monitor cache performance
let stats = table.get_cache_stats()
if stats.miss_rate > 0.1 {
  table.reoptimize_layout()
}
```

**Strategy: Table Compression**

```janus
// For large function families, use compressed tables
let large_table = CompressedDispatchTable.init("serialization")
large_table.set_compression_level(CompressionLevel.Balanced)

// Trade memory for speed
large_table.enable_lookup_acceleration()
```

### 4. Reduce Function Family Size

**Strategy: Split Large Families**

```janus
// Before: One large family
func process(data: Type1) -> Result
func process(data: Type2) -> Result
func process(data: Type3) -> Result
// ... 50 more implementations

// After: Split by domain
func process_primitives(data: PrimitiveType) -> Result
func process_collections(data: CollectionType) -> Result
func process_custom(data: CustomType) -> Result
```

**Benefits:**
- Smaller dispatch tables
- Better cache locality
- Faster lookup times
- Easier to optimize

### 5. Precompute Common Dispatches

**Strategy: Dispatch Table Prewarming**

```janus
// Prewarm dispatch tables for common types
func prewarm_dispatch_tables() do
  // Touch common dispatch paths
  let dummy_i32 = 0
  let dummy_f64 = 0.0
  let dummy_string = ""

  // This populates the dispatch cache
  _ = serialize(dummy_i32)
  _ = serialize(dummy_f64)
  _ = serialize(dummy_string)
end

// Call during application startup
func main() do
  prewarm_dispatch_tables()

  // Now dispatch is fast for common types
  run_application()
end
```

## Profiling and Monitoring

### Built-in Profiler

```janus
// Initialize comprehensive profiler
let profiler = DispatchProfiler.init()
profiler.config.track_call_sites = true
profiler.config.measure_dispatch_overhead = true
profiler.config.detect_hot_paths = true
profiler.config.warn_expensive_patterns = true

// Register call sites for detailed tracking
let call_site_id = profiler.register_call_site(
  "process",
  SourceLocation{ file: "main.janus", line: 42, column: 10 }
)

// Your application code here...

// Generate performance report
profiler.generate_report()
```

**Sample Output:**
```
🔥 Multiple Dispatch Performance Report

Overall Statistics:
  Total dispatch calls: 1,247,832
  Static dispatch: 1,156,234 (92.7%) - ✅ Excellent
  Dynamic dispatch: 91,598 (7.3%) - ⚠️ Monitor
  Average dispatch time: 12.3ns
  Dispatch overhead ratio: 2.1% - ✅ Good

Hot Paths (>1000 calls):
  process(i32) -> 856,234 calls, 8.2ns avg - ✅ Optimized
  serialize(string) -> 234,567 calls, 15.7ns avg - ✅ Good
  transform([]f64) -> 89,432 calls, 45.2ns avg - ⚠️ Consider optimization

Slow Dispatches (>100μs):
  process(any) -> 234 calls, 145.2μs avg - ❌ Needs attention
  serialize(ComplexType) -> 67 calls, 234.7μs avg - ❌ Needs attention

Recommendations:
  1. Consider specializing process(any) for common types
  2. Add caching for ComplexType serialization
  3. Hot path process(i32) is well optimized
```

### Memory Profiler

```janus
// Monitor dispatch table memory usage
let memory_profiler = DispatchMemoryProfiler.init()

// Register tables for monitoring
memory_profiler.register_table("serialize", serialize_table)
memory_profiler.register_table("process", process_table)

// Monitor during execution
memory_profiler.start_monitoring()

// Your application...

// Generate memory report
let stats = memory_profiler.get_memory_stats()
println("Total dispatch table memory: {stats.total_memory_mb}MB")
println("Cache efficiency: {stats.cache_efficiency * 100}%")

if stats.total_memory_mb > 50 {
  println("⚠️ High memory usage - consider table optimization")
}
```

### Real-time Monitoring

```janus
// Set up real-time performance monitoring
let monitor = RealTimeDispatchMonitor.init()
monitor.set_alert_threshold_overhead(0.05)  // 5% overhead threshold
monitor.set_alert_threshold_memory(100)     // 100MB memory threshold

monitor.on_high_overhead = |overhead| {
  println("⚠️ High dispatch overhead detected: {overhead * 100}%")
  // Trigger optimization
  optimize_hot_paths()
}

monitor.on_memory_pressure = |memory_mb| {
  println("⚠️ High dispatch table memory: {memory_mb}MB")
  // Trigger cleanup
  cleanup_unused_tables()
}

monitor.start()
```

## Memory Optimization

### Dispatch Table Management

```janus
// Efficient table lifecycle management
let table_manager = DispatchTableManager.init()

// Use reference counting for shared tables
let shared_table = table_manager.get_shared_table("common_operations")

// Automatic cleanup of unused tables
table_manager.enable_automatic_cleanup()
table_manager.set_cleanup_interval(Duration.minutes(5))

// Manual cleanup when needed
table_manager.cleanup_unused_tables()
```

### Memory-Efficient Data Structures

```janus
// Use compact representations for large families
let compact_table = CompactDispatchTable.init("large_family")
compact_table.set_memory_optimization(MemoryOptimization.Aggressive)

// Trade lookup speed for memory
compact_table.enable_compression()

// Monitor memory vs performance trade-off
let metrics = compact_table.get_performance_metrics()
if metrics.lookup_time_ns > 50 {
  // Revert to faster representation
  compact_table.disable_compression()
}
```

### Garbage Collection Integration

```janus
// Integrate with GC for optimal memory management
let gc_integration = DispatchGCIntegration.init()

// Register tables for GC-aware management
gc_integration.register_table(dispatch_table)

// Optimize collection timing
gc_integration.set_collection_strategy(CollectionStrategy.LowLatency)

// Handle memory pressure events
gc_integration.on_memory_pressure = || {
  // Aggressively clean up dispatch tables
  dispatch_table.compact()
  dispatch_table.cleanup_unused_entries()
}
```

## Best Practices

### 1. Design for Static Dispatch

```janus
// ✅ Good: Specific types enable static dispatch
func process_user_data(users: []User) -> []ProcessedUser do
  let result = []
  for user in users do
    result.append(process(user))  // Static dispatch
  end
  return result
end

// ❌ Avoid: Generic types force dynamic dispatch
func process_data(data: []any) -> []any do
  let result = []
  for item in data do
    result.append(process(item))  // Dynamic dispatch
  end
  return result
end
```

### 2. Use Explicit Cost Annotations

```janus
// ✅ Good: Make dynamic dispatch costs visible
func handle_request(request: any) -> Response {.dispatch: dynamic.} do
  return process_request(request)  // Cost is explicit
end

// ❌ Avoid: Hidden dynamic dispatch costs
func handle_request(request: any) -> Response do
  return process_request(request)  // Hidden cost
end
```

### 3. Profile Early and Often

```janus
// ✅ Good: Regular performance monitoring
func performance_critical_function() do
  let profiler = DispatchProfiler.init()
  profiler.start_profiling()

  // Your code here...

  let metrics = profiler.stop_profiling()
  if metrics.overhead_ratio > 0.05 {
    println("⚠️ Performance regression detected")
  }
end
```

### 4. Optimize Hot Paths

```janus
// ✅ Good: Specialized implementations for hot paths
func process_hot_path(data: []i32) -> i64 {.optimize: aggressive.} do
  let sum: i64 = 0
  for value in data do
    sum += process_i32_optimized(value)  // Specialized, inlined
  end
  return sum
end

func process_i32_optimized(value: i32) -> i64 {.inline: always.} do
  return (value * value + value) as i64
end
```

### 5. Monitor Memory Usage

```janus
// ✅ Good: Regular memory monitoring
func monitor_dispatch_memory() do
  let memory_stats = get_dispatch_memory_stats()

  if memory_stats.total_mb > 100 {
    println("⚠️ High dispatch table memory usage")
    optimize_dispatch_tables()
  }

  if memory_stats.fragmentation > 0.3 {
    println("⚠️ High memory fragmentation")
    compact_dispatch_tables()
  }
end
```

### 6. Use Appropriate Data Structures

```janus
// ✅ Good: Choose optimal table structure based on usage
func create_optimized_table(family_name: string, expected_size: usize) -> DispatchTable do
  if expected_size < 10 {
    return LinearDispatchTable.init(family_name)  // Simple linear search
  } else if expected_size < 100 {
    return HashDispatchTable.init(family_name)    // Hash table lookup
  } else {
    return TreeDispatchTable.init(family_name)    // Balanced tree
  }
end
```

## Performance Benchmarks

### Typical Performance Characteristics

| Dispatch Type | Overhead | Memory | Use Case |
|---------------|----------|---------|----------|
| Static | 0ns | 0 bytes | Known types at compile time |
| Cached Dynamic | 5-15ns | ~64 bytes/entry | Repeated calls with same types |
| Full Dynamic | 50-200ns | Variable | First call or complex hierarchies |
| Cross-Module | 100-500ns | Variable | Module boundaries, hot reloading |

### Optimization Impact

| Optimization | Performance Gain | Memory Impact | Complexity |
|--------------|------------------|---------------|------------|
| Type Batching | 5-10x | Minimal | Low |
| Hot Path Inlining | 2-5x | Minimal | Medium |
| Table Optimization | 1.5-3x | -20% to -50% | Medium |
| Specialization | 10-50x | +10% to +30% | High |

## Conclusion

Multiple dispatch performance in Janus is highly dependent on usage patterns. The key principles are:

1. **Favor static dispatch** through specific types
2. **Make costs explicit** with annotations
3. **Profile regularly** to catch regressions
4. **Optimize hot paths** with specialized implementations
5. **Monitor memory usage** to prevent bloat
6. **Use appropriate data structures** for dispatch tables

By following these guidelines and using the provided profiling tools, you can achieve excellent performance while maintaining the flexibility and expressiveness of multiple dispatch.

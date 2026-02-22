<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Multiple Dispatch Troubleshooting Guide

This guide helps you diagnose and resolve common issues when working with Janus multiple dispatch.

## Table of Contents

- [Compilation Errors](#compilation-errors)
- [Runtime Issues](#runtime-issues)
- [Performance Problems](#performance-problems)
- [Debugging Tools](#debugging-tools)
- [Common Pitfalls](#common-pitfalls)

## Compilation Errors

### Ambiguous Dispatch

**Error Message:**
```
Error: ambiguous call to 'process'
  at main.janus:42:10
  candidates:
    process(i32, f64) -> string at math.janus:15
    process(f64, i32) -> string at math.janus:20
  argument types: (i32, i32)
Note: both candidates require implicit conversion with equal cost
```

**Cause:** Multiple implementations have the same conversion cost for the given arguments.

**Solutions:**

1. **Add exact match implementation:**
```janus
// Add specific implementation for the ambiguous case
func process(a: i32, b: i32) -> string do
  return process(a as f64, b as f64)  // Delegate to existing implementation
end
```

2. **Use explicit type conversion:**
```janus
// At call site, be explicit about which overload to use
let result = process(value1 as f64, value2)  // Forces first candidate
```

3. **Redesign function signatures:**
```janus
// Use different parameter names or additional parameters to disambiguate
func process_int_float(a: i32, b: f64) -> string
func process_float_int(a: f64, b: i32) -> string
```

### No Matching Implementation

**Error Message:**
```
Error: no matching implementation for 'serialize'
  at main.janus:25:15
  argument types: (CustomType)
  available implementations:
    serialize(i32) -> string at serialization.janus:10
    serialize(string) -> string at serialization.janus:15
    serialize([]any) -> string at serialization.janus:20
```

**Cause:** No implementation exists for the given argument types.

**Solutions:**

1. **Add specific implementation:**
```janus
func serialize(custom: CustomType) -> string do
  return "CustomType{field1: {custom.field1}, field2: {custom.field2}}"
end
```

2. **Add generic fallback:**
```janus
func serialize(value: any) -> string do
  return "<unknown type: {typeof(value)}>"
end
```

3. **Use type conversion:**
```janus
// Convert to supported type
let result = serialize(custom_value.to_string())
```

### Circular Import Dependencies

**Error Message:**
```
Error: circular import dependency detected
  Module A imports B.serialize
  Module B imports A.CustomType
  This creates a circular dependency
```

**Cause:** Modules have circular import dependencies when extending function families.

**Solutions:**

1. **Create shared interface module:**
```janus
// shared_types.janus
module SharedTypes
export CustomType, AnotherType

// module_a.janus
module A
import SharedTypes.CustomType
func serialize(custom: CustomType) -> string

// module_b.janus
module B
import SharedTypes.AnotherType
import A.serialize  // No circular dependency
func serialize(another: AnotherType) -> string
```

2. **Use dependency injection:**
```janus
// Pass serializers as parameters instead of importing
func process_data(data: CustomType, serializer: (CustomType) -> string) -> string do
  return serializer(data)
end
```

### Type Hierarchy Conflicts

**Error Message:**
```
Error: conflicting type hierarchy
  Circle extends both Shape and Drawable
  Multiple inheritance paths found for method 'draw'
```

**Cause:** Complex inheritance hierarchies create ambiguous dispatch paths.

**Solutions:**

1. **Use composition over inheritance:**
```janus
type Circle = table {
  shape_data: Shape,
  drawable_data: Drawable,
  radius: f64
}

func draw(circle: Circle) -> string do
  // Explicitly choose which behavior to use
  return draw_shape(circle.shape_data)
end
```

2. **Explicit disambiguation:**
```janus
func draw(circle: Circle) -> string do
  // Explicitly call the desired implementation
  return draw(circle as Shape)  // Choose Shape's draw method
end
```

## Runtime Issues

### Unexpected Dynamic Dispatch

**Issue:** Performance is slower than expected due to unexpected dynamic dispatch.

**Diagnosis:**
```janus
// Enable dispatch profiling
let profiler = DispatchProfiler.init()
profiler.config.track_call_sites = true

// Your code here...

profiler.generate_report()
// Look for "Dynamic dispatch detected" warnings
```

**Solutions:**

1. **Use more specific types:**
```janus
// Instead of:
func process_items(items: []any) do
  for item in items do
    process(item)  // Dynamic dispatch
  end
end

// Use:
func process_items(items: []i32) do
  for item in items do
    process(item)  // Static dispatch
  end
end
```

2. **Type-based batching:**
```janus
func process_mixed_items(items: []any) do
  // Group by type first
  let int_items = []
  let string_items = []

  for item in items do
    match typeof(item) {
      i32 => int_items.append(item as i32)
      string => string_items.append(item as string)
    }
  end

  // Process homogeneous batches with static dispatch
  for item in int_items do
    process(item)  // Static dispatch
  end

  for item in string_items do
    process(item)  // Static dispatch
  end
end
```

### Memory Leaks in Dispatch Tables

**Issue:** Memory usage grows over time due to dispatch table leaks.

**Diagnosis:**
```janus
let memory_profiler = DispatchMemoryProfiler.init()
memory_profiler.register_table(dispatch_table)

// Run your application...

let stats = memory_profiler.get_memory_stats()
if stats.total_memory_mb > 100 do
  println("⚠️ High dispatch table memory usage: {stats.total_memory_mb}MB")
end
```

**Solutions:**

1. **Clean up unused tables:**
```janus
// Periodically clean up unused dispatch tables
dispatch_table.cleanup_unused_entries()
```

2. **Use table sharing:**
```janus
// Share tables between similar function families
let shared_table = create_shared_dispatch_table(["serialize", "deserialize"])
```

### Hot Reloading Issues

**Issue:** Function families don't update correctly during hot reloading.

**Solutions:**

1. **Explicit table refresh:**
```janus
// After hot reload
module_dispatcher.refresh_dispatch_tables()
```

2. **Version-aware dispatch:**
```janus
// Check module versions before dispatch
if module_dispatcher.has_version_mismatch("serialization") do
  module_dispatcher.reload_module("serialization")
end
```

## Performance Problems

### High Dispatch Overhead

**Issue:** Dispatch overhead is consuming significant CPU time.

**Diagnosis:**
```janus
let profiler = DispatchProfiler.init()
profiler.config.measure_dispatch_overhead = true

// Your code...

let counters = profiler.get_counters()
if counters.get_dispatch_overhead_ratio() > 0.05 do  // 5% threshold
  println("⚠️ High dispatch overhead: {counters.get_dispatch_overhead_ratio() * 100}%")
end
```

**Solutions:**

1. **Optimize hot paths:**
```janus
// Mark frequently called functions for optimization
{.optimize: inline_dispatch.}
func hot_path_function(data: []i32) -> i64 do
  let sum = 0
  for value in data do
    sum += process(value)  // Inlined dispatch
  end
  return sum
end
```

2. **Use dispatch table caching:**
```janus
// Enable aggressive caching for stable function families
dispatch_table.set_caching_strategy(CachingStrategy.Aggressive)
```

3. **Batch similar operations:**
```janus
// Instead of individual dispatches
for item in items do
  process(item)  // Many dispatch calls
end

// Use batch processing
process_batch(items)  // Single dispatch call
```

### Cache Misses

**Issue:** Poor cache performance due to dispatch table layout.

**Diagnosis:**
```janus
let cache_profiler = CacheProfiler.init()
cache_profiler.monitor_dispatch_tables()

// Your code...

let cache_stats = cache_profiler.get_cache_stats()
if cache_stats.miss_rate > 0.2 do  // 20% miss rate threshold
  println("⚠️ High cache miss rate: {cache_stats.miss_rate * 100}%")
end
```

**Solutions:**

1. **Optimize table layout:**
```janus
// Reorder dispatch table entries by frequency
dispatch_table.optimize_layout_by_frequency()
```

2. **Use smaller tables:**
```janus
// Split large function families into smaller, focused ones
func serialize_primitive(value: PrimitiveType) -> string
func serialize_collection(value: CollectionType) -> string
func serialize_custom(value: CustomType) -> string
```

## Debugging Tools

### Dispatch Tracer

```janus
// Enable detailed dispatch tracing
let tracer = DispatchTracer.init()
tracer.set_trace_level(TraceLevel.Verbose)
tracer.enable_call_stack_tracking()

// Your code here...

// View trace results
tracer.print_trace_summary()
```

**Output:**
```
Dispatch Trace Summary:
  Total calls: 1,247
  Static dispatch: 1,156 (92.7%)
  Dynamic dispatch: 91 (7.3%)

Hot paths:
  process(i32) -> 856 calls (68.6%)
  serialize(string) -> 234 calls (18.8%)

Slow dispatches:
  process(any) -> avg 45μs (dynamic)
  serialize(CustomType) -> avg 23μs (complex hierarchy)
```

### Type Hierarchy Visualizer

```janus
// Generate type hierarchy visualization
let visualizer = TypeHierarchyVisualizer.init()
visualizer.add_type_registry(type_registry)
visualizer.generate_dot_file("type_hierarchy.dot")
visualizer.generate_html_report("type_hierarchy.html")
```

### Performance Profiler

```janus
// Comprehensive performance profiling
let profiler = DispatchProfiler.init()
profiler.config.track_call_sites = true
profiler.config.measure_memory_usage = true
profiler.config.detect_hot_paths = true
profiler.config.warn_expensive_patterns = true

// Run your application...

// Generate detailed report
profiler.generate_detailed_report("dispatch_profile.html")
```

**Report includes:**
- Call frequency analysis
- Memory usage patterns
- Hot path identification
- Optimization recommendations
- Performance regression detection

## Common Pitfalls

### 1. Over-Generic Function Signatures

**Problem:**
```janus
// Too generic - forces dynamic dispatch
func process(data: any) -> any do
  // Implementation
end
```

**Solution:**
```janus
// More specific signatures enable static dispatch
func process(data: i32) -> string
func process(data: f64) -> string
func process(data: string) -> string

// Keep generic version as explicit fallback
func process(data: any) -> string do
  return "<unknown type>"
end
```

### 2. Hidden Performance Costs

**Problem:**
```janus
// Hidden dynamic dispatch cost
func process_list(items: []any) do
  for item in items do
    transform(item)  // Dynamic dispatch per item
  end
end
```

**Solution:**
```janus
// Make costs explicit
func process_list(items: []any) do
  for item in items do
    transform_dynamic(item)  // Explicit dynamic dispatch
  end
end

func transform_dynamic(item: any) -> any {.dispatch: dynamic.} do
  return transform(item)
end
```

### 3. Incomplete Function Families

**Problem:**
```janus
// Incomplete family - missing common cases
func serialize(x: i32) -> string
func serialize(x: string) -> string
// Missing: f64, bool, arrays, etc.
```

**Solution:**
```janus
// Complete the family or provide explicit fallback
func serialize(x: i32) -> string
func serialize(x: f64) -> string
func serialize(x: bool) -> string
func serialize(x: string) -> string
func serialize(x: []any) -> string
func serialize(x: any) -> string  // Explicit fallback
```

### 4. Ignoring Ambiguity Warnings

**Problem:**
```janus
// Ignoring compiler warnings about potential ambiguity
func combine(a: Numeric, b: Numeric) -> Numeric  // Warning: potentially ambiguous
```

**Solution:**
```janus
// Address ambiguity explicitly
func combine(a: i32, b: i32) -> i32
func combine(a: f64, b: f64) -> f64
func combine(a: i32, b: f64) -> f64  // Explicit mixed-type handling
func combine(a: f64, b: i32) -> f64
```

### 5. Poor Module Organization

**Problem:**
```janus
// All implementations in one giant module
module Everything
func serialize(x: i32) -> string
func serialize(x: CustomType1) -> string
func serialize(x: CustomType2) -> string
// ... 50 more implementations
```

**Solution:**
```janus
// Organize by domain
module Core.Serialization
func serialize(x: i32) -> string
func serialize(x: string) -> string

module CustomTypes.Serialization
import Core.Serialization.serialize
func serialize(x: CustomType1) -> string
func serialize(x: CustomType2) -> string
```

## Getting Help

If you encounter issues not covered in this guide:

1. **Enable verbose logging:**
   ```janus
   let debugger = DispatchDebugger.init()
   debugger.set_verbose_mode(true)
   ```

2. **Generate diagnostic report:**
   ```janus
   let diagnostics = DispatchDiagnostics.init()
   diagnostics.generate_full_report("dispatch_diagnostics.html")
   ```

3. **Check the community resources:**
   - [Multiple Dispatch Examples](examples/)
   - [API Documentation](api/)
   - [Performance Guide](README.md#performance-guide)

4. **File a bug report** with:
   - Minimal reproduction case
   - Diagnostic report
   - Expected vs actual behavior

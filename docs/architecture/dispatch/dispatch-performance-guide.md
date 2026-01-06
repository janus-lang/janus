<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Multiple Dispatch Performance Guide

## Table of Contents

1. [Performance Overview](#performance-overview)
2. [Static vs Dynamic Dispatch](#static-vs-dynamic-dispatch)
3. [Performance Optimization Strategies](#performance-optimization-strategies)
4. [Profiling and Measurement](#profiling-and-measurement)
5. [Memory Optimization](#memory-optimization)
6. [Best Practices for Performance](#best-practices-for-performance)
7. [Common Performance Pitfalls](#common-performance-pitfalls)
8. [Advanced Optimization Techniques](#advanced-optimization-techniques)

## Performance Overview

The Janus Multiple Dispatch System is designed for high performance with two dispatch modes:

- **Static Dispatch**: Zero overhead when types are known at compile time
- **Dynamic Dispatch**: Minimal overhead (~10-50ns) when runtime resolution is needed

### Performance Characteristics

| Scenario | Overhead | Use Case |
|----------|----------|----------|
| Static dispatch (sealed types) | 0-5ns | Performance-critical code |
| Small runtime dispatch (< 10 impls) | 10-30ns | Most application code |
| Large runtime dispatch (< 100 impls) | 30-100ns | Complex polymorphic systems |
| Massive dispatch (< 1000 impls) | 100-500ns | Extreme cases with compression |

## Static vs Dynamic Dispatch

### Static Dispatch (Zero Overhead)

Static dispatch occurs when:
- All argument types are known at compile time
- Types are sealed (closed for extension)
- Only one implementation can match

```janus
type sealed Color = Red | Green | Blue

func blend(a: Color, b: Color) -> Color {
    // Static dispatch - compiled to direct function calls
    match (a, b) {
        case (Red, Green) => Yellow
        case (Green, Blue) => Cyan
        case (Blue, Red) => Magenta
        // ... other combinations
    }
}

// This compiles to a direct function call - zero overhead
let result = blend(Red, Blue)
```

**Performance**: Identical to direct function calls.

### Dynamic Dispatch (Minimal Overhead)

Dynamic dispatch occurs when:
- Argument types are not fully known at compile time
- Types are open (extensible)
- Multiple implementations could match

```janus
type open Drawable = Shape | Text | Image

func render(item: Drawable, canvas: Canvas) -> void {
    // Runtime dispatch - small lookup overhead
}

// This requires runtime dispatch table lookup
let items: Array[Drawable] = getDrawableItems()
for item in items {
    render(item, canvas)  // ~10-50ns overhead per call
}
```

**Performance**: Small constant-time lookup overhead.

## Performance Optimization Strategies

### 1. Use Sealed Types When Possible

**Prefer sealed types for performance-critical code:**

```janus
// Good: Sealed type enables static dispatch
type sealed Operation = Add | Subtract | Multiply | Divide

func calculate(op: Operation, a: float, b: float) -> float {
    // Static dispatch - zero overhead
    match op {
        case Add => a + b
        case Subtract => a - b
        case Multiply => a * b
        case Divide => a / b
    }
}
```

**Avoid open types in hot paths:**

```janus
// Avoid in performance-critical code
type open Operation = Add | Subtract | Multiply | Divide

func calculate(op: Operation, a: float, b: float) -> float {
    // Runtime dispatch - small overhead
}
```

### 2. Minimize Dispatch in Tight Loops

**Bad: Dispatch inside tight loop**

```janus
func processArray(items: Array[Processable]) -> void {
    for item in items {
        process(item)  // Dispatch overhead on every iteration
    }
}
```

**Good: Batch processing or type-specific loops**

```janus
func processArray(items: Array[Processable]) -> void {
    // Group by type to minimize dispatch
    let grouped = groupByType(items)

    for (type, type_items) in grouped {
        match type {
            case TypeA => processTypeABatch(type_items as Array[TypeA])
            case TypeB => processTypeBBatch(type_items as Array[TypeB])
            // ... other types
        }
    }
}

func processTypeABatch(items: Array[TypeA]) -> void {
    // No dispatch overhead - direct calls
    for item in items {
        processTypeA(item)
    }
}
```

### 3. Use Specific Types When Known

**Bad: Using generic types when specific type is known**

```janus
func processKnownType(item: Drawable) -> void {
    // Runtime dispatch even though we know it's a Circle
    render(item, canvas)
}

let circle = Circle{radius: 5.0}
processKnownType(circle)  // Unnecessary dispatch
```

**Good: Use specific types**

```janus
func processCircle(circle: Circle) -> void {
    // Direct call - no dispatch
    renderCircle(circle, canvas)
}

let circle = Circle{radius: 5.0}
processCircle(circle)  // Zero overhead
```

### 4. Profile-Guided Optimization

Use profiling to identify hot dispatch sites:

```janus
import std.profiling.{profileDispatch}

func hotFunction() -> void {
    profileDispatch("hotFunction") {
        for i in 0..1000000 {
            process(getItem(i))  // This will be profiled
        }
    }
}
```

## Profiling and Measurement

### 1. Dispatch Performance Profiling

```janus
import std.profiling.{measureDispatch, DispatchStats}

func benchmarkDispatch() -> void {
    let stats = measureDispatch {
        // Code to benchmark
        for i in 0..10000 {
            process(getRandomItem())
        }
    }

    println("Dispatch Statistics:")
    println("  Total calls: {}", stats.totalCalls)
    println("  Static dispatch: {} ({:.1}%)", stats.staticCalls, stats.staticRatio * 100)
    println("  Dynamic dispatch: {} ({:.1}%)", stats.dynamicCalls, stats.dynamicRatio * 100)
    println("  Average dispatch time: {} ns", stats.averageDispatchTime)
    println("  Total dispatch overhead: {} ns", stats.totalOverhead)
}
```

### 2. Memory Usage Analysis

```janus
import std.profiling.{analyzeDispatchMemory}

func analyzeMemoryUsage() -> void {
    let analysis = analyzeDispatchMemory("process")

    println("Memory Analysis for 'process' signature:")
    println("  Dispatch table size: {} bytes", analysis.tableSize)
    println("  Number of implementations: {}", analysis.implementationCount)
    println("  Compression ratio: {:.1}%", analysis.compressionRatio * 100)
    println("  Cache efficiency: {:.1}%", analysis.cacheEfficiency * 100)
    println("  Memory per implementation: {} bytes", analysis.bytesPerImplementation)
}
```

### 3. Hot Path Identification

```janus
import std.profiling.{identifyHotPaths}

func findHotPaths() -> void {
    let hotPaths = identifyHotPaths(threshold: 1000)  // Calls > 1000

    println("Hot Dispatch Paths:")
    for path in hotPaths {
        println("  {}: {} calls, {} ns total", path.signature, path.callCount, path.totalTime)

        if path.dynamicRatio > 0.5 {
            println("    ⚠️  High dynamic dispatch ratio: {:.1}%", path.dynamicRatio * 100)
            println("    💡 Consider using sealed types or specific implementations")
        }
    }
}
```

## Memory Optimization

### 1. Dispatch Table Compression

Large signature groups automatically use compression:

```janus
// Large signature groups (>50 implementations) automatically compressed
func render(shape: Shape, material: Material, lighting: Lighting, camera: Camera) -> void {
    // System automatically compresses dispatch tables
    // No code changes needed
}
```

### 2. Memory-Efficient Type Design

**Good: Compact type representations**

```janus
type sealed Color = Red | Green | Blue | Yellow | Cyan | Magenta

// Efficient: Uses small enum representation
func blend(a: Color, b: Color) -> Color { /* ... */ }
```

**Avoid: Large type hierarchies when not needed**

```janus
// Less efficient: Large type hierarchy
type Color = Red{r: float} | Green{g: float} | Blue{b: float} | /* ... many more */

// Each variant requires more memory in dispatch tables
```

### 3. Signature Optimization

**Minimize signature proliferation:**

```janus
// Good: Focused signatures
func render(shape: Shape, context: RenderContext) -> void

// Avoid: Too many specific signatures
func render(shape: Shape, material: Material, lighting: Lighting, camera: Camera,
           shadows: ShadowSettings, postprocess: PostProcessSettings) -> void
```

## Best Practices for Performance

### 1. Design Guidelines

**Use the Right Dispatch Mode:**

```janus
// Performance-critical: Use sealed types
type sealed MathOp = Add | Sub | Mul | Div

// Extensible systems: Use open types
type open Plugin = AudioPlugin | VideoPlugin | NetworkPlugin
```

**Minimize Dispatch Depth:**

```janus
// Good: Flat dispatch
func process(item: Item) -> void

// Avoid: Nested dispatch
func process(container: Container) -> void {
    for item in container.items {
        process(item)  // Dispatch inside dispatch
    }
}
```

### 2. Code Organization

**Group Related Implementations:**

```janus
// Good: Related implementations together
func serialize(value: int, writer: Writer) -> void { /* ... */ }
func serialize(value: float, writer: Writer) -> void { /* ... */ }
func serialize(value: string, writer: Writer) -> void { /* ... */ }

// Better: Use modules to organize
module serialization {
    func serialize(value: int, writer: Writer) -> void { /* ... */ }
    func serialize(value: float, writer: Writer) -> void { /* ... */ }
    func serialize(value: string, writer: Writer) -> void { /* ... */ }
}
```

### 3. Performance Testing

**Include dispatch performance in benchmarks:**

```janus
import std.benchmark.{benchmark}

func benchmarkProcessing() -> void {
    let items = generateTestItems(10000)

    benchmark("Direct processing") {
        for item in items {
            processSpecific(item)  // Direct calls
        }
    }

    benchmark("Dispatch processing") {
        for item in items {
            process(item)  // Dispatch calls
        }
    }
}
```

## Common Performance Pitfalls

### 1. Unnecessary Dynamic Dispatch

**Problem**: Using open types when sealed would work

```janus
// Inefficient: Open type when closed set is known
type open Color = Red | Green | Blue

func blend(a: Color, b: Color) -> Color {
    // Runtime dispatch even though all colors are known
}
```

**Solution**: Use sealed types

```janus
// Efficient: Sealed type enables static dispatch
type sealed Color = Red | Green | Blue

func blend(a: Color, b: Color) -> Color {
    // Static dispatch - zero overhead
}
```

### 2. Dispatch in Hot Loops

**Problem**: Dispatch overhead multiplied by loop iterations

```janus
// Inefficient: Dispatch on every iteration
func processPixels(pixels: Array[Pixel]) -> void {
    for pixel in pixels {
        process(pixel)  // Dispatch overhead × pixel count
    }
}
```

**Solution**: Batch processing or loop hoisting

```janus
// Efficient: Minimize dispatch
func processPixels(pixels: Array[Pixel]) -> void {
    // Group by type to reduce dispatch
    let (red_pixels, green_pixels, blue_pixels) = groupPixelsByType(pixels)

    processRedPixels(red_pixels)    // Direct calls
    processGreenPixels(green_pixels)
    processBluePixels(blue_pixels)
}
```

### 3. Over-Specific Implementations

**Problem**: Too many implementations hurt performance

```janus
// Inefficient: Too many specific cases
func format(value: int, precision: 0) -> string { /* ... */ }
func format(value: int, precision: 1) -> string { /* ... */ }
func format(value: int, precision: 2) -> string { /* ... */ }
// ... 20 more implementations
```

**Solution**: Use parameters instead of dispatch

```janus
// Efficient: Single implementation with parameters
func format(value: int, precision: int) -> string {
    // Handle all precisions in one implementation
}
```

### 4. Ignoring Compression Opportunities

**Problem**: Large dispatch tables without compression

```janus
// Large signature group - should use compression
func transform(shape: Shape, operation: Operation, context: Context,
              settings: Settings, cache: Cache) -> Result {
    // 100+ implementations - needs compression
}
```

**Solution**: Enable compression monitoring

```janus
import std.profiling.{monitorCompression}

func checkCompressionStatus() -> void {
    let status = monitorCompression("transform")

    if status.shouldCompress && !status.isCompressed {
        println("⚠️  Large signature 'transform' should use compression")
        println("   Implementations: {}", status.implementationCount)
        println("   Memory usage: {} bytes", status.memoryUsage)
    }
}
```

## Advanced Optimization Techniques

### 1. Profile-Guided Dispatch Optimization

```janus
import std.optimization.{optimizeDispatchTables}

func optimizeForProduction() -> void {
    // Collect runtime profile data
    let profile = collectDispatchProfile(duration: 60_seconds)

    // Optimize dispatch tables based on actual usage
    optimizeDispatchTables(profile, strategy: .hotPathFirst)

    println("Dispatch optimization complete:")
    println("  Hot paths optimized: {}", profile.hotPathCount)
    println("  Memory saved: {} bytes", profile.memorySaved)
    println("  Performance improvement: {:.1}%", profile.performanceGain * 100)
}
```

### 2. Custom Dispatch Strategies

```janus
import std.dispatch.{customDispatchStrategy}

// For very specific performance requirements
func setupCustomDispatch() -> void {
    customDispatchStrategy("render") {
        // Use perfect hashing for graphics rendering
        strategy: .perfectHash,
        fallback: .decisionTree,
        cacheSize: 1024
    }

    customDispatchStrategy("serialize") {
        // Use compressed tables for serialization
        strategy: .compressedTable,
        compressionLevel: .maximum,
        decompressOnDemand: true
    }
}
```

### 3. Dispatch Table Precomputation

```janus
import std.dispatch.{precomputeDispatchTables}

// For applications with known type sets
func precomputeForDeployment() -> void {
    let knownTypes = [
        typeof(Circle), typeof(Rectangle), typeof(Triangle),
        typeof(Sphere), typeof(Cube), typeof(Cylinder)
    ]

    // Precompute all dispatch tables for known types
    precomputeDispatchTables(signatures: ["render", "collide", "serialize"],
                           types: knownTypes)

    println("Precomputed dispatch tables for {} type combinations",
            knownTypes.length * knownTypes.length)
}
```

## Performance Monitoring in Production

### 1. Runtime Performance Metrics

```janus
import std.metrics.{dispatchMetrics}

func monitorProductionPerformance() -> void {
    let metrics = dispatchMetrics.collect()

    // Log performance metrics
    log.info("Dispatch Performance Metrics:")
    log.info("  Total dispatch calls: {}", metrics.totalCalls)
    log.info("  Average dispatch time: {} ns", metrics.averageTime)
    log.info("  95th percentile: {} ns", metrics.p95Time)
    log.info("  99th percentile: {} ns", metrics.p99Time)

    // Alert on performance degradation
    if metrics.averageTime > 100 {  // 100ns threshold
        alert.warn("Dispatch performance degraded: {} ns average", metrics.averageTime)
    }
}
```

### 2. Memory Usage Monitoring

```janus
import std.metrics.{memoryMetrics}

func monitorMemoryUsage() -> void {
    let memory = memoryMetrics.dispatchTables()

    log.info("Dispatch Memory Usage:")
    log.info("  Total table memory: {} MB", memory.totalBytes / 1_000_000)
    log.info("  Compression ratio: {:.1}%", memory.compressionRatio * 100)
    log.info("  Cache hit rate: {:.1}%", memory.cacheHitRate * 100)

    // Alert on memory issues
    if memory.totalBytes > 100_000_000 {  // 100MB threshold
        alert.warn("Dispatch tables using {} MB memory", memory.totalBytes / 1_000_000)
    }
}
```

## Conclusion

The Janus Multiple Dispatch System is designed for high performance while maintaining flexibility. Key takeaways:

### Performance Hierarchy (Best to Worst)
1. **Static dispatch with sealed types**: 0-5ns overhead
2. **Small dynamic dispatch**: 10-30ns overhead
3. **Large dynamic dispatch with compression**: 50-200ns overhead
4. **Massive unoptimized dispatch**: 200-1000ns overhead

### Optimization Strategy
1. **Profile first**: Identify actual bottlenecks
2. **Use sealed types**: For performance-critical code
3. **Batch processing**: Minimize dispatch in loops
4. **Monitor in production**: Track performance metrics
5. **Leverage compression**: For large signature groups

### Remember
- Most applications will see excellent performance with default settings
- Profile before optimizing - dispatch is rarely the bottleneck
- The system is designed to scale from simple cases to complex polymorphic systems
- When in doubt, measure actual performance impact

The dispatch system provides both the flexibility you need for complex domains and the performance you need for production systems.

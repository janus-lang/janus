<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Multiple Dispatch API Reference

## Table of Contents

1. [Core Dispatch APIs](#core-dispatch-apis)
2. [Advanced Strategy Selection](#advanced-strategy-selection) **NEW**
3. [Performance Profiling APIs](#performance-profiling-apis) **ENHANCED**
4. [Profiling and Debugging APIs](#profiling-and-debugging-apis)
5. [Optimization APIs](#optimization-apis)
6. [Cross-Module Dispatch APIs](#cross-module-dispatch-apis)
7. [Error Handling](#error-handling)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Configuration Options](#configuration-options)

## Core Dispatch APIs

### Function Definition

```janus
// Basic function definition - automatically participates in dispatch
func function_name(param1: Type1, param2: Type2) -> ReturnType {
    // Implementation
}

// Multiple implementations form a function family
func function_name(param1: SpecificType1, param2: Type2) -> ReturnType {
    // More specific implementation
}
```

### Type Annotations for Dispatch Control

```janus
// Sealed types enable static dispatch
type sealed FastType = Variant1 | Variant2 | Variant3

// Open types use runtime dispatch
type open ExtensibleType = Variant1 | Variant2 | Variant3

// Effect annotations affect dispatch signatures
func process(data: Data) -> Result {.pure} { /* pure implementation */ }
func process(data: Data) -> Result {.io} { /* I/O implementation */ }
```

### Explicit Type Annotations

```janus
// Force specific implementation selection
let result = function_name(value as SpecificType, other_param)

// Qualified calls to bypass dispatch
let result = module_name::function_name(param1, param2)
```

## Advanced Strategy Selection

### Automatic Strategy Selection (Task 19 Enhancement)

The Janus compiler now features intelligent dispatch strategy selection with performance profiling and fallback mechanisms.

#### Strategy Selection Logic

```zig
// Compiler automatically selects optimal strategy based on call patterns:
// - High frequency (>1000 calls/sec) → Static (direct call)
// - Low complexity (≤4 args) → SwitchTable dispatch
// - High branch factor + good locality → Jump table
// - Large dispatch space → Perfect hash
// - Complex cases → Inline cache (fallback)
```

#### Performance Profiling Integration

```zig
// The compiler tracks effectiveness metrics for each strategy:
pub const StrategyEffectiveness = struct {
    execution_time_ns: u64,        // Runtime performance
    cache_miss_rate: f64,          // Cache efficiency (0.0-1.0)
    branch_misprediction_rate: f64, // Branch prediction accuracy
    generated_code_size: u64,      // Code size impact
    compilation_time_ms: f64,      // Compilation overhead
    success_rate: f64,             // Reliability metric
};
```

#### Fallback Mechanism

```zig
// Automatic fallback chain for strategy failures:
// PerfectHash → SwitchTable → Static → InlineCache
// Maximum 3 attempts with comprehensive error recovery
```

#### AI-Auditable Decision Tracking

```zig
// Every strategy decision is recorded with detailed rationale:
pub const StrategyDecision = struct {
    decision_factors: DecisionFactors,     // Weights and constraints
    risk_assessment: RiskAssessment,       // Failure risk analysis
    expected_performance: PerformanceProjection, // Predicted outcomes
    alternatives_considered: []Strategy,    // All evaluated options
    selection_rationale: []const u8,      // Human-readable explanation
};
```

#### Compiler Integration

```bash
# Enable advanced strategy selection (default in release builds)
janus build --dispatch-strategy=auto

# Force specific strategy for debugging
janus build --dispatch-strategy=static

# Enable detailed strategy profiling
janus build --dispatch-profiling=verbose
```

## Performance Profiling APIs

### std.dispatch Module

```janus
import std.dispatch.{
    queryDispatch,
    traceDispatch,
    inspectSignature,
    getDispatchStats
}
```

#### queryDispatch

Query which implementation would be chosen for given argument types.

```janus
func queryDispatch(signature_name: string, arg_types: Array[Type]) -> DispatchResolution

type DispatchResolution = union {
    unique: Implementation,
    ambiguous: Array[Implementation],
    noMatch: void
}

type Implementation = {
    signature: string,
    module: string,
    location: SourceLocation,
    specificity_rank: int
}

// Example usage
let resolution = queryDispatch("process", [typeof(int), typeof(string)])
match resolution {
    case .unique(impl) => println("Would call: {}", impl.signature)
    case .ambiguous(impls) => println("Ambiguous between {} implementations", impls.length)
    case .noMatch => println("No matching implementation")
}
```

#### traceDispatch

Enable/disable dispatch tracing for debugging.

```janus
func traceDispatch(enabled: bool) -> void

// Example usage
traceDispatch(true)   // Enable tracing
process(some_value)   // This will log dispatch decisions
traceDispatch(false)  // Disable tracing
```

#### inspectSignature

Get detailed information about a function signature.

```janus
func inspectSignature(signature_name: string) -> SignatureInfo

type SignatureInfo = {
    name: string,
    arity: int,
    implementations: Array[Implementation],
    dispatch_strategy: DispatchStrategy,
    memory_usage: int,
    call_count: int
}

type DispatchStrategy = enum {
    static_single,     // Single implementation
    static_sealed,     // Sealed types, static dispatch
    dynamic_cached,    // Runtime dispatch with caching
    dynamic_compressed // Large tables with compression
}

// Example usage
let info = inspectSignature("render")
println("Signature: {} ({} implementations)", info.name, info.implementations.length)
println("Strategy: {}", info.dispatch_strategy)
println("Memory usage: {} bytes", info.memory_usage)
```

#### getDispatchStats

Get global dispatch performance statistics.

```janus
func getDispatchStats() -> DispatchStats

type DispatchStats = {
    total_calls: int,
    static_calls: int,
    dynamic_calls: int,
    average_dispatch_time_ns: int,
    total_dispatch_overhead_ns: int,
    cache_hit_rate: float,
    memory_usage_bytes: int
}

// Example usage
let stats = getDispatchStats()
println("Total calls: {}", stats.total_calls)
println("Static dispatch ratio: {:.1}%", stats.static_calls as float / stats.total_calls as float * 100)
println("Average dispatch time: {} ns", stats.average_dispatch_time_ns)
```

### std.profiling Module

```janus
import std.profiling.{
    measureDispatch,
    profileDispatch,
    analyzeDispatchMemory,
    identifyHotPaths
}
```

#### measureDispatch

Measure dispatch performance for a code block.

```janus
func measureDispatch[T](block: () -> T) -> (T, DispatchMeasurement)

type DispatchMeasurement = {
    total_time_ns: int,
    dispatch_time_ns: int,
    dispatch_calls: int,
    static_calls: int,
    dynamic_calls: int,
    cache_hits: int,
    cache_misses: int
}

// Example usage
let (result, measurement) = measureDispatch {
    for i in 0..10000 {
        process(getItem(i))
    }
}

println("Dispatch overhead: {} ns ({:.1}% of total)",
        measurement.dispatch_time_ns,
        measurement.dispatch_time_ns as float / measurement.total_time_ns as float * 100)
```

#### profileDispatch

Profile dispatch calls within a named scope.

```janus
func profileDispatch[T](scope_name: string, block: () -> T) -> T

// Example usage
profileDispatch("image_processing") {
    for pixel in pixels {
        process(pixel)  // These calls will be profiled
    }
}

// View results
let profile = getProfile("image_processing")
println("Scope: {}", profile.scope_name)
println("Dispatch calls: {}", profile.dispatch_calls)
println("Hot signatures: {}", profile.hot_signatures)
```

#### analyzeDispatchMemory

Analyze memory usage of dispatch tables.

```janus
func analyzeDispatchMemory(signature_name: string) -> MemoryAnalysis

type MemoryAnalysis = {
    signature_name: string,
    table_size_bytes: int,
    implementation_count: int,
    compression_ratio: float,
    cache_efficiency: float,
    bytes_per_implementation: int,
    memory_overhead_percent: float
}

// Example usage
let analysis = analyzeDispatchMemory("render")
println("Memory analysis for 'render':")
println("  Table size: {} bytes", analysis.table_size_bytes)
println("  Compression ratio: {:.1}%", analysis.compression_ratio * 100)
println("  Cache efficiency: {:.1}%", analysis.cache_efficiency * 100)
```

#### identifyHotPaths

Identify frequently called dispatch sites.

```janus
func identifyHotPaths(threshold: int) -> Array[HotPath]

type HotPath = {
    signature_name: string,
    call_count: int,
    total_time_ns: int,
    average_time_ns: int,
    static_ratio: float,
    dynamic_ratio: float,
    memory_usage: int
}

// Example usage
let hot_paths = identifyHotPaths(threshold: 1000)  // Calls > 1000
for path in hot_paths {
    println("Hot path: {} ({} calls)", path.signature_name, path.call_count)
    if path.dynamic_ratio > 0.8 {
        println("  ⚠️  High dynamic dispatch ratio: {:.1}%", path.dynamic_ratio * 100)
    }
}
```

## Optimization APIs

### std.optimization Module

```janus
import std.optimization.{
    optimizeDispatchTables,
    setDispatchStrategy,
    precomputeDispatchTables,
    enableCompression
}
```

#### optimizeDispatchTables

Optimize dispatch tables based on runtime profile data.

```janus
func optimizeDispatchTables(profile: DispatchProfile, strategy: OptimizationStrategy) -> OptimizationResult

type OptimizationStrategy = enum {
    hotPathFirst,      // Optimize most frequently called signatures first
    memoryEfficient,   // Minimize memory usage
    latencyOptimized,  // Minimize dispatch latency
    balanced          // Balance between memory and performance
}

type OptimizationResult = {
    signatures_optimized: int,
    memory_saved_bytes: int,
    performance_improvement_percent: float,
    optimization_time_ms: int
}

// Example usage
let profile = collectDispatchProfile(duration: 60_seconds)
let result = optimizeDispatchTables(profile, strategy: .hotPathFirst)
println("Optimized {} signatures", result.signatures_optimized)
println("Memory saved: {} bytes", result.memory_saved_bytes)
println("Performance improvement: {:.1}%", result.performance_improvement_percent)
```

#### setDispatchStrategy

Set custom dispatch strategy for specific signatures.

```janus
func setDispatchStrategy(signature_name: string, strategy: CustomDispatchStrategy) -> void

type CustomDispatchStrategy = {
    strategy_type: StrategyType,
    cache_size: ?int,
    compression_level: ?CompressionLevel,
    fallback_strategy: ?StrategyType
}

type StrategyType = enum {
    perfectHash,       // Perfect hashing for known type sets
    decisionTree,      // Decision tree for hierarchical types
    compressedTable,   // Compressed table for large signatures
    linearSearch      // Linear search for small signatures
}

type CompressionLevel = enum { fast, balanced, maximum }

// Example usage
setDispatchStrategy("render", CustomDispatchStrategy{
    strategy_type: .perfectHash,
    cache_size: 1024,
    fallback_strategy: .decisionTree
})
```

#### precomputeDispatchTables

Precompute dispatch tables for known type combinations.

```janus
func precomputeDispatchTables(signatures: Array[string], types: Array[Type]) -> PrecomputationResult

type PrecomputationResult = {
    tables_generated: int,
    type_combinations: int,
    total_memory_bytes: int,
    generation_time_ms: int
}

// Example usage
let known_types = [typeof(Circle), typeof(Rectangle), typeof(Triangle)]
let result = precomputeDispatchTables(
    signatures: ["render", "collide", "serialize"],
    types: known_types
)
println("Precomputed {} tables for {} type combinations",
        result.tables_generated, result.type_combinations)
```

#### enableCompression

Enable or configure compression for large dispatch tables.

```janus
func enableCompression(signature_name: string, config: CompressionConfig) -> void

type CompressionConfig = {
    enabled: bool,
    threshold: int,           // Minimum implementations to trigger compression
    level: CompressionLevel,
    algorithm: CompressionAlgorithm
}

type CompressionAlgorithm = enum {
    semantic,     // Semantic compression (bit vectors, sharing)
    lz4,         // LZ4 general-purpose compression
    zstd,        // Zstandard compression
    custom,      // Custom domain-specific compression
    hybrid       // Combination of semantic + general compression
}

// Example usage
enableCompression("large_signature", CompressionConfig{
    enabled: true,
    threshold: 50,
    level: .balanced,
    algorithm: .hybrid
})
```

## Cross-Module Dispatch APIs

### Module Export/Import

```janus
// Export signature for cross-module use
export func signature_name(params...) -> ReturnType { /* ... */ }

// Import existing signature for extension
import module_name.{signature_name}

// Extend imported signature
func signature_name(new_param_types...) -> ReturnType { /* ... */ }
```

### Qualified Calls

```janus
// Call specific module's implementation
let result = module_name::signature_name(params...)

// Bypass dispatch entirely
let result = @direct module_name::signature_name(params...)
```

### Conflict Resolution

```janus
import std.dispatch.{resolveConflict, getConflicts}

// Get active conflicts
func getConflicts() -> Array[DispatchConflict]

type DispatchConflict = {
    signature_name: string,
    conflicting_modules: Array[string],
    conflict_type: ConflictType
}

type ConflictType = enum {
    nameCollision,        // Same signature name from different modules
    ambiguousDispatch,    // Multiple equally specific implementations
    versionMismatch      // Incompatible signature versions
}

// Resolve conflicts
func resolveConflict(signature_name: string, resolution: ConflictResolution) -> void

type ConflictResolution = enum {
    preferModule(string),     // Prefer specific module's implementation
    requireQualified,         // Require qualified calls
    merge,                   // Merge all implementations
    error                    // Fail on conflict
}

// Example usage
let conflicts = getConflicts()
for conflict in conflicts {
    println("Conflict in signature: {}", conflict.signature_name)
    resolveConflict(conflict.signature_name, .preferModule("core"))
}
```

## Error Handling

### Dispatch Errors

```janus
type DispatchError = union {
    noMatchingImplementation: NoMatchError,
    ambiguousDispatch: AmbiguityError,
    moduleNotFound: ModuleError,
    signatureNotExported: ExportError
}

type NoMatchError = {
    signature_name: string,
    argument_types: Array[Type],
    available_implementations: Array[Implementation],
    call_site: SourceLocation
}

type AmbiguityError = {
    signature_name: string,
    argument_types: Array[Type],
    conflicting_implementations: Array[Implementation],
    call_site: SourceLocation,
    suggestions: Array[string]
}
```

### Error Recovery

```janus
import std.dispatch.{setErrorHandler, ErrorHandler}

type ErrorHandler = (DispatchError) -> ErrorAction

type ErrorAction = union {
    retry: Implementation,    // Use specific implementation
    fallback: any,           // Return fallback value
    propagate: void,         // Propagate error
    log: string             // Log and continue
}

// Example usage
setErrorHandler(|error| {
    match error {
        case .noMatchingImplementation(e) => {
            log.warn("No implementation for {} with types {}", e.signature_name, e.argument_types)
            .fallback(null)
        }
        case .ambiguousDispatch(e) => {
            log.error("Ambiguous dispatch: {}", e.signature_name)
            .propagate
        }
    }
})
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue: "No matching implementation" error

**Symptoms:**
```
Error E0020: No matching implementation for call to 'process'
  at line 42, column 15
  with argument types: (CustomType, int)

  Available implementations:
    process(string, int) -> Result at line 10, column 1
      Rejected: argument type 'CustomType' is not compatible with parameter type 'string'
```

**Solutions:**
1. Add missing implementation:
   ```janus
   func process(custom: CustomType, value: int) -> Result {
       // Implementation for CustomType
   }
   ```

2. Add type conversion:
   ```janus
   let result = process(custom.toString(), value)
   ```

3. Use explicit fallback:
   ```janus
   func process(value: any, number: int) -> Result {
       // Generic fallback implementation
   }
   ```

#### Issue: "Ambiguous dispatch" error

**Symptoms:**
```
Error E0021: Ambiguous dispatch for call to 'combine'
  at line 25, column 8
  with argument types: (TypeA | TypeB, TypeA | TypeB)

  Conflicting implementations:
    combine(TypeA, TypeB) -> Result at line 5, column 1
    combine(TypeB, TypeA) -> Result at line 8, column 1
```

**Solutions:**
1. Add specific implementations for all combinations:
   ```janus
   func combine(a: TypeA, b: TypeA) -> Result { /* ... */ }
   func combine(a: TypeB, b: TypeB) -> Result { /* ... */ }
   ```

2. Use explicit type annotations:
   ```janus
   let result = combine(value as TypeA, other as TypeB)
   ```

3. Redesign type hierarchy to avoid ambiguity:
   ```janus
   type CombinableType = TypeA | TypeB
   func combine(a: CombinableType, b: CombinableType) -> Result {
       // Handle all combinations in one implementation
   }
   ```

#### Issue: Poor dispatch performance

**Symptoms:**
- High dispatch overhead in profiling
- Slow performance in tight loops
- Large memory usage for dispatch tables

**Diagnosis:**
```janus
let hot_paths = identifyHotPaths(threshold: 1000)
for path in hot_paths {
    if path.dynamic_ratio > 0.8 {
        println("Performance issue: {} has {:.1}% dynamic dispatch",
                path.signature_name, path.dynamic_ratio * 100)
    }
}
```

**Solutions:**
1. Use sealed types for static dispatch:
   ```janus
   type sealed FastType = Variant1 | Variant2 | Variant3
   ```

2. Batch processing to reduce dispatch frequency:
   ```janus
   // Instead of dispatching on every item
   for item in items {
       process(item)  // Dispatch × item count
   }

   // Group by type and batch process
   let grouped = groupByType(items)
   for (type, type_items) in grouped {
       processType(type, type_items)  // Dispatch × type count
   }
   ```

3. Enable compression for large signatures:
   ```janus
   enableCompression("large_signature", CompressionConfig{
       enabled: true,
       threshold: 50,
       level: .balanced,
       algorithm: .hybrid
   })
   ```

#### Issue: Module conflicts

**Symptoms:**
```
Error: Conflicting implementations for signature 'process'
  Module 'core' exports: process(Data) -> Result
  Module 'extended' exports: process(Data) -> Result
```

**Solutions:**
1. Use qualified calls:
   ```janus
   let result1 = core::process(data)
   let result2 = extended::process(data)
   ```

2. Resolve conflict with preference:
   ```janus
   resolveConflict("process", .preferModule("extended"))
   ```

3. Rename one of the implementations:
   ```janus
   import extended.{process as processExtended}
   ```

### Debugging Workflow

1. **Enable tracing:**
   ```janus
   traceDispatch(true)
   // Run problematic code
   traceDispatch(false)
   ```

2. **Query dispatch resolution:**
   ```janus
   let resolution = queryDispatch("problematic_function", [typeof(arg1), typeof(arg2)])
   println("Dispatch resolution: {}", resolution)
   ```

3. **Inspect signature details:**
   ```janus
   let info = inspectSignature("problematic_function")
   println("Implementations: {}", info.implementations.length)
   println("Strategy: {}", info.dispatch_strategy)
   ```

4. **Profile performance:**
   ```janus
   let (result, measurement) = measureDispatch {
       // Problematic code here
   }
   println("Dispatch overhead: {} ns", measurement.dispatch_time_ns)
   ```

## Configuration Options

### Global Dispatch Configuration

```janus
import std.dispatch.config.{
    setGlobalConfig,
    getGlobalConfig,
    DispatchConfig
}

type DispatchConfig = {
    enable_tracing: bool,
    enable_profiling: bool,
    cache_size: int,
    compression_threshold: int,
    optimization_level: OptimizationLevel,
    error_handling: ErrorHandlingMode
}

type OptimizationLevel = enum { none, basic, aggressive }
type ErrorHandlingMode = enum { strict, permissive, custom }

// Example usage
setGlobalConfig(DispatchConfig{
    enable_tracing: false,
    enable_profiling: true,
    cache_size: 4096,
    compression_threshold: 100,
    optimization_level: .aggressive,
    error_handling: .strict
})
```

### Per-Signature Configuration

```janus
import std.dispatch.config.{setSignatureConfig, SignatureConfig}

type SignatureConfig = {
    dispatch_strategy: ?DispatchStrategy,
    cache_size: ?int,
    compression: ?CompressionConfig,
    profiling: ?bool
}

// Example usage
setSignatureConfig("render", SignatureConfig{
    dispatch_strategy: .static_sealed,
    cache_size: 1024,
    compression: CompressionConfig{
        enabled: true,
        level: .maximum,
        algorithm: .hybrid
    },
    profiling: true
})
```

This API reference provides comprehensive coverage of all dispatch system APIs, from basic usage to advanced optimization and debugging. Use it as a reference when working with the Janus Multiple Dispatch System.

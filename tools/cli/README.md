<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Dispatch CLI Tools

A comprehensive toolkit for analyzing, debugging, and optimizing Janus dispatch behavior. These tools provide deep visibility into dispatch resolution, performance characteristics, and optimization strategies.

## 🎯 Overview

The Janus Dispatch CLI Tools transform dispatch from a black box into a transparent, debuggable, and optimizable system. Whether you're debugging ambiguous dispatch, optimizing hot paths, or understanding IR generation, these tools provide the insights you need.

### Core Philosophy

- **Complete Transparency**: Every dispatch decision is explainable and debuggable
- **Performance Visibility**: See exactly what dispatch costs and why
- **Optimization Guidance**: Get actionable recommendations for better performance
- **Developer Experience**: Tools that teach, not just report

## 🚀 Quick Start

```bash
# Build the CLI tools
cd tools/cli
zig build

# Query dispatch IR for a function
./zig-out/bin/janus-dispatch query dispatch-ir add --show-performance

# Trace a specific dispatch call
./zig-out/bin/janus-dispatch trace dispatch 'process(data)' --verbose

# Interactive tracing session
./zig-out/bin/janus-dispatch trace dispatch --json
```

## 📋 Commands

### Query Commands

#### `janus query dispatch-ir <symbol>`

Inspect the generated LLVM IR for a dispatch family, showing optimization strategies and performance characteristics.

```bash
# Basic IR query
janus query dispatch-ir add

# With performance analysis
janus query dispatch-ir add --show-performance

# With optimization details
janus query dispatch-ir add --show-optimization --show-performance
```

**Output Example:**
```
🔍 Dispatch IR Query: add
==================================================

📊 Family Overview:
  Name: add
  Implementations: 3
  Strategy: perfect_hash
  Static Resolvable: ❌ No

🔧 Generated LLVM IR:
------------------------------
define i32 @dispatch_add_optimized(%TypeId* %arg_types, i8** %args) {
entry:
  %hash = call i64 @perfect_hash_lookup(%TypeId* %arg_types, i32 2)
  %impl_ptr = getelementptr [8 x i8*], [8 x i8*]* @add_dispatch_table, i64 0, i64 %hash
  %impl = load i8*, i8** %impl_ptr
  %result = call i32 %impl(i8** %args)
  ret i32 %result
}

📈 Performance Characteristics:
  Strategy: perfect_hash
  Estimated Cycles: 12
  Memory Overhead: 64 bytes
  Cache Efficiency: excellent

⚡ Optimization Details:
  • Perfect Hash Generation: CHD algorithm with 1.2x space efficiency
  • Cache-Friendly Layout: Sequential memory access pattern
  • Branch Elimination: No conditional jumps in hot path
```

#### `janus query dispatch <signature>`

Show comprehensive information about a dispatch signature, including all implementations and resolution rules.

```bash
# Basic signature query
janus query dispatch process

# Show all candidates
janus query dispatch process --show-candidates

# Show resolution rules and ordering
janus query dispatch process --show-resolution --show-candidates
```

**Output Example:**
```
📋 Dispatch Query: process
========================================

📝 Signature: process
  Arity: 1 parameters
  Implementations: 4
  Ambiguities: 0

🎯 Implementation Summary:
  1. ✅ process_string(string) -> string
  2. ✅ process_data(Data) -> Result
  3. ✅ process_json(JsonValue) -> JsonValue
  4. ❌ process_legacy(any) -> any

🔍 All Candidates:
--------------------
Candidate 1: process_string
  Parameters: (string)
  Return Type: string
  Specificity Rank: 1
  Source: data.jan:15:1
  Reachable: ✅ Yes

Candidate 2: process_data
  Parameters: (Data)
  Return Type: Result
  Specificity Rank: 2
  Source: data.jan:25:1
  Reachable: ✅ Yes

⚖️  Resolution Rules:
--------------------
1. Exact Type Match (highest priority)
2. Subtype Match (by specificity)
3. Convertible Match (lowest priority)

🎯 Specificity Ordering:
  1. process_string(string)
  2. process_data(Data)
  3. process_json(JsonValue)
```

### Trace Commands

#### `janus trace dispatch [call]`

Trace dispatch resolution step-by-step, either for a specific call or in interactive mode.

```bash
# Trace a specific call
janus trace dispatch 'add(5, 10)' --verbose --timing

# Interactive tracing mode
janus trace dispatch --json

# Trace with filtering
janus trace dispatch --filter=math --flamegraph > dispatch.flame
```

**Single Call Output:**
```
🔍 Dispatch Trace: add(5, 10)
==================================================

🔍 Resolution Trace for: add(i32, i32)
----------------------------------------

Step 1: Finding matching candidates...
  Found 2 matching candidates:
    • add_i32(i32, i32)
    • add_number(Number, Number)

Step 2: Applying specificity rules...
  📋 [STEP] candidate_filtering: Found 2 matching candidates (125ns)
  📋 [STEP] specificity_analysis: Applying subtype ordering (89ns)
  📋 [STEP] cache_lookup: Cache miss, performing full resolution (45ns)
  📋 [STEP] ir_generation: Generated optimized dispatch code (234ns)

✅ Resolution successful!
  Selected: add_i32(i32, i32)

⏱️  Timing Analysis:
  Dispatch Resolution: 493ns
  Cache Lookup: 45ns
  Total Overhead: 538ns
```

**Interactive Mode:**
```
🔍 Janus Dispatch Tracer - Interactive Mode
=============================================
Commands:
  start <filter>     - Start tracing (optional filter)
  stop              - Stop tracing
  report <format>   - Generate report (console/json/csv/flamegraph)
  clear             - Clear trace buffer
  status            - Show current status
  help              - Show this help
  quit              - Exit tracer

tracer> start math
✅ Started tracing functions matching: math

tracer> status
📊 Tracer Status
-----------------
Active Traces: 0
Total Trace Entries: 0
Total Dispatches: 0
Average Resolution Time: 0ns
Active Filter: math
Detailed Tracing: Enabled

tracer> report console
📊 Dispatch Performance Report
==================================================

📈 Overall Statistics:
  Total Dispatches: 1,247
  Static Dispatches: 892 (71.5%)
  Dynamic Dispatches: 355 (28.5%)
  Cache Hit Rate: 94.2%
  Average Resolution Time: 67ns

🔥 Hot Paths:
  math_add:
    Calls: 456
    Average Time: 23ns
    Cache Hit Rate: 98.9%
    Total Time: 10.49ms

⚡ Strategy Breakdown:
  static_direct: 892 calls, 0ns avg
  perfect_hash_lookup: 201 calls, 25ns avg
  inline_cache_hit: 134 calls: 15ns avg
  switch_table_lookup: 20 calls, 89ns avg
```

## 🔧 Options Reference

### Query Options

| Option | Description |
|--------|-------------|
| `--show-performance` | Include performance analysis in IR query |
| `--show-optimization` | Show optimization strategy details |
| `--show-candidates` | List all candidate implementations |
| `--show-resolution` | Show resolution rules and ordering |

### Trace Options

| Option | Description |
|--------|-------------|
| `--verbose` | Show detailed resolution steps |
| `--timing` | Include timing analysis |
| `--json` | Output in JSON format |
| `--csv` | Output in CSV format |
| `--flamegraph` | Output flamegraph data |
| `--filter=<pattern>` | Trace only functions matching pattern |
| `--max-entries=<n>` | Maximum trace entries to keep (default: 10000) |

## 📊 Output Formats

### Console Format (Default)

Human-readable output with colors, icons, and structured information. Perfect for interactive debugging and development.

### JSON Format

Machine-readable structured data for integration with other tools:

```json
{
  "performance_counters": {
    "total_dispatches": 1247,
    "static_dispatches": 892,
    "dynamic_dispatches": 355,
    "cache_hits": 1174,
    "cache_misses": 73,
    "average_resolution_time_ns": 67
  },
  "traces": [
    {
      "timestamp": 1640995200000000000,
      "call_id": 1,
      "function_name": "add",
      "resolution_strategy": "perfect_hash_lookup",
      "resolution_time_ns": 25,
      "selected_implementation": "add_i32",
      "cache_hit": true
    }
  ]
}
```

### CSV Format

Tabular data for spreadsheet analysis and data processing:

```csv
timestamp,call_id,function_name,resolution_strategy,resolution_time_ns,selected_implementation,cache_hit
1640995200000000000,1,add,perfect_hash_lookup,25,add_i32,true
1640995200000000001,2,process,inline_cache_hit,15,process_string,true
```

### Flamegraph Format

Stack-based performance visualization data:

```
add;perfect_hash_lookup 25
process;inline_cache_hit 15
compute;switch_table_lookup 89
```

Use with [FlameGraph](https://github.com/brendangregg/FlameGraph):
```bash
janus trace dispatch --flamegraph > dispatch.flame
flamegraph.pl dispatch.flame > dispatch.svg
```

## 🎯 Use Cases

### 1. Debugging Ambiguous Dispatch

When you encounter ambiguous dispatch errors:

```bash
# Find the conflicting implementations
janus query dispatch problematic_function --show-candidates --show-resolution

# Trace the specific call that's failing
janus trace dispatch 'problematic_function(arg1, arg2)' --verbose
```

### 2. Performance Optimization

Identify and optimize dispatch hot paths:

```bash
# Start interactive tracing
janus trace dispatch

tracer> start
# ... run your application ...
tracer> report console
# Look for hot paths with high call counts or resolution times

# Get detailed IR for hot functions
janus query dispatch-ir hot_function --show-performance --show-optimization
```

### 3. Understanding Optimization Strategies

See how the compiler optimizes your dispatch:

```bash
# Check what strategy was selected and why
janus query dispatch-ir my_function --show-optimization

# Compare different implementations
janus query dispatch my_signature --show-candidates
```

### 4. CI/CD Integration

Automate dispatch performance monitoring:

```bash
# Generate machine-readable performance report
janus trace dispatch --json > dispatch_report.json

# Check for performance regressions
janus query dispatch-ir critical_function --show-performance | grep "Estimated Cycles"
```

### 5. Learning and Teaching

Understand how dispatch works:

```bash
# Step through resolution process
janus trace dispatch 'example_call(args)' --verbose

# See the generated code
janus query dispatch-ir example_function --show-optimization
```

## 🏗️ Architecture

### Components

1. **DispatchQueryCLI**: Handles `query` commands, loads dispatch families, generates IR analysis
2. **DispatchTracer**: Core tracing engine with performance counters and trace buffer management
3. **DispatchTracerCLI**: Interactive tracing interface with real-time monitoring
4. **JanusDispatchCLI**: Main entry point that coordinates all tools

### Integration Points

- **libjanus**: Core dispatch system integration
- **DispatchFamily**: Function family management
- **DispatchTableOptimizer**: IR generation and optimization
- **AdvancedStrategySelector**: Optimization strategy selection (shared types via `compiler/codegen/types.zig`)

### Performance Characteristics

- **Query Operations**: O(1) lookup, <1ms typical response
- **Trace Recording**: <100ns overhead per dispatch
- **Report Generation**: O(n) where n = trace count, <50ms for 10k traces
- **Memory Usage**: ~100 bytes per trace entry, configurable limits

## 🧪 Testing

Run the comprehensive test suite:

```bash
# Run all tests
zig build test

# Run with coverage
zig build test --summary all

# Performance tests
zig build test --release-fast
```

Test coverage includes:
- ✅ CLI argument parsing and validation
- ✅ Dispatch family loading and querying
- ✅ Trace recording and performance counters
- ✅ Report generation in all formats
- ✅ Error handling and edge cases
- ✅ Memory management and leak detection
- ✅ Performance benchmarks

## 🚀 Development

### Building

```bash
# Development build
zig build

# Optimized build
zig build -Drelease-fast

# Individual tools
zig build-exe dispatch_query.zig
zig build-exe dispatch_tracer.zig
```

### Adding New Features

1. **New Query Types**: Extend `DispatchQueryCLI` with additional analysis
2. **Trace Filters**: Add filtering logic to `DispatchTracer`
3. **Output Formats**: Implement new formats in report generation
4. **Optimization Strategies**: Integrate with new dispatch optimizations

### Integration with IDE

The CLI tools are designed to integrate with IDE plugins and language servers:

- JSON output for structured data exchange
- Fast query responses for real-time analysis
- Detailed error information for diagnostics
- Performance data for optimization hints

## 📚 Examples

### Example 1: Debugging Performance Issues

```bash
# Start performance monitoring
janus trace dispatch --filter=hot_path

# In another terminal, run your application
./my_janus_app

# Back in tracer
tracer> report console
# Look for functions with high resolution times

# Investigate specific hot functions
janus query dispatch-ir slow_function --show-performance
```

### Example 2: Understanding Dispatch Behavior

```bash
# See all implementations of a polymorphic function
janus query dispatch render --show-candidates

# Trace how a specific call resolves
janus trace dispatch 'render(my_object)' --verbose

# Check the generated IR
janus query dispatch-ir render --show-optimization
```

### Example 3: Automated Performance Testing

```bash
#!/bin/bash
# performance_test.sh

# Run application with tracing
janus trace dispatch --json > baseline.json &
TRACER_PID=$!

./run_benchmarks.jan

kill $TRACER_PID

# Analyze results
jq '.performance_counters.average_resolution_time_ns' baseline.json
```

## 🤝 Contributing

We welcome contributions to the CLI tools! Areas of interest:

- **Visualization**: Web-based dispatch table explorer
- **IDE Integration**: VSCode/IntelliJ plugins
- **Performance**: Optimization of tracing overhead
- **Analysis**: Advanced performance analytics
- **Documentation**: Examples and tutorials

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## 📄 License

Part of the Janus Programming Language project.
- CLI Tools: LSL-1.0 (same as compiler core)
- Documentation: CC-BY-4.0

---

**The dispatch system is no longer a black box. With these tools, every dispatch decision is transparent, debuggable, and optimizable. Happy dispatching! 🚀**

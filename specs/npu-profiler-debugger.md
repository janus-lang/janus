<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus :compute Profile — Profiler and Debugger Guide

**Version:** 0.1.1-dev (DRAFT)
**Status:** DRAFT — Implementation Complete
**Last Updated:** 2025-10-06
**Authority:** Language Architecture Team

---

## Overview

The Janus :compute profile includes comprehensive profiling and debugging tools for tensor graph optimization and execution. This guide covers the profiler integration, graph debugger, and performance monitoring capabilities that enable developers to optimize NPU-native workloads effectively.

## Quick Start

### Basic Profiling

```bash
# Build with profiling enabled
janus --profile=npu build --debug-profile my_app.jan

# Run with profiling output
./my_app --profile-output=profile.json

# Analyze profile data
janus profile analyze profile.json --format=html > report.html
```

### Graph Debugging

```bash
# Enable graph debugging
janus --profile=npu build --debug-graph my_app.jan

# Run with graph visualization
./my_app --graphviz-output=graph.dot

# View the graph
dot -Tpng graph.dot -o graph.png
```

## Profiler Integration

### Kernel and Transfer Timing

The profiler tracks performance metrics for all tensor operations:

```janus
// Example: Profile-guided optimization
let config = {
  profiling: {
    enabled: true,
    output_file: "perf.json",
    track_kernels: true,
    track_transfers: true,
    track_fusion: true
  }
}

let app := build_tensor_app(config)
app.run()  // Generates detailed profile
```

**Profile Output:**
```json
{
  "kernels": {
    "matmul_0": {
      "device": "npu",
      "execution_time_us": 1250,
      "memory_bandwidth_gbps": 45.2,
      "utilization_percent": 78.5
    }
  },
  "transfers": {
    "dram_to_sram_0": {
      "bytes": 1048576,
      "time_us": 85,
      "bandwidth_gbps": 98.7
    }
  }
}
```

### Fusion Plan Analysis

Track how optimization passes affect graph structure:

```bash
janus profile analyze profile.json --focus=fusion
```

**Fusion Report:**
```
Fusion Groups:
  Group 0: Matmul + Relu (2 nodes -> 1 fused kernel)
    - Memory savings: 4MB
    - Performance gain: 23%
  Group 1: Conv2D + BN + Relu (3 nodes -> 1 fused kernel)
    - Memory savings: 8MB
    - Performance gain: 41%
```

## Graph Debugger

### Visual Graph Inspection

The graph debugger provides visual representations of J-IR graphs:

```bash
# Generate visual graph with optimization annotations
janus debug graph my_app.jan --output=debug_graph.html

# Include memory layout information
janus debug graph my_app.jan --memory-layout --output=mem_graph.html
```

### Interactive Debugging

```janus
// Insert debug points in tensor code
let input: tensor<f32, 128 x 256> on dram
let weights: tensor<f32, 256 x 64> on sram

// Debug tensor values at runtime
debug_tensor(input, "input_layer")
debug_tensor(weights, "weight_matrix")

let output := input.matmul(weights) on device(npu)
debug_tensor(output, "output_before_activation")

let activated := output.relu()
debug_tensor(activated, "final_output")
```

### Memory Residency Tracking

Monitor memory space transitions and transfer costs:

```bash
# Track memory residency changes
janus debug memory my_app.jan --track-transfers --output=memory_trace.json

# Visualize memory layout
janus debug memory my_app.jan --visualize --output=memory_map.svg
```

## Stream and Event Debugging

### Stream Occupancy Analysis

Monitor device utilization across execution streams:

```bash
# Analyze stream utilization
janus debug streams my_app.jan --timeline --output=timeline.html

# Detect synchronization bottlenecks
janus debug streams my_app.jan --bottleneck-analysis --output=bottlenecks.txt
```

**Stream Timeline Output:**
```
NPU Stream:
  [0.0ms - 1.2ms] Matmul (128x256 * 256x64)
  [1.2ms - 1.8ms] Transfer (4MB DRAM -> SRAM)
  [1.8ms - 2.1ms] Conv2D (128x64 * 3x3)
  [2.1ms - 2.3ms] Transfer (2MB SRAM -> DRAM)

CPU Stream:
  [0.5ms - 1.0ms] Data preprocessing
  [2.0ms - 2.2ms] Post-processing
```

### Event Synchronization Debugging

Debug event-based synchronization issues:

```janus
stream compute_stream on device(npu)
stream io_stream on device(cpu)

event compute_done
event io_ready

// Submit work to streams
submit compute_stream, {
  let result := heavy_computation(input)
  record compute_done, compute_stream
}

submit io_stream, {
  await compute_done
  let output := save_to_disk(result)
  record io_ready, io_stream
}

// Debug event dependencies
debug_events(compute_done, io_ready)
```

## Unified Fabric Metrics (CapApu)

When a unified fabric is detected, profiling reports include `device: "apu"` and zero-copy residency markers that demonstrate Janus's capability-based approach to heterogeneous computing:

```bash
janus profile analyze profile.json --focus=memory-plan
```

**Sample Memory Plan Excerpt:**
```json
{
  "actions": [],
  "default_residency": "shared",
  "capability": "CapApu"
}
```

- `actions: []` indicates no extra transfers were needed (Memory.Shared zero-copy).
- Use `janus debug memory ... --highlight=shared` to ensure tensors stay on the unified fabric.

**Tip:** Enable `JANUS_FAKE_APU=1` in staging environments to validate APU code paths without hardware.

## Performance Optimization Guide

### Memory-Aware Tiling

Use the tile pass profiler to optimize for SRAM capacity:

```bash
# Profile tiling decisions
janus profile tile my_app.jan --sram-capacity=64KB --output=tile_analysis.json

# Optimize tile sizes based on profile
janus optimize tiles my_app.jan --target-device=npu --output=optimized.jan
```

### Quantization Impact Analysis

Measure the performance vs accuracy trade-offs:

```bash
# Profile quantization effects
janus profile quant my_app.jan --tolerance=0.01 --output=quant_profile.json

# Generate accuracy report
janus debug accuracy my_app.jan --baseline=f32 --quantized=int8 --output=accuracy.html
```

### Device Selection Optimization

Profile different device assignments:

```bash
# Profile device selection strategies
janus profile devices my_app.jan --strategy=auto --output=device_profile.json
janus profile devices my_app.jan --strategy=manual --device-map=cpu:0-2,npu:3-5 --output=manual_profile.json

# Compare strategies
janus profile compare device_profile.json manual_profile.json --output=comparison.html
```

## Integration with External Tools

### Export to Standard Formats

```bash
# Export profile data for external analysis
janus profile export my_profile.json --format=chrome-trace --output=trace.json
janus profile export my_profile.json --format=pytorch-profiler --output=pt_profile.json

# Import external profile data
janus profile import external_profile.json --format=tensorboard --merge-with=my_profile.json
```

### Custom Profiler Integration

```zig
// Custom profiler implementation
const TensorProfiler = struct {
    pub fn onKernelStart(kernel: KernelId, device: DeviceKind) void {
        // Custom profiling logic
        startTimer(kernel);
    }

    pub fn onKernelEnd(kernel: KernelId, duration_ns: u64) void {
        // Record custom metrics
        recordMetric(kernel, duration_ns);
    }

    pub fn onTransfer(src: MemSpace, dst: MemSpace, bytes: u64, duration_ns: u64) void {
        // Track transfer efficiency
        recordTransferMetric(src, dst, bytes, duration_ns);
    }
};
```

## Best Practices

### Profiling Workflow

1. **Start Simple**: Begin with basic kernel timing
2. **Identify Bottlenecks**: Use transfer profiling to find memory bottlenecks
3. **Optimize Memory**: Use tiling analysis for SRAM optimization
4. **Tune Fusion**: Profile fusion decisions for your specific workload
5. **Monitor End-to-End**: Track total execution time across devices

### Debugging Workflow

1. **Visualize First**: Generate graph visualizations to understand structure
2. **Check Memory Layout**: Verify memory residency matches expectations
3. **Monitor Streams**: Identify synchronization and concurrency issues
4. **Profile Hot Paths**: Focus optimization on frequently executed code
5. **Validate Changes**: Compare profiles before and after optimizations

### Performance Guidelines

- **Target Utilization**: Aim for >80% device utilization
- **Minimize Transfers**: Keep frequently accessed data in fast memory
- **Balance Load**: Distribute work evenly across available devices
- **Monitor Memory**: Track memory usage to avoid OOM conditions
- **Profile Regularly**: Make profiling part of your development workflow

## Troubleshooting

### Common Issues

**High Transfer Overhead**
```bash
# Problem: Too much time spent in memory transfers
janus profile analyze profile.json --focus=transfers

# Solution: Increase SRAM capacity or adjust tiling
janus optimize memory my_app.jan --increase-sram-usage --output=optimized.jan
```

**Low Device Utilization**
```bash
# Problem: Device not fully utilized
janus profile analyze profile.json --focus=utilization

# Solution: Increase parallelism or batch size
janus optimize parallelism my_app.jan --increase-batch-size --output=optimized.jan
```

**Synchronization Bottlenecks**
```bash
# Problem: Events causing unnecessary synchronization
janus debug streams my_app.jan --detect-deadlocks --output=stream_analysis.txt

# Solution: Reorganize stream dependencies
janus optimize streams my_app.jan --minimize-sync --output=optimized.jan
```

## Advanced Features

### Custom Metrics Collection

```janus
// Define custom profiling metrics
let custom_profiler = {
  metrics: {
    "custom_throughput": 0,
    "memory_efficiency": 0,
    "cache_hit_rate": 0
  }
}

// Use in tensor operations
let result := process_data(input, profiler: custom_profiler)
```

### Real-time Monitoring

```bash
# Enable real-time profiling output
janus run my_app.jan --profile=npu --real-time-profile --profile-interval=100ms

# Monitor specific metrics in real-time
janus monitor my_app.jan --metrics=kernel_time,transfer_bw,device_util
```

## API Reference

### Profiler API

```zig
// Core profiling interface
pub const TensorProfiler = struct {
    pub fn startSession(self: *TensorProfiler, config: ProfilingConfig) !void;
    pub fn endSession(self: *TensorProfiler) !void;
    pub fn recordKernel(self: *TensorProfiler, kernel: KernelInfo) !void;
    pub fn recordTransfer(self: *TensorProfiler, transfer: TransferInfo) !void;
    pub fn exportData(self: *TensorProfiler, format: ExportFormat) ![]const u8;
};
```

### Debugger API

```zig
// Core debugging interface
pub const GraphDebugger = struct {
    pub fn visualizeGraph(self: *GraphDebugger, graph: *Graph) ![]const u8;
    pub fn traceExecution(self: *GraphDebugger, graph: *Graph) !TraceResult;
    pub fn inspectTensor(self: *GraphDebugger, tensor: TensorId) !TensorInfo;
    pub fn analyzeMemory(self: *GraphDebugger, graph: *Graph) !MemoryAnalysis;
};
```

## Examples

See the `examples/npu/` directory for complete working examples:

- `basic_profiling.jan` - Basic profiling setup
- `graph_debugging.jan` - Interactive graph debugging
- `performance_optimization.jan` - Complete optimization workflow
- `stream_synchronization.jan` - Multi-stream coordination

## References

- [SPEC-profile-npu.md](SPEC-profile-npu.md) - NPU profile specification
- [SPEC-syntax.md](SPEC-syntax.md) - Syntax extensions for NPU
- [tensor_jir.zig](../../../compiler/libjanus/tensor_jir.zig) - J-IR implementation
- [tensor_runtime.zig](../../../compiler/libjanus/tensor_runtime.zig) - Runtime implementation

---

**Document Status:** Complete implementation with comprehensive profiling and debugging capabilities ready for production use.

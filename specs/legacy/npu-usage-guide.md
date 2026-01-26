<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus :compute Profile — Usage Guide

**Version:** 0.1.1-dev (DRAFT)
**Status:** DRAFT — Implementation Complete
**Last Updated:** 2025-10-06
**Authority:** Language Architecture Team

---

## Overview

This guide provides comprehensive instructions for using the Janus :compute profile features including tensor types, memory spaces, device pinning, streams, and events. The :compute profile enables native AI/ML workloads with heterogeneous device acceleration.

## Prerequisites

### Enable NPU Profile

```bash
# Build with NPU profile
janus --profile=npu build my_app.jan

# Or set environment variable
export JANUS_PROFILE=npu
janus build my_app.jan
```

### Basic Setup

```janus
// Import NPU runtime
import std.npu

// Initialize NPU context
let ctx := npu.init_context()
defer ctx.deinit()

// Your NPU-accelerated code here
```

## Tensor Types

### Basic Tensor Declaration

```janus
// Declare tensors with shape and element type
let input: tensor<f32, 128 x 256>
let weights: tensor<f16, 256 x 512>
let bias: tensor<f32, 512>

// Initialize from arrays
let data := [1.0, 2.0, 3.0, 4.0]
let tensor_data := tensor<f32, 2 x 2>.from_array(data)
```

### Memory Space Qualifiers

```janus
// Pin tensors to specific memory spaces
let fast_memory: tensor<f16, 1024 x 1024> on sram    // Fast on-chip memory
let gpu_memory: tensor<f32, 512 x 512> on vram       // GPU video memory
let host_memory: tensor<i8, 256 x 256> on host       // System memory
let default_memory: tensor<f64, 128 x 128> on dram   // Default DRAM

// Memory spaces affect performance and availability
// - sram: Fastest, limited capacity (64-256KB typical)
// - vram: Fast, large capacity (GPU memory)
// - dram: Slower, very large capacity
// - host: Slowest, system memory, accessible by CPU
```

## Device Pinning and Execution

### Device Hints

```janus
// Specify preferred execution device
let result1 := input.matmul(weights) on device(npu)
let result2 := data.conv2d(kernel) on device(gpu)
let result3 := preprocessing(data) on device(cpu)

// Device hints guide scheduling but may fall back if unavailable
let flexible := compute_heavy(input) on device(npu|gpu)  // Either device
```

### Stream-based Execution

```janus
// Create execution streams for concurrent execution
stream compute_stream on device(npu)
stream io_stream on device(cpu)
stream gpu_stream on device(gpu)

// Submit work to streams
submit compute_stream, {
  let features := extract_features(input)
  record compute_done, compute_stream
}

submit io_stream, {
  await compute_done
  let saved := save_to_disk(features)
  record io_complete, io_stream
}

// Wait for completion
await io_complete
```

### Event Synchronization

```janus
// Create events for fine-grained synchronization
event data_ready
event compute_done
event output_ready

// Record events on streams
submit compute_stream, {
  let result := heavy_computation(input)
  record compute_done, compute_stream
}

// Wait for events before proceeding
submit io_stream, {
  await compute_done
  let output := save_result(result)
  record output_ready, io_stream
}
```

## Memory Management

### Automatic Memory Residency

```janus
// Runtime automatically manages memory placement
let model: tensor<f32, 1000 x 1000> on dram
let input: tensor<f32, 1 x 1000> on host

// Operations may trigger automatic transfers
let output := input.matmul(model) on device(npu)
// Runtime transfers input to SRAM for NPU execution
// Keeps model in DRAM (too large for SRAM)
// Transfers result back to host memory
```

### Explicit Memory Transfers

```janus
// Explicit control over memory placement
let data: tensor<f32, 256 x 256> on host

// Prefetch to fast memory
let fast_data := data.transfer(to: sram)

// Compute on fast memory
let result := fast_data.conv2d(kernel) on device(npu)

// Transfer result back
let host_result := result.transfer(to: host)
```

### Memory Pools

```janus
// Use memory pools for efficient allocation
let pool := memory_pool(sram, capacity: 1MB)

using pool do
  let temp1: tensor<f32, 128 x 128> on sram := pool.allocate()
  let temp2: tensor<f32, 64 x 64> on sram := pool.allocate()

  // Use temporary tensors
  let combined := temp1.concat(temp2)

  // Automatic cleanup when pool goes out of scope
end  // temp1 and temp2 returned to pool
```

## Unified Fabric (APU/AGPU) Support

Janus automatically detects unified fabrics (HSA/ROCm, Level Zero, simulated) and advertises `CapApu` with shared residency, enabling zero-copy execution across CPU, GPU, and NPU while maintaining the language's core doctrines of capability security and allocator sovereignty.

### Detecting CapApu at Runtime

```janus
import std.npu.runtime

let ctx := runtime.init()
defer ctx.deinit()

const manifest = try ctx.capabilityManifest(allocator)
defer allocator.free(manifest)

for (manifest) |entry| {
  if (entry.capability == "CapApu") {
    log.info("Unified fabric available; zero-copy = {}", .{entry.zero_copy})
  }
}
```

**Environment Overrides (for testing and CI):**
- `JANUS_FAKE_APU=1` — force unified fabric detection
- `JANUS_APU_SYSFS_ROOT=/tmp/apu` — override ROCm topology probe
- `JANUS_APU_LEVEL0_HINT=1` — force Intel Level Zero detection

### Zero-Copy with `Memory.Shared`

```janus
let shared_tensor: tensor<f32, 1024 x 64> on shared
let logits := shared_tensor.matmul(weights) on device(auto)
// MemoryPlanner respects Memory.Shared and avoids redundant transfers.
```

`device(auto)` resolves to the best available accelerator:

```
auto → apu (CapApu) → npu (CapNpu) → gpu (CapGpu) → cpu
```

Inspect planned devices with:

```bash
janus --profile=npu build my_app.jan --explain-device-plan
```

## Advanced Patterns

### Pipeline Parallelism

```janus
// Stage 1: Data loading (CPU)
stream load_stream on device(cpu)
event load_done

submit load_stream, {
  let batch := load_data_batch(batch_id)
  record load_done, load_stream
}

// Stage 2: Preprocessing (CPU/GPU)
stream prep_stream on device(cpu)
event prep_done

submit prep_stream, {
  await load_done
  let processed := preprocess_data(batch)
  record prep_done, prep_stream
}

// Stage 3: Inference (NPU)
stream compute_stream on device(npu)
event compute_done

submit compute_stream, {
  await prep_done
  let predictions := model.infer(processed)
  record compute_done, compute_stream
}

// Stage 4: Post-processing (CPU)
stream post_stream on device(cpu)

submit post_stream, {
  await compute_done
  let results := postprocess_predictions(predictions)
  save_results(results)
}
```

### Model Parallelism

```janus
// Split model across devices
let model_part1: tensor<f32, 512 x 512> on device(npu:0)
let model_part2: tensor<f32, 512 x 256> on device(npu:1)

// Pipeline execution across model parts
let intermediate := input.matmul(model_part1) on device(npu:0)
let output := intermediate.matmul(model_part2) on device(npu:1)
```

### Memory-Efficient Training

```janus
// Gradient accumulation for large models
let accumulated_gradients: tensor<f32, 1024 x 1024> on sram

for batch in training_batches do
  // Forward pass
  let predictions := model.forward(batch.input)
  let loss := compute_loss(predictions, batch.target)

  // Backward pass (accumulate gradients)
  let gradients := loss.backward()
  accumulated_gradients.add_in_place(gradients)

  // Update model every N batches
  if batch.id % 16 == 0 do
    model.update(accumulated_gradients.scale(1.0/16.0))
    accumulated_gradients.zero()
  end
end
```

## Optimization Techniques

### Fusion Optimization

```janus
// Manual fusion for better performance
let efficient := input
  .matmul(weights)
  .relu()
  .add(bias)
  .conv2d(kernel) on device(npu)

// The compiler may automatically fuse compatible operations
// Check fusion plan with profiling tools
```

### Tiling for Memory Constraints

```janus
// Manual tiling for large tensors
let large_tensor: tensor<f32, 4096 x 4096> on dram

// Process in tiles that fit in SRAM
let tile_size := 512
for i in 0..<(4096/tile_size) do
  for j in 0..<(4096/tile_size) do
    let tile := large_tensor[i*tile_size..<(i+1)*tile_size,
                            j*tile_size..<(j+1)*tile_size]
    let fast_tile := tile.transfer(to: sram)
    let result_tile := fast_tile.matmul(weight_tile) on device(npu)
    results[i*tile_size..<(i+1)*tile_size,
            j*tile_size..<(j+1)*tile_size] := result_tile.transfer(to: dram)
  end
end
```

### Quantization

```janus
// Mixed precision for memory savings
let model_fp32: tensor<f32, 1000 x 1000> on dram
let model_fp16: tensor<f16, 1000 x 1000> on sram

// Quantize for inference
let quantized_model := model_fp32.quantize(to: int8, scale: 0.1)
let dequantized := quantized_model.dequantize(scale: 0.1)

// Use quantized model for inference
let predictions := quantized_model.infer(input) on device(npu)
```

## Error Handling and Debugging

### Profile-Aware Error Handling

```janus
// NPU features require :compute profile
let tensor_data: tensor<f32, 128 x 128>  // ❌ Error without :compute

// Correct usage with profile
let tensor_data: tensor<f32, 128 x 128> on sram  // ✅ With :compute
```

### Runtime Error Handling

```janus
// Handle device-specific errors
let result := try compute_on_npu(input) or do |err|
  log.warn("NPU computation failed", err: err)
  let fallback := compute_on_cpu(input)
  fallback
end
```

### Debugging Tensor Operations

```janus
// Debug tensor values and shapes
let input: tensor<f32, 64 x 64> on dram
debug_tensor(input, "input_before_processing")

let processed := preprocess(input)
debug_tensor(processed, "processed_data")

// Debug memory usage
debug_memory_usage("after_preprocessing")

// Debug device utilization
debug_device_utilization(npu)
```

## Performance Monitoring

### Real-time Metrics

```janus
// Monitor performance metrics
let monitor := performance_monitor()
monitor.track_metric("npu_utilization")
monitor.track_metric("memory_bandwidth")
monitor.track_metric("kernel_latency")

// Use in performance-critical code
let start_time := monitor.start_timing("inference")
let result := model.infer(input) on device(npu)
let latency := monitor.end_timing("inference")

log.info("Inference latency", ms: latency)
```

### Profiling Integration

```janus
// Enable detailed profiling
let profiler := npu_profiler()
profiler.enable_kernel_timing()
profiler.enable_memory_tracking()
profiler.enable_transfer_tracking()

// Profile a complete workload
let profile_result := profiler.profile({
  let features := extract_features(input)
  let predictions := model.predict(features)
  save_predictions(predictions)
})

log.info("Profile results", profile: profile_result)
```

## Best Practices

### Memory Management

1. **Pin frequently accessed data in SRAM**
   ```janus
   let weights: tensor<f32, 512 x 512> on sram  // Frequently reused
   let input: tensor<f32, 1 x 512> on dram      // Streamed data
   ```

2. **Use memory pools for temporary allocations**
   ```janus
   let temp_pool := memory_pool(sram, capacity: 2MB)
   using temp_pool do
     // Efficient temporary allocations
   end
   ```

3. **Minimize cross-device transfers**
   ```janus
   // Keep data local to computation device
   let local_data := data.transfer(to: sram)
   let result := local_data.compute() on device(npu)
   // Result stays in SRAM until needed elsewhere
   ```

### Stream Usage

1. **Use streams for concurrent execution**
   ```janus
   // Overlap computation and I/O
   stream compute_stream on device(npu)
   stream io_stream on device(cpu)

   submit compute_stream, { compute_heavy_task() }
   submit io_stream, { load_next_batch() }
   ```

2. **Minimize synchronization points**
   ```janus
   // Use events only when necessary
   event necessary_sync
   // Avoid unnecessary event waits
   ```

3. **Balance load across streams**
   ```janus
   // Distribute work evenly
   let workload_per_stream := total_work / num_streams
   ```

### Device Selection

1. **Choose devices based on workload characteristics**
   ```janus
   // CPU: Complex control flow, small computations
   // GPU: Regular, parallel computations
   // NPU: Tensor operations, matrix multiplications
   ```

2. **Use device hints appropriately**
   ```janus
   let matrix_mult := a.matmul(b) on device(npu)    // NPU preferred
   let preprocessing := prepare_data(x) on device(cpu)  // CPU preferred
   ```

## Common Patterns

### Batch Inference

```janus
func batch_infer(model: Model, batch: []Tensor) -> []Tensor {
  let results := []

  // Prefetch model weights to fast memory
  let model_sram := model.weights.transfer(to: sram)

  for input in batch do
    // Transfer input to SRAM for computation
    let input_sram := input.transfer(to: sram)

    // Compute on NPU with fast memory
    let prediction := input_sram.matmul(model_sram) on device(npu)

    // Transfer result back to host
    let host_result := prediction.transfer(to: host)
    results.append(host_result)
  end

  return results
}
```

### Model Training Loop

```janus
func train_model(model: Model, dataset: Dataset) -> Model {
  let optimizer := Adam(learning_rate: 0.001)

  for epoch in 0..<100 do
    for batch in dataset.batches() do
      // Forward pass
      let predictions := model.forward(batch.input)

      // Compute loss
      let loss := cross_entropy(predictions, batch.target)

      // Backward pass (accumulate gradients)
      let gradients := loss.backward()

      // Update parameters
      optimizer.step(model.parameters, gradients)
    end

    log.info("Epoch completed", epoch: epoch, loss: epoch_loss)
  end

  return model
}
```

### Real-time Processing

```janus
func real_time_pipeline(input_stream: InputStream) -> OutputStream {
  stream processing_stream on device(npu)
  stream output_stream on device(cpu)

  event frame_ready
  event processing_done

  while true do
    let frame := input_stream.next()

    submit processing_stream, {
      let features := extract_features(frame)
      let result := model.process(features)
      record processing_done, processing_stream
    }

    submit output_stream, {
      await processing_done
      output_stream.send(result)
    }
  end
}
```

## Troubleshooting

### Common Issues

**Memory Capacity Exceeded**
```janus
// Problem: Tensor too large for SRAM
let huge_tensor: tensor<f32, 4096 x 4096> on sram  // ❌ May fail

// Solution: Use DRAM with explicit transfers
let huge_tensor: tensor<f32, 4096 x 4096> on dram
let fast_tile := huge_tensor[0..512, 0..512].transfer(to: sram)
```

**Device Not Available**
```janus
// Problem: Requested device not available
let result := compute(data) on device(npu)  // ❌ May fail

// Solution: Provide fallback
let result := try compute(data) on device(npu)
              or compute(data) on device(gpu)
              or compute(data) on device(cpu)
```

**Synchronization Issues**
```janus
// Problem: Race conditions between streams
submit stream1, { compute_a() }
submit stream2, { compute_b() }  // ❌ May depend on compute_a()

// Solution: Use events for proper synchronization
event a_done
submit stream1, {
  compute_a()
  record a_done, stream1
}
submit stream2, {
  await a_done
  compute_b()
}
```

## Examples

See the `examples/npu/` directory for complete working examples:

- `basic_tensors.jan` - Basic tensor operations
- `memory_management.jan` - Memory space usage patterns
- `stream_synchronization.jan` - Multi-stream coordination
- `model_inference.jan` - Complete inference pipeline
- `training_loop.jan` - Training with memory optimization
- `real_time_processing.jan` - Real-time stream processing

## Performance Tips

1. **Maximize SRAM usage** for frequently accessed data
2. **Minimize memory transfers** between devices
3. **Use streams** for concurrent execution
4. **Profile regularly** to identify bottlenecks
5. **Consider fusion** for multi-operation kernels
6. **Use appropriate precision** (f16, int8) for memory savings

## References

- [SPEC-profile-npu.md](SPEC-profile-npu.md) - NPU profile specification
- [SPEC-syntax.md](SPEC-syntax.md) - Syntax reference
- [SPEC-grammar.md](SPEC-grammar.md) - Grammar specification
- [tensor_jir.zig](../../../compiler/libjanus/tensor_jir.zig) - J-IR implementation
- [tensor_runtime.zig](../../../compiler/libjanus/tensor_runtime.zig) - Runtime implementation

---

**Document Status:** Complete implementation with comprehensive usage patterns and optimization techniques ready for production use.

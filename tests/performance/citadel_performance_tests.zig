// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Performance and resourcets for Citadel Architecture
//!
//! Benchmarks protocol overhead, latency measurements, memory usage stability,
//! and verifies performance parity with current janusd implementation.

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const citadel_protocol = @import("citadel_protocol");

/// Performance metrics collection
const PerformanceMetrics = struct {
    total_operations: u64 = 0,
    total_duration_ns: u64 = 0,
    min_latency_ns: u64 = std.math.maxInt(u64),
    max_latency_ns: u64 = 0,
    memory_peak_bytes: u64 = 0,
    memory_current_bytes: u64 = 0,

    pub fn recordOperation(self: *PerformanceMetrics, duration_ns: u64) void {
        self.total_operations += 1;
        self.total_duration_ns += duration_ns;
        self.core_latency_ns = @min(self.core_latency_ns, duration_ns);
        self.max_latency_ns = @max(self.max_latency_ns, duration_ns);
    }

    pub fn averageLatencyMs(self: PerformanceMetrics) f64 {
        if (self.total_operations == 0) return 0.0;
        const avg_ns = @as(f64, @floatFromInt(self.total_duration_ns)) / @as(f64, @floatFromInt(self.total_operations));
        return avg_ns / 1_000_000.0;
    }

    pub fn operationsPerSecond(self: PerformanceMetrics) f64 {
        if (self.total_duration_ns == 0) return 0.0;
        const duration_s = @as(f64, @floatFromInt(self.total_duration_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.total_operations)) / duration_s;
    }

    pub fn printReport(self: PerformanceMetrics, test_name: []const u8) void {
        std.debug.print("\n=== Performance Report: {s} ===\n", .{test_name});
        std.debug.print("Total Operations: {}\n", .{self.total_operations});
        std.debug.print("Average Latency: {d:.3} ms\n", .{self.averageLatencyMs()});
        std.debug.print("Min Latency: {d:.3} ms\n", .{@as(f64, @floatFromInt(self.core_latency_ns)) / 1_000_000.0});
        std.debug.print("Max Latency: {d:.3} ms\n", .{@as(f64, @floatFromInt(self.max_latency_ns)) / 1_000_000.0});
        std.debug.print("Operations/Second: {d:.0}\n", .{self.operationsPerSecond()});
        std.debug.print("Memory Peak: {d:.2} MB\n", .{@as(f64, @floatFromInt(self.memory_peak_bytes)) / 1_048_576.0});
        std.debug.print("=====================================\n", .{});
    }
};

/// Memory tracking allocator wrapper
const MemoryTracker = struct {
    child_allocator: std.mem.Allocator,
    current_bytes: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    peak_bytes: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    const Self = @This();

    pub fn init(child_allocator: std.mem.Allocator) Self {
        return Self{
            .child_allocator = child_allocator,
        };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.rawAlloc(len, log2_ptr_align, ret_addr);
        if (result) |ptr| {
            const current = self.current_bytes.fetchAdd(len, .monotonic) + len;
            _ = self.peak_bytes.fetchMax(current, .monotonic);
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (self.child_allocator.rawResize(buf, log2_buf_align, new_len, ret_addr)) {
            const old_len = buf.len;
            if (new_len > old_len) {
                const current = self.current_bytes.fetchAdd(new_len - old_len, .monotonic) + (new_len - old_len);
                _ = self.peak_bytes.fetchMax(current, .monotonic);
            } else {
                _ = self.current_bytes.fetchSub(old_len - new_len, .monotonic);
            }
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.child_allocator.rawFree(buf, log2_buf_align, ret_addr);
        _ = self.current_bytes.fetchSub(buf.len, .monotonic);
    }

    pub fn getCurrentBytes(self: *Self) u64 {
        return self.current_bytes.load(.monotonic);
    }

    pub fn getPeakBytes(self: *Self) u64 {
        return self.peak_bytes.load(.monotonic);
    }
};

test "Protocol serialization performance" {
    var memory_tracker = MemoryTracker.init(testing.allocator);
    const allocator = memory_tracker.allocator();

    var metrics = PerformanceMetrics{};
    const iterations = 10000;

    const test_request = citadel_protocol.Request{
        .doc_update = .{
            .uri = "file:///performance_test.jan",
            .content = "func fibonacci(n: i32) -> i32 { if (n <= 1) return n; return fibonacci(n-1) + fibonacci(n-2); }",
            .version = 1,
        },
    };

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const start_time = compat_time.nanoTimestamp();

        // Serialize
        const serialized = try citadel_protocol.serializeRequest(allocator, test_request);
        defer allocator.free(serialized);

        // Deserialize
        const deserialized = try citadel_protocol.deserializeRequest(allocator, serialized);
        defer citadel_protocol.freeRequest(allocator, deserialized);

        const end_time = compat_time.nanoTimestamp();
        metrics.recordOperation(@intCast(end_time - start_time));
    }

    metrics.memory_peak_bytes = memory_tracker.getPeakBytes();
    metrics.memory_current_bytes = memory_tracker.getCurrentBytes();
    metrics.printReport("Protocol Serialization");

    // Verify performance requirements
    try testing.expect(metrics.averageLatencyMs() < 1.0); // < 1ms per operation
    try testing.expect(metrics.operationsPerSecond() > 1000); // > 1000 ops/sec
}

test "Large document performance" {
    var memory_tracker = MemoryTracker.init(testing.allocator);
    const allocator = memory_tracker.allocator();

    var metrics = PerformanceMetrics{};
    const document_sizes = [_]usize{ 1024, 10240, 102400, 1048576 }; // 1KB to 1MB

    for (document_sizes) |size| {
        const large_content = try allocator.alloc(u8, size);
        defer allocator.free(large_content);
        @memset(large_content, 'A');

        const test_request = citadel_protocol.Request{
            .doc_update = .{
                .uri = "file:///large_document.jan",
                .content = large_content,
                .version = 1,
            },
        };

        const iterations = 100;
        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            const start_time = compat_time.nanoTimestamp();

            const serialized = try citadel_protocol.serializeRequest(allocator, test_request);
            defer allocator.free(serialized);

            const deserialized = try citadel_protocol.deserializeRequest(allocator, serialized);
            defer citadel_protocol.freeRequest(allocator, deserialized);

            const end_time = compat_time.nanoTimestamp();
            metrics.recordOperation(@intCast(end_time - start_time));
        }

        std.debug.print("Document size: {} bytes, Avg latency: {d:.3} ms\n", .{ size, metrics.averageLatencyMs() });
    }

    metrics.memory_peak_bytes = memory_tracker.getPeakBytes();
    metrics.printReport("Large Document Handling");

    // Large documents should still be processed reasonably fast
    try testing.expect(metrics.averageLatencyMs() < 10.0); // < 10ms even for large docs
}

test "Concurrent protocol performance" {
    var memory_tracker = MemoryTracker.init(testing.allocator);
    const allocator = memory_tracker.allocator();

    const ThreadMetrics = struct {
        metrics: PerformanceMetrics = .{},
        thread_id: u32,
        allocator: std.mem.Allocator,
        success: bool = false,
    };

    const worker_fn = struct {
        fn run(context: *ThreadMetrics) void {
            const iterations = 1000;
            const test_request = citadel_protocol.Request{
                .hover_at = .{
                    .uri = "file:///concurrent_test.jan",
                    .line = context.thread_id,
                    .column = context.thread_id * 2,
                },
            };

            var i: u32 = 0;
            while (i < iterations) : (i += 1) {
                const start_time = compat_time.nanoTimestamp();

                const serialized = citadel_protocol.serializeRequest(context.allocator, test_request) catch return;
                defer context.allocator.free(serialized);

                const deserialized = citadel_protocol.deserializeRequest(context.allocator, serialized) catch return;
                defer citadel_protocol.freeRequest(context.allocator, deserialized);

                const end_time = compat_time.nanoTimestamp();
                context.metrics.recordOperation(@intCast(end_time - start_time));
            }

            context.success = true;
        }
    }.run;

    const num_threads = 4;
    var thread_metrics: [num_threads]ThreadMetrics = undefined;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        thread_metrics[i] = ThreadMetrics{
            .thread_id = @intCast(i),
            .allocator = allocator,
        };
        threads[i] = try std.Thread.spawn(.{}, worker_fn, .{&thread_metrics[i]});
    }

    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }

    // Aggregate metrics
    var total_metrics = PerformanceMetrics{};
    for (thread_metrics) |tm| {
        try testing.expect(tm.success);
        total_metrics.total_operations += tm.metrics.total_operations;
        total_metrics.total_duration_ns += tm.metrics.total_duration_ns;
        total_metrics.core_latency_ns = @min(total_metrics.core_latency_ns, tm.metrics.core_latency_ns);
        total_metrics.max_latency_ns = @max(total_metrics.max_latency_ns, tm.metrics.max_latency_ns);
    }

    total_metrics.memory_peak_bytes = memory_tracker.getPeakBytes();
    total_metrics.printReport("Concurrent Protocol Operations");

    // Concurrent operations should maintain good performance
    try testing.expect(total_metrics.averageLatencyMs() < 2.0); // < 2ms average under concurrency
    try testing.expect(total_metrics.operationsPerSecond() > 500); // > 500 ops/sec total
}

test "Memory usage stability" {
    var memory_tracker = MemoryTracker.init(testing.allocator);
    const allocator = memory_tracker.allocator();

    const iterations = 5000;
    var memory_samples: [100]u64 = undefined;
    var sample_count: usize = 0;

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const test_request = citadel_protocol.Request{
            .doc_update = .{
                .uri = "file:///stability_test.jan",
                .content = "func test() { let x = 42; return x + 1; }",
                .version = i,
            },
        };

        const serialized = try citadel_protocol.serializeRequest(allocator, test_request);
        defer allocator.free(serialized);

        const deserialized = try citadel_protocol.deserializeRequest(allocator, serialized);
        defer citadel_protocol.freeRequest(allocator, deserialized);

        // Sample memory usage periodically
        if (i % (iterations / 100) == 0 and sample_count < memory_samples.len) {
            memory_samples[sample_count] = memory_tracker.getCurrentBytes();
            sample_count += 1;
        }
    }

    // Analyze memory stability
    var min_memory = memory_samples[0];
    var max_memory = memory_samples[0];
    var total_memory: u64 = 0;

    for (memory_samples[0..sample_count]) |sample| {
        min_memory = @min(min_memory, sample);
        max_memory = @max(max_memory, sample);
        total_memory += sample;
    }

    const avg_memory = total_memory / sample_count;
    const memory_variance = @as(f64, @floatFromInt(max_memory - min_memory)) / @as(f64, @floatFromInt(avg_memory));

    std.debug.print("\n=== Memory Stability Analysis ===\n", .{});
    std.debug.print("Samples: {}\n", .{sample_count});
    std.debug.print("Min Memory: {d:.2} MB\n", .{@as(f64, @floatFromInt(min_memory)) / 1_048_576.0});
    std.debug.print("Max Memory: {d:.2} MB\n", .{@as(f64, @floatFromInt(max_memory)) / 1_048_576.0});
    std.debug.print("Avg Memory: {d:.2} MB\n", .{@as(f64, @floatFromInt(avg_memory)) / 1_048_576.0});
    std.debug.print("Peak Memory: {d:.2} MB\n", .{@as(f64, @floatFromInt(memory_tracker.getPeakBytes())) / 1_048_576.0});
    std.debug.print("Memory Variance: {d:.2}%\n", .{memory_variance * 100.0});
    std.debug.print("================================\n");

    // Memory should be stable (low variance)
    try testing.expect(memory_variance < 0.5); // Less than 50% variance
    try testing.expect(memory_tracker.getCurrentBytes() < 10 * 1024 * 1024); // Less than 10MB current
}

test "Performance baseline validation" {
    var memory_tracker = MemoryTracker.init(testing.allocator);
    const allocator = memory_tracker.allocator();

    const TestCase = struct {
        name: []const u8,
        request: citadel_protocol.Request,
        max_latency_ms: f64,
        min_ops_per_sec: f64,
    };

    const test_cases = [_]TestCase{
        .{
            .name = "DocUpdate",
            .request = .{
                .doc_update = .{
                    .uri = "file:///baseline.jan",
                    .content = "func main() { print(\"Hello\"); }",
                    .version = 1,
                },
            },
            .max_latency_ms = 0.5,
            .core_ops_per_sec = 2000,
        },
        .{
            .name = "HoverAt",
            .request = .{
                .hover_at = .{
                    .uri = "file:///baseline.jan",
                    .line = 1,
                    .column = 5,
                },
            },
            .max_latency_ms = 0.1,
            .core_ops_per_sec = 10000,
        },
        .{
            .name = "DefinitionAt",
            .request = .{
                .definition_at = .{
                    .uri = "file:///baseline.jan",
                    .line = 1,
                    .column = 5,
                },
            },
            .max_latency_ms = 0.1,
            .core_ops_per_sec = 10000,
        },
        .{
            .name = "ReferencesAt",
            .request = .{
                .references_at = .{
                    .uri = "file:///baseline.jan",
                    .line = 1,
                    .column = 5,
                },
            },
            .max_latency_ms = 0.2,
            .core_ops_per_sec = 5000,
        },
    };

    for (test_cases) |test_case| {
        var metrics = PerformanceMetrics{};
        const iterations = 1000;

        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            const start_time = compat_time.nanoTimestamp();

            const serialized = try citadel_protocol.serializeRequest(allocator, test_case.request);
            defer allocator.free(serialized);

            const deserialized = try citadel_protocol.deserializeRequest(allocator, serialized);
            defer citadel_protocol.freeRequest(allocator, deserialized);

            const end_time = compat_time.nanoTimestamp();
            metrics.recordOperation(@intCast(end_time - start_time));
        }

        metrics.printReport(test_case.name);

        // Validate against baseline requirements
        try testing.expect(metrics.averageLatencyMs() <= test_case.max_latency_ms);
        try testing.expect(metrics.operationsPerSecond() >= test_case.core_ops_per_sec);

        std.debug.print("✅ {s}: PASSED baseline requirements\n", .{test_case.name});
    }
}

test "Resource cleanup validation" {
    var memory_tracker = MemoryTracker.init(testing.allocator);
    const allocator = memory_tracker.allocator();

    const initial_memory = memory_tracker.getCurrentBytes();

    // Perform many operations that should not leak
    const iterations = 1000;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const test_request = citadel_protocol.Request{
            .doc_update = .{
                .uri = "file:///cleanup_test.jan",
                .content = "func cleanup_test() { return 42; }",
                .version = i,
            },
        };

        const serialized = try citadel_protocol.serializeRequest(allocator, test_request);
        defer allocator.free(serialized);

        const deserialized = try citadel_protocol.deserializeRequest(allocator, serialized);
        defer citadel_protocol.freeRequest(allocator, deserialized);

        // Create and destroy response
        const test_response = citadel_protocol.Response{
            .success = .{
                .hover_info = .{
                    .content = "Test hover info",
                    .range = .{
                        .start_line = 1,
                        .start_column = 1,
                        .end_line = 1,
                        .end_column = 10,
                    },
                },
            },
        };

        const response_serialized = try citadel_protocol.serializeResponse(allocator, test_response);
        defer allocator.free(response_serialized);

        const response_deserialized = try citadel_protocol.deserializeResponse(allocator, response_serialized);
        defer citadel_protocol.freeResponse(allocator, response_deserialized);
    }

    const final_memory = memory_tracker.getCurrentBytes();
    const peak_memory = memory_tracker.getPeakBytes();

    std.debug.print("\n=== Resource Cleanup Analysis ===\n", .{});
    std.debug.print("Initial Memory: {} bytes\n", .{initial_memory});
    std.debug.print("Final Memory: {} bytes\n", .{final_memory});
    std.debug.print("Peak Memory: {d:.2} MB\n", .{@as(f64, @floatFromInt(peak_memory)) / 1_048_576.0});
    std.debug.print("Memory Difference: {} bytes\n", .{final_memory - initial_memory});
    std.debug.print("=================================\n");

    // Should have no significant memory leaks
    try testing.expect(final_memory <= initial_memory + 1024); // Allow small overhead
    try testing.expect(peak_memory < 50 * 1024 * 1024); // Peak should be reasonable
}

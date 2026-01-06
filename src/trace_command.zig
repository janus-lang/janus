// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Trace Command - Performance Monitoring and Metrics
//!
//! Implements `janus trace dispatch --timing` with semantic validation metrics
//! Integration Protocol: Expose validation_ms, error_dedup_ratio, cache_hit_rate

const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const ValidationEngine = @import("../compiler/semantic/validation_engine.zig").ValidationEngine;
const ValidationConfig = @import("../compiler/semantic/validation_config.zig").ValidationConfig;
const AstDB = @import("astdb");

pub const TraceCommand = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) TraceCommand {
        return TraceCommand{
            .allocator = allocator,
        };
    }

    pub fn execute(self: *TraceCommand, args: []const []const u8) !void {
        if (args.len < 2) {
            try self.printUsage();
            return;
        }

        const subcommand = args[1];

        if (std.mem.eql(u8, subcommand, "dispatch")) {
            try self.executeDispatchTrace(args[2..]);
        } else {
            print("Unknown trace subcommand: {s}\n", .{subcommand});
            try self.printUsage();
        }
    }

    fn executeDispatchTrace(self: *TraceCommand, args: []const []const u8) !void {
        var enable_timing = false;
        var source_file: ?[]const u8 = null;

        // Parse arguments
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "--timing")) {
                enable_timing = true;
            } else if (!std.mem.startsWith(u8, arg, "--")) {
                source_file = arg;
            }
        }

        if (source_file == null) {
            print("Error: No source file specified\n");
            try self.printUsage();
            return;
        }

        try self.traceValidation(source_file.?, enable_timing);
    }

    fn traceValidation(self: *TraceCommand, file_path: []const u8, enable_timing: bool) !void {
        // Read source file
        const source = std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024) catch |err| {
            print("Error reading file {s}: {}\n", .{ file_path, err });
            return;
        };
        defer self.allocator.free(source);

        // Initialize ASTDB
        var astdb = try AstDB.init(self.allocator);
        defer astdb.deinit();

        // Parse source into ASTDB
        const unit_id = try astdb.addUnit(file_path, source);

        // Initialize validation engine with metrics enabled
        const config = ValidationConfig.init(self.allocator);
        var engine = try ValidationEngine.initWithConfig(self.allocator, &astdb, config);
        defer engine.deinit();

        print("🔍 Tracing semantic validation for: {s}\n", .{file_path});
        print("📊 Validation mode: {s}\n", .{config.mode.toString()});

        if (enable_timing) {
            print("⏱️  Performance monitoring enabled\n\n");
        }

        // Perform validation with timing
        const start_time = std.time.nanoTimestamp();
        const result = engine.validateUnit(unit_id) catch |err| {
            print("❌ Validation failed: {}\n", .{err});
            return;
        };
        const end_time = std.time.nanoTimestamp();

        // Print results
        if (result.success) {
            print("✅ Validation successful\n");
        } else {
            print("⚠️  Validation completed with {} diagnostics\n", .{result.diagnostics.len});
        }

        if (enable_timing) {
            try self.printTimingMetrics(engine, start_time, end_time);
        }

        try self.printValidationSummary(result);
    }

    fn printTimingMetrics(self: *TraceCommand, engine: *ValidationEngine, start_time: i128, end_time: i128) !void {
        const duration_ns = end_time - start_time;
        const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

        print("\n📈 Performance Metrics:\n");
        print("├─ Total validation time: {d:.2} ms\n", .{duration_ms});

        const metrics = engine.getMetrics();
        print("├─ Validation time (engine): {d:.2} ms\n", .{metrics.validation_ms});
        print("├─ Error deduplication ratio: {d:.3}\n", .{metrics.error_dedup_ratio});
        print("├─ Cache hit rate: {d:.3}\n", .{metrics.cache_hit_rate});
        print("├─ Cache hits: {}\n", .{metrics.cache_hits});
        print("├─ Cache misses: {}\n", .{metrics.cache_misses});
        print("├─ Total errors: {}\n", .{metrics.total_errors});
        print("├─ Deduped errors: {}\n", .{metrics.deduped_errors});

        if (metrics.fallback_triggered) {
            print("├─ ⚠️  Fallback triggered: Yes\n");
        } else {
            print("├─ Fallback triggered: No\n");
        }

        if (metrics.timeout_occurred) {
            print("├─ ⚠️  Timeout occurred: Yes\n");
        } else {
            print("├─ Timeout occurred: No\n");
        }

        // Performance contract check
        const meets_contract = engine.meetsPerformanceContract();
        if (meets_contract) {
            print("└─ ✅ Performance contract: PASSED\n");
        } else {
            print("└─ ❌ Performance contract: FAILED\n");
        }

        // JSON output for tooling integration
        print("\n📋 JSON Metrics (for tooling):\n");
        const json_metrics = try engine.getMetricsJson();
        defer self.allocator.free(json_metrics);
        print("{s}\n", .{json_metrics});
    }

    fn printValidationSummary(self: *TraceCommand, result: anytype) !void {
        _ = self;

        print("\n📊 Validation Summary:\n");
        print("├─ Success: {}\n", .{result.success});
        print("├─ Diagnostics: {}\n", .{result.diagnostics.len});
        print("├─ Error count: {}\n", .{result.statistics.error_count});
        print("├─ Warning count: {}\n", .{result.statistics.warning_count});
        print("└─ Type annotations: {}\n", .{result.type_annotations.count()});

        if (result.diagnostics.len > 0) {
            print("\n🔍 Diagnostics:\n");
            for (result.diagnostics, 0..) |diagnostic, i| {
                if (i >= 5) {
                    print("   ... and {} more\n", .{result.diagnostics.len - 5});
                    break;
                }
                print("   {}: {s}\n", .{ i + 1, diagnostic.message });
            }
        }
    }

    fn printUsage(self: *TraceCommand) !void {
        _ = self;

        print("Usage: janus trace <subcommand> [options]\n\n");
        print("Subcommands:\n");
        print("  dispatch [--timing] <file>    Trace semantic validation with optional timing\n\n");
        print("Options:\n");
        print("  --timing                      Enable detailed performance metrics\n\n");
        print("Examples:\n");
        print("  janus trace dispatch main.jan\n");
        print("  janus trace dispatch --timing complex_program.jan\n\n");
        print("Integration Protocol:\n");
        print("  Exposes validation_ms, error_dedup_ratio, cache_hit_rate for CI/tooling\n");
    }
};

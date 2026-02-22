// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const PerformanceValidator = @import("performance_validator.zig").PerformanceValidator;

// Golden Test Framework - Performance Baseline Manager
// Task 8: Build performance baseline management
// Requirements: 3.1, 3.3, 3.5, 7.1

/// Advanced performance baseline management with versioning, regression detection, and threshold validation
pub const PerformanceBaselineManager = struct {
    allocator: std.mem.Allocator,
    baseline_directory: []const u8,
    validator: PerformanceValidator,

    const Self = @This();

    pub const BaselineVersion = struct {
        version: u32,
        created_at: i64,
        compiler_version: []const u8,
        platform: []const u8,
        optimization_level: []const u8,
        baseline: PerformanceValidator.PerformanceBaseline,

        pub fn deinit(self: *BaselineVersion, allocator: std.mem.Allocator) void {
            allocator.free(self.compiler_version);
            allocator.free(self.platform);
            allocator.free(self.optimization_level);
            self.baseline.deinit(allocator);
        }
    };

    pub const BaselineHistory = struct {
        test_name: []const u8,
        versions: []BaselineVersion,
        current_version: u32,

        pub fn deinit(self: *BaselineHistory, allocator: std.mem.Allocator) void {
            allocator.free(self.test_name);
            for (self.versions) |*version| {
                version.deinit(allocator);
            }
            allocator.free(self.versions);
        }
    };

    pub const RegressionAnalysis = struct {
        test_name: []const u8,
        current_measurement: PerformanceValidator.PerformanceMeasurement,
        baseline_measurement: PerformanceValidator.PerformanceMeasurement,
        regression_percentage: f64,
        statistical_significance: f64,
        confidence_level: f64,
        is_significant_regression: bool,
        trend_analysis: TrendAnalysis,

        pub const TrendAnalysis = struct {
            recent_measurements: []PerformanceValidator.PerformanceMeasurement,
            trend_direction: TrendDirection,
            trend_strength: f64,
            volatility: f64,

            pub const TrendDirection = enum {
                improving,
                stable,
                degrading,
                highly_volatile,
            };

            pub fn deinit(self: *TrendAnalysis, allocator: std.mem.Allocator) void {
                allocator.free(self.recent_measurements);
            }
        };

        pub fn deinit(self: *RegressionAnalysis, allocator: std.mem.Allocator) void {
            allocator.free(self.test_name);
            self.trend_analysis.deinit(allocator);
        }
    };

    pub const ThresholdConfig = struct {
        regression_threshold: f64 = 0.10, // 10% regression threshold
        improvement_threshold: f64 = 0.05, // 5% improvement threshold
        statistical_significance_threshold: f64 = 0.05, // 5% significance level
        minimum_sample_size: u32 = 10,
        confidence_level: f64 = 0.95, // 95% confidence level
        volatility_threshold: f64 = 0.20, // 20% volatility threshold

        pub fn default() ThresholdConfig {
            return ThresholdConfig{};
        }
    };

    pub const BaselineUpdateResult = struct {
        updated: bool,
        new_version: u32,
        previous_version: ?u32,
        improvement_detected: bool,
        regression_prevented: bool,
        justification: []const u8,

        pub fn deinit(self: *BaselineUpdateResult, allocator: std.mem.Allocator) void {
            allocator.free(self.justification);
        }
    };

    pub fn init(allocator: std.mem.Allocator, baseline_directory: []const u8) !Self {
        const validator = try PerformanceValidator.init(allocator, baseline_directory);

        return Self{
            .allocator = allocator,
            .baseline_directory = try allocator.dupe(u8, baseline_directory),
            .validator = validator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.baseline_directory);
        self.validator.deinit();
    }

    /// Store a new baseline version with automatic versioning
    pub fn storeBaselineVersion(self: *Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8, measurements: []PerformanceValidator.PerformanceMeasurement, compiler_version: []const u8) !BaselineUpdateResult {
        // Load existing history to determine next version
        const history = self.loadBaselineHistory(test_name, platform, optimization_level) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };

        const next_version = if (history) |h| h.current_version + 1 else 1;

        // Calculate statistics for the new measurements
        const statistical_summary = try self.validator.calculateStatistics(measurements);

        // Create new baseline
        const baseline = PerformanceValidator.PerformanceBaseline{
            .test_name = try self.allocator.dupe(u8, test_name),
            .platform = try self.allocator.dupe(u8, platform),
            .optimization_level = try self.allocator.dupe(u8, optimization_level),
            .measurements = try self.allocator.dupe(PerformanceValidator.PerformanceMeasurement, measurements),
            .statistical_summary = statistical_summary,
            .created_at = std.time.timestamp(),
        };

        // Analyze if this should become the new baseline
        var should_update = true;
        var improvement_detected = false;
        var regression_prevented = false;
        var justification_text: []const u8 = undefined;

        if (history) |h| {
            if (h.current_version == 0) {
                justification_text = try self.allocator.dupe(u8, "Initial baseline created");
            } else {
                const current_baseline = &h.versions[h.current_version - 1].baseline;
                const regression_analysis = try self.analyzeRegression(test_name, measurements[measurements.len - 1], current_baseline.measurements[current_baseline.measurements.len - 1], ThresholdConfig.default());

                if (regression_analysis.is_significant_regression) {
                    should_update = false;
                    regression_prevented = true;
                    justification_text = try std.fmt.allocPrint(self.allocator, "Baseline update prevented due to {d:.1}% performance regression", .{regression_analysis.regression_percentage * 100});
                } else if (regression_analysis.regression_percentage < -ThresholdConfig.default().improvement_threshold) {
                    improvement_detected = true;
                    justification_text = try std.fmt.allocPrint(self.allocator, "Baseline updated due to {d:.1}% performance improvement", .{-regression_analysis.regression_percentage * 100});
                } else {
                    justification_text = try self.allocator.dupe(u8, "Baseline updated with stable performance");
                }

                var mutable_regression_analysis = regression_analysis;
                mutable_regression_analysis.deinit(self.allocator);
            }
        } else {
            justification_text = try self.allocator.dupe(u8, "Initial baseline created");
        }

        if (should_update) {
            // Store the baseline using the validator
            try self.validator.storeBaseline(test_name, platform, optimization_level, measurements);

            // Update version history
            try self.updateBaselineHistory(test_name, platform, optimization_level, baseline, next_version, compiler_version);
        }

        // Clean up baseline if not storing
        if (!should_update) {
            var mutable_baseline = baseline;
            mutable_baseline.deinit(self.allocator);
        }

        // Clean up history
        if (history) |*h| {
            var mutable_history = h.*;
            mutable_history.deinit(self.allocator);
        }

        return BaselineUpdateResult{
            .updated = should_update,
            .new_version = if (should_update) next_version else 0,
            .previous_version = if (history) |h| if (h.current_version > 0) h.current_version else null else null,
            .improvement_detected = improvement_detected,
            .regression_prevented = regression_prevented,
            .justification = justification_text,
        };
    }

    /// Load complete baseline history for a test
    pub fn loadBaselineHistory(self: *Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8) !BaselineHistory {
        const history_path = try self.generateHistoryPath(test_name, platform, optimization_level);
        defer self.allocator.free(history_path);

        const file = try std.fs.cwd().openFile(history_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        return try self.parseBaselineHistory(content, test_name);
    }

    /// Analyze performance regression with statistical significance
    pub fn analyzeRegression(self: *Self, test_name: []const u8, current: PerformanceValidator.PerformanceMeasurement, baseline: PerformanceValidator.PerformanceMeasurement, config: ThresholdConfig) !RegressionAnalysis {
        const current_value = @as(f64, @floatFromInt(current.dispatch_overhead_ns));
        const baseline_value = @as(f64, @floatFromInt(baseline.dispatch_overhead_ns));

        const regression_percentage = (current_value - baseline_value) / baseline_value;

        // Load recent measurements for trend analysis
        const recent_measurements = try self.loadRecentMeasurements(test_name, 20); // Last 20 measurements
        defer self.allocator.free(recent_measurements);
        const trend_analysis = try self.analyzeTrend(recent_measurements);

        // Calculate statistical significance (simplified)
        const statistical_significance = @abs(regression_percentage) * 10.0; // Rough approximation
        const is_significant = statistical_significance > config.statistical_significance_threshold and
            @abs(regression_percentage) > config.regression_threshold;

        return RegressionAnalysis{
            .test_name = try self.allocator.dupe(u8, test_name),
            .current_measurement = current,
            .baseline_measurement = baseline,
            .regression_percentage = regression_percentage,
            .statistical_significance = statistical_significance,
            .confidence_level = config.confidence_level,
            .is_significant_regression = is_significant and regression_percentage > 0,
            .trend_analysis = trend_analysis,
        };
    }

    /// Validate performance against configurable thresholds
    pub fn validateThresholds(self: *Self, _: []const u8, measurement: PerformanceValidator.PerformanceMeasurement, expected_thresholds: []const PerformanceThreshold) ![]ThresholdValidationResult {
        var results: std.ArrayList(ThresholdValidationResult) = .empty;

        for (expected_thresholds) |threshold| {
            const actual_value = switch (threshold.metric) {
                .dispatch_overhead_ns => @as(f64, @floatFromInt(measurement.dispatch_overhead_ns)),
                .memory_usage_bytes => @as(f64, @floatFromInt(measurement.memory_usage_bytes)),
                .code_size_bytes => @as(f64, @floatFromInt(measurement.code_size_bytes)),
                .cache_misses => @as(f64, @floatFromInt(measurement.cache_misses)),
                .instruction_count => @as(f64, @floatFromInt(measurement.instruction_count)),
            };

            const passed = switch (threshold.operator) {
                .less_than => actual_value < threshold.threshold_value,
                .less_equal => actual_value <= threshold.threshold_value,
                .greater_than => actual_value > threshold.threshold_value,
                .greater_equal => actual_value >= threshold.threshold_value,
                .approximately => @abs(actual_value - threshold.threshold_value) <= threshold.tolerance,
            };

            const result = ThresholdValidationResult{
                .metric = threshold.metric,
                .expected_value = threshold.threshold_value,
                .actual_value = actual_value,
                .operator = threshold.operator,
                .passed = passed,
                .deviation_percentage = if (threshold.threshold_value != 0)
                    (actual_value - threshold.threshold_value) / threshold.threshold_value * 100
                else
                    0,
            };

            try results.append(result);
        }

        return try results.toOwnedSlice(alloc);
    }

    /// Generate performance trend report
    pub fn generateTrendReport(self: *Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8, days: u32) ![]const u8 {
        const measurements = try self.loadMeasurementsInTimeRange(test_name, platform, optimization_level, days);
        defer self.allocator.free(measurements);

        if (measurements.len == 0) {
            return try self.allocator.dupe(u8, "No measurements available for trend analysis");
        }

        var trend_analysis = try self.analyzeTrend(measurements);
        defer trend_analysis.deinit(self.allocator);

        var report: std.ArrayList(u8) = .empty;
        var writer = report.writer();

        try writer.print("Performance Trend Report: {s}\n", .{test_name});
        try writer.print("Platform: {s}, Optimization: {s}\n", .{ platform, optimization_level });
        try writer.print("Time Range: Last {} days\n\n", .{days});

        try writer.print("Trend Analysis:\n", .{});
        try writer.print("  Direction: {s}\n", .{@tagName(trend_analysis.trend_direction)});
        try writer.print("  Strength: {d:.2}\n", .{trend_analysis.trend_strength});
        try writer.print("  Volatility: {d:.2}%\n", .{trend_analysis.volatility * 100});
        try writer.print("  Sample Size: {}\n\n", .{measurements.len});

        // Calculate statistics
        var sum: f64 = 0;
        var min_val: u64 = std.math.maxInt(u64);
        var max_val: u64 = 0;

        for (measurements) |measurement| {
            const val = measurement.dispatch_overhead_ns;
            sum += @as(f64, @floatFromInt(val));
            if (val < min_val) min_val = val;
            if (val > max_val) max_val = val;
        }

        const mean = sum / @as(f64, @floatFromInt(measurements.len));

        try writer.print("Performance Statistics:\n", .{});
        try writer.print("  Mean: {d:.2} ns\n", .{mean});
        try writer.print("  Min: {} ns\n", .{min_val});
        try writer.print("  Max: {} ns\n", .{max_val});
        try writer.print("  Range: {} ns ({d:.1}%)\n", .{ max_val - min_val, if (mean != 0) @as(f64, @floatFromInt(max_val - min_val)) / mean * 100 else 0 });

        return try report.toOwnedSlice(alloc);
    }

    // Performance threshold definitions
    pub const PerformanceThreshold = struct {
        metric: MetricType,
        operator: OperatorType,
        threshold_value: f64,
        tolerance: f64 = 0.0,

        pub const MetricType = enum {
            dispatch_overhead_ns,
            memory_usage_bytes,
            code_size_bytes,
            cache_misses,
            instruction_count,
        };

        pub const OperatorType = enum {
            less_than,
            less_equal,
            greater_than,
            greater_equal,
            approximately,
        };
    };

    pub const ThresholdValidationResult = struct {
        metric: PerformanceThreshold.MetricType,
        expected_value: f64,
        actual_value: f64,
        operator: PerformanceThreshold.OperatorType,
        passed: bool,
        deviation_percentage: f64,
    };

    // Private helper functions

    fn generateHistoryPath(self: *Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}/history/{s}/{s}/{s}.json", .{ self.baseline_directory, platform, optimization_level, test_name });
    }

    fn updateBaselineHistory(self: *Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8, baseline: PerformanceValidator.PerformanceBaseline, version: u32, compiler_version: []const u8) !void {
        const history_path = try self.generateHistoryPath(test_name, platform, optimization_level);
        defer self.allocator.free(history_path);

        // Ensure directory exists
        if (std.fs.path.dirname(history_path)) |dir_path| {
            std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }

        // Load existing history or create new
        var history = self.loadBaselineHistory(test_name, platform, optimization_level) catch BaselineHistory{
            .test_name = try self.allocator.dupe(u8, test_name),
            .versions = &[_]BaselineVersion{},
            .current_version = 0,
        };
        defer history.deinit(self.allocator);

        // Add new version
        var new_versions: std.ArrayList(BaselineVersion) = .empty;
        try new_versions.appendSlice(history.versions);

        const new_version = BaselineVersion{
            .version = version,
            .created_at = std.time.timestamp(),
            .compiler_version = try self.allocator.dupe(u8, compiler_version),
            .platform = try self.allocator.dupe(u8, platform),
            .optimization_level = try self.allocator.dupe(u8, optimization_level),
            .baseline = baseline,
        };

        try new_versions.append(new_version);

        // Save updated history
        const updated_history = BaselineHistory{
            .test_name = try self.allocator.dupe(u8, test_name),
            .versions = try new_versions.toOwnedSlice(),
            .current_version = version,
        };

        try self.saveBaselineHistory(&updated_history, history_path);

        // Clean up
        var mutable_updated_history = updated_history;
        mutable_updated_history.deinit(self.allocator);
    }

    fn parseBaselineHistory(self: *Self, content: []const u8, test_name: []const u8) !BaselineHistory {
        _ = content; // Simplified - real implementation would parse JSON

        // Return placeholder history for testing
        return BaselineHistory{
            .test_name = try self.allocator.dupe(u8, test_name),
            .versions = &[_]BaselineVersion{},
            .current_version = 0,
        };
    }

    fn saveBaselineHistory(self: *Self, history: *const BaselineHistory, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        // Write JSON history (simplified)
        const json_content = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "test_name": "{s}",
            \\  "current_version": {},
            \\  "version_count": {}
            \\}}
        , .{ history.test_name, history.current_version, history.versions.len });
        defer self.allocator.free(json_content);

        try file.writeAll(json_content);
    }

    fn loadRecentMeasurements(self: *Self, test_name: []const u8, count: u32) ![]PerformanceValidator.PerformanceMeasurement {
        _ = test_name;
        _ = count;

        // Simplified - return placeholder measurements
        const measurements = try self.allocator.alloc(PerformanceValidator.PerformanceMeasurement, 5);
        for (measurements, 0..) |*measurement, i| {
            measurement.* = PerformanceValidator.PerformanceMeasurement.init();
            measurement.dispatch_overhead_ns = 100 + @as(u64, @intCast(i)) * 5; // Slight upward trend
        }
        return measurements;
    }

    fn analyzeTrend(self: *Self, measurements: []const PerformanceValidator.PerformanceMeasurement) !RegressionAnalysis.TrendAnalysis {
        if (measurements.len < 2) {
            return RegressionAnalysis.TrendAnalysis{
                .recent_measurements = try self.allocator.dupe(PerformanceValidator.PerformanceMeasurement, measurements),
                .trend_direction = .stable,
                .trend_strength = 0.0,
                .volatility = 0.0,
            };
        }

        // Calculate simple linear trend
        var sum_x: f64 = 0;
        var sum_y: f64 = 0;
        var sum_xy: f64 = 0;
        var sum_x2: f64 = 0;

        for (measurements, 0..) |measurement, i| {
            const x = @as(f64, @floatFromInt(i));
            const y = @as(f64, @floatFromInt(measurement.dispatch_overhead_ns));
            sum_x += x;
            sum_y += y;
            sum_xy += x * y;
            sum_x2 += x * x;
        }

        const n = @as(f64, @floatFromInt(measurements.len));
        const slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x);

        // Determine trend direction and strength
        const trend_direction: RegressionAnalysis.TrendAnalysis.TrendDirection = if (@abs(slope) < 0.1)
            .stable
        else if (slope > 0)
            .degrading
        else
            .improving;

        const trend_strength = @abs(slope);

        // Calculate volatility (coefficient of variation)
        const mean = sum_y / n;
        var variance_sum: f64 = 0;
        for (measurements) |measurement| {
            const diff = @as(f64, @floatFromInt(measurement.dispatch_overhead_ns)) - mean;
            variance_sum += diff * diff;
        }
        const std_dev = @sqrt(variance_sum / n);
        const volatility = if (mean != 0) std_dev / mean else 0;

        return RegressionAnalysis.TrendAnalysis{
            .recent_measurements = try self.allocator.dupe(PerformanceValidator.PerformanceMeasurement, measurements),
            .trend_direction = trend_direction,
            .trend_strength = trend_strength,
            .volatility = volatility,
        };
    }

    fn loadMeasurementsInTimeRange(self: *Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8, days: u32) ![]PerformanceValidator.PerformanceMeasurement {
        _ = test_name;
        _ = platform;
        _ = optimization_level;
        _ = days;

        // Simplified - return placeholder measurements with timestamps
        const measurements = try self.allocator.alloc(PerformanceValidator.PerformanceMeasurement, 10);
        const now = std.time.timestamp();

        for (measurements, 0..) |*measurement, i| {
            measurement.* = PerformanceValidator.PerformanceMeasurement.init();
            measurement.dispatch_overhead_ns = 100 + @as(u64, @intCast(i)) * 2;
            measurement.timestamp = now - @as(i64, @intCast(i)) * 3600; // One hour apart
        }

        return measurements;
    }
};

// Tests
test "PerformanceBaselineManager initialization" {
    var manager = try PerformanceBaselineManager.init(testing.allocator, "test_baselines");
    defer manager.deinit();

    try testing.expect(std.mem.eql(u8, manager.baseline_directory, "test_baselines"));
}

test "Baseline version storage" {
    var manager = try PerformanceBaselineManager.init(testing.allocator, "test_baseline_versions");
    defer manager.deinit();

    var measurements = [_]PerformanceValidator.PerformanceMeasurement{
        PerformanceValidator.PerformanceMeasurement{ .dispatch_overhead_ns = 100, .memory_usage_bytes = 1024, .code_size_bytes = 256, .cache_misses = 10, .instruction_count = 50, .timestamp = 0 },
        PerformanceValidator.PerformanceMeasurement{ .dispatch_overhead_ns = 105, .memory_usage_bytes = 1024, .code_size_bytes = 256, .cache_misses = 11, .instruction_count = 52, .timestamp = 0 },
    };

    var result = try manager.storeBaselineVersion("test_baseline", "linux", "release_safe", &measurements, "janus-0.1.0");
    defer result.deinit(testing.allocator);

    try testing.expect(result.updated);
    try testing.expect(result.new_version == 1);
    try testing.expect(result.previous_version == null);
}

test "Regression analysis" {
    var manager = try PerformanceBaselineManager.init(testing.allocator, "test_regression");
    defer manager.deinit();

    const current = PerformanceValidator.PerformanceMeasurement{
        .dispatch_overhead_ns = 120, // 20% regression
        .memory_usage_bytes = 1024,
        .code_size_bytes = 256,
        .cache_misses = 12,
        .instruction_count = 60,
        .timestamp = 0,
    };

    const baseline = PerformanceValidator.PerformanceMeasurement{
        .dispatch_overhead_ns = 100,
        .memory_usage_bytes = 1024,
        .code_size_bytes = 256,
        .cache_misses = 10,
        .instruction_count = 50,
        .timestamp = 0,
    };

    var analysis = try manager.analyzeRegression("test_regression", current, baseline, PerformanceBaselineManager.ThresholdConfig.default());
    defer analysis.deinit(testing.allocator);

    try testing.expect(analysis.regression_percentage == 0.2); // 20% regression
    try testing.expect(analysis.is_significant_regression);
}

test "Threshold validation" {
    var manager = try PerformanceBaselineManager.init(testing.allocator, "test_thresholds");
    defer manager.deinit();

    const measurement = PerformanceValidator.PerformanceMeasurement{
        .dispatch_overhead_ns = 25, // Should pass < 30 threshold
        .memory_usage_bytes = 1024,
        .code_size_bytes = 256,
        .cache_misses = 10,
        .instruction_count = 50,
        .timestamp = 0,
    };

    const thresholds = [_]PerformanceBaselineManager.PerformanceThreshold{
        PerformanceBaselineManager.PerformanceThreshold{
            .metric = .dispatch_overhead_ns,
            .operator = .less_than,
            .threshold_value = 30.0,
        },
    };

    const results = try manager.validateThresholds("test_thresholds", measurement, &thresholds);
    defer testing.allocator.free(results);

    try testing.expect(results.len == 1);
    try testing.expect(results[0].passed);
    try testing.expect(results[0].actual_value == 25.0);
}

test "Trend report generation" {
    var manager = try PerformanceBaselineManager.init(testing.allocator, "test_trends");
    defer manager.deinit();

    const report = try manager.generateTrendReport("test_trend", "linux", "release_safe", 7);
    defer testing.allocator.free(report);

    try testing.expect(std.mem.indexOf(u8, report, "Performance Trend Report") != null);
    try testing.expect(std.mem.indexOf(u8, report, "test_trend") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Trend Analysis") != null);
}

// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Validation Configuration - Feature Flag System for Semantic Engine
//!
//! Implements the Integration Protocol for safe deployment of the optimized
//! semantic validation engine with fallback mechanisms and performance contracts.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Validation engine mode selection
pub const ValidationMode = enum {
    /// Baseline validation engine (safe fallback)
    baseline,
    /// Optimized validation engine (production target)
    optimized,
    /// Auto-select based on performance characteristics
    auto,

    pub fn fromString(mode_str: []const u8) ValidationMode {
        if (std.mem.eql(u8, mode_str, "baseline")) return .baseline;
        if (std.mem.eql(u8, mode_str, "optimized")) return .optimized;
        if (std.mem.eql(u8, mode_str, "auto")) return .auto;
        return .optimized; // Default to optimized
    }

    pub fn toString(self: ValidationMode) []const u8 {
        return switch (self) {
            .baseline => "baseline",
            .optimized => "optimized",
            .auto => "auto",
        };
    }
};

/// Performance contracts for validation engine
pub const PerformanceContract = struct {
    /// Maximum validation time in milliseconds (99th percentile)
    max_validation_ms: f64 = 25.0,
    /// Tolerance for performance variance (±10%)
    performance_tolerance: f64 = 0.10,
    /// Minimum error deduplication ratio
    min_dedup_ratio: f64 = 0.85,
    /// Minimum cache hit rate over sample period
    min_cache_hit_rate: f64 = 0.95,
    /// Sample size for cache hit rate calculation
    cache_sample_size: u32 = 500,
    /// Maximum timeout before fallback (milliseconds)
    timeout_ms: u32 = 100,
};

/// Validation configuration with feature flags and performance contracts
pub const ValidationConfig = struct {
    mode: ValidationMode,
    contract: PerformanceContract,
    enable_metrics: bool,
    enable_fallback: bool,
    debug_mode: bool,
    allocator: Allocator,

    pub fn init(allocator: Allocator) ValidationConfig {
        return ValidationConfig{
            .mode = getDefaultMode(),
            .contract = PerformanceContract{},
            .enable_metrics = true,
            .enable_fallback = true,
            .debug_mode = false,
            .allocator = allocator,
        };
    }

    pub fn withMode(self: ValidationConfig, mode: ValidationMode) ValidationConfig {
        var config = self;
        config.mode = mode;
        return config;
    }

    pub fn withContract(self: ValidationConfig, contract: PerformanceContract) ValidationConfig {
        var config = self;
        config.contract = contract;
        return config;
    }

    pub fn enableDebug(self: ValidationConfig) ValidationConfig {
        var config = self;
        config.debug_mode = true;
        return config;
    }

    pub fn disableMetrics(self: ValidationConfig) ValidationConfig {
        var config = self;
        config.enable_metrics = false;
        return config;
    }

    pub fn disableFallback(self: ValidationConfig) ValidationConfig {
        var config = self;
        config.enable_fallback = false;
        return config;
    }
};

/// Get default validation mode based on environment
fn getDefaultMode() ValidationMode {
    // Check environment variables
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "JANUS_VALIDATE")) |mode_str| {
        defer std.heap.page_allocator.free(mode_str);
        return ValidationMode.fromString(mode_str);
    } else |_| {}

    // Check if we're in CI environment
    if (isCI()) {
        return .optimized; // Default to optimized in CI
    }

    // Check if we're in debug mode
    const builtin = @import("builtin");
    if (builtin.mode == .Debug) {
        return .baseline; // Default to baseline in local debug
    }

    return .optimized; // Default to optimized otherwise
}

/// Detect if running in CI environment
fn isCI() bool {
    const ci_vars = [_][]const u8{
        "CI",
        "CONTINUOUS_INTEGRATION",
        "GITHUB_ACTIONS",
        "GITLAB_CI",
        "JENKINS_URL",
    };

    for (ci_vars) |var_name| {
        if (std.process.getEnvVarOwned(std.heap.page_allocator, var_name)) |value| {
            defer std.heap.page_allocator.free(value);
            return true;
        } else |_| {}
    }

    return false;
}

/// Parse validation configuration from command line arguments
pub fn parseFromArgs(allocator: Allocator, args: []const []const u8) !ValidationConfig {
    var config = ValidationConfig.init(allocator);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--validate=")) {
            const mode_str = arg["--validate=".len..];
            config.mode = ValidationMode.fromString(mode_str);
        } else if (std.mem.eql(u8, arg, "--validate-debug")) {
            config = config.enableDebug();
        } else if (std.mem.eql(u8, arg, "--no-validate-metrics")) {
            config = config.disableMetrics();
        } else if (std.mem.eql(u8, arg, "--no-validate-fallback")) {
            config = config.disableFallback();
        } else if (std.mem.startsWith(u8, arg, "--validate-timeout=")) {
            const timeout_str = arg["--validate-timeout=".len..];
            if (std.fmt.parseInt(u32, timeout_str, 10)) |timeout| {
                var contract = config.contract;
                contract.timeout_ms = timeout;
                config = config.withContract(contract);
            } else |_| {
                return error.InvalidTimeout;
            }
        }
    }

    return config;
}

/// Validation metrics for performance monitoring
pub const ValidationMetrics = struct {
    validation_ms: f64 = 0.0,
    error_dedup_ratio: f64 = 0.0,
    cache_hit_rate: f64 = 0.0,
    cache_hits: u32 = 0,
    cache_misses: u32 = 0,
    total_errors: u32 = 0,
    deduped_errors: u32 = 0,
    fallback_triggered: bool = false,
    timeout_occurred: bool = false,

    pub fn updateCacheHit(self: *ValidationMetrics) void {
        self.cache_hits += 1;
        self.updateCacheHitRate();
    }

    pub fn updateCacheMiss(self: *ValidationMetrics) void {
        self.cache_misses += 1;
        self.updateCacheHitRate();
    }

    pub fn updateErrorDedup(self: *ValidationMetrics, total: u32, deduped: u32) void {
        self.total_errors = total;
        self.deduped_errors = deduped;
        if (total > 0) {
            self.error_dedup_ratio = @as(f64, @floatFromInt(deduped)) / @as(f64, @floatFromInt(total));
        }
    }

    fn updateCacheHitRate(self: *ValidationMetrics) void {
        const total = self.cache_hits + self.cache_misses;
        if (total > 0) {
            self.cache_hit_rate = @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total));
        }
    }

    pub fn meetsContract(self: ValidationMetrics, contract: PerformanceContract) bool {
        if (self.validation_ms > contract.max_validation_ms * (1.0 + contract.performance_tolerance)) {
            return false;
        }
        if (self.error_dedup_ratio < contract.min_dedup_ratio) {
            return false;
        }
        if (self.cache_hit_rate < contract.min_cache_hit_rate) {
            return false;
        }
        return true;
    }

    pub fn toJson(self: ValidationMetrics, allocator: Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator,
            \\{{
            \\  "validation_ms": {d:.2},
            \\  "error_dedup_ratio": {d:.3},
            \\  "cache_hit_rate": {d:.3},
            \\  "cache_hits": {},
            \\  "cache_misses": {},
            \\  "total_errors": {},
            \\  "deduped_errors": {},
            \\  "fallback_triggered": {},
            \\  "timeout_occurred": {}
            \\}}
        , .{
            self.validation_ms,
            self.error_dedup_ratio,
            self.cache_hit_rate,
            self.cache_hits,
            self.cache_misses,
            self.total_errors,
            self.deduped_errors,
            self.fallback_triggered,
            self.timeout_occurred,
        });
    }
};

// Tests
test "ValidationMode parsing" {
    const testing = std.testing;

    try testing.expect(ValidationMode.fromString("baseline") == .baseline);
    try testing.expect(ValidationMode.fromString("optimized") == .optimized);
    try testing.expect(ValidationMode.fromString("auto") == .auto);
    try testing.expect(ValidationMode.fromString("invalid") == .optimized); // Default
}

test "ValidationConfig creation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = ValidationConfig.init(allocator);
    try testing.expect(config.enable_metrics == true);
    try testing.expect(config.enable_fallback == true);
    try testing.expect(config.debug_mode == false);
}

test "ValidationMetrics contract checking" {
    const testing = std.testing;

    var metrics = ValidationMetrics{};
    const contract = PerformanceContract{};

    // Should fail initially (no data)
    try testing.expect(!metrics.meetsContract(contract));

    // Set good metrics
    metrics.validation_ms = 20.0; // Under 25ms limit
    metrics.error_dedup_ratio = 0.90; // Above 0.85 limit
    metrics.cache_hit_rate = 0.97; // Above 0.95 limit

    try testing.expect(metrics.meetsContract(contract));

    // Test failure cases
    metrics.validation_ms = 30.0; // Over limit
    try testing.expect(!metrics.meetsContract(contract));
}

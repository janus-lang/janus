// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// CID Comparison and Validation - Core Utilities for Incremental Compilation
// Task 2.2: Implement CID Comparison and Validation
//
// This module provides utilities for comparing current vs cached CIDs,
// integrity verification, logging, diagnostics, and performance benchmarking.

const std = @import("std");
const astdb = @import("../astdb.zig");
const compilation_unit = @import("compilation_unit.zig");
const interface_cid_mod = @import("interface_cid.zig");
const CompilationUnit = compilation_unit.CompilationUnit;
const SemanticCID = compilation_unit.SemanticCID;
const InterfaceCID = interface_cid_mod.InterfaceCID;

// BLAKE3 for integrity verification
const Blake3 = std.crypto.hash.Blake3;

/// CID Comparison Result - detailed result of CID comparison
pub const CIDComparisonResult = struct {
    /// Whether the CIDs are identical
    are_equal: bool,

    /// Type of comparison performed
    comparison_type: ComparisonType,

    /// Detailed comparison information
    details: ComparisonDetails,

    /// Performance metrics for the comparison
    metrics: ComparisonMetrics,
};

pub const ComparisonType = enum {
    interface_cid,
    semantic_cid,
    dependency_cid,
    compilation_unit,
};

pub const ComparisonDetails = union(ComparisonType) {
    interface_cid: InterfaceCIDComparison,
    semantic_cid: SemanticCIDComparison,
    dependency_cid: DependencyCIDComparison,
    compilation_unit: CompilationUnitComparison,
};

pub const InterfaceCIDComparison = struct {
    current_cid: InterfaceCID,
    cached_cid: InterfaceCID,
    hash_difference_count: u32, // Number of differing bytes in hash
};

pub const SemanticCIDComparison = struct {
    current_cid: SemanticCID,
    cached_cid: SemanticCID,
    hash_difference_count: u32,
};

pub const DependencyCIDComparison = struct {
    current_cid: InterfaceCID,
    cached_cid: InterfaceCID,
    dependency_count: u32,
};

pub const CompilationUnitComparison = struct {
    interface_changed: bool,
    implementation_changed: bool,
    dependencies_changed: bool,
    source_file: []const u8,
};

pub const ComparisonMetrics = struct {
    comparison_time_ns: u64,
    memory_used_bytes: u64,
    hash_operations: u32,
};

/// CID Validator - provides comprehensive CID validation and comparison utilities
pub const CIDValidator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CIDValidator {
        return CIDValidator{
            .allocator = allocator,
        };
    }

    /// Compare current vs cached InterfaceCID with detailed analysis
    pub fn compareInterfaceCIDs(
        self: *CIDValidator,
        current_cid: InterfaceCID,
        cached_cid: InterfaceCID,
    ) !CIDComparisonResult {
        const start_time = std.time.nanoTimestamp();

        const are_equal = current_cid.eql(cached_cid);
        const hash_diff_count = self.countHashDifferences(&current_cid.hash, &cached_cid.hash);

        const end_time = std.time.nanoTimestamp();

        return CIDComparisonResult{
            .are_equal = are_equal,
            .comparison_type = .interface_cid,
            .details = ComparisonDetails{
                .interface_cid = InterfaceCIDComparison{
                    .current_cid = current_cid,
                    .cached_cid = cached_cid,
                    .hash_difference_count = hash_diff_count,
                },
            },
            .metrics = ComparisonMetrics{
                .comparison_time_ns = @as(u64, @intCast(end_time - start_time)),
                .memory_used_bytes = 0, // No additional memory used
                .hash_operations = 1,
            },
        };
    }

    /// Compare current vs cached SemanticCID with detailed analysis
    pub fn compareSemanticCIDs(
        self: *CIDValidator,
        current_cid: SemanticCID,
        cached_cid: SemanticCID,
    ) !CIDComparisonResult {
        const start_time = std.time.nanoTimestamp();

        const are_equal = current_cid.eql(cached_cid);
        const hash_diff_count = self.countHashDifferences(&current_cid.hash, &cached_cid.hash);

        const end_time = std.time.nanoTimestamp();

        return CIDComparisonResult{
            .are_equal = are_equal,
            .comparison_type = .semantic_cid,
            .details = ComparisonDetails{
                .semantic_cid = SemanticCIDComparison{
                    .current_cid = current_cid,
                    .cached_cid = cached_cid,
                    .hash_difference_count = hash_diff_count,
                },
            },
            .metrics = ComparisonMetrics{
                .comparison_time_ns = @as(u64, @intCast(end_time - start_time)),
                .memory_used_bytes = 0,
                .hash_operations = 1,
            },
        };
    }

    /// Compare complete compilation units with comprehensive analysis
    pub fn compareCompilationUnits(
        _: *CIDValidator,
        current_unit: *const CompilationUnit,
        cached_unit: *const CompilationUnit,
    ) !CIDComparisonResult {
        const start_time = std.time.nanoTimestamp();

        const interface_changed = current_unit.interfaceChanged(cached_unit.interface_cid);
        const implementation_changed = current_unit.implementationChanged(cached_unit.semantic_cid);
        const dependencies_changed = current_unit.needsRebuild(cached_unit.dependency_cid);

        const are_equal = !interface_changed and !implementation_changed and !dependencies_changed;

        const end_time = std.time.nanoTimestamp();

        return CIDComparisonResult{
            .are_equal = are_equal,
            .comparison_type = .compilation_unit,
            .details = ComparisonDetails{
                .compilation_unit = CompilationUnitComparison{
                    .interface_changed = interface_changed,
                    .implementation_changed = implementation_changed,
                    .dependencies_changed = dependencies_changed,
                    .source_file = current_unit.source_file,
                },
            },
            .metrics = ComparisonMetrics{
                .comparison_time_ns = @as(u64, @intCast(end_time - start_time)),
                .memory_used_bytes = 0,
                .hash_operations = 3, // Three CID comparisons
            },
        };
    }

    /// Verify integrity of a CID using BLAKE3 properties
    pub fn verifyIntegrity(self: *CIDValidator, cid_hash: *const [32]u8) !IntegrityResult {

        // Check for obvious corruption patterns
        var all_zeros = true;
        var all_ones = true;
        var pattern_detected = false;

        for (cid_hash) |byte| {
            if (byte != 0) all_zeros = false;
            if (byte != 0xFF) all_ones = false;
        }

        // Check for simple patterns (like repeating bytes)
        if (cid_hash.len >= 4) {
            const first_four = cid_hash[0..4];
            var pattern_count: u32 = 0;
            var i: usize = 4;
            while (i + 4 <= cid_hash.len) : (i += 4) {
                if (std.mem.eql(u8, first_four, cid_hash[i .. i + 4])) {
                    pattern_count += 1;
                }
            }
            if (pattern_count >= 6) { // More than 6 repeating 4-byte patterns
                pattern_detected = true;
            }
        }

        const is_valid = !all_zeros and !all_ones and !pattern_detected;

        return IntegrityResult{
            .is_valid = is_valid,
            .corruption_indicators = CorruptionIndicators{
                .all_zeros = all_zeros,
                .all_ones = all_ones,
                .pattern_detected = pattern_detected,
                .entropy_score = self.calculateEntropy(cid_hash),
            },
        };
    }

    /// Generate detailed diagnostic information for CID comparison
    pub fn generateDiagnostics(
        self: *CIDValidator,
        comparison_result: *const CIDComparisonResult,
    ) !CIDDiagnostics {
        var diagnostics = CIDDiagnostics{
            .comparison_type = comparison_result.comparison_type,
            .summary = if (comparison_result.are_equal) "CIDs are identical" else "CIDs differ",
            .recommendations = .empty,
            .performance_analysis = PerformanceAnalysis{
                .is_fast = comparison_result.metrics.comparison_time_ns < 1000000, // < 1ms
                .memory_efficient = comparison_result.metrics.memory_used_bytes < 1024,
                .optimization_suggestions = .empty,
            },
        };

        // Generate specific recommendations based on comparison type and results
        switch (comparison_result.details) {
            .interface_cid => |interface_comp| {
                if (!comparison_result.are_equal) {
                    try diagnostics.recommendations.append("Interface has changed - dependent modules need rebuilding");
                    if (interface_comp.hash_difference_count > 16) {
                        try diagnostics.recommendations.append("Major interface changes detected - consider API versioning");
                    }
                } else {
                    try diagnostics.recommendations.append("Interface unchanged - can reuse cached compilation results");
                }
            },
            .semantic_cid => |semantic_comp| {
                if (!comparison_result.are_equal) {
                    try diagnostics.recommendations.append("Implementation has changed - recompilation required");
                    if (semantic_comp.hash_difference_count < 4) {
                        try diagnostics.recommendations.append("Minor implementation changes - likely safe for hot reload");
                    }
                } else {
                    try diagnostics.recommendations.append("Implementation unchanged - can reuse all cached results");
                }
            },
            .compilation_unit => |unit_comp| {
                if (unit_comp.interface_changed) {
                    try diagnostics.recommendations.append("Interface changed - rebuild dependents");
                }
                if (unit_comp.implementation_changed) {
                    try diagnostics.recommendations.append("Implementation changed - recompile this unit");
                }
                if (unit_comp.dependencies_changed) {
                    try diagnostics.recommendations.append("Dependencies changed - rebuild required");
                }
                if (!unit_comp.interface_changed and !unit_comp.implementation_changed and !unit_comp.dependencies_changed) {
                    try diagnostics.recommendations.append("No changes detected - can skip compilation entirely");
                }
            },
            .dependency_cid => {
                if (!comparison_result.are_equal) {
                    try diagnostics.recommendations.append("Dependencies changed - rebuild this compilation unit");
                } else {
                    try diagnostics.recommendations.append("Dependencies unchanged - can reuse cached results");
                }
            },
        }

        // Performance optimization suggestions
        if (!diagnostics.performance_analysis.is_fast) {
            try diagnostics.performance_analysis.optimization_suggestions.append("Consider caching comparison results");
        }

        return diagnostics;
    }

    /// Benchmark CID comparison performance
    pub fn benchmarkComparison(
        _: *CIDValidator,
        iterations: u32,
        cid1: anytype,
        cid2: anytype,
    ) !BenchmarkResult {
        const start_time = std.time.nanoTimestamp();
        var total_operations: u64 = 0;

        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            const result = cid1.eql(cid2);
            _ = result; // Prevent optimization
            total_operations += 1;
        }

        const end_time = std.time.nanoTimestamp();
        const total_time_ns = @as(u64, @intCast(end_time - start_time));

        return BenchmarkResult{
            .iterations = iterations,
            .total_time_ns = total_time_ns,
            .average_time_ns = total_time_ns / iterations,
            .operations_per_second = (total_operations * 1_000_000_000) / total_time_ns,
            .memory_usage_bytes = 0, // CID comparisons don't allocate
        };
    }

    // Helper functions

    fn countHashDifferences(self: *CIDValidator, hash1: *const [32]u8, hash2: *const [32]u8) u32 {
        _ = self;
        var diff_count: u32 = 0;
        for (hash1, hash2) |b1, b2| {
            if (b1 != b2) {
                diff_count += 1;
            }
        }
        return diff_count;
    }

    fn calculateEntropy(self: *CIDValidator, data: *const [32]u8) f64 {
        _ = self;

        // Simple entropy calculation based on byte frequency
        var byte_counts = [_]u32{0} ** 256;
        for (data) |byte| {
            byte_counts[byte] += 1;
        }

        var entropy: f64 = 0.0;
        const total_bytes = @as(f64, @floatFromInt(data.len));

        for (byte_counts) |count| {
            if (count > 0) {
                const probability = @as(f64, @floatFromInt(count)) / total_bytes;
                entropy -= probability * std.math.log2(probability);
            }
        }

        return entropy;
    }
};

/// Integrity verification result
pub const IntegrityResult = struct {
    is_valid: bool,
    corruption_indicators: CorruptionIndicators,
};

pub const CorruptionIndicators = struct {
    all_zeros: bool,
    all_ones: bool,
    pattern_detected: bool,
    entropy_score: f64, // Higher is better (max ~8.0 for random data)
};

/// Comprehensive diagnostics for CID comparisons
pub const CIDDiagnostics = struct {
    comparison_type: ComparisonType,
    summary: []const u8,
    recommendations: std.ArrayList([]const u8),
    performance_analysis: PerformanceAnalysis,

    pub fn deinit(self: *CIDDiagnostics) void {
        self.recommendations.deinit();
        self.performance_analysis.optimization_suggestions.deinit();
    }
};

pub const PerformanceAnalysis = struct {
    is_fast: bool,
    memory_efficient: bool,
    optimization_suggestions: std.ArrayList([]const u8),
};

/// Benchmark results for performance analysis
pub const BenchmarkResult = struct {
    iterations: u32,
    total_time_ns: u64,
    average_time_ns: u64,
    operations_per_second: u64,
    memory_usage_bytes: u64,

    pub fn format(self: BenchmarkResult, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("BenchmarkResult{{ iterations: {}, avg_time: {}ns, ops/sec: {} }}", .{
            self.iterations,
            self.average_time_ns,
            self.operations_per_second,
        });
    }
};

// CID Validation Rules and Best Practices
//
// COMPARISON ACCURACY:
// - InterfaceCID comparisons determine rebuild necessity
// - SemanticCID comparisons determine cache validity
// - Dependency CID comparisons determine transitive rebuild needs
// - All comparisons must be cryptographically secure (no hash collisions)
//
// INTEGRITY VERIFICATION:
// - Detect obvious corruption patterns (all zeros, all ones, repeating patterns)
// - Calculate entropy to detect non-random hash distributions
// - Verify BLAKE3 hash properties are maintained
// - Flag suspicious hash patterns for investigation
//
// PERFORMANCE REQUIREMENTS:
// - CID comparisons must be sub-millisecond for individual operations
// - Batch comparisons should scale linearly with count
// - Memory usage should be constant (no allocations for basic comparisons)
// - Benchmark results should guide optimization decisions
//
// DIAGNOSTIC QUALITY:
// - Provide actionable recommendations based on comparison results
// - Explain the implications of CID changes for incremental compilation
// - Suggest optimization strategies for performance improvements
// - Generate detailed reports for debugging and analysis
//
// ERROR HANDLING:
// - Gracefully handle corrupted CIDs with clear error messages
// - Provide fallback strategies when integrity verification fails
// - Log all validation failures for debugging and monitoring
// - Never silently ignore validation errors
//
// This validation system ensures that the incremental compilation engine
// can trust its CID-based decisions and provides comprehensive diagnostics
// for debugging and optimization.

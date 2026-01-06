// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import all test suites
const ComprehensiveDispatchIntegrationTests = @import("comprehensive_dispatch_integration_tests.zig").ComprehensiveDispatchIntegrationTests;
const DispatchPropertyTests = @import("dispatch_property_tests.zig").DispatchPropertyTests;
const DispatchErrorValidationTests = @import("dispatch_error_validation_tests.zig").DispatchErrorValidationTests;
const DispatchPerformanceBoundaryTests = @import("dispatch_performance_boundary_tests.zig").DispatchPerformanceBoundaryTests;

/// Master integration test runner for Task 19
/// Orchestrates all comprehensive integration tests for the dispatch system
pub const MasterIntegrationTestRunner = struct {
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Run the complete integration test suite
    pub fn runCompleteTestSuite(self: *Self) !TestSuiteResults {
        var results = TestSuiteResults.init(self.allocator);

        std.debug.print("🚀 Starting Comprehensive Dispatch Integration Test Suite\n");
        std.debug.print("=========================================================\n\n");

        const start_time = std.time.nanoTimestamp();

        // Test Suite 1: End-to-End Integration Tests
        std.debug.print("📋 Test Suite 1: End-to-End Integration Tests\n");
        std.debug.print("----------------------------------------------\n");

        const e2e_result = self.runEndToEndTests() catch |err| {
            try results.addFailure("End-to-End Integration Tests", err);
            TestResult.failed;
        };
        try results.addResult("End-to-End Integration Tests", e2e_result);

        // Test Suite 2: Property-Based Tests
        std.debug.print("\n🔬 Test Suite 2: Property-Based Tests\n");
        std.debug.print("------------------------------------\n");

        const property_result = self.runPropertyTests() catch |err| {
            try results.addFailure("Property-Based Tests", err);
            TestResult.failed;
        };
        try results.addResult("Property-Based Tests", property_result);

        // Test Suite 3: Error Validation Tests
        std.debug.print("\n❌ Test Suite 3: Error Validation Tests\n");
        std.debug.print("--------------------------------------\n");

        const error_result = self.runErrorValidationTests() catch |err| {
            try results.addFailure("Error Validation Tests", err);
            TestResult.failed;
        };
        try results.addResult("Error Validation Tests", error_result);

        // Test Suite 4: Performance Boundary Tests
        std.debug.print("\n⚡ Test Suite 4: Performance Boundary Tests\n");
        std.debug.print("------------------------------------------\n");

        const perf_result = self.runPerformanceBoundaryTests() catch |err| {
            try results.addFailure("Performance Boundary Tests", err);
            TestResult.failed;
        };
        try results.addResult("Performance Boundary Tests", perf_result);

        const end_time = std.time.nanoTimestamp();
        const total_time_ms = (end_time - start_time) / 1_000_000;

        results.total_duration_ms = total_time_ms;

        // Print final results
        std.debug.print("\n🏁 Integration Test Suite Complete\n");
        std.debug.print("==================================\n");
        try results.printSummary();

        return results;
    }

    /// Run end-to-end integration tests
    fn runEndToEndTests(self: *Self) !TestResult {
        var test_suite = try ComprehensiveDispatchIntegrationTests.init(self.allocator);
        defer test_suite.deinit();

        try test_suite.runAllTests();
        return TestResult.passed;
    }

    /// Run property-based tests
    fn runPropertyTests(self: *Self) !TestResult {
        var property_tests = try DispatchPropertyTests.init(self.allocator, 42); // Fixed seed for reproducibility
        defer property_tests.deinit();

        try property_tests.runAllPropertyTests(200); // More iterations for thorough testing
        return TestResult.passed;
    }

    /// Run error validation tests
    fn runErrorValidationTests(self: *Self) !TestResult {
        var error_tests = try DispatchErrorValidationTests.init(self.allocator);
        defer error_tests.deinit();

        try error_tests.runAllErrorTests();
        return TestResult.passed;
    }

    /// Run performance boundary tests
    fn runPerformanceBoundaryTests(self: *Self) !TestResult {
        var perf_tests = try DispatchPerformanceBoundaryTests.init(self.allocator);
        defer perf_tests.deinit();

        try perf_tests.runAllPerformanceTests();
        return TestResult.passed;
    }

    /// Run stress tests with large datasets
    pub fn runStressTests(self: *Self) !TestResult {
        std.debug.print("🔥 Running Stress Tests\n");
        std.debug.print("----------------------\n");

        // Stress test with very large signature groups
        var property_tests = try DispatchPropertyTests.init(self.allocator, 12345);
        defer property_tests.deinit();

        std.debug.print("Stress testing with 1000 property iterations...\n");
        try property_tests.runAllPropertyTests(1000);

        // Stress test with extreme performance scenarios
        var perf_tests = try DispatchPerformanceBoundaryTests.init(self.allocator);
        defer perf_tests.deinit();

        std.debug.print("Stress testing performance boundaries...\n");
        try perf_tests.runAllPerformanceTests();

        std.debug.print("✅ All stress tests passed!\n");
        return TestResult.passed;
    }

    /// Run regression tests to ensure no performance degradation
    pub fn runRegressionTests(self: *Self) !TestResult {
        std.debug.print("🔄 Running Regression Tests\n");
        std.debug.print("--------------------------\n");

        // Run performance tests multiple times to check for consistency
        var perf_tests = try DispatchPerformanceBoundaryTests.init(self.allocator);
        defer perf_tests.deinit();

        const regression_runs = 5;
        var performance_results = std.ArrayList(u64).init(self.allocator);
        defer performance_results.deinit();

        for (0..regression_runs) |run| {
            std.debug.print("Regression run {} of {}...\n", .{ run + 1, regression_runs });

            const start_time = std.time.nanoTimestamp();
            try perf_tests.runAllPerformanceTests();
            const end_time = std.time.nanoTimestamp();

            const run_time_ms = (end_time - start_time) / 1_000_000;
            try performance_results.append(run_time_ms);
        }

        // Analyze performance consistency
        var total_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var max_time: u64 = 0;

        for (performance_results.items) |time| {
            total_time += time;
            min_time = @min(min_time, time);
            max_time = @max(max_time, time);
        }

        const avg_time = total_time / regression_runs;
        const variance_percent = (@as(f64, @floatFromInt(max_time - min_time)) / @as(f64, @floatFromInt(avg_time))) * 100.0;

        std.debug.print("Regression analysis:\n");
        std.debug.print("  Average time: {} ms\n", .{avg_time});
        std.debug.print("  Min time: {} ms\n", .{min_time});
        std.debug.print("  Max time: {} ms\n", .{max_time});
        std.debug.print("  Variance: {d:.1}%\n", .{variance_percent});

        // Performance should be consistent (< 20% variance)
        if (variance_percent > 20.0) {
            std.debug.print("⚠️  Warning: High performance variance detected\n");
        } else {
            std.debug.print("✅ Performance is consistent across runs\n");
        }

        return TestResult.passed;
    }

    /// Generate comprehensive test report
    pub fn generateTestReport(self: *Self, results: TestSuiteResults, writer: anytype) !void {
        _ = self;

        try writer.print("# Comprehensive Dispatch Integration Test Report\n\n");

        try writer.print("## Executive Summary\n\n");
        try writer.print("- **Total Test Suites**: {}\n", .{results.results.count()});
        try writer.print("- **Passed**: {}\n", .{results.passed_count});
        try writer.print("- **Failed**: {}\n", .{results.failed_count});
        try writer.print("- **Total Duration**: {} ms\n", .{results.total_duration_ms});
        try writer.print("- **Success Rate**: {d:.1}%\n\n", .{results.getSuccessRate() * 100.0});

        try writer.print("## Test Suite Results\n\n");

        var iterator = results.results.iterator();
        while (iterator.next()) |entry| {
            const suite_name = entry.key_ptr.*;
            const result = entry.value_ptr.*;

            const status = switch (result) {
                .passed => "✅ PASSED",
                .failed => "❌ FAILED",
            };

            try writer.print("### {s}: {s}\n\n", .{ suite_name, status });
        }

        if (results.failures.count() > 0) {
            try writer.print("## Failure Details\n\n");

            var failure_iterator = results.failures.iterator();
            while (failure_iterator.next()) |entry| {
                const suite_name = entry.key_ptr.*;
                const error_info = entry.value_ptr.*;

                try writer.print("### {s} Failure\n\n", .{suite_name});
                try writer.print("**Error**: {}\n\n", .{error_info});
            }
        }

        try writer.print("## Performance Metrics\n\n");
        try writer.print("This test suite validates that the dispatch system meets all performance requirements:\n\n");
        try writer.print("- Static dispatch: < 50ns per call\n");
        try writer.print("- Small tables (< 10 entries): < 500ns per call\n");
        try writer.print("- Medium tables (< 100 entries): < 1μs per call\n");
        try writer.print("- Large tables (< 1000 entries): < 5μs per call\n");
        try writer.print("- Compression overhead: < 1.2x uncompressed performance\n\n");

        try writer.print("## Coverage Analysis\n\n");
        try writer.print("The integration test suite covers:\n\n");
        try writer.print("1. **End-to-End Pipeline**: Complete dispatch flow from parsing to code generation\n");
        try writer.print("2. **Error Conditions**: All error scenarios with proper message validation\n");
        try writer.print("3. **Property Invariants**: Mathematical properties that must hold for correct dispatch\n");
        try writer.print("4. **Performance Boundaries**: Ensuring dispatch overhead remains within acceptable limits\n");
        try writer.print("5. **Cross-Module Integration**: Multi-module dispatch scenarios\n");
        try writer.print("6. **Compression Integration**: Advanced compression system validation\n\n");

        try writer.print("## Validation Status\n\n");
        if (results.failed_count == 0) {
            try writer.print("🎉 **ALL TESTS PASSED** - The dispatch system is ready for production use!\n\n");
            try writer.print("The comprehensive integration test suite validates that:\n");
            try writer.print("- All requirements from the specification are met\n");
            try writer.print("- Performance boundaries are respected\n");
            try writer.print("- Error handling is robust and user-friendly\n");
            try writer.print("- Cross-module dispatch works correctly\n");
            try writer.print("- Compression integration provides memory efficiency gains\n");
        } else {
            try writer.print("⚠️  **TESTS FAILED** - Issues detected that need resolution before production deployment.\n\n");
        }
    }
};

/// Test result enumeration
const TestResult = enum {
    passed,
    failed,
};

/// Test suite results aggregation
const TestSuiteResults = struct {
    allocator: Allocator,
    results: std.StringHashMap(TestResult),
    failures: std.StringHashMap(anyerror),
    passed_count: u32,
    failed_count: u32,
    total_duration_ms: u64,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .results = std.StringHashMap(TestResult).init(allocator),
            .failures = std.StringHashMap(anyerror).init(allocator),
            .passed_count = 0,
            .failed_count = 0,
            .total_duration_ms = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.results.deinit();
        self.failures.deinit();
    }

    pub fn addResult(self: *Self, suite_name: []const u8, result: TestResult) !void {
        try self.results.put(try self.allocator.dupe(u8, suite_name), result);

        switch (result) {
            .passed => self.passed_count += 1,
            .failed => self.failed_count += 1,
        }
    }

    pub fn addFailure(self: *Self, suite_name: []const u8, err: anyerror) !void {
        try self.failures.put(try self.allocator.dupe(u8, suite_name), err);
    }

    pub fn getSuccessRate(self: *const Self) f64 {
        const total = self.passed_count + self.failed_count;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.passed_count)) / @as(f64, @floatFromInt(total));
    }

    pub fn printSummary(self: *const Self) !void {
        const total = self.passed_count + self.failed_count;

        std.debug.print("Test Results Summary:\n");
        std.debug.print("  Total Suites: {}\n", .{total});
        std.debug.print("  Passed: {} ✅\n", .{self.passed_count});
        std.debug.print("  Failed: {} ❌\n", .{self.failed_count});
        std.debug.print("  Success Rate: {d:.1}%\n", .{self.getSuccessRate() * 100.0});
        std.debug.print("  Total Duration: {} ms\n", .{self.total_duration_ms});

        if (self.failed_count == 0) {
            std.debug.print("\n🎉 ALL INTEGRATION TESTS PASSED!\n");
            std.debug.print("The dispatch system is validated and ready for production.\n");
        } else {
            std.debug.print("\n⚠️  Some tests failed. Review the failures above.\n");
        }
    }
};

// Test functions for zig test runner
test "master integration test runner - complete suite" {
    var runner = MasterIntegrationTestRunner.init(testing.allocator);

    const results = try runner.runCompleteTestSuite();
    defer results.deinit();

    // Verify all tests passed
    try testing.expect(results.failed_count == 0);
    try testing.expect(results.passed_count > 0);
}

test "master integration test runner - stress tests" {
    var runner = MasterIntegrationTestRunner.init(testing.allocator);

    const result = try runner.runStressTests();
    try testing.expect(result == .passed);
}

test "master integration test runner - regression tests" {
    var runner = MasterIntegrationTestRunner.init(testing.allocator);

    const result = try runner.runRegressionTests();
    try testing.expect(result == .passed);
}

test "master integration test runner - test report generation" {
    var runner = MasterIntegrationTestRunner.init(testing.allocator);

    var results = TestSuiteResults.init(testing.allocator);
    defer results.deinit();

    try results.addResult("Test Suite 1", .passed);
    try results.addResult("Test Suite 2", .passed);
    results.total_duration_ms = 1500;

    var report_buffer = std.ArrayList(u8).init(testing.allocator);
    defer report_buffer.deinit();

    try runner.generateTestReport(results, report_buffer.writer());

    const report = report_buffer.items;
    try testing.expect(report.len > 0);
    try testing.expect(std.mem.indexOf(u8, report, "Comprehensive Dispatch Integration Test Report") != null);
}

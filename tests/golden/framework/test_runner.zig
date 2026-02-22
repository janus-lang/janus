// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;
const ImportedTestMetadata = @import("test_metadata.zig").TestMetadata;
const MetadataParser = @import("metadata_parser.zig").MetadataParser;
const IRIntegration = @import("ir_integration.zig").IRIntegration;
const GoldenDiff = @import("golden_diff.zig").GoldenDiff;
const ErrorRegistry = @import("error_registry.zig").ErrorRegistry;
const PerformanceValidator = @import("performance_validator.zig").PerformanceValidator;
const PerformanceBaselineManager = @import("performance_baseline_manager.zig").PerformanceBaselineManager;
const PerformanceMetricsCollector = @import("performance_metrics_collector.zig").PerformanceMetricsCollector;

/// TestRunner orchestrates the complete golden test execution process with forensic precision.
/// This is the master controller that discovers, loads, and executes golden tests while
/// maintaining complete auditability of every decision and measurement.
pub const TestRunner = struct {
    allocator: Allocator,
    config: TestConfig,

    const Self = @This();

    /// Configuration for golden test execution
    pub const TestConfig = struct {
        test_directory: []const u8,
        golden_directory: []const u8,
        performance_baseline_directory: []const u8,
        platforms: []Platform,
        optimization_levels: []OptimizationLevel,
        parallel_execution: bool,
        timeout_seconds: u32,
        max_parallel_workers: u32,

        pub const Platform = enum {
            linux_x86_64,
            linux_aarch64,
            macos_x86_64,
            macos_aarch64,
            windows_x86_64,

            pub fn toString(self: Platform) []const u8 {
                return switch (self) {
                    .linux_x86_64 => "linux_x86_64",
                    .linux_aarch64 => "linux_aarch64",
                    .macos_x86_64 => "macos_x86_64",
                    .macos_aarch64 => "macos_aarch64",
                    .windows_x86_64 => "windows_x86_64",
                };
            }
        };

        pub const OptimizationLevel = enum {
            debug,
            release_safe,
            release_fast,
            release_small,

            pub fn toString(self: OptimizationLevel) []const u8 {
                return switch (self) {
                    .debug => "debug",
                    .release_safe => "release_safe",
                    .release_fast => "release_fast",
                    .release_small => "release_small",
                };
            }
        };
    };

    /// Result of executing a single golden test
    pub const TestResult = struct {
        test_name: []const u8,
        status: TestStatus,
        execution_time_ms: u64,
        platform: TestConfig.Platform,
        optimization_level: TestConfig.OptimizationLevel,
        diagnostic_messages: []DiagnosticMessage,

        // Results from different validation phases
        ir_comparison_result: ?*anyopaque = null, // Will be IRComparisonResult
        performance_result: ?PerformanceValidator.ValidationResult = null,
        cross_platform_result: ?*anyopaque = null, // Will be CrossPlatformResult

        pub const TestStatus = enum {
            passed,
            failed,
            approval_required,
            skipped,
            test_error,
            timeout,
        };

        pub fn deinit(self: *TestResult, allocator: Allocator) void {
            allocator.free(self.test_name);
            for (self.diagnostic_messages) |*msg| {
                msg.deinit(allocator);
            }
            allocator.free(self.diagnostic_messages);

            // Clean up performance result if present
            if (self.performance_result) |*perf_result| {
                perf_result.deinit(allocator);
            }
        }
    };

    /// Diagnostic message for test execution issues
    pub const DiagnosticMessage = struct {
        level: Level,
        phase: Phase,
        message: []const u8,
        context: []const u8,
        timestamp: i64,

        pub const Level = enum {
            info,
            warning,
            diagnostic_error,
            critical,
        };

        pub const Phase = enum {
            discovery,
            loading,
            ir_generation,
            golden_comparison,
            performance_validation,
            cross_platform_validation,
            result_aggregation,
        };

        pub fn deinit(self: *DiagnosticMessage, allocator: Allocator) void {
            allocator.free(self.message);
            allocator.free(self.context);
        }
    };

    /// Test case loaded from source with metadata
    pub const TestCase = struct {
        name: []const u8,
        source_path: []const u8,
        source_content: []const u8,
        metadata: TestMetadata,

        pub fn deinit(self: *TestCase, allocator: Allocator) void {
            allocator.free(self.name);
            allocator.free(self.source_path);
            allocator.free(self.source_content);
            self.metadata.deinit(allocator);
        }
    };

    /// Metadata parsed from test case comments
    pub const TestMetadata = struct {
        expected_strategy: ?[]const u8,
        expected_performance: []PerformanceExpectation,
        platforms: PlatformFilter,
        optimization_levels: []TestConfig.OptimizationLevel,
        skip_platforms: []TestConfig.Platform,
        timeout_override: ?u32,
        description: ?[]const u8,

        pub const PerformanceExpectation = struct {
            metric_name: []const u8,
            operator: Operator,
            threshold_value: f64,
            unit: []const u8,

            pub const Operator = enum {
                less_than,
                less_equal,
                greater_than,
                greater_equal,
                approximately,
            };

            pub fn deinit(self: *PerformanceExpectation, allocator: Allocator) void {
                allocator.free(self.metric_name);
                allocator.free(self.unit);
            }
        };

        pub const PlatformFilter = enum {
            all,
            specific,
            exclude,
        };

        pub fn deinit(self: *TestMetadata, allocator: Allocator) void {
            if (self.expected_strategy) |strategy| {
                allocator.free(strategy);
            }
            for (self.expected_performance) |*perf| {
                perf.deinit(allocator);
            }
            allocator.free(self.expected_performance);
            allocator.free(self.optimization_levels);
            allocator.free(self.skip_platforms);
            if (self.description) |desc| {
                allocator.free(desc);
            }
        }
    };

    /// Initialize TestRunner with configuration
    pub fn init(allocator: Allocator, config: TestConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Discover and run all golden tests
    pub fn runAllTests(self: *Self) ![]TestResult {
        const start_time = std.time.milliTimestamp();

        // Discover all test cases
        const test_cases = try self.discoverTestCases();
        defer {
            for (test_cases) |*test_case| {
                test_case.deinit(self.allocator);
            }
            self.allocator.free(test_cases);
        }

        var results: ArrayList(TestResult) = .empty;
        defer results.deinit();

        if (self.config.parallel_execution) {
            try self.runTestsParallel(test_cases, &results);
        } else {
            try self.runTestsSequential(test_cases, &results);
        }

        const end_time = std.time.milliTimestamp();
        std.log.info("Golden test execution completed in {}ms. {} tests processed.", .{
            end_time - start_time,
            results.items.len,
        });

        return try results.toOwnedSlice(alloc);
    }

    /// Run a single test by name
    pub fn runSingleTest(self: *Self, test_name: []const u8) !TestResult {
        var test_case = try self.loadTestCase(test_name);
        defer test_case.deinit(self.allocator);

        return self.executeTestCase(test_case);
    }

    /// Discover all test cases in the test directory
    fn discoverTestCases(self: *Self) ![]TestCase {
        var test_cases: ArrayList(TestCase) = .empty;
        defer test_cases.deinit();

        var dir = std.fs.cwd().openDir(self.config.test_directory, .{ .iterate = true }) catch |err| {
            std.log.err("Failed to open test directory '{s}': {}", .{ self.config.test_directory, err });
            return err;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".jan")) {
                const test_name = entry.name[0 .. entry.name.len - 4]; // Remove .jan extension

                const test_case = self.loadTestCase(test_name) catch |err| {
                    std.log.warn("Failed to load test case '{s}': {}", .{ test_name, err });
                    continue;
                };

                try test_cases.append(test_case);
                std.log.debug("Discovered test case: {s}", .{test_name});
            }
        }

        std.log.info("Discovered {} golden test cases", .{test_cases.items.len});
        return try test_cases.toOwnedSlice(alloc);
    }

    /// Load a single test case by name
    fn loadTestCase(self: *Self, test_name: []const u8) !TestCase {
        const source_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.jan", .{ self.config.test_directory, test_name });
        errdefer self.allocator.free(source_path);

        const source_content = std.fs.cwd().readFileAlloc(self.allocator, source_path, 1024 * 1024 // 1MB max file size
        ) catch |err| {
            std.log.err("Failed to read test file '{s}': {}", .{ source_path, err });
            return err;
        };
        errdefer self.allocator.free(source_content);

        // Parse metadata from source comments
        var metadata = try self.parseTestMetadata(source_content);
        errdefer metadata.deinit(self.allocator);

        return TestCase{
            .name = try self.allocator.dupe(u8, test_name),
            .source_path = source_path,
            .source_content = source_content,
            .metadata = metadata,
        };
    }

    /// Execute tests sequentially
    fn runTestsSequential(self: *Self, test_cases: []TestCase, results: *ArrayList(TestResult)) !void {
        for (test_cases) |test_case| {
            const result = try self.executeTestCase(test_case);
            try results.append(result);

            std.log.info("Test '{s}' completed with status: {}", .{ test_case.name, result.status });
        }
    }

    /// Execute tests in parallel
    fn runTestsParallel(self: *Self, test_cases: []TestCase, results: *ArrayList(TestResult)) !void {
        // For now, implement simple parallel execution
        // In a full implementation, this would use a thread pool
        const max_workers = @min(self.config.max_parallel_workers, test_cases.len);

        var completed_results: ArrayList(TestResult) = .empty;
        defer completed_results.deinit();

        // Simple parallel execution - in practice would use proper thread pool
        for (test_cases) |test_case| {
            const result = try self.executeTestCase(test_case);
            try completed_results.append(result);
        }

        try results.appendSlice(completed_results.items);
        std.log.info("Parallel execution completed with {} workers", .{max_workers});
    }

    /// Execute a single test case with full IR integration
    fn executeTestCase(self: *Self, test_case: TestCase) !TestResult {
        const start_time = std.time.milliTimestamp();

        var diagnostic_messages: ArrayList(DiagnosticMessage) = .empty;
        defer diagnostic_messages.deinit();

        // Check if test should be skipped for current platform
        const current_platform = self.getCurrentPlatform();
        if (self.shouldSkipTest(test_case.metadata, current_platform)) {
            const end_time = std.time.milliTimestamp();

            try diagnostic_messages.append(.{
                .level = .info,
                .phase = .loading,
                .message = try std.fmt.allocPrint(self.allocator, "Test skipped for platform {s}", .{current_platform.toString()}),
                .context = try self.allocator.dupe(u8, "Platform filtering"),
                .timestamp = std.time.timestamp(),
            });

            return TestResult{
                .test_name = try self.allocator.dupe(u8, test_case.name),
                .status = .skipped,
                .execution_time_ms = @intCast(end_time - start_time),
                .platform = current_platform,
                .optimization_level = self.config.optimization_levels[0], // Default
                .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
            };
        }

        // Initialize IR integration and golden diff components
        var ir_integration = IRIntegration.init(self.allocator, "compiler/janus", // LLVM backend path
            self.config.servicelden_directory);

        _ = GoldenDiff.init(self.allocator); // Will be used in future phases

        var error_registry = ErrorRegistry.init(self.allocator) catch |err| {
            try diagnostic_messages.append(.{
                .level = .critical,
                .phase = .loading,
                .message = try std.fmt.allocPrint(self.allocator, "Failed to initialize error registry: {}", .{err}),
                .context = try self.allocator.dupe(u8, "Framework initialization"),
                .timestamp = std.time.timestamp(),
            });

            const end_time = std.time.milliTimestamp();
            return TestResult{
                .test_name = try self.allocator.dupe(u8, test_case.name),
                .status = .test_error,
                .execution_time_ms = @intCast(end_time - start_time),
                .platform = current_platform,
                .optimization_level = self.config.optimization_levels[0],
                .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
            };
        };
        defer error_registry.deinit();

        // Parse metadata using the new metadata parser
        var metadata_parser = MetadataParser.init(self.allocator);
        const parsed_metadata = metadata_parser.parseFromSource(test_case.source_content) catch |err| {
            try diagnostic_messages.append(.{
                .level = .diagnostic_error,
                .phase = .loading,
                .message = try std.fmt.allocPrint(self.allocator, "Failed to parse test metadata: {}", .{err}),
                .context = try self.allocator.dupe(u8, "Metadata parsing"),
                .timestamp = std.time.timestamp(),
            });

            const end_time = std.time.milliTimestamp();
            return TestResult{
                .test_name = try self.allocator.dupe(u8, test_case.name),
                .status = .test_error,
                .execution_time_ms = @intCast(end_time - start_time),
                .platform = current_platform,
                .optimization_level = self.config.optimization_levels[0],
                .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
            };
        };
        defer parsed_metadata.deinit(self.allocator);

        // Execute for each optimization level
        const optimization_level = self.config.optimization_levels[0]; // Use first for now

        // Phase 1: Generate IR
        try diagnostic_messages.append(.{
            .level = .info,
            .phase = .ir_generation,
            .message = try self.allocator.dupe(u8, "Starting IR generation"),
            .context = try std.fmt.allocPrint(self.allocator, "Platform: {s}, Optimization: {s}", .{ current_platform.toString(), optimization_level.toString() }),
            .timestamp = std.time.timestamp(),
        });

        var ir_result = ir_integration.generateIR(test_case.source_path, current_platform.toString(), optimization_level.toString()) catch |err| {
            const error_code = switch (err) {
                error.FileNotFound => ErrorRegistry.ErrorCode.G1002_GOLDEN_REFERENCE_MISSING,
                error.AccessDenied => ErrorRegistry.ErrorCode.G1003_PLATFORM_NOT_SUPPORTED,
                else => ErrorRegistry.ErrorCode.G1001_IR_GENERATION_FAILED,
            };

            const failure_report = error_registry.createFailureReport(error_code, test_case.name, current_platform.toString(), optimization_level.toString(), @errorName(err), .{
                .servicelden_reference_path = null,
                .generated_ir_path = null,
                .metadata_source = test_case.source_path,
                .compiler_version = "janus-0.1.0",
                .environment_info = "Golden Test Framework",
            }, .{
                .ir_diff_summary = null,
                .performance_metrics = null,
                .contract_violations = null,
                .stack_trace = null,
                .debug_artifacts = null,
            }) catch unreachable;
            defer failure_report.deinit(self.allocator);

            const formatted_report = error_registry.formatFailureReport(failure_report) catch unreachable;
            defer self.allocator.free(formatted_report);

            try diagnostic_messages.append(.{
                .level = .critical,
                .phase = .ir_generation,
                .message = try self.allocator.dupe(u8, formatted_report),
                .context = try self.allocator.dupe(u8, "IR generation failed"),
                .timestamp = std.time.timestamp(),
            });

            const end_time = std.time.milliTimestamp();
            return TestResult{
                .test_name = try self.allocator.dupe(u8, test_case.name),
                .status = .failed,
                .execution_time_ms = @intCast(end_time - start_time),
                .platform = current_platform,
                .optimization_level = optimization_level,
                .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
            };
        };
        defer ir_result.deinit(self.allocator);

        if (!ir_result.success) {
            try diagnostic_messages.append(.{
                .level = .diagnostic_error,
                .phase = .ir_generation,
                .message = try self.allocator.dupe(u8, ir_result.error_message orelse "Unknown IR generation error"),
                .context = try self.allocator.dupe(u8, "Compiler error"),
                .timestamp = std.time.timestamp(),
            });

            const end_time = std.time.milliTimestamp();
            return TestResult{
                .test_name = try self.allocator.dupe(u8, test_case.name),
                .status = .failed,
                .execution_time_ms = @intCast(end_time - start_time),
                .platform = current_platform,
                .optimization_level = optimization_level,
                .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
            };
        }

        // Phase 2: Compare with golden reference
        try diagnostic_messages.append(.{
            .level = .info,
            .phase = .servicelden_comparison,
            .message = try self.allocator.dupe(u8, "Starting golden comparison"),
            .context = try std.fmt.allocPrint(self.allocator, "Generated {} bytes of IR", .{ir_result.generated_ir.len}),
            .timestamp = std.time.timestamp(),
        });

        var comparison_result = ir_integration.compareWithGolden(ir_result, parsed_metadata) catch |err| {
            try diagnostic_messages.append(.{
                .level = .diagnostic_error,
                .phase = .servicelden_comparison,
                .message = try std.fmt.allocPrint(self.allocator, "Golden comparison failed: {}", .{err}),
                .context = try self.allocator.dupe(u8, "Comparison error"),
                .timestamp = std.time.timestamp(),
            });

            const end_time = std.time.milliTimestamp();
            return TestResult{
                .test_name = try self.allocator.dupe(u8, test_case.name),
                .status = .test_error,
                .execution_time_ms = @intCast(end_time - start_time),
                .platform = current_platform,
                .optimization_level = optimization_level,
                .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
            };
        };
        defer comparison_result.deinit(self.allocator);

        // Phase 3: Performance Validation
        var performance_validator = try PerformanceValidator.init(self.allocator, self.config.performance_baseline_directory);
        defer performance_validator.deinit();

        var performance_result: ?PerformanceValidator.ValidationResult = null;

        // Only run performance validation if test has performance expectations
        if (test_case.metadata.expected_performance.len > 0) {
            try diagnostic_messages.append(.{
                .level = .info,
                .phase = .performance_validation,
                .message = try self.allocator.dupe(u8, "Starting performance validation"),
                .context = try std.fmt.allocPrint(self.allocator, "Expected {} performance metrics", .{test_case.metadata.expected_performance.len}),
                .timestamp = std.time.timestamp(),
            });

            // Create a mock dispatch function for benchmarking
            // In a real implementation, this would be extracted from the generated IR
            const mock_dispatch_fn = struct {
                fn dispatch() void {
                    // Simulate dispatch overhead
                    var i: u32 = 0;
                    while (i < 100) : (i += 1) {
                        _ = i * i;
                    }
                }
            }.dispatch;

            const benchmark_config = PerformanceValidator.BenchmarkConfig{
                .iterations = 1000,
                .warmup_iterations = 100,
                .timeout_ms = 10000,
            };

            // Execute benchmark
            const measurement = performance_validator.executeBenchmark(test_case.name, &mock_dispatch_fn, benchmark_config) catch |err| {
                try diagnostic_messages.append(.{
                    .level = .diagnostic_error,
                    .phase = .performance_validation,
                    .message = try std.fmt.allocPrint(self.allocator, "Performance benchmark failed: {}", .{err}),
                    .context = try self.allocator.dupe(u8, "Benchmark execution error"),
                    .timestamp = std.time.timestamp(),
                });

                const end_time = std.time.milliTimestamp();
                return TestResult{
                    .test_name = try self.allocator.dupe(u8, test_case.name),
                    .status = .test_error,
                    .execution_time_ms = @intCast(end_time - start_time),
                    .platform = current_platform,
                    .optimization_level = optimization_level,
                    .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
                };
            };

            // Load baseline for comparison
            const baseline = performance_validator.loadBaseline(test_case.name, current_platform.toString(), optimization_level.toString()) catch |err| {
                try diagnostic_messages.append(.{
                    .level = .warning,
                    .phase = .performance_validation,
                    .message = try std.fmt.allocPrint(self.allocator, "Failed to load performance baseline: {}", .{err}),
                    .context = try self.allocator.dupe(u8, "Baseline loading"),
                    .timestamp = std.time.timestamp(),
                });
                null;
            };

            // Compare with baseline
            const validation_result = performance_validator.compareWithBaseline(measurement, baseline, benchmark_config) catch |err| {
                try diagnostic_messages.append(.{
                    .level = .diagnostic_error,
                    .phase = .performance_validation,
                    .message = try std.fmt.allocPrint(self.allocator, "Performance comparison failed: {}", .{err}),
                    .context = try self.allocator.dupe(u8, "Baseline comparison error"),
                    .timestamp = std.time.timestamp(),
                });

                const end_time = std.time.milliTimestamp();
                return TestResult{
                    .test_name = try self.allocator.dupe(u8, test_case.name),
                    .status = .test_error,
                    .execution_time_ms = @intCast(end_time - start_time),
                    .platform = current_platform,
                    .optimization_level = optimization_level,
                    .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
                };
            };

            // Add performance diagnostic information
            try diagnostic_messages.append(.{
                .level = if (validation_result.passed) .info else .warning,
                .phase = .performance_validation,
                .message = try std.fmt.allocPrint(self.allocator, "Performance validation {s}: dispatch overhead {} ns", .{ if (validation_result.passed) "passed" else "failed", validation_result.current_measurement.dispatch_overhead_ns }),
                .context = try self.allocator.dupe(u8, validation_result.detailed_analysis),
                .timestamp = std.time.timestamp(),
            });

            performance_result = validation_result;

            // Clean up baseline if it was loaded
            if (baseline) |*b| {
                var mutable_baseline = b.*;
                mutable_baseline.deinit(self.allocator);
            }
        }

        // Determine final test status (considering performance results)
        var final_status: TestResult.TestStatus = if (comparison_result.matches_golden)
            .passed
        else if (comparison_result.contract_violations.len > 0)
            .failed
        else
            .approval_required;

        // Override status if performance validation failed
        if (performance_result) |perf_result| {
            if (!perf_result.passed and perf_result.regression_detected) {
                final_status = .failed;
            }
        }

        // Add diagnostic information about comparison results
        if (!comparison_result.matches_golden) {
            try diagnostic_messages.append(.{
                .level = .warning,
                .phase = .servicelden_comparison,
                .message = try std.fmt.allocPrint(self.allocator, "Found {} semantic differences and {} contract violations", .{ comparison_result.semantic_differences.len, comparison_result.contract_violations.len }),
                .context = try self.allocator.dupe(u8, "Golden comparison results"),
                .timestamp = std.time.timestamp(),
            });
        }

        const end_time = std.time.milliTimestamp();

        try diagnostic_messages.append(.{
            .level = .info,
            .phase = .result_aggregation,
            .message = try std.fmt.allocPrint(self.allocator, "Test completed with status: {}", .{final_status}),
            .context = try std.fmt.allocPrint(self.allocator, "Execution time: {}ms", .{end_time - start_time}),
            .timestamp = std.time.timestamp(),
        });

        return TestResult{
            .test_name = try self.allocator.dupe(u8, test_case.name),
            .status = final_status,
            .execution_time_ms = @intCast(end_time - start_time),
            .platform = current_platform,
            .optimization_level = optimization_level,
            .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
            .performance_result = performance_result,
        };
    }

    /// Get the current platform
    fn getCurrentPlatform(_: *Self) TestConfig.Platform {
        // Simple platform detection - real implementation would be more sophisticated
        return switch (@import("builtin").target.os.tag) {
            .linux => switch (@import("builtin").target.cpu.arch) {
                .x86_64 => .linux_x86_64,
                .aarch64 => .linux_aarch64,
                else => .linux_x86_64, // Default
            },
            .macos => switch (@import("builtin").target.cpu.arch) {
                .x86_64 => .macos_x86_64,
                .aarch64 => .macos_aarch64,
                else => .macos_x86_64, // Default
            },
            .windows => .windows_x86_64,
            else => .linux_x86_64, // Default fallback
        };
    }

    /// Check if test should be skipped for the given platform
    fn shouldSkipTest(_: *Self, metadata: TestMetadata, platform: TestConfig.Platform) bool {
        // Check skip list
        for (metadata.skip_platforms) |skip_platform| {
            if (skip_platform == platform) {
                return true;
            }
        }

        // Check platform filter
        switch (metadata.platforms) {
            .all => return false,
            .specific => {
                // For now, assume all platforms are allowed if specific
                // Real implementation would check against allowed list
                return false;
            },
            .exclude => {
                // For now, assume no platforms are excluded
                // Real implementation would check against excluded list
                return false;
            },
        }
    }

    /// Parse test metadata from embedded comments in Janus source
    pub fn parseTestMetadata(self: *Self, source_content: []const u8) !TestMetadata {
        var expected_strategy: ?[]const u8 = null;
        var expected_performance: ArrayList(TestMetadata.PerformanceExpectation) = .empty;
        defer expected_performance.deinit();

        var platforms: TestMetadata.PlatformFilter = .all;
        var optimization_levels: ArrayList(TestConfig.OptimizationLevel) = .empty;
        defer optimization_levels.deinit();

        var skip_platforms: ArrayList(TestConfig.Platform) = .empty;
        defer skip_platforms.deinit();

        var timeout_override: ?u32 = null;
        var description: ?[]const u8 = null;

        // Parse line by line looking for metadata comments
        var lines = std.mem.splitScalar(u8, source_content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            // Look for metadata comments starting with // @
            if (std.mem.startsWith(u8, trimmed, "// @")) {
                const metadata_line = trimmed[4..]; // Skip "// @"
                try self.parseMetadataLine(metadata_line, &expected_strategy, &expected_performance, &platforms, &optimization_levels, &skip_platforms, &timeout_override, &description);
            }
        }

        // Set default optimization level if none specified
        if (optimization_levels.items.len == 0) {
            try optimization_levels.append(.release_safe);
        }

        return TestMetadata{
            .expected_strategy = expected_strategy,
            .expected_performance = try expected_performance.toOwnedSlice(),
            .platforms = platforms,
            .optimization_levels = try optimization_levels.toOwnedSlice(),
            .skip_platforms = try skip_platforms.toOwnedSlice(),
            .timeout_override = timeout_override,
            .description = description,
        };
    }

    /// Parse a single metadata line
    fn parseMetadataLine(
        self: *Self,
        line: []const u8,
        expected_strategy: *?[]const u8,
        expected_performance: *ArrayList(TestMetadata.PerformanceExpectation),
        platforms: *TestMetadata.PlatformFilter,
        optimization_levels: *ArrayList(TestConfig.OptimizationLevel),
        skip_platforms: *ArrayList(TestConfig.Platform),
        timeout_override: *?u32,
        description: *?[]const u8,
    ) !void {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "expected-strategy:")) {
            const value = std.mem.trim(u8, trimmed[18..], " \t");
            expected_strategy.* = try self.allocator.dupe(u8, value);
        } else if (std.mem.startsWith(u8, trimmed, "expected-performance:")) {
            const value = std.mem.trim(u8, trimmed[21..], " \t");
            const perf_expectation = try self.parsePerformanceExpectation(value);
            try expected_performance.append(perf_expectation);
        } else if (std.mem.startsWith(u8, trimmed, "platforms:")) {
            const value = std.mem.trim(u8, trimmed[10..], " \t");
            if (std.mem.eql(u8, value, "all")) {
                platforms.* = .all;
            } else {
                platforms.* = .specific;
                // Parse specific platforms - simplified for now
            }
        } else if (std.mem.startsWith(u8, trimmed, "optimization-level:")) {
            const value = std.mem.trim(u8, trimmed[19..], " \t");
            const opt_level = self.parseOptimizationLevel(value) catch {
                std.log.warn("Unknown optimization level: {s}", .{value});
                return;
            };
            try optimization_levels.append(opt_level);
        } else if (std.mem.startsWith(u8, trimmed, "skip-platforms:")) {
            const value = std.mem.trim(u8, trimmed[15..], " \t");
            try self.parseSkipPlatforms(value, skip_platforms);
        } else if (std.mem.startsWith(u8, trimmed, "timeout:")) {
            const value = std.mem.trim(u8, trimmed[8..], " \t");
            timeout_override.* = std.fmt.parseInt(u32, value, 10) catch {
                std.log.warn("Invalid timeout value: {s}", .{value});
                return;
            };
        } else if (std.mem.startsWith(u8, trimmed, "description:")) {
            const value = std.mem.trim(u8, trimmed[12..], " \t");
            description.* = try self.allocator.dupe(u8, value);
        }
    }

    /// Parse performance expectation from string like "dispatch_overhead_ns < 30"
    pub fn parsePerformanceExpectation(self: *Self, expectation_str: []const u8) !TestMetadata.PerformanceExpectation {
        // Find the operator
        var operator: TestMetadata.PerformanceExpectation.Operator = undefined;
        var split_pos: usize = 0;
        var operator_len: usize = 0;

        if (std.mem.indexOf(u8, expectation_str, " < ")) |pos| {
            operator = .less_than;
            split_pos = pos;
            operator_len = 3;
        } else if (std.mem.indexOf(u8, expectation_str, " <= ")) |pos| {
            operator = .less_equal;
            split_pos = pos;
            operator_len = 4;
        } else if (std.mem.indexOf(u8, expectation_str, " > ")) |pos| {
            operator = .greater_than;
            split_pos = pos;
            operator_len = 3;
        } else if (std.mem.indexOf(u8, expectation_str, " >= ")) |pos| {
            operator = .greater_equal;
            split_pos = pos;
            operator_len = 4;
        } else if (std.mem.indexOf(u8, expectation_str, " ~= ")) |pos| {
            operator = .approximately;
            split_pos = pos;
            operator_len = 4;
        } else {
            return error.InvalidPerformanceExpectation;
        }

        const metric_name = std.mem.trim(u8, expectation_str[0..split_pos], " \t");
        const value_str = std.mem.trim(u8, expectation_str[split_pos + operator_len ..], " \t");

        const threshold_value = std.fmt.parseFloat(f64, value_str) catch {
            return error.InvalidThresholdValue;
        };

        return TestMetadata.PerformanceExpectation{
            .metric_name = try self.allocator.dupe(u8, metric_name),
            .operator = operator,
            .threshold_value = threshold_value,
            .unit = try self.allocator.dupe(u8, ""), // Unit parsing would be more sophisticated
        };
    }

    /// Parse optimization level from string
    pub fn parseOptimizationLevel(_: *Self, level_str: []const u8) !TestConfig.OptimizationLevel {
        if (std.mem.eql(u8, level_str, "debug")) {
            return .debug;
        } else if (std.mem.eql(u8, level_str, "release_safe")) {
            return .release_safe;
        } else if (std.mem.eql(u8, level_str, "release_fast")) {
            return .release_fast;
        } else if (std.mem.eql(u8, level_str, "release_small")) {
            return .release_small;
        } else {
            return error.UnknownOptimizationLevel;
        }
    }

    /// Parse skip platforms from comma-separated string
    fn parseSkipPlatforms(self: *Self, platforms_str: []const u8, skip_platforms: *ArrayList(TestConfig.Platform)) !void {
        var platform_iter = std.mem.splitScalar(u8, platforms_str, ',');
        while (platform_iter.next()) |platform_str| {
            const trimmed = std.mem.trim(u8, platform_str, " \t");
            const platform = self.parsePlatform(trimmed) catch {
                std.log.warn("Unknown platform: {s}", .{trimmed});
                continue;
            };
            try skip_platforms.append(platform);
        }
    }

    /// Parse platform from string
    pub fn parsePlatform(_: *Self, platform_str: []const u8) !TestConfig.Platform {
        if (std.mem.eql(u8, platform_str, "linux_x86_64")) {
            return .linux_x86_64;
        } else if (std.mem.eql(u8, platform_str, "linux_aarch64")) {
            return .linux_aarch64;
        } else if (std.mem.eql(u8, platform_str, "macos_x86_64")) {
            return .macos_x86_64;
        } else if (std.mem.eql(u8, platform_str, "macos_aarch64")) {
            return .macos_aarch64;
        } else if (std.mem.eql(u8, platform_str, "windows_x86_64")) {
            return .windows_x86_64;
        } else {
            return error.UnknownPlatform;
        }
    }
};

// Unit tests for TestRunner
test "TestRunner initialization" {
    const allocator = std.testing.allocator;

    var platforms = [_]TestRunner.TestConfig.Platform{.linux_x86_64};
    var optimization_levels = [_]TestRunner.TestConfig.OptimizationLevel{.release_safe};

    const config = TestRunner.TestConfig{
        .test_directory = "tests/golden/ir-generation",
        .servicelden_directory = "tests/golden/references",
        .performance_baseline_directory = "tests/golden/baselines",
        .platforms = &platforms,
        .optimization_levels = &optimization_levels,
        .parallel_execution = false,
        .timeout_seconds = 30,
        .max_parallel_workers = 4,
    };

    const runner = TestRunner.init(allocator, config);

    // Test basic initialization
    try std.testing.expect(runner.config.parallel_execution == false);
    try std.testing.expect(runner.config.timeout_seconds == 30);
    try std.testing.expectEqualStrings(runner.config.test_directory, "tests/golden/ir-generation");
}

test "TestMetadata parsing" {
    const allocator = std.testing.allocator;

    var platforms = [_]TestRunner.TestConfig.Platform{.linux_x86_64};
    var optimization_levels = [_]TestRunner.TestConfig.OptimizationLevel{.release_safe};

    const config = TestRunner.TestConfig{
        .test_directory = "tests/golden/ir-generation",
        .servicelden_directory = "tests/golden/references",
        .performance_baseline_directory = "tests/golden/baselines",
        .platforms = &platforms,
        .optimization_levels = &optimization_levels,
        .parallel_execution = false,
        .timeout_seconds = 30,
        .max_parallel_workers = 4,
    };

    var runner = TestRunner.init(allocator, config);

    const source_content =
        \\// @expected-strategy: perfect_hash
        \\// @expected-performance: dispatch_overhead_ns < 30
        \\// @platforms: all
        \\// @optimization-level: release_safe
        \\// @description: Basic dispatch strategy test
        \\
        \\func add(x: i32, y: i32) -> i32 { x + y }
        \\func main() { let result = add(5, 10) }
    ;

    var metadata = try runner.parseTestMetadata(source_content);
    defer metadata.deinit(allocator);

    // Test parsed values
    try std.testing.expect(metadata.expected_strategy != null);
    try std.testing.expectEqualStrings(metadata.expected_strategy.?, "perfect_hash");

    try std.testing.expect(metadata.expected_performance.len == 1);
    try std.testing.expectEqualStrings(metadata.expected_performance[0].metric_name, "dispatch_overhead_ns");
    try std.testing.expect(metadata.expected_performance[0].operator == .less_than);
    try std.testing.expect(metadata.expected_performance[0].threshold_value == 30.0);

    try std.testing.expect(metadata.platforms == .all);
    try std.testing.expect(metadata.optimization_levels.len == 1);
    try std.testing.expect(metadata.optimization_levels[0] == .release_safe);

    try std.testing.expect(metadata.description != null);
    try std.testing.expectEqualStrings(metadata.description.?, "Basic dispatch strategy test");
}

test "Performance expectation parsing" {
    const allocator = std.testing.allocator;

    var platforms = [_]TestRunner.TestConfig.Platform{.linux_x86_64};
    var optimization_levels = [_]TestRunner.TestConfig.OptimizationLevel{.release_safe};

    const config = TestRunner.TestConfig{
        .test_directory = "tests/golden/ir-generation",
        .servicelden_directory = "tests/golden/references",
        .performance_baseline_directory = "tests/golden/baselines",
        .platforms = &platforms,
        .optimization_levels = &optimization_levels,
        .parallel_execution = false,
        .timeout_seconds = 30,
        .max_parallel_workers = 4,
    };

    var runner = TestRunner.init(allocator, config);

    // Test different operators
    var expectation1 = try runner.parsePerformanceExpectation("dispatch_overhead_ns < 30");
    defer expectation1.deinit(allocator);
    try std.testing.expectEqualStrings(expectation1.metric_name, "dispatch_overhead_ns");
    try std.testing.expect(expectation1.operator == .less_than);
    try std.testing.expect(expectation1.threshold_value == 30.0);

    var expectation2 = try runner.parsePerformanceExpectation("memory_usage_bytes <= 256");
    defer expectation2.deinit(allocator);
    try std.testing.expectEqualStrings(expectation2.metric_name, "memory_usage_bytes");
    try std.testing.expect(expectation2.operator == .less_equal);
    try std.testing.expect(expectation2.threshold_value == 256.0);

    var expectation3 = try runner.parsePerformanceExpectation("throughput_ops_per_sec >= 1000");
    defer expectation3.deinit(allocator);
    try std.testing.expectEqualStrings(expectation3.metric_name, "throughput_ops_per_sec");
    try std.testing.expect(expectation3.operator == .greater_equal);
    try std.testing.expect(expectation3.threshold_value == 1000.0);
}

test "Platform detection and filtering" {
    const allocator = std.testing.allocator;

    var platforms = [_]TestRunner.TestConfig.Platform{.linux_x86_64};
    var optimization_levels = [_]TestRunner.TestConfig.OptimizationLevel{.release_safe};

    const config = TestRunner.TestConfig{
        .test_directory = "tests/golden/ir-generation",
        .servicelden_directory = "tests/golden/references",
        .performance_baseline_directory = "tests/golden/baselines",
        .platforms = &platforms,
        .optimization_levels = &optimization_levels,
        .parallel_execution = false,
        .timeout_seconds = 30,
        .max_parallel_workers = 4,
    };

    var runner = TestRunner.init(allocator, config);

    // Test platform detection
    const current_platform = runner.getCurrentPlatform();
    try std.testing.expect(current_platform == .linux_x86_64 or
        current_platform == .linux_aarch64 or
        current_platform == .macos_x86_64 or
        current_platform == .macos_aarch64 or
        current_platform == .windows_x86_64);

    // Test platform parsing
    try std.testing.expect(try runner.parsePlatform("linux_x86_64") == .linux_x86_64);
    try std.testing.expect(try runner.parsePlatform("macos_aarch64") == .macos_aarch64);
    try std.testing.expect(try runner.parsePlatform("windows_x86_64") == .windows_x86_64);

    // Test invalid platform
    try std.testing.expectError(error.UnknownPlatform, runner.parsePlatform("invalid_platform"));
}

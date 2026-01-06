// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;

/// Advanced test metadata system for Golden Test Framework
/// Provides structured parsing, validation, and management of test case metadata
/// with support for complex performance expectations, platform requirements, and test dependencies
pub const TestMetadata = struct {
    allocator: Allocator,

    // Core test identificaon
    test_name: []const u8,
    description: ?[]const u8,
    author: ?[]const u8,
    created_date: ?[]const u8,

    // Dispatch strategy expectations
    expected_strategy: ?DispatchStrategy,
    fallback_strategies: []DispatchStrategy,

    // Performance requirements
    performance_expectations: []PerformanceExpectation,
    performance_profile: ?PerformanceProfile,

    // Platform and environment requirements
    platform_requirements: PlatformRequirements,
    optimization_requirements: OptimizationRequirements,

    // Test execution configuration
    execution_config: ExecutionConfig,

    // Test dependencies and relationships
    dependencies: []TestDependency,
    test_groups: [][]const u8,

    // Validation and quality assurance
    validation_rules: []ValidationRule,
    quality_gates: []QualityGate,

    const Self = @This();

    /// Dispatch strategy types that can be expected
    pub const DispatchStrategy = enum {
        static_dispatch,
        perfect_hash,
        switch_table,
        binary_search,
        linear_search,
        inline_cache,
        polymorphic_inline_cache,
        megamorphic_dispatch,

        pub fn toString(self: DispatchStrategy) []const u8 {
            return switch (self) {
                .static_dispatch => "static_dispatch",
                .perfect_hash => "perfect_hash",
                .switch_table => "switch_table",
                .binary_search => "binary_search",
                .linear_search => "linear_search",
                .inline_cache => "inline_cache",
                .polymorphic_inline_cache => "polymorphic_i_cache",
                .megamorphic_dispatch => "megamorphic_dispatch",
            };
        }

        pub fn fromString(str: []const u8) !DispatchStrategy {
            if (std.mem.eql(u8, str, "static_dispatch")) return .static_dispatch;
            if (std.mem.eql(u8, str, "perfect_hash")) return .perfect_hash;
            if (std.mem.eql(u8, str, "switch_table")) return .switch_table;
            if (std.mem.eql(u8, str, "binary_search")) return .binary_search;
            if (std.mem.eql(u8, str, "linear_search")) return .linear_search;
            if (std.mem.eql(u8, str, "inline_cache")) return .inline_cache;
            if (std.mem.eql(u8, str, "polymorphic_inline_cache")) return .polymorphic_inline_cache;
            if (std.mem.eql(u8, str, "megamorphic_dispatch")) return .megamorphic_dispatch;
            return error.UnknownDispatchStrategy;
        }
    };

    /// Performance expectation with metric, operator, and threshold
    pub const PerformanceExpectation = struct {
        metric: PerformanceMetric,
        operator: ComparisonOperator,
        threshold: f64,
        unit: []const u8,
        tolerance: ?f64, // Allowed variance percentage
        confidence_level: f64, // Statistical confidence required (0.0-1.0)

        pub const PerformanceMetric = enum {
            dispatch_overhead_ns,
            memory_usage_bytes,
            code_size_bytes,
            cache_hit_ratio,
            branch_prediction_accuracy,
            instruction_count,
            cycles_per_dispatch,
            throughput_ops_per_sec,
            latency_percentile_95,
            latency_percentile_99,

            pub fn toString(self: PerformanceMetric) []const u8 {
                return switch (self) {
                    .dispatch_overhead_ns => "dispatch_overhead_ns",
                    .memory_usage_bytes => "memory_usage_bytes",
                    .code_size_bytes => "code_size_bytes",
                    .cache_hit_ratio => "cache_hit_ratio",
                    .branch_prediction_accuracy => "branch_prediction_accuracy",
                    .instruction_count => "instruction_count",
                    .cycles_per_dispatch => "cycles_per_dispatch",
                    .throughput_ops_per_sec => "throughput_ops_per_sec",
                    .latency_percentile_95 => "latency_percentile_95",
                    .latency_percentile_99 => "latency_percentile_99",
                };
            }

            pub fn fromString(str: []const u8) !PerformanceMetric {
                if (std.mem.eql(u8, str, "dispatch_overhead_ns")) return .dispatch_overhead_ns;
                if (std.mem.eql(u8, str, "memory_usage_bytes")) return .memory_usage_bytes;
                if (std.mem.eql(u8, str, "code_size_bytes")) return .code_size_bytes;
                if (std.mem.eql(u8, str, "cache_hit_ratio")) return .cache_hit_ratio;
                if (std.mem.eql(u8, str, "branch_prediction_accuracy")) return .branch_prediction_accuracy;
                if (std.mem.eql(u8, str, "instruction_count")) return .instruction_count;
                if (std.mem.eql(u8, str, "cycles_per_dispatch")) return .cycles_per_dispatch;
                if (std.mem.eql(u8, str, "throughput_ops_per_sec")) return .throughput_ops_per_sec;
                if (std.mem.eql(u8, str, "latency_percentile_95")) return .latency_percentile_95;
                if (std.mem.eql(u8, str, "latency_percentile_99")) return .latency_percentile_99;
                return error.UnknownPerformanceMetric;
            }
        };

        pub const ComparisonOperator = enum {
            less_than,
            less_equal,
            greater_than,
            greater_equal,
            approximately,
            within_range,

            pub fn toString(self: ComparisonOperator) []const u8 {
                return switch (self) {
                    .less_than => "<",
                    .less_equal => "<=",
                    .greater_than => ">",
                    .greater_equal => ">=",
                    .approximately => "~=",
                    .within_range => "±",
                };
            }
        };

        pub fn deinit(self: *PerformanceExpectation, allocator: Allocator) void {
            allocator.free(self.unit);
        }
    };

    /// Performance profile for comprehensive performance characterization
    pub const PerformanceProfile = struct {
        profile_name: []const u8,
        target_architecture: []const u8,
        expected_complexity: ComplexityClass,
        scaling_behavior: ScalingBehavior,
        resource_requirements: ResourceRequirements,

        pub const ComplexityClass = enum {
            constant, // O(1)
            logarithmic, // O(log n)
            linear, // O(n)
            linearithmic, // O(n log n)
            quadratic, // O(n²)

            pub fn toString(self: ComplexityClass) []const u8 {
                return switch (self) {
                    .constant => "O(1)",
                    .logarithmic => "O(log n)",
                    .linear => "O(n)",
                    .linearithmic => "O(n log n)",
                    .quadratic => "O(n²)",
                };
            }
        };

        pub const ScalingBehavior = struct {
            input_size_factor: []const u8, // What drives scaling (implementations, call sites, etc.)
            expected_slope: f64, // Expected performance change per unit increase
            measurement_points: []u32, // Input sizes to test
        };

        pub const ResourceRequirements = struct {
            max_memory_mb: u32,
            max_cpu_cores: u32,
            requires_hardware_counters: bool,
            min_cache_size_kb: u32,
        };

        pub fn deinit(self: *PerformanceProfile, allocator: Allocator) void {
            allocator.free(self.profile_name);
            allocator.free(self.target_architecture);
            allocator.free(self.scaling_behavior.input_size_factor);
            allocator.free(self.scaling_behavior.measurement_points);
        }
    };

    /// Platform requirements and constraints
    pub const PlatformRequirements = struct {
        supported_platforms: []Platform,
        excluded_platforms: []Platform,
        minimum_versions: []PlatformVersion,
        architecture_specific: []ArchitectureRequirement,

        pub const Platform = enum {
            linux_x86_64,
            linux_aarch64,
            macos_x86_64,
            macos_aarch64,
            windows_x86_64,
            freebsd_x86_64,

            pub fn toString(self: Platform) []const u8 {
                return switch (self) {
                    .linux_x86_64 => "linux_x86_64",
                    .linux_aarch64 => "linux_aarch64",
                    .macos_x86_64 => "macos_x86_64",
                    .macos_aarch64 => "macos_aarch64",
                    .windows_x86_64 => "windows_x86_64",
                    .freebsd_x86_64 => "freebsd_x86_64",
                };
            }
        };

        pub const PlatformVersion = struct {
            platform: Platform,
            minimum_version: []const u8,
            reason: []const u8,
        };

        pub const ArchitectureRequirement = struct {
            architecture: []const u8,
            required_features: [][]const u8, // CPU features like AVX2, NEON, etc.
            performance_adjustments: []PerformanceAdjustment,
        };

        pub const PerformanceAdjustment = struct {
            metric: PerformanceExpectation.PerformanceMetric,
            adjustment_factor: f64, // Multiplier for threshold on this architecture
            reason: []const u8,
        };

        pub fn deinit(self: *PlatformRequirements, allocator: Allocator) void {
            allocator.free(self.supported_platforms);
            allocator.free(self.excluded_platforms);

            for (self.coreimum_versions) |*version| {
                allocator.free(version.coreimum_version);
                allocator.free(version.reason);
            }
            allocator.free(self.coreimum_versions);

            for (self.architecture_specific) |*arch_req| {
                allocator.free(arch_req.architecture);
                for (arch_req.required_features) |feature| {
                    allocator.free(feature);
                }
                allocator.free(arch_req.required_features);

                for (arch_req.performance_adjustments) |*adj| {
                    allocator.free(adj.reason);
                }
                allocator.free(arch_req.performance_adjustments);
            }
            allocator.free(self.architecture_specific);
        }
    };

    /// Optimization level requirements and constraints
    pub const OptimizationRequirements = struct {
        required_levels: []OptimizationLevel,
        excluded_levels: []OptimizationLevel,
        level_specific_expectations: []LevelSpecificExpectation,

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

        pub const LevelSpecificExpectation = struct {
            level: OptimizationLevel,
            performance_multiplier: f64, // Expected performance relative to release_safe
            additional_expectations: []PerformanceExpectation,
        };

        pub fn deinit(self: *OptimizationRequirements, allocator: Allocator) void {
            allocator.free(self.required_levels);
            allocator.free(self.excluded_levels);

            for (self.level_specific_expectations) |*expectation| {
                for (expectation.additional_expectations) |*perf| {
                    perf.deinit(allocator);
                }
                allocator.free(expectation.additional_expectations);
            }
            allocator.free(self.level_specific_expectations);
        }
    };

    /// Test execution configuration
    pub const ExecutionConfig = struct {
        timeout_seconds: u32,
        max_retries: u32,
        parallel_execution: bool,
        requires_isolation: bool,
        setup_commands: [][]const u8,
        cleanup_commands: [][]const u8,
        environment_variables: []EnvironmentVariable,

        pub const EnvironmentVariable = struct {
            name: []const u8,
            value: []const u8,
        };

        pub fn deinit(self: *ExecutionConfig, allocator: Allocator) void {
            for (self.setup_commands) |cmd| {
                allocator.free(cmd);
            }
            allocator.free(self.setup_commands);

            for (self.cleanup_commands) |cmd| {
                allocator.free(cmd);
            }
            allocator.free(self.cleanup_commands);

            for (self.environment_variables) |*env_var| {
                allocator.free(env_var.name);
                allocator.free(env_var.value);
            }
            allocator.free(self.environment_variables);
        }
    };

    /// Test dependency specification
    pub const TestDependency = struct {
        dependency_type: DependencyType,
        target_test: []const u8,
        relationship: DependencyRelationship,

        pub const DependencyType = enum {
            requires_success, // This test requires another to pass
            requires_failure, // This test requires another to fail
            setup_dependency, // Another test sets up state for this one
            data_dependency, // This test uses data generated by another
        };

        pub const DependencyRelationship = enum {
            before, // Dependency must run before this test
            after, // Dependency must run after this test
            concurrent, // Dependency can run concurrently
        };

        pub fn deinit(self: *TestDependency, allocator: Allocator) void {
            allocator.free(self.target_test);
        }
    };

    /// Validation rule for test correctness
    pub const ValidationRule = struct {
        rule_type: RuleType,
        description: []const u8,
        validation_function: []const u8, // Name of validation function to call
        parameters: []ValidationParameter,

        pub const RuleType = enum {
            ir_structure, // Validate IR structure and correctness
            performance_bounds, // Validate performance is within bounds
            memory_safety, // Validate memory safety properties
            determinism, // Validate deterministic behavior
            cross_platform, // Validate cross-platform consistency
        };

        pub const ValidationParameter = struct {
            name: []const u8,
            value: []const u8,
        };

        pub fn deinit(self: *ValidationRule, allocator: Allocator) void {
            allocator.free(self.description);
            allocator.free(self.validation_function);

            for (self.parameters) |*param| {
                allocator.free(param.name);
                allocator.free(param.value);
            }
            allocator.free(self.parameters);
        }
    };

    /// Quality gate for test acceptance
    pub const QualityGate = struct {
        gate_name: []const u8,
        gate_type: GateType,
        threshold: f64,
        measurement_window: u32, // Number of recent runs to consider

        pub const GateType = enum {
            success_rate, // Percentage of successful runs
            performance_stability, // Coefficient of variation in performance
            regression_detection, // Maximum allowed performance regression
            coverage_requirement, // Minimum code coverage percentage
        };

        pub fn deinit(self: *QualityGate, allocator: Allocator) void {
            allocator.free(self.gate_name);
        }
    };

    /// Initialize empty metadata
    pub fn init(allocator: Allocator, test_name: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .test_name = try allocator.dupe(u8, test_name),
            .description = null,
            .author = null,
            .created_date = null,
            .expected_strategy = null,
            .fallback_strategies = &.{},
            .performance_expectations = &.{},
            .performance_profile = null,
            .platform_requirements = PlatformRequirements{
                .supported_platforms = &.{},
                .excluded_platforms = &.{},
                .coreimum_versions = &.{},
                .architecture_specific = &.{},
            },
            .optimization_requirements = OptimizationRequirements{
                .required_levels = &.{},
                .excluded_levels = &.{},
                .level_specific_expectations = &.{},
            },
            .execution_config = ExecutionConfig{
                .timeout_seconds = 30,
                .max_retries = 0,
                .parallel_execution = true,
                .requires_isolation = false,
                .setup_commands = &.{},
                .cleanup_commands = &.{},
                .environment_variables = &.{},
            },
            .dependencies = &.{},
            .test_groups = &.{},
            .validation_rules = &.{},
            .quality_gates = &.{},
        };
    }

    /// Clean up all allocated memory
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.test_name);

        if (self.description) |desc| {
            self.allocator.free(desc);
        }

        if (self.author) |author| {
            self.allocator.free(author);
        }

        if (self.created_date) |date| {
            self.allocator.free(date);
        }

        self.allocator.free(self.fallback_strategies);

        for (self.performance_expectations) |*expectation| {
            expectation.deinit(self.allocator);
        }
        self.allocator.free(self.performance_expectations);

        if (self.performance_profile) |*profile| {
            profile.deinit(self.allocator);
        }

        self.platform_requirements.deinit(self.allocator);
        self.optimization_requirements.deinit(self.allocator);
        self.execution_config.deinit(self.allocator);

        for (self.dependencies) |*dep| {
            dep.deinit(self.allocator);
        }
        self.allocator.free(self.dependencies);

        for (self.test_groups) |group| {
            self.allocator.free(group);
        }
        self.allocator.free(self.test_groups);

        for (self.validation_rules) |*rule| {
            rule.deinit(self.allocator);
        }
        self.allocator.free(self.validation_rules);

        for (self.quality_gates) |*gate| {
            gate.deinit(self.allocator);
        }
        self.allocator.free(self.quality_gates);
    }
};

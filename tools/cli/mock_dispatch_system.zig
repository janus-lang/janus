// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Mock implementations for testing CLI tools without full compiler dependency

const std = @import("std");
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;

// Mock DispatchFamily
pub const DispatchFamily = struct {
    name: []const u8,
    arity: u32,
    implementations: ArrayList(Implementation),
    strategy: DispatchStrategy,
    is_static_resolvable: bool,
    ambiguity_count: u32,

    const Self = @This();

    pub const Implementation = struct {
        name: []const u8,
        parameter_types: []const []const u8,
        return_type: []const u8,
        specificity_rank: u32,
        is_reachable: bool,
        source_file: []const u8,
        source_line: u32,
        source_column: u32,
        unreachable_reason: []const u8,
    };

    pub const DispatchStrategy = enum {
        switch_table,
        perfect_hash,
        inline_cache,
    };

    pub fn init(allocator: Allocator, name: []const u8) !Self {
        return Self{
            .name = name,
            .arity = 0,
            .implementations = .empty,
            .strategy = .switch_table,
            .is_static_resolvable = false,
            .ambiguity_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.implementations.deinit();
    }

    pub fn addImplementation(self: *Self, impl: Implementation) !void {
        try self.implementations.append(impl);
        if (self.implementations.items.len > 0) {
            self.arity = @intCast(impl.parameter_types.len);
        }
    }
};

// Mock DispatchTableOptimizer
pub const DispatchTableOptimizer = struct {
    allocator: Allocator,

    const Self = @This();

    pub const IRResult = struct {
        ir_code: []const u8,
        strategy: DispatchFamily.DispatchStrategy,
        estimated_cycles: u32,
        memory_overhead: u32,
        cache_efficiency: []const u8,
        optimizations: []Optimization,

        pub const Optimization = struct {
            name: []const u8,
            description: []const u8,
        };

        pub fn deinit(self: *IRResult) void {
            // Mock deinit
            _ = self;
        }
    };

    pub const PerformanceAnalysis = struct {
        dispatch_overhead_ns: u64,
        memory_usage_bytes: u64,
        cache_miss_percentage: u32,
        has_hot_path_optimization: bool,
        bottlenecks: []Bottleneck,
        recommendations: [][]const u8,

        pub const Bottleneck = struct {
            location: []const u8,
            description: []const u8,
        };

        pub fn deinit(self: *PerformanceAnalysis) void {
            // Mock deinit
            _ = self;
        }
    };

    pub const StrategyInfo = struct {
        strategy: DispatchFamily.DispatchStrategy,
        selection_reason: []const u8,
        has_fallback: bool,
        perfect_hash: PerfectHashInfo,
        inline_cache: InlineCacheInfo,
        switch_table: SwitchTableInfo,

        pub const PerfectHashInfo = struct {
            hash_function: []const u8,
            table_size: u32,
            load_factor: f64,
        };

        pub const InlineCacheInfo = struct {
            cache_size: u32,
            hit_rate: f64,
            eviction_policy: []const u8,
        };

        pub const SwitchTableInfo = struct {
            entry_count: u32,
            uses_jump_table: bool,
        };

        pub fn deinit(self: *StrategyInfo) void {
            // Mock deinit
            _ = self;
        }
    };

    pub fn init(allocator: Allocator) !*Self {
        const optimizer = try allocator.create(Self);
        optimizer.* = Self{
            .allocator = allocator,
        };
        return optimizer;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn generateDispatchIR(self: *Self, family: *DispatchFamily) !IRResult {
        _ = self;

        const mock_ir =
            \\define i32 @dispatch_add_optimized(%TypeId* %arg_types, i8** %args) {
            \\entry:
            \\  %hash = call i64 @perfect_hash_lookup(%TypeId* %arg_types, i32 2)
            \\  %impl_ptr = getelementptr [8 x i8*], [8 x i8*]* @add_dispatch_table, i64 0, i64 %hash
            \\  %impl = load i8*, i8** %impl_ptr
            \\  %result = call i32 %impl(i8** %args)
            \\  ret i32 %result
            \\}
        ;

        return IRResult{
            .ir_code = mock_ir,
            .strategy = family.strategy,
            .estimated_cycles = 12,
            .memory_overhead = 64,
            .cache_efficiency = "excellent",
            .optimizations = @constCast(&[_]IRResult.Optimization{
                .{ .name = "Perfect Hash Generation", .description = "CHD algorithm with 1.2x space efficiency" },
                .{ .name = "Cache-Friendly Layout", .description = "Sequential memory access pattern" },
            }),
        };
    }

    pub fn analyzePerformance(self: *Self, family: *DispatchFamily) !PerformanceAnalysis {
        _ = self;
        _ = family;

        return PerformanceAnalysis{
            .dispatch_overhead_ns = 67,
            .memory_usage_bytes = 256,
            .cache_miss_percentage = 5,
            .has_hot_path_optimization = true,
            .bottlenecks = &[_]PerformanceAnalysis.Bottleneck{},
            .recommendations = &[_][]const u8{
                "Consider using inline cache for hot paths",
                "Reduce parameter count for better cache efficiency",
            },
        };
    }

    pub fn getStrategyInfo(self: *Self, family: *DispatchFamily) !StrategyInfo {
        _ = self;

        return StrategyInfo{
            .strategy = family.strategy,
            .selection_reason = "Large overload set with simple types",
            .has_fallback = true,
            .perfect_hash = .{
                .hash_function = "CHD",
                .table_size = 8,
                .load_factor = 0.75,
            },
            .inline_cache = .{
                .cache_size = 4,
                .hit_rate = 0.95,
                .eviction_policy = "LRU",
            },
            .switch_table = .{
                .entry_count = 3,
                .uses_jump_table = true,
            },
        };
    }
};

// Mock RuntimeDispatch
pub const RuntimeDispatch = struct {
    // Mock implementation for testing
};

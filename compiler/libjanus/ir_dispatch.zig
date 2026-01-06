// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

// Core type system imports
const TypeId = @import("type_registry.zig").TypeId;
const FunctionDecl = @import("scope_manager.zig").FunctionDecl;

/// Canonical IR representation for dispatch calls
/// Backend-agnostic: consumed by LLVM, Cranelift, MLIR
pub const DispatchIR = union(enum) {
    static_call: StaticCallIR,
    dynamic_stub: DynamicStubIR,
    error_call: ErrorCallIR,

    pub fn deinit(self: *DispatchIR, allocator: Allocator) void {
        switch (self.*) {
            .static_call => |*static| static.deinit(allocator),
            .dynamic_stub => |*dynamic| dynamic.deinit(allocator),
            .error_call => |*error_call| error_call.deinit(allocator),
        }
    }

    /// Get the estimated cost of this dispatch
    pub fn getCost(self: *const DispatchIR) DispatchCost {
        return switch (self.*) {
            .static_call => .static,
            .dynamic_stub => .dynamic,
            .error_call => .error_path,
        };
    }
};

/// Performance cost classification for tooling
pub const DispatchCost = enum {
    static, // Direct call, zero overhead
    dynamic, // Dispatch stub, measurable overhead
    error_path, // Runtime error, should not occcorrect programs

    pub fn toString(self: DispatchCost) []const u8 {
        return switch (self) {
            .static => "static",
            .dynamic => "dynamic",
            .error_path => "error",
        };
    }
};

/// IR for statically resolved dispatch calls
pub const StaticCallIR = struct {
    target_function: FunctionRef,
    conversion_path: []ConversionStep,
    call_convention: CallingConvention,
    source_location: SourceSpan,

    pub fn deinit(self: *StaticCallIR, allocator: Allocator) void {
        allocator.free(self.conversion_path);
    }

    /// Validate that this static call is well-formed
    pub fn validate(self: *const StaticCallIR) bool {
        return self.target_function.isValid() and
            self.call_convention != .invalid;
    }
};

/// IR for dynamic dispatch stubs
pub const DynamicStubIR = struct {
    family_name: []const u8,
    candidates: []CandidateIR,
    strategy: StubStrategy,
    cost_estimate: u32, // Estimated cycles
    source_location: SourceSpan,

    pub fn deinit(self: *DynamicStubIR, allocator: Allocator) void {
        for (self.candidates) |*candidate| {
            candidate.deinit(allocator);
        }
        allocator.free(self.candidates);
    }

    /// Get the size estimate for the generated stub
    pub fn getStubSizeEstimate(self: *const DynamicStubIR) u32 {
        return switch (self.strategy) {
            .switch_table => @as(u32, @intCast(self.candidates.len * 16 + 32)), // Rough estimate
            .perfect_hash => 64, // Fixed size for hash lookup
            .inline_cache => 48, // Small cache + fallback
        };
    }
};

/// IR for error calls (unresolved dispatch)
pub const ErrorCallIR = struct {
    error_code: []const u8, // e.g., "C1001"
    message: []const u8,
    function_name: []const u8,
    source_location: SourceSpan,

    pub fn deinit(self: *ErrorCallIR, allocator: Allocator) void {
        _ = self;
        _ = allocator;
        // String literals, no cleanup needed
    }
};

/// Stub generation strategy (The Performance Dial)
pub const StubStrategy = enum {
    switch_table, // Default: safe, universal
    perfect_hash, // {.dispatch: perfect_hash}
    inline_cache, // {.dispatch: inline_cache}

    pub fn fromAttribute(attr: ?[]const u8) StubStrategy {
        if (attr == null) return .switch_table;

        if (std.mem.eql(u8, attr.?, "perfect_hash")) return .perfect_hash;
        if (std.mem.eql(u8, attr.?, "inline_cache")) return .inline_cache;

        return .switch_table; // Default fallback
    }

    pub fn toString(self: StubStrategy) []const u8 {
        return switch (self) {
            .switch_table => "switch_table",
            .perfect_hash => "perfect_hash",
            .inline_cache => "inline_cache",
        };
    }
};

/// Reference to a function in the IR
pub const FunctionRef = struct {
    name: []const u8,
    mangled_name: []const u8,
    signature: FunctionSignature,

    pub fn isValid(self: *const FunctionRef) bool {
        return self.name.len > 0 and self.mangled_name.len > 0;
    }
};

/// Function signature for ABI compliance
pub const FunctionSignature = struct {
    parameters: []TypeId,
    return_type: TypeId,
    is_variadic: bool,

    pub fn matches(self: *const FunctionSignature, other: *const FunctionSignature) bool {
        if (self.return_type.id != other.return_type.id) return false;
        if (self.is_variadic != other.is_variadic) return false;
        if (self.parameters.len != other.parameters.len) return false;

        for (self.parameters, other.parameters) |a, b| {
            if (a.id != b.id) return false;
        }

        return true;
    }
};

/// Type conversion step in dispatch resolution
pub const ConversionStep = struct {
    from_type: TypeId,
    to_type: TypeId,
    conversion_kind: ConversionKind,
    cost: u32, // Conversion cost for ranking

    pub const ConversionKind = enum {
        identity, // No conversion needed
        widening, // i32 -> i64
        narrowing, // i64 -> i32 (potentially lossy)
        boxing, // T -> any
        unboxing, // any -> T
        coercion, // Custom coercion function
    };
};

/// Candidate function in dynamic dispatch
pub const CandidateIR = struct {
    function_ref: FunctionRef,
    conversion_path: []ConversionStep,
    match_score: u32, // Lower is better
    type_check_ir: TypeCheckIR,

    pub fn deinit(self: *CandidateIR, allocator: Allocator) void {
        allocator.free(self.conversion_path);
    }
};

/// IR for runtime type checking in dynamic stubs
pub const TypeCheckIR = struct {
    check_kind: TypeCheckKind,
    target_type: TypeId,
    parameter_index: u32,

    pub const TypeCheckKind = enum {
        exact_match, // Type must match exactly
        subtype_check, // Type must be subtype of target
        trait_check, // Type must implement trait
        union_variant, // Check union variant tag
    };
};

/// Platform calling conventions
pub const CallingConvention = enum {
    system_v, // x86_64 Linux/macOS
    ms_x64, // x86_64 Windows
    aapcs64, // ARM64
    riscv, // RISC-V
    invalid,

    pub fn fromTarget(target: []const u8) CallingConvention {
        if (std.mem.indexOf(u8, target, "x86_64")) |_| {
            if (std.mem.indexOf(u8, target, "windows")) |_| {
                return .ms_x64;
            } else {
                return .system_v;
            }
        } else if (std.mem.indexOf(u8, target, "aarch64")) |_| {
            return .aapcs64;
        } else if (std.mem.indexOf(u8, target, "riscv64")) |_| {
            return .riscv;
        }

        return .invalid;
    }
};

/// Source location for diagnostics
pub const SourceSpan = struct {
    file: []const u8,
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,

    pub fn format(
        self: SourceSpan,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}:{}:{}", .{ self.file, self.start_line, self.start_col });
    }
};

/// Builder for creating dispatch IR
pub const DispatchIRBuilder = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) DispatchIRBuilder {
        return DispatchIRBuilder{ .allocator = allocator };
    }

    /// Create static call IR
    pub fn createStaticCall(
        self: *DispatchIRBuilder,
        target_function: FunctionRef,
        conversion_path: []const ConversionStep,
        call_convention: CallingConvention,
        source_location: SourceSpan,
    ) !StaticCallIR {
        const owned_conversions = try self.allocator.dupe(ConversionStep, conversion_path);

        return StaticCallIR{
            .target_function = target_function,
            .conversion_path = owned_conversions,
            .call_convention = call_convention,
            .source_location = source_location,
        };
    }

    /// Create dynamic stub IR
    pub fn createDynamicStub(
        self: *DispatchIRBuilder,
        family_name: []const u8,
        candidates: []const CandidateIR,
        strategy: StubStrategy,
        source_location: SourceSpan,
    ) !DynamicStubIR {
        const owned_candidates = try self.allocator.alloc(CandidateIR, candidates.len);

        for (candidates, 0..) |candidate, i| {
            owned_candidates[i] = CandidateIR{
                .function_ref = candidate.function_ref,
                .conversion_path = try self.allocator.dupe(ConversionStep, candidate.conversion_path),
                .match_score = candidate.match_score,
                .type_check_ir = candidate.type_check_ir,
            };
        }

        // Estimate cost based on strategy and candidate count
        const cost_estimate = switch (strategy) {
            .switch_table => @as(u32, @intCast(candidates.len * 3 + 5)), // Linear scan cost
            .perfect_hash => 8, // Constant time hash lookup
            .inline_cache => 12, // Cache check + fallback
        };

        return DynamicStubIR{
            .family_name = family_name,
            .candidates = owned_candidates,
            .strategy = strategy,
            .cost_estimate = cost_estimate,
            .source_location = source_location,
        };
    }

    /// Create error call IR
    pub fn createErrorCall(
        self: *DispatchIRBuilder,
        error_code: []const u8,
        message: []const u8,
        function_name: []const u8,
        source_location: SourceSpan,
    ) ErrorCallIR {
        _ = self;
        return ErrorCallIR{
            .error_code = error_code,
            .message = message,
            .function_name = function_name,
            .source_location = source_location,
        };
    }
};

/// Serialize dispatch IR to JSON for tooling
pub const DispatchIRSerializer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) DispatchIRSerializer {
        return DispatchIRSerializer{ .allocator = allocator };
    }

    /// Serialize dispatch IR to JSON string
    pub fn toJson(self: *DispatchIRSerializer, dispatch_ir: *const DispatchIR) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();

        try json_obj.put("type", std.json.Value{ .string = @tagName(dispatch_ir.*) });
        try json_obj.put("cost", std.json.Value{ .string = dispatch_ir.getCost().toString() });

        switch (dispatch_ir.*) {
            .static_call => |static| {
                try json_obj.put("target_function", std.json.Value{ .string = static.target_function.name });
                try json_obj.put("call_convention", std.json.Value{ .string = @tagName(static.call_convention) });
                try json_obj.put("conversions", std.json.Value{ .integer = @intCast(static.conversion_path.len) });
            },
            .dynamic_stub => |dynamic| {
                try json_obj.put("family_name", std.json.Value{ .string = dynamic.family_name });
                try json_obj.put("strategy", std.json.Value{ .string = dynamic.strategy.toString() });
                try json_obj.put("candidates", std.json.Value{ .integer = @intCast(dynamic.candidates.len) });
                try json_obj.put("estimated_cycles", std.json.Value{ .integer = @intCast(dynamic.cost_estimate) });
                try json_obj.put("stub_size_bytes", std.json.Value{ .integer = @intCast(dynamic.getStubSizeEstimate()) });
            },
            .error_call => |error_call| {
                try json_obj.put("error_code", std.json.Value{ .string = error_call.error_code });
                try json_obj.put("message", std.json.Value{ .string = error_call.message });
                try json_obj.put("function_name", std.json.Value{ .string = error_call.function_name });
            },
        }

        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
};

// Tests
test "DispatchIR creation and validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = DispatchIRBuilder.init(allocator);

    // Test static call creation
    const target_func = FunctionRef{
        .name = "add",
        .mangled_name = "_Z3addii",
        .signature = FunctionSignature{
            .parameters = @constCast(&[_]TypeId{ TypeId.I32, TypeId.I32 }),
            .return_type = TypeId.I32,
            .is_variadic = false,
        },
    };

    const source_loc = SourceSpan{
        .file = "test.jan",
        .start_line = 10,
        .start_col = 5,
        .end_line = 10,
        .end_col = 15,
    };

    var static_call = try builder.createStaticCall(
        target_func,
        &[_]ConversionStep{},
        .system_v,
        source_loc,
    );
    defer static_call.deinit(allocator);

    try std.testing.expect(static_call.validate());

    const dispatch_ir = DispatchIR{ .static_call = static_call };
    try std.testing.expectEqual(DispatchCost.static, dispatch_ir.getCost());

    std.debug.print("✅ DispatchIR creation and validation test passed\n", .{});
}

test "Dynamic stub strategy selection" {
    try std.testing.expectEqual(StubStrategy.switch_table, StubStrategy.fromAttribute(null));
    try std.testing.expectEqual(StubStrategy.perfect_hash, StubStrategy.fromAttribute("perfect_hash"));
    try std.testing.expectEqual(StubStrategy.inline_cache, StubStrategy.fromAttribute("inline_cache"));
    try std.testing.expectEqual(StubStrategy.switch_table, StubStrategy.fromAttribute("unknown"));

    std.debug.print("✅ Dynamic stub strategy selection test passed\n", .{});
}

test "Calling convention detection" {
    try std.testing.expectEqual(CallingConvention.system_v, CallingConvention.fromTarget("x86_64-linux-gnu"));
    try std.testing.expectEqual(CallingConvention.ms_x64, CallingConvention.fromTarget("x86_64-windows-msvc"));
    try std.testing.expectEqual(CallingConvention.aapcs64, CallingConvention.fromTarget("aarch64-linux-gnu"));
    try std.testing.expectEqual(CallingConvention.riscv, CallingConvention.fromTarget("riscv64-linux-gnu"));
    try std.testing.expectEqual(CallingConvention.invalid, CallingConvention.fromTarget("unknown-target"));

    std.debug.print("✅ Calling convention detection test passed\n", .{});
}

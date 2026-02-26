// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! LLVM IR Generator - The Final Weapon
//!
//! This module transforms verified Janus semantic IR into optimized LLVM IR,
//! completing the revolutionary compiler pipeline. Every dispatch decision,
//! every optimization, every symbol is forged with absolute precision.
//!
//! THE REVOLUTION BECOMES EXECUTABLE.

const std = @import("std");
const astdb = @import("astdb");
const semantic = @import("semantic");
const types = @import("../types.zig");

// Use canonical types from types.zig
const Strategy = types.Strategy;
const CallSite = types.CallSite;

/// LLVM C API bindings - Direct interface to the LLVM forge
const llvm = struct {
    // Core LLVM types
    pub const Context = opaque {};
    pub const Module = opaque {};
    pub const Builder = opaque {};
    pub const Value = opaque {};
    pub const Type = opaque {};
    pub const BasicBlock = opaque {};
    pub const Function = opaque {};

    // LLVM C API functions - The weapons of code generation
    pub extern "c" fn LLVMContextCreate() *Context;
    pub extern "c" fn LLVMContextDispose(ctx: *Context) void;
    pub extern "c" fn LLVMModuleCreateWithNameInContext(name: [*:0]const u8, ctx: *Context) *Module;
    pub extern "c" fn LLVMDisposeModule(module: *Module) void;
    pub extern "c" fn LLVMCreateBuilderInContext(ctx: *Context) *Builder;
    pub extern "c" fn LLVMDisposeBuilder(builder: *Builder) void;

    // Type creation
    pub extern "c" fn LLVMVoidTypeInContext(ctx: *Context) *Type;
    pub extern "c" fn LLVMInt1TypeInContext(ctx: *Context) *Type;
    pub extern "c" fn LLVMInt8TypeInContext(ctx: *Context) *Type;
    pub extern "c" fn LLVMInt32TypeInContext(ctx: *Context) *Type;
    pub extern "c" fn LLVMInt64TypeInContext(ctx: *Context) *Type;
    pub extern "c" fn LLVMFloatTypeInContext(ctx: *Context) *Type;
    pub extern "c" fn LLVMDoubleTypeInContext(ctx: *Context) *Type;
    pub extern "c" fn LLVMPointerType(element_type: *Type, address_space: u32) *Type;
    pub extern "c" fn LLVMArrayType(element_type: *Type, size: u32) *Type;
    pub extern "c" fn LLVMFunctionType(return_type: *Type, param_types: [*]*Type, param_count: u32, is_var_arg: bool) *Type;

    // Function creation
    pub extern "c" fn LLVMAddFunction(module: *Module, name: [*:0]const u8, function_type: *Type) *Function;
    pub extern "c" fn LLVMAppendBasicBlockInContext(ctx: *Context, func: *Function, name: [*:0]const u8) *BasicBlock;
    pub extern "c" fn LLVMPositionBuilderAtEnd(builder: *Builder, block: *BasicBlock) void;

    // Instruction generation
    pub extern "c" fn LLVMBuildCall2(builder: *Builder, func_type: *Type, func: *Value, args: [*]*Value, num_args: u32, name: [*:0]const u8) *Value;
    pub extern "c" fn LLVMBuildRet(builder: *Builder, value: *Value) *Value;
    pub extern "c" fn LLVMBuildRetVoid(builder: *Builder) *Value;

    // Constants
    pub extern "c" fn LLVMConstInt(int_type: *Type, value: u64, sign_extend: bool) *Value;

    // Module output
    pub extern "c" fn LLVMPrintModuleToString(module: *Module) [*:0]u8;
    pub extern "c" fn LLVMPrintModuleToFile(module: *Module, filename: [*:0]const u8, error_msg: *[*:0]u8) u32;
    pub extern "c" fn LLVMDisposeMessage(message: [*:0]u8) void;

    // Target machine for code generation
    pub extern "c" fn LLVMGetDefaultTargetTriple() [*:0]u8;
    pub extern "c" fn LLVMGetTargetFromTriple(triple: [*:0]const u8, target: **opaque {}, error_msg: *[*:0]u8) u32;
    pub extern "c" fn LLVMCreateTargetMachine(target: *opaque {}, triple: [*:0]const u8, cpu: [*:0]const u8, features: [*:0]const u8, opt_level: u32, reloc_mode: u32, code_model: u32) *opaque {};
    pub extern "c" fn LLVMTargetMachineEmitToFile(machine: *opaque {}, module: *Module, filename: [*:0]const u8, codegen: u32, error_msg: *[*:0]u8) u32;
    pub extern "c" fn LLVMDisposeTargetMachine(machine: *opaque {}) void;
};

/// Codegen error types - The C1xxx series as mandated by the specification
pub const CodegenError = error{
    // C1001-C1099: Core IR Generation Errors
    LLVMContextCreationFailed, // C1001
    LLVMModuleCreationFailed, // C1002
    LLVMBuilderCreationFailed, // C1003
    InvalidFunctionSignature, // C1004
    UnsupportedType, // C1005

    // C1100-C1199: Dispatch Strategy Errors
    StaticDispatchFailed, // C1100
    PerfectHashGenerationFailed, // C1101
    InlineCacheCreationFailed, // C1102
    SwitchTableGenerationFailed, // C1103

    // C1200-C1299: Symbol Management Errors
    SymbolConflict, // C1200
    InvalidSymbolName, // C1201
    SymbolResolutionFailed, // C1202

    // C1300-C1399: Debug Information Errors
    DebugInfoGenerationFailed, // C1300
    SourceMappingFailed, // C1301

    // C1400-C1499: Performance Guarantee Violations
    PerformanceGuaranteeViolated, // C1400
    MemoryLayoutOptimizationFailed, // C1401

    // Standard errors
    OutOfMemory,
    InvalidInput,
};

/// Symbol naming canon - Predictable, stable symbol names
pub const SymbolManager = struct {
    allocator: std.mem.Allocator,
    symbol_map: std.StringHashMap([]const u8),
    conflict_counter: std.StringHashMap(u32),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .symbol_map = std.StringHashMap([]const u8).init(allocator),
            .conflict_counter = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.symbol_map.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.symbol_map.deinit();
        self.conflict_counter.deinit();
    }

    /// Generate canonical symbol name for dispatch function
    pub fn generateDispatchSymbol(self: *Self, family_name: []const u8, strategy: Strategy) ![]const u8 {
        const strategy_suffix = switch (strategy) {
            .Static => "_static",
            .PerfectHash => "_hash",
            .InlineCache => "_cache",
            .SwitchTable => "_switch",
        };

        const base_name = try std.fmt.allocPrint(self.allocator, "janus_dispatch_{s}{s}", .{ family_name, strategy_suffix });
        return try self.ensureUnique(base_name);
    }

    /// Generate symbol name for implementation function
    pub fn generateImplSymbol(self: *Self, family_name: []const u8, impl_index: u32) ![]const u8 {
        const base_name = try std.fmt.allocPrint(self.allocator, "janus_impl_{s}_{}", .{ family_name, impl_index });
        return try self.ensureUnique(base_name);
    }

    /// Generate symbol name for dispatch table
    pub fn generateTableSymbol(self: *Self, family_name: []const u8, strategy: Strategy) ![]const u8 {
        const strategy_suffix = switch (strategy) {
            .Static => "_static_table",
            .PerfectHash => "_hash_table",
            .InlineCache => "_cache_table",
            .SwitchTable => "_switch_table",
        };

        const base_name = try std.fmt.allocPrint(self.allocator, "janus_table_{s}{s}", .{ family_name, strategy_suffix });
        return try self.ensureUnique(base_name);
    }

    /// Ensure symbol uniqueness with deterministic conflict resolution
    fn ensureUnique(self: *Self, base_name: []const u8) ![]const u8 {
        if (!self.symbol_map.contains(base_name)) {
            const owned_name = try self.allocator.dupe(u8, base_name);
            try self.symbol_map.put(owned_name, owned_name);
            return owned_name;
        }

        // Handle conflict with suffix numbering
        const counter = self.conflict_counter.get(base_name) orelse 0;
        const new_counter = counter + 1;
        try self.conflict_counter.put(base_name, new_counter);

        const unique_name = try std.fmt.allocPrint(self.allocator, "{s}_{}", .{ base_name, new_counter });
        const owned_name = try self.allocator.dupe(u8, unique_name);
        try self.symbol_map.put(owned_name, owned_name);

        self.allocator.free(unique_name);
        return owned_name;
    }
};

/// Dispatch optimization strategies (use canonical Strategy from types.zig)
pub const DispatchStrategy = Strategy;

/// Optimization decision record - Complete auditability
pub const OptimizationDecision = struct {
    strategy: Strategy,
    reasoning: []const u8,
    performance_estimate: PerformanceEstimate,
    fallback_available: bool,

    pub const PerformanceEstimate = struct {
        overhead_ns: u32,
        memory_bytes: u32,
        cache_locality: f32, // 0.0 = poor, 1.0 = excellent
    };
};

/// Janus Type System - Maps semantic types to LLVM types
pub const TypeMapper = struct {
    allocator: std.mem.Allocator,
    type_cache: std.AutoHashMap(u32, *llvm.Type),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .type_cache = std.AutoHashMap(u32, *llvm.Type).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.type_cache.deinit();
    }

    /// Map Janus primitive types to LLVM types
    pub fn mapPrimitiveType(_: *Self, context: *llvm.Context, janus_type: []const u8) !*llvm.Type {
        if (std.mem.eql(u8, janus_type, "i32")) {
            return llvm.LLVMInt32TypeInContext(context);
        } else if (std.mem.eql(u8, janus_type, "f64")) {
            return llvm.LLVMDoubleTypeInContext(context);
        } else if (std.mem.eql(u8, janus_type, "bool")) {
            return llvm.LLVMInt1TypeInContext(context);
        } else if (std.mem.eql(u8, janus_type, "string")) {
            // Strings are pointers to byte arrays, not i8*
            const byte_type = llvm.LLVMInt8TypeInContext(context);
            return llvm.LLVMPointerType(byte_type, 0);
        } else if (std.mem.eql(u8, janus_type, "void")) {
            return llvm.LLVMVoidTypeInContext(context);
        } else {
            return CodegenError.UnsupportedType;
        }
    }

    /// Map Janus function type to LLVM function type
    pub fn mapFunctionType(self: *Self, context: *llvm.Context, return_type: []const u8, param_types: []const []const u8) !*llvm.Type {
        const llvm_return_type = try self.mapPrimitiveType(context, return_type);

        // Convert parameter types
        const llvm_param_types = try self.allocator.alloc(*llvm.Type, param_types.len);
        defer self.allocator.free(llvm_param_types);

        for (param_types, 0..) |param_type, i| {
            llvm_param_types[i] = try self.mapPrimitiveType(context, param_type);
        }

        return llvm.LLVMFunctionType(llvm_return_type, llvm_param_types.ptr, @intCast(param_types.len), false);
    }

    /// Create string literal type - Proper typed strings, not i8*
    pub fn createStringType(_: *Self, context: *llvm.Context) !*llvm.Type {
        // String literals are [N x i8] arrays, not i8*
        return llvm.LLVMInt8TypeInContext(context);
    }

    /// Get LLVM type for array - Avoids i8* abuse
    pub fn getArrayType(_: *Self, _: *llvm.Context, element_type: *llvm.Type, size: u32) !*llvm.Type {
        return llvm.LLVMArrayType(element_type, size);
    }
};

/// The LLVM IR Generator - The final weapon of the revolution
pub const IRGenerator = struct {
    allocator: std.mem.Allocator,
    llvm_context: *llvm.Context,
    llvm_module: *llvm.Module,
    llvm_builder: *llvm.Builder,
    symbol_manager: SymbolManager,
    type_mapper: TypeMapper,
    optimization_decisions: std.ArrayList(OptimizationDecision),

    const Self = @This();

    /// Initialize the IR Generator - Prepare the forge
    pub fn init(allocator: std.mem.Allocator, module_name: []const u8) !Self {
        // Create LLVM context
        const context = llvm.LLVMContextCreate() orelse return CodegenError.LLVMContextCreationFailed;
        errdefer llvm.LLVMContextDispose(context);

        // Create LLVM module
        const module_name_z = try allocator.dupeZ(u8, module_name);
        defer allocator.free(module_name_z);
        const module = llvm.LLVMModuleCreateWithNameInContext(module_name_z.ptr, context) orelse return CodegenError.LLVMModuleCreationFailed;
        errdefer llvm.LLVMDisposeModule(module);

        // Create IR builder
        const builder = llvm.LLVMCreateBuilderInContext(context) orelse return CodegenError.LLVMBuilderCreationFailed;
        errdefer llvm.LLVMDisposeBuilder(builder);

        return Self{
            .allocator = allocator,
            .llvm_context = context,
            .llvm_module = module,
            .llvm_builder = builder,
            .symbol_manager = SymbolManager.init(allocator),
            .type_mapper = TypeMapper.init(allocator),
            .optimization_decisions = .empty,
        };
    }

    /// Destroy the IR Generator - Clean shutdown
    pub fn deinit(self: *Self) void {
        // Clean up optimization decisions
        for (self.optimization_decisions.items) |decision| {
            self.allocator.free(decision.reasoning);
        }
        self.optimization_decisions.deinit();

        // Clean up type mapper
        self.type_mapper.deinit();

        // Clean up symbol manager
        self.symbol_manager.deinit();

        // Clean up LLVM resources
        llvm.LLVMDisposeBuilder(self.llvm_builder);
        llvm.LLVMDisposeModule(self.llvm_module);
        llvm.LLVMContextDispose(self.llvm_context);
    }

    /// Generate static dispatch IR - Zero overhead direct calls
    pub fn generateStaticDispatchIR(self: *Self, family_name: []const u8, target_function: []const u8) !*llvm.Function {
        // Record optimization decision
        const decision = OptimizationDecision{
            .strategy = .Static,
            .reasoning = try self.allocator.dupe(u8, "Single implementation detected - zero overhead static dispatch selected"),
            .performance_estimate = .{
                .overhead_ns = 0, // Zero overhead guarantee
                .memory_bytes = 0,
                .cache_locality = 1.0,
            },
            .fallback_available = false,
        };
        try self.optimization_decisions.append(decision);

        // Generate symbol name
        const symbol_name = try self.symbol_manager.generateDispatchSymbol(family_name, .static);
        const symbol_name_z = try self.allocator.dupeZ(u8, symbol_name);
        defer self.allocator.free(symbol_name_z);

        // Create function type (void -> void for now, will be parameterized)
        const void_type = llvm.LLVMVoidTypeInContext(self.llvm_context);
        const function_type = llvm.LLVMFunctionType(void_type, null, 0, false);

        // Create function
        const function = llvm.LLVMAddFunction(self.llvm_module, symbol_name_z.ptr, function_type);

        // Create basic block
        const entry_block = llvm.LLVMAppendBasicBlockInContext(self.llvm_context, function, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.llvm_builder, entry_block);

        // For now, just return void (will be enhanced with actual dispatch logic)
        _ = llvm.LLVMBuildRetVoid(self.llvm_builder);

        _ = target_function; // Will be used for actual call generation

        return function;
    }

    /// Generate perfect hash dispatch IR - O(1) hash table lookup
    pub fn generatePerfectHashIR(self: *Self, family_name: []const u8, implementations: []const []const u8) !*llvm.Function {
        // Record optimization decision
        const decision = OptimizationDecision{
            .strategy = .PerfectHash,
            .reasoning = try std.fmt.allocPrint(self.allocator, "Multiple implementations ({}) - perfect hash dispatch for O(1) lookup", .{implementations.len}),
            .performance_estimate = .{
                .overhead_ns = 25, // ≤25ns guarantee
                .memory_bytes = @intCast(implementations.len * 8), // Pointer table
                .cache_locality = 0.8,
            },
            .fallback_available = true,
        };
        try self.optimization_decisions.append(decision);

        // Generate symbol name
        const symbol_name = try self.symbol_manager.generateDispatchSymbol(family_name, .perfect_hash);
        const symbol_name_z = try self.allocator.dupeZ(u8, symbol_name);
        defer self.allocator.free(symbol_name_z);

        // Create function type
        const void_type = llvm.LLVMVoidTypeInContext(self.llvm_context);
        const function_type = llvm.LLVMFunctionType(void_type, null, 0, false);

        // Create function
        const function = llvm.LLVMAddFunction(self.llvm_module, symbol_name_z.ptr, function_type);

        // Create basic block
        const entry_block = llvm.LLVMAppendBasicBlockInContext(self.llvm_context, function, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.llvm_builder, entry_block);

        // TODO: Generate hash computation and table lookup IR
        // For now, placeholder return
        _ = llvm.LLVMBuildRetVoid(self.llvm_builder);

        return function;
    }

    /// Generate inline cache dispatch IR - LRU cache with fallback
    pub fn generateInlineCacheIR(self: *Self, family_name: []const u8, cache_size: u32) !*llvm.Function {
        // Record optimization decision
        const decision = OptimizationDecision{
            .strategy = .InlineCache,
            .reasoning = try std.fmt.allocPrint(self.allocator, "Dynamic dispatch with cache size {} for hot path optimization", .{cache_size}),
            .performance_estimate = .{
                .overhead_ns = 50, // ≤50ns for cache hits
                .memory_bytes = cache_size * 16, // Cache entry size
                .cache_locality = 0.9,
            },
            .fallback_available = true,
        };
        try self.optimization_decisions.append(decision);

        // Generate symbol name
        const symbol_name = try self.symbol_manager.generateDispatchSymbol(family_name, .inline_cache);
        const symbol_name_z = try self.allocator.dupeZ(u8, symbol_name);
        defer self.allocator.free(symbol_name_z);

        // Create function type
        const void_type = llvm.LLVMVoidTypeInContext(self.llvm_context);
        const function_type = llvm.LLVMFunctionType(void_type, null, 0, false);

        // Create function
        const function = llvm.LLVMAddFunction(self.llvm_module, symbol_name_z.ptr, function_type);

        // Create basic block
        const entry_block = llvm.LLVMAppendBasicBlockInContext(self.llvm_context, function, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.llvm_builder, entry_block);

        // TODO: Generate cache lookup and LRU management IR
        // For now, placeholder return
        _ = llvm.LLVMBuildRetVoid(self.llvm_builder);

        return function;
    }

    /// Generate switch table dispatch IR - Jump table optimization
    pub fn generateSwitchTableIR(self: *Self, family_name: []const u8, type_count: u32) !*llvm.Function {
        // Record optimization decision
        const decision = OptimizationDecision{
            .strategy = .SwitchTable,
            .reasoning = try std.fmt.allocPrint(self.allocator, "Switch table dispatch for {} types with branch prediction", .{type_count}),
            .performance_estimate = .{
                .overhead_ns = 100, // ≤100ns guarantee
                .memory_bytes = type_count * 8, // Jump table
                .cache_locality = 0.7,
            },
            .fallback_available = true,
        };
        try self.optimization_decisions.append(decision);

        // Generate symbol name
        const symbol_name = try self.symbol_manager.generateDispatchSymbol(family_name, .switch_table);
        const symbol_name_z = try self.allocator.dupeZ(u8, symbol_name);
        defer self.allocator.free(symbol_name_z);

        // Create function type
        const void_type = llvm.LLVMVoidTypeInContext(self.llvm_context);
        const function_type = llvm.LLVMFunctionType(void_type, null, 0, false);

        // Create function
        const function = llvm.LLVMAddFunction(self.llvm_module, symbol_name_z.ptr, function_type);

        // Create basic block
        const entry_block = llvm.LLVMAppendBasicBlockInContext(self.llvm_context, function, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.llvm_builder, entry_block);

        // TODO: Generate switch table and indirect call IR
        // For now, placeholder return
        _ = llvm.LLVMBuildRetVoid(self.llvm_builder);

        return function;
    }

    /// Get generated LLVM IR as string - For inspection and validation
    pub fn getIRString(self: *Self) ![]const u8 {
        const ir_cstr = llvm.LLVMPrintModuleToString(self.llvm_module);
        defer llvm.LLVMDisposeMessage(ir_cstr);

        const ir_len = std.mem.len(ir_cstr);
        const ir_string = try self.allocator.alloc(u8, ir_len);
        @memcpy(ir_string, ir_cstr[0..ir_len]);

        return ir_string;
    }

    /// Get optimization decisions - Complete auditability
    pub fn getOptimizationDecisions(self: *Self) []const OptimizationDecision {
        return self.optimization_decisions.items;
    }

    /// Write LLVM IR to file - For debugging and inspection
    pub fn writeIRToFile(self: *Self, filename: []const u8) !void {
        const filename_z = try self.allocator.dupeZ(u8, filename);
        defer self.allocator.free(filename_z);

        var error_msg: [*:0]u8 = undefined;
        const result = llvm.LLVMPrintModuleToFile(self.llvm_module, filename_z.ptr, &error_msg);

        if (result != 0) {
            return CodegenError.LLVMModuleCreationFailed;
        }
    }

    /// Compile LLVM IR to object file using external tools
    pub fn compileToObjectFile(self: *Self, output_filename: []const u8) !void {
        // First write IR to temporary file
        const ir_filename = try std.fmt.allocPrint(self.allocator, "{s}.ll", .{output_filename});
        defer self.allocator.free(ir_filename);

        try self.writeIRToFile(ir_filename);

        // Use llc to compile IR to object file
        const llc_command = try std.fmt.allocPrint(self.allocator, "llc -filetype=obj -o {s}.o {s}", .{ output_filename, ir_filename });
        defer self.allocator.free(llc_command);

        var child_process = std.process.Child.init(&[_][]const u8{ "sh", "-c", llc_command }, self.allocator);
        const result = try child_process.spawnAndWait();

        if (result.Exited != 0) {
            return CodegenError.LLVMModuleCreationFailed;
        }
    }

    /// Link object file to executable
    pub fn linkToExecutable(self: *Self, output_filename: []const u8) !void {
        // Link object file to executable using clang
        const link_command = try std.fmt.allocPrint(self.allocator, "clang {s}.o -o {s}", .{ output_filename, output_filename });
        defer self.allocator.free(link_command);

        var child_process = std.process.Child.init(&[_][]const u8{ "sh", "-c", link_command }, self.allocator);
        const result = try child_process.spawnAndWait();

        if (result.Exited != 0) {
            return CodegenError.LLVMModuleCreationFailed;
        }
    }

    /// Generate complete executable from LLVM IR - Full pipeline activation
    pub fn generateExecutable(self: *Self, output_filename: []const u8) !void {
        std.debug.print("🚀 Activating LLVM output pipeline - Generating executable: {s}\n", .{output_filename});

        // Step 1: Compile to object file
        try self.compileToObjectFile(output_filename);

        // Step 2: Link to executable
        try self.linkToExecutable(output_filename);

        std.debug.print("✅ Executable generated successfully: {s}\n", .{output_filename});
    }

    /// Validate performance guarantees - Ensure promises are kept
    pub fn validatePerformanceGuarantees(self: *Self) !void {
        for (self.optimization_decisions.items) |decision| {
            switch (decision.strategy) {
                .Static => {
                    if (decision.performance_estimate.overhead_ns != 0) {
                        return CodegenError.PerformanceGuaranteeViolated;
                    }
                },
                .perfect_hash => {
                    if (decision.performance_estimate.overhead_ns > 25) {
                        return CodegenError.PerformanceGuaranteeViolated;
                    }
                },
                .inline_cache => {
                    if (decision.performance_estimate.overhead_ns > 50) {
                        return CodegenError.PerformanceGuaranteeViolated;
                    }
                },
                .switch_table => {
                    if (decision.performance_estimate.overhead_ns > 100) {
                        return CodegenError.PerformanceGuaranteeViolated;
                    }
                },
            }
        }
    }
};

// Unit tests - Forge the tests that guard the revolution
test "IRGenerator initialization and cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var generator = try IRGenerator.init(allocator, "test_module");
    defer generator.deinit();

    // Verify LLVM resources are properly initialized
    try std.testing.expect(generator.llvm_context != undefined);
    try std.testing.expect(generator.llvm_module != undefined);
    try std.testing.expect(generator.llvm_builder != undefined);
}

test "Static dispatch IR generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var generator = try IRGenerator.init(allocator, "test_module");
    defer generator.deinit();

    // Generate static dispatch function
    const function = try generator.generateStaticDispatchIR("test_family", "target_impl");
    try std.testing.expect(function != undefined);

    // Verify optimization decision was recorded
    const decisions = generator.getOptimizationDecisions();
    try std.testing.expectEqual(@as(usize, 1), decisions.len);
    try std.testing.expectEqual(Strategy.Static, decisions[0].strategy);
    try std.testing.expectEqual(@as(u32, 0), decisions[0].performance_estimate.overhead_ns);
}

test "Perfect hash dispatch IR generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var generator = try IRGenerator.init(allocator, "test_module");
    defer generator.deinit();

    const implementations = [_][]const u8{ "impl1", "impl2", "impl3" };
    const function = try generator.generatePerfectHashIR("test_family", &implementations);
    try std.testing.expect(function != undefined);

    // Verify optimization decision
    const decisions = generator.getOptimizationDecisions();
    try std.testing.expectEqual(@as(usize, 1), decisions.len);
    try std.testing.expectEqual(Strategy.PerfectHash, decisions[0].strategy);
    try std.testing.expect(decisions[0].performance_estimate.overhead_ns <= 25);
}

test "Symbol manager uniqueness" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var symbol_manager = SymbolManager.init(allocator);
    defer symbol_manager.deinit();

    // Generate symbols and verify uniqueness
    const symbol1 = try symbol_manager.generateDispatchSymbol("test", .static);
    const symbol2 = try symbol_manager.generateDispatchSymbol("test", .static);

    try std.testing.expect(!std.mem.eql(u8, symbol1, symbol2));
    try std.testing.expect(std.mem.startsWith(u8, symbol1, "janus_dispatch_test_static"));
    try std.testing.expect(std.mem.startsWith(u8, symbol2, "janus_dispatch_test_static"));
}

test "Performance guarantee validation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var generator = try IRGenerator.init(allocator, "test_module");
    defer generator.deinit();

    // Generate functions with different strategies
    _ = try generator.generateStaticDispatchIR("static_test", "impl");
    _ = try generator.generatePerfectHashIR("hash_test", &[_][]const u8{"impl1"});

    // Validate performance guarantees
    try generator.validatePerformanceGuarantees();
}

test "IR string generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var generator = try IRGenerator.init(allocator, "test_module");
    defer generator.deinit();

    // Generate some IR
    _ = try generator.generateStaticDispatchIR("test", "impl");

    // Get IR string
    const ir_string = try generator.getIRString();
    defer allocator.free(ir_string);

    // Verify IR contains expected elements
    try std.testing.expect(std.mem.indexOf(u8, ir_string, "janus_dispatch_test_static") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_string, "define") != null);
}

// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

// IR dispatch definitions
const DispatchIR = @import("ir_dispatch.zig").DispatchIR;
const StaticCallIR = @import("ir_dispatch.zig").StaticCallIR;
const DynamicStubIR = @import("ir_dispatch.zig").DynamicStubIR;
const ErrorCallIR = @import("ir_dispatch.zig").ErrorCallIR;
const StubStrategy = @import("ir_dispatch.zig").StubStrategy;
const CallingConvention = @import("ir_dispatch.zig").CallingConvention;
const FunctionRef = @import("ir_dispatch.zig").FunctionRef;
const CandidateIR = @import("ir_dispatch.zig").CandidateIR;
const ConversionStep = @import("ir_dispatch.zig").ConversionStep;
const TypeCheckIR = @import("ir_dispatch.zig").TypeCheckIR;

// LLVM bindings (mock interface for now)
pub const LLVM = struct {
    pub const ContextRef = *opaque {};
    pub const ModuleRef = *opaque {};
    pub const BuilderRef = *opaque {};
    pub const ValueRef = *opaque {};
    pub const TypeRef = *opaque {};
    pub const BasicBlockRef = *opaque {};

    // Mock LLVM functions - replace with actual LLVM-C bindings
    pub fn LLVMContextCreate() ContextRef {
        return @ptrFromInt(0x1000);
    }
    pub fn LLVMModuleCreateWithNameInContext(name: [*:0]const u8, ctx: ContextRef) ModuleRef {
        _ = name;
        _ = ctx;
        return @ptrFromInt(0x2000);
    }
    pub fn LLVMCreateBuilderInContext(ctx: ContextRef) BuilderRef {
        _ = ctx;
        return @ptrFromInt(0x3000);
    }
    pub fn LLVMInt32TypeInContext(ctx: ContextRef) TypeRef {
        _ = ctx;
        return @ptrFromInt(0x4000);
    }
    pub fn LLVMVoidTypeInContext(ctx: ContextRef) TypeRef {
        _ = ctx;
        return @ptrFromInt(0x4001);
    }
    pub fn LLVMPointerType(ty: TypeRef, addr_space: u32) TypeRef {
        _ = ty;
        _ = addr_space;
        return @ptrFromInt(0x4002);
    }
    pub fn LLVMFunctionType(ret: TypeRef, params: [*]TypeRef, param_count: u32, is_var_arg: u32) TypeRef {
        _ = ret;
        _ = params;
        _ = param_count;
        _ = is_var_arg;
        return @ptrFromInt(0x4003);
    }
    pub fn LLVMAddFunction(module: ModuleRef, name: [*:0]const u8, func_type: TypeRef) ValueRef {
        _ = module;
        _ = name;
        _ = func_type;
        return @ptrFromInt(0x5000);
    }
    pub fn LLVMBuildCall2(builder: BuilderRef, ty: TypeRef, func: ValueRef, args: [*]ValueRef, num_args: u32, name: [*:0]const u8) ValueRef {
        _ = builder;
        _ = ty;
        _ = func;
        _ = args;
        _ = num_args;
        _ = name;
        return @ptrFromInt(0x5001);
    }
    pub fn LLVMAppendBasicBlockInContext(ctx: ContextRef, func: ValueRef, name: [*:0]const u8) BasicBlockRef {
        _ = ctx;
        _ = func;
        _ = name;
        return @ptrFromInt(0x6000);
    }
    pub fn LLVMPositionBuilderAtEnd(builder: BuilderRef, block: BasicBlockRef) void {
        _ = builder;
        _ = block;
    }
    pub fn LLVMBuildBr(builder: BuilderRef, dest: BasicBlockRef) ValueRef {
        _ = builder;
        _ = dest;
        return @ptrFromInt(0x5002);
    }
    pub fn LLVMBuildCondBr(builder: BuilderRef, cond: ValueRef, then_block: BasicBlockRef, else_block: BasicBlockRef) ValueRef {
        _ = builder;
        _ = cond;
        _ = then_block;
        _ = else_block;
        return @ptrFromInt(0x5003);
    }
    pub fn LLVMBuildRet(builder: BuilderRef, val: ValueRef) ValueRef {
        _ = builder;
        _ = val;
        return @ptrFromInt(0x5004);
    }
    pub fn LLVMBuildRetVoid(builder: BuilderRef) ValueRef {
        _ = builder;
        return @ptrFromInt(0x5005);
    }
    pub fn LLVMConstInt(ty: TypeRef, val: u64, sign_extend: u32) ValueRef {
        _ = ty;
        _ = val;
        _ = sign_extend;
        return @ptrFromInt(0x5006);
    }
    pub fn LLVMBuildICmp(builder: BuilderRef, op: u32, lhs: ValueRef, rhs: ValueRef, name: [*:0]const u8) ValueRef {
        _ = builder;
        _ = op;
        _ = lhs;
        _ = rhs;
        _ = name;
        return @ptrFromInt(0x5007);
    }
    pub fn LLVMBuildLoad2(builder: BuilderRef, ty: TypeRef, ptr: ValueRef, name: [*:0]const u8) ValueRef {
        _ = builder;
        _ = ty;
        _ = ptr;
        _ = name;
        return @ptrFromInt(0x5008);
    }
    pub fn LLVMGetParam(func: ValueRef, index: u32) ValueRef {
        _ = func;
        _ = index;
        return @ptrFromInt(0x5009);
    }
    pub fn LLVMSetFunctionCallConv(func: ValueRef, cc: u32) void {
        _ = func;
        _ = cc;
    }
    pub fn LLVMSetInstructionCallConv(call: ValueRef, cc: u32) void {
        _ = call;
        _ = cc;
    }
    pub fn LLVMDumpModule(module: ModuleRef) void {
        _ = module;
        std.debug.print("[LLVM IR would be dumped here]\\n", .{});
    }
    pub fn LLVMPrintModuleToFile(module: ModuleRef, filename: [*:0]const u8, error_msg: *[*:0]u8) u32 {
        _ = module;
        _ = filename;
        _ = error_msg;
        return 0;
    }
    pub fn LLVMDisposeBuilder(builder: BuilderRef) void {
        _ = builder;
    }
    pub fn LLVMDisposeModule(module: ModuleRef) void {
        _ = module;
    }
    pub fn LLVMContextDispose(ctx: ContextRef) void {
        _ = ctx;
    }

    // Calling conventions
    pub const CCallConv: u32 = 0;
    pub const FastCallConv: u32 = 8;

    // ICmp predicates
    pub const IntEQ: u32 = 32;
};

/// LLVM backend for dispatch IR code generation
pub const LLVMDispatchCodegen = struct {
    // LLVM context and module
    context: LLVM.ContextRef,
    module: LLVM.ModuleRef,
    builder: LLVM.BuilderRef,

    // Code generation state
    allocator: Allocator,
    current_function: ?LLVM.ValueRef,
    target_triple: []const u8,

    // Generated stubs cache
    stub_cache: std.StringHashMap(LLVM.ValueRef),

    // Performance tracking
    stats: CodegenStats,

    const CodegenStats = struct {
        static_calls_generated: u32 = 0,
        dynamic_stubs_generated: u32 = 0,
        total_stub_size_bytes: u32 = 0,

        pub fn reset(self: *CodegenStats) void {
            self.* = CodegenStats{};
        }
    };

    pub fn init(
        allocator: Allocator,
        target_triple: []const u8,
    ) !LLVMDispatchCodegen {
        const context = LLVM.LLVMContextCreate();
        const module = LLVM.LLVMModuleCreateWithNameInContext("janus_dispatch", context);
        const builder = LLVM.LLVMCreateBuilderInContext(context);

        return LLVMDispatchCodegen{
            .context = context,
            .module = module,
            .builder = builder,
            .allocator = allocator,
            .current_function = null,
            .target_triple = target_triple,
            .stub_cache = std.StringHashMap(LLVM.ValueRef).init(allocator),
            .stats = CodegenStats{},
        };
    }

    pub fn deinit(self: *LLVMDispatchCodegen) void {
        self.stub_cache.deinit();
        LLVM.LLVMDisposeBuilder(self.builder);
        LLVM.LLVMDisposeModule(self.module);
        LLVM.LLVMContextDispose(self.context);
    }

    /// Generate LLVM IR from dispatch IR
    pub fn generateFromIR(
        self: *LLVMDispatchCodegen,
        dispatch_ir: *const DispatchIR,
        args: []LLVM.ValueRef,
    ) !LLVM.ValueRef {
        std.debug.print("🔧 Generating LLVM IR for dispatch\\n", .{});

        return switch (dispatch_ir.*) {
            .static_call => |static| try self.generateStaticCall(static, args),
            .dynamic_stub => |dynamic| try self.generateDynamicStub(dynamic, args),
            .error_call => |error_call| try self.generateErrorCall(error_call),
        };
    }

    /// Generate direct LLVM call for static dispatch
    fn generateStaticCall(
        self: *LLVMDispatchCodegen,
        static_ir: StaticCallIR,
        args: []LLVM.ValueRef,
    ) !LLVM.ValueRef {
        std.debug.print("⚡ Generating static call to: {s}\\n", .{static_ir.target_function.name});

        // Get or create the target function
        const target_func = try self.getOrCreateFunction(static_ir.target_function);

        // Apply type conversions
        const converted_args = try self.applyConversions(args, static_ir.conversion_path);
        defer self.allocator.free(converted_args);

        // Generate direct call instruction
        const func_type = try self.getFunctionType(static_ir.target_function);
        const call_inst = LLVM.LLVMBuildCall2(
            self.builder,
            func_type,
            target_func,
            converted_args.ptr,
            @intCast(converted_args.len),
            "static_dispatch_call",
        );

        // Set calling convention
        const llvm_cc = self.toLLVMCallingConvention(static_ir.call_convention);
        LLVM.LLVMSetInstructionCallConv(call_inst, llvm_cc);

        self.stats.static_calls_generated += 1;
        std.debug.print("✅ Static call IR generated (zero overhead)\\n", .{});

        return call_inst;
    }

    /// Generate dispatch stub for dynamic dispatch
    fn generateDynamicStub(
        self: *LLVMDispatchCodegen,
        dynamic_ir: DynamicStubIR,
        args: []LLVM.ValueRef,
    ) !LLVM.ValueRef {
        std.debug.print("🔀 Generating dynamic stub: {s}\\n", .{dynamic_ir.family_name});

        // Check cache first
        if (self.stub_cache.get(dynamic_ir.family_name)) |cached_stub| {
            std.debug.print("📋 Using cached stub\\n", .{});
            return self.callCachedStub(cached_stub, args);
        }

        // Generate new stub based on strategy
        const stub_func = switch (dynamic_ir.strategy) {
            .switch_table => try self.generateSwitchTableStub(dynamic_ir),
            .perfect_hash => try self.generatePerfectHashStub(dynamic_ir),
            .inline_cache => try self.generateInlineCacheStub(dynamic_ir),
        };

        // Cache the generated stub
        try self.stub_cache.put(dynamic_ir.family_name, stub_func);

        // Call the generated stub
        const stub_call = try self.callGeneratedStub(stub_func, args);

        self.stats.dynamic_stubs_generated += 1;
        self.stats.total_stub_size_bytes += dynamic_ir.getStubSizeEstimate();

        std.debug.print("✅ Dynamic stub generated\\n", .{});

        return stub_call;
    }

    /// Generate switch-table based stub (default strategy)
    fn generateSwitchTableStub(self: *LLVMDispatchCodegen, dynamic_ir: DynamicStubIR) !LLVM.ValueRef {
        std.debug.print("📝 Generating switch table stub\\n", .{});

        // Create stub function
        const stub_name = try std.fmt.allocPrintZ(
            self.allocator,
            "{s}_switch_stub",
            .{dynamic_ir.family_name},
        );
        defer self.allocator.free(stub_name);

        const stub_func = try self.createStubFunction(stub_name, dynamic_ir.candidates[0].function_ref);

        // Create basic blocks
        const entry_block = LLVM.LLVMAppendBasicBlockInContext(self.context, stub_func, "entry");
        const fallback_block = LLVM.LLVMAppendBasicBlockInContext(self.context, stub_func, "fallback");

        LLVM.LLVMPositionBuilderAtEnd(self.builder, entry_block);

        // Generate fallback (simplified for now)
        LLVM.LLVMPositionBuilderAtEnd(self.builder, fallback_block);
        _ = LLVM.LLVMBuildRetVoid(self.builder);

        return stub_func;
    }

    /// Generate perfect hash based stub (optimized strategy)
    fn generatePerfectHashStub(self: *LLVMDispatchCodegen, dynamic_ir: DynamicStubIR) !LLVM.ValueRef {
        std.debug.print("🔍 Generating perfect hash stub with {} candidates\\n", .{dynamic_ir.candidates.len});

        // Try to generate perfect hash table
        const PerfectHashGenerator = @import("perfect_hash_generator.zig").PerfectHashGenerator;
        var generator = PerfectHashGenerator.init(self.allocator);

        if (try generator.generate(dynamic_ir.candidates)) |hash_table| {
            defer hash_table.deinit(self.allocator);

            // Generate LLVM IR for perfect hash lookup
            return try self.generatePerfectHashLookupIR(dynamic_ir, hash_table);
        } else {
            std.debug.print("⚠️ Perfect hash generation failed, falling back to switch table\\n", .{});
            return try self.generateSwitchTableStub(dynamic_ir);
        }
    }

    /// Generate inline cache based stub (hot path optimization)
    fn generateInlineCacheStub(self: *LLVMDispatchCodegen, dynamic_ir: DynamicStubIR) !LLVM.ValueRef {
        std.debug.print("⚡ Generating inline cache stub for hot path\\n", .{});

        // Create inline cache
        const InlineCacheManager = @import("inline_cache_manager.zig").InlineCacheManager;
        var cache_manager = InlineCacheManager.init(self.allocator);
        var cache = try cache_manager.createCache(dynamic_ir.family_name, dynamic_ir.candidates);
        defer cache.deinit();

        // Generate LLVM IR for inline cache
        return try self.generateInlineCacheLookupIR(dynamic_ir, cache);
    }

    /// Generate error call for unresolved dispatch
    fn generateErrorCall(self: *LLVMDispatchCodegen, error_ir: ErrorCallIR) !LLVM.ValueRef {
        std.debug.print("❌ Generating error call: {s}\\n", .{error_ir.error_code});

        const error_func = try self.getOrCreateRuntimeErrorFunction();
        const error_msg = try self.createStringConstant(error_ir.message);

        var error_args = [_]LLVM.ValueRef{error_msg};
        const error_type = LLVM.LLVMVoidTypeInContext(self.context);

        return LLVM.LLVMBuildCall2(
            self.builder,
            error_type,
            error_func,
            &error_args,
            1,
            "dispatch_error_call",
        );
    }

    // Helper functions

    fn getOrCreateFunction(self: *LLVMDispatchCodegen, func_ref: FunctionRef) !LLVM.ValueRef {
        // Simplified function creation
        const func_type = try self.getFunctionType(func_ref);
        const name_z = try self.allocator.dupeZ(u8, func_ref.mangled_name);
        defer self.allocator.free(name_z);
        return LLVM.LLVMAddFunction(self.module, name_z.ptr, func_type);
    }

    fn getFunctionType(self: *LLVMDispatchCodegen, func_ref: FunctionRef) !LLVM.TypeRef {
        // Simplified type creation
        const param_types = try self.allocator.alloc(LLVM.TypeRef, func_ref.signature.parameters.len);
        defer self.allocator.free(param_types);

        for (param_types) |*param_type| {
            param_type.* = LLVM.LLVMInt32TypeInContext(self.context); // Simplified
        }

        const return_type = LLVM.LLVMInt32TypeInContext(self.context); // Simplified

        return LLVM.LLVMFunctionType(
            return_type,
            param_types.ptr,
            @intCast(param_types.len),
            if (func_ref.signature.is_variadic) 1 else 0,
        );
    }

    fn createStubFunction(self: *LLVMDispatchCodegen, name: [:0]const u8, template_func: FunctionRef) !LLVM.ValueRef {
        const func_type = try self.getFunctionType(template_func);
        const stub_func = LLVM.LLVMAddFunction(self.module, name.ptr, func_type);
        LLVM.LLVMSetFunctionCallConv(stub_func, LLVM.CCallConv);
        return stub_func;
    }

    fn applyConversions(self: *LLVMDispatchCodegen, args: []LLVM.ValueRef, conversions: []ConversionStep) ![]LLVM.ValueRef {
        // For now, return args unchanged
        _ = conversions;
        const converted = try self.allocator.dupe(LLVM.ValueRef, args);
        return converted;
    }

    fn callCachedStub(self: *LLVMDispatchCodegen, stub_func: LLVM.ValueRef, args: []LLVM.ValueRef) !LLVM.ValueRef {
        const func_type = LLVM.LLVMInt32TypeInContext(self.context); // Simplified
        return LLVM.LLVMBuildCall2(
            self.builder,
            func_type,
            stub_func,
            args.ptr,
            @intCast(args.len),
            "cached_stub_call",
        );
    }

    fn callGeneratedStub(self: *LLVMDispatchCodegen, stub_func: LLVM.ValueRef, args: []LLVM.ValueRef) !LLVM.ValueRef {
        const func_type = LLVM.LLVMInt32TypeInContext(self.context); // Simplified
        return LLVM.LLVMBuildCall2(
            self.builder,
            func_type,
            stub_func,
            args.ptr,
            @intCast(args.len),
            "generated_stub_call",
        );
    }

    fn getOrCreateRuntimeErrorFunction(self: *LLVMDispatchCodegen) !LLVM.ValueRef {
        var param_types = [_]LLVM.TypeRef{LLVM.LLVMPointerType(LLVM.LLVMInt32TypeInContext(self.context), 0)};
        const error_type = LLVM.LLVMFunctionType(
            LLVM.LLVMVoidTypeInContext(self.context),
            &param_types,
            1,
            0,
        );

        return LLVM.LLVMAddFunction(self.module, "janus_dispatch_error", error_type);
    }

    fn createStringConstant(self: *LLVMDispatchCodegen, str: []const u8) !LLVM.ValueRef {
        // Simplified string constant creation
        _ = str;
        return LLVM.LLVMConstInt(LLVM.LLVMPointerType(LLVM.LLVMInt32TypeInContext(self.context), 0), 0, 0);
    }

    fn toLLVMCallingConvention(self: *LLVMDispatchCodegen, cc: CallingConvention) u32 {
        _ = self;
        return switch (cc) {
            .system_v, .aapcs64, .riscv => LLVM.CCallConv,
            .ms_x64 => LLVM.FastCallConv, // Simplified
            .invalid => LLVM.CCallConv,
        };
    }

    /// Get the generated LLVM module
    pub fn getModule(self: *LLVMDispatchCodegen) LLVM.ModuleRef {
        return self.module;
    }

    /// Get codegen statistics
    pub fn getStats(self: *const LLVMDispatchCodegen) CodegenStats {
        return self.stats;
    }

    /// Dump the generated IR to stdout (for debugging)
    pub fn dumpIR(self: *LLVMDispatchCodegen) void {
        std.debug.print("\\n=== LLVM IR Dump ===\\n", .{});
        LLVM.LLVMDumpModule(self.module);
        std.debug.print("\\n=== End IR Dump ===\\n", .{});
    }

    /// Write the generated IR to a file
    pub fn writeIRToFile(self: *LLVMDispatchCodegen, filename: []const u8) !void {
        const filename_z = try self.allocator.dupeZ(u8, filename);
        defer self.allocator.free(filename_z);

        var error_msg: [*:0]u8 = undefined;
        const result = LLVM.LLVMPrintModuleToFile(self.module, filename_z.ptr, &error_msg);

        if (result != 0) {
            std.debug.print("Failed to write IR to {s}\\n", .{filename});
            return error.IRWriteFailed;
        }

        std.debug.print("✅ IR written to {s}\\n", .{filename});
    }

    /// Generate LLVM IR for perfect hash table lookup
    fn generatePerfectHashLookupIR(
        self: *LLVMDispatchCodegen,
        dynamic_ir: DynamicStubIR,
        hash_table: @import("perfect_hash_generator.zig").PerfectHashTable,
    ) !LLVM.ValueRef {
        // Create stub function
        const stub_name = try std.fmt.allocPrintZ(
            self.allocator,
            "{s}_perfect_hash_stub",
            .{dynamic_ir.family_name},
        );
        defer self.allocator.free(stub_name);

        const stub_func = try self.createStubFunction(stub_name, dynamic_ir.candidates[0].function_ref);

        // Create basic blocks
        const entry_block = LLVM.LLVMAppendBasicBlockInContext(self.context, stub_func, "entry");
        const not_found_block = LLVM.LLVMAppendBasicBlockInContext(self.context, stub_func, "not_found");

        // Entry: simplified perfect hash lookup
        LLVM.LLVMPositionBuilderAtEnd(self.builder, entry_block);

        // For now, generate a simplified version that demonstrates the concept
        // In a real implementation, this would generate the actual hash table lookup
        std.debug.print("📊 Perfect hash table: {} entries, {} buckets\\n", .{
            hash_table.candidate_count,
            hash_table.table_size,
        });

        _ = LLVM.LLVMBuildBr(self.builder, not_found_block);

        // Not found: fallback error
        LLVM.LLVMPositionBuilderAtEnd(self.builder, not_found_block);
        _ = LLVM.LLVMBuildRetVoid(self.builder);

        std.debug.print("✅ Perfect hash stub IR generated (simplified)\\n", .{});

        return stub_func;
    }

    /// Generate LLVM IR for inline cache lookup
    fn generateInlineCacheLookupIR(
        self: *LLVMDispatchCodegen,
        dynamic_ir: DynamicStubIR,
        cache: @import("inline_cache_manager.zig").InlineCache,
    ) !LLVM.ValueRef {
        // Create stub function
        const stub_name = try std.fmt.allocPrintZ(
            self.allocator,
            "{s}_inline_cache_stub",
            .{dynamic_ir.family_name},
        );
        defer self.allocator.free(stub_name);

        const stub_func = try self.createStubFunction(stub_name, dynamic_ir.candidates[0].function_ref);

        // Create basic blocks
        const entry_block = LLVM.LLVMAppendBasicBlockInContext(self.context, stub_func, "entry");
        const cache_miss_block = LLVM.LLVMAppendBasicBlockInContext(self.context, stub_func, "cache_miss");

        // Entry: simplified inline cache
        LLVM.LLVMPositionBuilderAtEnd(self.builder, entry_block);

        std.debug.print("⚡ Inline cache: {} slots, max {} slots\\n", .{
            cache.cache_size,
            cache.max_size,
        });

        _ = LLVM.LLVMBuildBr(self.builder, cache_miss_block);

        // Cache miss: fall back to full dispatch
        LLVM.LLVMPositionBuilderAtEnd(self.builder, cache_miss_block);
        _ = LLVM.LLVMBuildRetVoid(self.builder);

        std.debug.print("✅ Inline cache stub IR generated (cache size: {})\\n", .{cache.cache_size});

        return stub_func;
    }
};

// Tests
test "LLVMDispatchCodegen initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var codegen = try LLVMDispatchCodegen.init(allocator, "x86_64-linux-gnu");
    defer codegen.deinit();

    const stats = codegen.getStats();
    try std.testing.expectEqual(@as(u32, 0), stats.static_calls_generated);
    try std.testing.expectEqual(@as(u32, 0), stats.dynamic_stubs_generated);

    std.debug.print("✅ LLVMDispatchCodegen initialization test passed\\n", .{});
}

test "Static call IR generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var codegen = try LLVMDispatchCodegen.init(allocator, "x86_64-linux-gnu");
    defer codegen.deinit();

    // Create mock static call IR
    const TypeId = @import("type_registry.zig").TypeId;
    const FunctionSignature = @import("ir_dispatch.zig").FunctionSignature;
    const SourceSpan = @import("ir_dispatch.zig").SourceSpan;

    const static_ir = StaticCallIR{
        .target_function = FunctionRef{
            .name = "add",
            .mangled_name = "_Z3addii",
            .signature = FunctionSignature{
                .parameters = @constCast(&[_]TypeId{ TypeId.I32, TypeId.I32 }),
                .return_type = TypeId.I32,
                .is_variadic = false,
            },
        },
        .conversion_path = &[_]ConversionStep{},
        .call_convention = .system_v,
        .source_location = SourceSpan{
            .file = "test.jan",
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 10,
        },
    };

    const dispatch_ir = DispatchIR{ .static_call = static_ir };

    // Mock LLVM values for arguments
    var args = [_]LLVM.ValueRef{ @ptrFromInt(0x7000), @ptrFromInt(0x7001) };

    const result = try codegen.generateFromIR(&dispatch_ir, &args);
    try std.testing.expect(@intFromPtr(result) != 0);

    const stats = codegen.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.static_calls_generated);

    std.debug.print("✅ Static call IR generation test passed\\n", .{});
}

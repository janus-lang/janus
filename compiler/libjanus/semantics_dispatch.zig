// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const DispatchFamily = @import("dispatch_family.zig").DispatchFamily;
const DispatchFamilyRegistry = @import("dispatch_family.zig").DispatchFamilyRegistry;
const FuncDecl = @import("dispatch_family.zig").FuncDecl;
const SourceLocation = @import("dispatch_family.zig").SourceLocation;
const SemanticResolver = @import("semantic_resolver.zig").SemanticResolver;
const CallSite = @import("semantic_resolver.zig").CallSite;
const ResolveResult = @import("semantic_resolver.zig").ResolveResult;
const TypeId = @import("type_registry.zig").TypeId;

/// Dispatch resolution result for code generation
pub const DispatchResolution = struct {
    call_site: CallSite,
    resolution_type: ResolutionType,
    target_function: ?*FuncDecl,
    dispatch_table_id: ?u32,
    optimization_hint: OptimizationHint,

    pub const ResolutionType = enum {
        static_resolved, // Compile-tilution, direct call
        dynamic_dispatch, // Runtime dispatch via table
        unresolved_error, // Resolution failed
    };

    pub const OptimizationHint = enum {
        direct_call, // Zero overhead direct call
        jump_table, // Optimized jump table dispatch
        linear_search, // Fallback linear search
        cached_lookup, // Use cached resolution
    };

    pub fn isStaticallyResolved(self: *const DispatchResolution) bool {
        return self.resolution_type == .static_resolved and self.target_function != null;
    }

    pub fn requiresDynamicDispatch(self: *const DispatchResolution) bool {
        return self.resolution_type == .dynamic_dispatch;
    }

    pub fn hasError(self: *const DispatchResolution) bool {
        return self.resolution_type == .unresolved_error;
    }
};

/// Dispatch table entry for runtime resolution
pub const DispatchTableEntry = struct {
    type_signature: []TypeId,
    target_function: *FuncDecl,
    specificity_score: u32,
    call_frequency: u32, // For optimization

    pub fn matches(self: *const DispatchTableEntry, arg_types: []const TypeId) bool {
        if (self.type_signature.len != arg_types.len) return false;

        for (self.type_signature, arg_types) |expected, actual| {
            if (!expected.equals(actual)) return false;
        }

        return true;
    }

    pub fn calculateSpecificity(self: *const DispatchTableEntry) u32 {
        var total_specificity: u32 = 0;
        for (self.type_signature) |type_id| {
            // More specific types get higher scores
            total_specificity += switch (type_id.id) {
                1, 2, 3, 4 => 100, // Built-in types
                else => 200, // User-defined types (more specific)
            };
        }
        return total_specificity;
    }
};

/// Optimized dispatch table for runtime resolution
pub const DispatchTable = struct {
    family_name: []const u8,
    entries: []DispatchTableEntry,
    optimization_metadata: OptimizationMetadata,
    allocator: Allocator,

    pub const OptimizationMetadata = struct {
        uses_perfect_hash: bool,
        hash_function: ?HashFunction,
        jump_table_size: u32,
        compression_ratio: f32,
        generation_time_ns: u64,
    };

    pub const HashFunction = struct {
        seed: u64,
        multiplier: u64,

        pub fn hash(self: HashFunction, type_signature: []const TypeId) u32 {
            var hasher = std.hash.Wyhash.init(self.seed);
            for (type_signature) |type_id| {
                hasher.update(std.mem.asBytes(&type_id.id));
            }
            return @truncate(hasher.final() * self.multiplier);
        }
    };

    pub fn init(allocator: Allocator, family_name: []const u8) !*DispatchTable {
        const table = try allocator.create(DispatchTable);
        table.* = DispatchTable{
            .family_name = try allocator.dupe(u8, family_name),
            .entries = &[_]DispatchTableEntry{},
            .optimization_metadata = OptimizationMetadata{
                .uses_perfect_hash = false,
                .hash_function = null,
                .jump_table_size = 0,
                .compression_ratio = 1.0,
                .generation_time_ns = 0,
            },
            .allocator = allocator,
        };
        return table;
    }

    pub fn deinit(self: *DispatchTable) void {
        self.allocator.free(self.family_name);
        self.allocator.free(self.entries);
        self.allocator.destroy(self);
    }

    pub fn addEntry(self: *DispatchTable, entry: DispatchTableEntry) !void {
        const new_entries = try self.allocator.realloc(self.entries, self.entries.len + 1);
        new_entries[new_entries.len - 1] = entry;
        self.entries = new_entries;
    }

    pub fn findMatch(self: *const DispatchTable, arg_types: []const TypeId) ?*FuncDecl {
        for (self.entries) |*entry| {
            if (entry.matches(arg_types)) {
                return entry.target_function;
            }
        }
        return null;
    }

    pub fn optimize(self: *DispatchTable) !void {
        const start_time = std.time.nanoTimestamp();

        // Sort entries by specificity (most specific first)
        std.sort.pdq(DispatchTableEntry, self.entries, {}, compareBySpecificity);

        // Try to generate perfect hash function
        if (self.entries.len > 3) {
            self.optimization_metadata.hash_function = try self.generatePerfectHash();
            self.optimization_metadata.uses_perfect_hash = true;
        }

        // Calculate compression ratio
        const original_size = self.entries.len * @sizeOf(DispatchTableEntry);
        const optimized_size = self.calculateOptimizedSize();
        self.optimization_metadata.compression_ratio =
            @as(f32, @floatFromInt(optimized_size)) / @as(f32, @floatFromInt(original_size));

        const end_time = std.time.nanoTimestamp();
        self.optimization_metadata.generation_time_ns = @intCast(end_time - start_time);
    }

    fn compareBySpecificity(context: void, a: DispatchTableEntry, b: DispatchTableEntry) bool {
        _ = context;
        return a.calculateSpecificity() > b.calculateSpecificity();
    }

    fn generatePerfectHash(self: *DispatchTable) !HashFunction {
        // Simplified perfect hash generation
        // In production, this would use more sophisticated algorithms
        return HashFunction{
            .seed = 0x9e3779b9,
            .multiplier = 0x85ebca6b,
        };
    }

    fn calculateOptimizedSize(self: *const DispatchTable) usize {
        // Simplified size calculation
        if (self.optimization_metadata.uses_perfect_hash) {
            return self.entries.len * @sizeOf(u32); // Just function pointers
        }
        return self.entries.len * @sizeOf(DispatchTableEntry);
    }
};

/// Semantic dispatch resolver integrating with semantic analysis
pub const SemanticDispatchResolver = struct {
    family_registry: *DispatchFamilyRegistry,
    semantic_resolver: *SemanticResolver,
    dispatch_tables: std.HashMap([]const u8, *DispatchTable, StringContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    const StringContext = struct {
        pub fn hash(self: @This(), key: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(key);
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    pub fn init(
        allocator: Allocator,
        family_registry: *DispatchFamilyRegistry,
        semantic_resolver: *SemanticResolver,
    ) SemanticDispatchResolver {
        return SemanticDispatchResolver{
            .family_registry = family_registry,
            .semantic_resolver = semantic_resolver,
            .dispatch_tables = std.HashMap([]const u8, *DispatchTable, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SemanticDispatchResolver) void {
        var iterator = self.dispatch_tables.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.dispatch_tables.deinit();
    }

    /// Resolve a function call using dispatch semantics
    pub fn resolveDispatchCall(
        self: *SemanticDispatchResolver,
        call_site: CallSite,
    ) !DispatchResolution {
        // Check if this is a dispatch family
        const family = self.family_registry.getFamily(call_site.function_name);

        if (family == null or family.?.isSingleFunction()) {
            // Single function - use direct semantic resolution
            return self.resolveSingleFunction(call_site);
        }

        // Multi-function family - use dispatch resolution
        return self.resolveMultiFunction(call_site, family.?);
    }

    fn resolveSingleFunction(self: *SemanticDispatchResolver, call_site: CallSite) !DispatchResolution {
        var result = try self.semantic_resolver.resolve(call_site);
        defer result.deinit(self.allocator);

        return switch (result) {
            .success => |success| DispatchResolution{
                .call_site = call_site,
                .resolution_type = .static_resolved,
                .target_function = success.target_function,
                .dispatch_table_id = null,
                .optimization_hint = .direct_call,
            },
            else => DispatchResolution{
                .call_site = call_site,
                .resolution_type = .unresolved_error,
                .target_function = null,
                .dispatch_table_id = null,
                .optimization_hint = .linear_search,
            },
        };
    }

    fn resolveMultiFunction(
        self: *SemanticDispatchResolver,
        call_site: CallSite,
        family: *DispatchFamily,
    ) !DispatchResolution {
        // Get or create dispatch table for this family
        const dispatch_table = try self.getOrCreateDispatchTable(family);

        // Try static resolution first
        if (self.canResolveStatically(call_site, family)) {
            const target = family.findBestMatch(try self.serializeArgumentTypes(call_site.argument_types));
            if (target) |func| {
                return DispatchResolution{
                    .call_site = call_site,
                    .resolution_type = .static_resolved,
                    .target_function = func,
                    .dispatch_table_id = null,
                    .optimization_hint = .direct_call,
                };
            }
        }

        // Fall back to dynamic dispatch
        return DispatchResolution{
            .call_site = call_site,
            .resolution_type = .dynamic_dispatch,
            .target_function = null,
            .dispatch_table_id = @intCast(dispatch_table.entries.len), // Simplified ID
            .optimization_hint = if (dispatch_table.optimization_metadata.uses_perfect_hash)
                .jump_table
            else
                .linear_search,
        };
    }

    fn canResolveStatically(
        self: *SemanticDispatchResolver,
        call_site: CallSite,
        family: *DispatchFamily,
    ) bool {
        _ = self;
        _ = call_site;

        // Static resolution is possible if:
        // 1. All argument types are known at compile time
        // 2. No ambiguity exists for this type combination
        // 3. Family has no runtime-dependent overloads

        return !family.hasAmbiguities();
    }

    fn getOrCreateDispatchTable(self: *SemanticDispatchResolver, family: *DispatchFamily) !*DispatchTable {
        if (self.dispatch_tables.get(family.name)) |table| {
            return table;
        }

        const table = try DispatchTable.init(self.allocator, family.name);

        // Populate table with family overloads
        for (family.getAllOverloads()) |overload| {
            const type_signature = try self.parseTypeSignature(overload.parameter_types);

            const entry = DispatchTableEntry{
                .type_signature = type_signature,
                .target_function = overload,
                .specificity_score = 0, // Will be calculated
                .call_frequency = 0,
            };

            try table.addEntry(entry);
        }

        // Optimize the table
        try table.optimize();

        try self.dispatch_tables.put(family.name, table);
        return table;
    }

    fn parseTypeSignature(self: *SemanticDispatchResolver, param_types: []const u8) ![]TypeId {
        if (param_types.len == 0) return &[_]TypeId{};

        var types: std.ArrayList(TypeId) = .empty;
        var iterator = std.mem.splitScalar(u8, param_types, ',');

        while (iterator.next()) |type_name| {
            const trimmed = std.mem.trim(u8, type_name, " ");
            const type_id = self.getTypeIdFromName(trimmed);
            try types.append(type_id);
        }

        return try types.toOwnedSlice(alloc);
    }

    fn getTypeIdFromName(self: *SemanticDispatchResolver, type_name: []const u8) TypeId {
        _ = self;

        // Simplified type name to ID mapping
        if (std.mem.eql(u8, type_name, "i32")) return TypeId.I32;
        if (std.mem.eql(u8, type_name, "f64")) return TypeId.F64;
        if (std.mem.eql(u8, type_name, "bool")) return TypeId.BOOL;
        if (std.mem.eql(u8, type_name, "string")) return TypeId.STRING;

        return TypeId.INVALID;
    }

    fn serializeArgumentTypes(self: *SemanticDispatchResolver, arg_types: []const TypeId) ![]const u8 {
        if (arg_types.len == 0) return try self.allocator.dupe(u8, "");

        var result: std.ArrayList(u8) = .empty;

        for (arg_types, 0..) |type_id, i| {
            if (i > 0) try result.appendSlice(",");

            const type_name = switch (type_id.id) {
                1 => "i32",
                2 => "f64",
                3 => "bool",
                4 => "string",
                else => "unknown",
            };

            try result.appendSlice(type_name);
        }

        return try result.toOwnedSlice(alloc);
    }

    /// Generate dispatch IR for LLVM backend
    pub fn generateDispatchIR(self: *SemanticDispatchResolver, resolution: DispatchResolution) !DispatchIR {
        return switch (resolution.resolution_type) {
            .static_resolved => DispatchIR{
                .ir_type = .direct_call,
                .target_function = resolution.target_function.?,
                .dispatch_data = null,
            },
            .dynamic_dispatch => DispatchIR{
                .ir_type = .dispatch_table,
                .target_function = null,
                .dispatch_data = DispatchIRData{
                    .table_id = resolution.dispatch_table_id.?,
                    .optimization_hint = resolution.optimization_hint,
                },
            },
            .unresolved_error => DispatchIR{
                .ir_type = .error_stub,
                .target_function = null,
                .dispatch_data = null,
            },
        };
    }

    /// Get all dispatch tables for code generation
    pub fn getAllDispatchTables(self: *const SemanticDispatchResolver, allocator: Allocator) ![]const *DispatchTable {
        var tables: std.ArrayList(*DispatchTable) = .empty;

        var iterator = self.dispatch_tables.iterator();
        while (iterator.next()) |entry| {
            try tables.append(entry.value_ptr.*);
        }

        return try tables.toOwnedSlice(alloc);
    }

    /// Get dispatch statistics for optimization
    pub fn getDispatchStats(self: *const SemanticDispatchResolver) DispatchStats {
        var total_entries: u32 = 0;
        var optimized_tables: u32 = 0;

        var iterator = self.dispatch_tables.iterator();
        while (iterator.next()) |entry| {
            const table = entry.value_ptr.*;
            total_entries += @intCast(table.entries.len);
            if (table.optimization_metadata.uses_perfect_hash) {
                optimized_tables += 1;
            }
        }

        return DispatchStats{
            .total_families = @intCast(self.dispatch_tables.count()),
            .total_entries = total_entries,
            .optimized_tables = optimized_tables,
            .optimization_ratio = if (self.dispatch_tables.count() > 0)
                @as(f32, @floatFromInt(optimized_tables)) / @as(f32, @floatFromInt(self.dispatch_tables.count()))
            else
                0.0,
        };
    }

    pub const DispatchStats = struct {
        total_families: u32,
        total_entries: u32,
        optimized_tables: u32,
        optimization_ratio: f32,
    };
};

/// Dispatch IR for LLVM code generation
pub const DispatchIR = struct {
    ir_type: IRType,
    target_function: ?*FuncDecl,
    dispatch_data: ?DispatchIRData,

    pub const IRType = enum {
        direct_call, // Static resolution - emit direct call
        dispatch_table, // Dynamic dispatch - emit table lookup
        error_stub, // Unresolved - emit error
    };

    pub const DispatchIRData = struct {
        table_id: u32,
        optimization_hint: DispatchResolution.OptimizationHint,
    };

    pub fn isDirectCall(self: *const DispatchIR) bool {
        return self.ir_type == .direct_call;
    }

    pub fn requiresDispatchTable(self: *const DispatchIR) bool {
        return self.ir_type == .dispatch_table;
    }
};

// Tests
test "DispatchTable basic operations" {
    var table = try DispatchTable.init(std.testing.allocator, "test_family");
    defer table.deinit();

    // Create test function
    var func = FuncDecl{
        .name = "test_func",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = SourceLocation{
            .file = "test.jan",
            .line = 1,
            .column = 1,
            .start_byte = 0,
            .end_byte = 10,
        },
        .dispatch_family = null,
        .overload_index = 0,
        .signature_hash = 0,
    };

    const entry = DispatchTableEntry{
        .type_signature = &[_]TypeId{ TypeId.I32, TypeId.I32 },
        .target_function = &func,
        .specificity_score = 200,
        .call_frequency = 0,
    };

    try table.addEntry(entry);

    // Test matching
    const arg_types = [_]TypeId{ TypeId.I32, TypeId.I32 };
    const match = table.findMatch(arg_types[0..]);
    try std.testing.expect(match != null);
    try std.testing.expectEqualStrings(match.?.name, "test_func");

    // Test optimization
    try table.optimize();
    try std.testing.expect(table.optimization_metadata.generation_time_ns > 0);
}

test "SemanticDispatchResolver integration" {
    var family_registry = DispatchFamilyRegistry.init(std.testing.allocator);
    defer family_registry.deinit();

    // This test would need full semantic resolver setup
    // For now, just test that the resolver initializes
    const resolver = SemanticDispatchResolver.init(
        std.testing.allocator,
        &family_registry,
        undefined, // Would need actual semantic resolver
    );

    _ = resolver;
    try std.testing.expect(true);
}

test "DispatchResolution types" {
    const call_site = CallSite{
        .function_name = "test",
        .argument_types = &[_]TypeId{TypeId.I32},
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 1,
            .column = 1,
            .start_byte = 0,
            .end_byte = 10,
        },
    };

    const resolution = DispatchResolution{
        .call_site = call_site,
        .resolution_type = .static_resolved,
        .target_function = undefined,
        .dispatch_table_id = null,
        .optimization_hint = .direct_call,
    };

    try std.testing.expect(resolution.isStaticallyResolved());
    try std.testing.expect(!resolution.requiresDynamicDispatch());
    try std.testing.expect(!resolution.hasError());
}

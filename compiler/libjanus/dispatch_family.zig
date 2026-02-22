// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Source location information for functions
pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,
    start_byte: u32,
    end_byte: u32,
};

/// Function declaration with dispatch metadata
pub const FuncDecl = struct {
    name: []const u8,
    parameter_types: []const u8, // Will be replaced with proper Type[] later
    return_type: []const u8,
    visibility: VisibilityLevel,
    module_path: []const u8,
    source_location: SourceLocation,

    // Dispatch integration fields
    dispatch_family: ?*DispatchFamily,
    overload_index: u32,
    signature_hash: u64,

    pub const VisibilityLevel = enum {
        private,
        module,
        public,
    };

    pub fn attachToFamily(self: *FuncDecl, family: *DispatchFamily) !void {
        self.dispatch_family = family;
        self.overload_index = @intCast(family.overloads.items.len);
        try family.addOverload(self);
    }

    pub fn calculateSignatureHash(self: *const FuncDecl) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(self.name);
        hasher.update(self.parameter_types);
        hasher.update(self.return_type);
        return hasher.final();
    }

    pub fn isInFamily(self: *const FuncDecl) bool {
        return self.dispatch_family != null;
    }

    pub fn getQualifiedName(self: *const FuncDecl, allocator: Allocator) ![]const u8 {
        if (self.module_path.len > 0) {
            return std.fmt.allocPrint(allocator, "{s}::{s}", .{ self.module_path, self.name });
        }
        return try allocator.dupe(u8, self.name);
    }
};

/// Dispatch family grouping functions by name
pub const DispatchFamily = struct {
    name: []const u8,
    overloads: std.ArrayList(*FuncDecl),
    source_locations: std.ArrayList(SourceLocation),
    family_metadata: FamilyMetadata,
    allocator: Allocator,

    pub const FamilyMetadata = struct {
        is_single_function: bool,
        has_ambiguities: bool,
        max_arity: u32,
        min_arity: u32,
        total_overloads: u32,
        creation_timestamp: i64,
    };

    pub fn init(allocator: Allocator, name: []const u8) !*DispatchFamily {
        const family = try allocator.create(DispatchFamily);
        family.* = DispatchFamily{
            .name = try allocator.dupe(u8, name),
            .overloads = .empty,
            .source_locations = .empty,
            .family_metadata = FamilyMetadata{
                .is_single_function = true,
                .has_ambiguities = false,
                .max_arity = 0,
                .min_arity = std.math.maxInt(u32),
                .total_overloads = 0,
                .creation_timestamp = std.time.timestamp(),
            },
            .allocator = allocator,
        };
        return family;
    }

    pub fn deinit(self: *DispatchFamily) void {
        self.allocator.free(self.name);
        self.overloads.deinit();
        self.source_locations.deinit();
        self.allocator.destroy(self);
    }

    pub fn addOverload(self: *DispatchFamily, func_decl: *FuncDecl) !void {
        // Validate signature uniqueness
        for (self.overloads.items) |existing| {
            if (self.signaturesConflict(existing, func_decl)) {
                return error.ConflictingSignature;
            }
        }

        try self.overloads.append(func_decl);
        try self.source_locations.append(func_decl.source_location);

        // Update metadata
        self.updateMetadata(func_decl);

        // Update function's family reference
        func_decl.dispatch_family = self;
        func_decl.overload_index = @intCast(self.overloads.items.len - 1);
        func_decl.signature_hash = func_decl.calculateSignatureHash();
    }

    fn updateMetadata(self: *DispatchFamily, func_decl: *FuncDecl) void {
        self.family_metadata.total_overloads = @intCast(self.overloads.items.len);
        self.family_metadata.is_single_function = self.overloads.items.len == 1;

        // Calculate arity from parameter string (simplified)
        const arity = self.calculateArity(func_decl.parameter_types);
        if (arity > self.family_metadata.max_arity) {
            self.family_metadata.max_arity = arity;
        }
        if (arity < self.family_metadata.min_arity) {
            self.family_metadata.min_arity = arity;
        }

        // Check for potential ambiguities
        self.family_metadata.has_ambiguities = self.checkForAmbiguities();
    }

    fn calculateArity(self: *DispatchFamily, param_types: []const u8) u32 {
        _ = self;
        if (param_types.len == 0) return 0;

        var arity: u32 = 1;
        for (param_types) |char| {
            if (char == ',') arity += 1;
        }
        return arity;
    }

    pub fn signaturesConflict(self: *DispatchFamily, existing: *FuncDecl, new_func: *FuncDecl) bool {
        _ = self;
        // Simplified signature conflict detection
        return std.mem.eql(u8, existing.parameter_types, new_func.parameter_types);
    }

    fn checkForAmbiguities(self: *DispatchFamily) bool {
        // Simplified ambiguity detection
        if (self.overloads.items.len < 2) return false;

        // Check for functions with same arity but different types
        for (self.overloads.items, 0..) |func1, i| {
            for (self.overloads.items[i + 1 ..]) |func2| {
                const arity1 = self.calculateArity(func1.parameter_types);
                const arity2 = self.calculateArity(func2.parameter_types);

                if (arity1 == arity2 and !std.mem.eql(u8, func1.parameter_types, func2.parameter_types)) {
                    return true; // Potential ambiguity
                }
            }
        }

        return false;
    }

    pub fn isAmbiguous(self: *const DispatchFamily, arg_types: []const u8) bool {
        var matching_count: u32 = 0;

        for (self.overloads.items) |overload| {
            if (self.typesMatch(overload.parameter_types, arg_types)) {
                matching_count += 1;
                if (matching_count > 1) return true;
            }
        }

        return false;
    }

    fn typesMatch(self: *const DispatchFamily, param_types: []const u8, arg_types: []const u8) bool {
        _ = self;
        // Simplified type matching
        return std.mem.eql(u8, param_types, arg_types);
    }

    pub fn findBestMatch(self: *const DispatchFamily, arg_types: []const u8) ?*FuncDecl {
        for (self.overloads.items) |overload| {
            if (self.typesMatch(overload.parameter_types, arg_types)) {
                return overload;
            }
        }
        return null;
    }

    pub fn getAllOverloads(self: *const DispatchFamily) []const *FuncDecl {
        return self.overloads.items;
    }

    pub fn getOverloadCount(self: *const DispatchFamily) u32 {
        return @intCast(self.overloads.items.len);
    }

    pub fn isSingleFunction(self: *const DispatchFamily) bool {
        return self.family_metadata.is_single_function;
    }

    pub fn hasAmbiguities(self: *const DispatchFamily) bool {
        return self.family_metadata.has_ambiguities;
    }

    pub fn getSignatureList(self: *const DispatchFamily, allocator: Allocator) ![][]const u8 {
        var signatures: std.ArrayList([]const u8) = .empty;

        for (self.overloads.items) |overload| {
            const signature = try std.fmt.allocPrint(allocator, "{s}({s}) -> {s}", .{ overload.name, overload.parameter_types, overload.return_type });
            try signatures.append(signature);
        }

        return try signatures.toOwnedSlice(alloc);
    }
};

/// Dispatch family registry for managing all families in a compilation unit
pub const DispatchFamilyRegistry = struct {
    families: std.HashMap([]const u8, *DispatchFamily, StringContext, std.hash_map.default_max_load_percentage),
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

    pub fn init(allocator: Allocator) DispatchFamilyRegistry {
        return DispatchFamilyRegistry{
            .families = std.HashMap([]const u8, *DispatchFamily, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DispatchFamilyRegistry) void {
        var iterator = self.families.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.families.deinit();
    }

    pub fn getOrCreateFamily(self: *DispatchFamilyRegistry, name: []const u8) !*DispatchFamily {
        if (self.families.get(name)) |family| {
            return family;
        }

        const family = try DispatchFamily.init(self.allocator, name);
        try self.families.put(family.name, family);
        return family;
    }

    pub fn registerFunction(self: *DispatchFamilyRegistry, func_decl: *FuncDecl) !void {
        const family = try self.getOrCreateFamily(func_decl.name);
        try family.addOverload(func_decl);
    }

    pub fn getFamily(self: *const DispatchFamilyRegistry, name: []const u8) ?*DispatchFamily {
        return self.families.get(name);
    }

    pub fn getAllFamilies(self: *const DispatchFamilyRegistry, allocator: Allocator) ![]const *DispatchFamily {
        var family_list: std.ArrayList(*DispatchFamily) = .empty;

        var iterator = self.families.iterator();
        while (iterator.next()) |entry| {
            try family_list.append(entry.value_ptr.*);
        }

        return try family_list.toOwnedSlice(alloc);
    }

    pub fn getFamilyCount(self: *const DispatchFamilyRegistry) u32 {
        return @intCast(self.families.count());
    }

    pub fn getTotalOverloads(self: *const DispatchFamilyRegistry) u32 {
        var total: u32 = 0;
        var iterator = self.families.iterator();
        while (iterator.next()) |entry| {
            total += entry.value_ptr.*.getOverloadCount();
        }
        return total;
    }

    pub fn validateAllFamilies(self: *const DispatchFamilyRegistry) !void {
        var iterator = self.families.iterator();
        while (iterator.next()) |entry| {
            const family = entry.value_ptr.*;

            // Validate no conflicting signatures within family
            for (family.overloads.items, 0..) |func1, i| {
                for (family.overloads.items[i + 1 ..]) |func2| {
                    if (family.signaturesConflict(func1, func2)) {
                        return error.ConflictingSignatures;
                    }
                }
            }
        }
    }
};

// Tests
test "DispatchFamily basic operations" {
    var family = try DispatchFamily.init(std.testing.allocator, "add");
    defer family.deinit();

    // Create test functions
    var func1 = FuncDecl{
        .name = "add",
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

    var func2 = FuncDecl{
        .name = "add",
        .parameter_types = "f64,f64",
        .return_type = "f64",
        .visibility = .public,
        .module_path = "",
        .source_location = SourceLocation{
            .file = "test.jan",
            .line = 5,
            .column = 1,
            .start_byte = 50,
            .end_byte = 60,
        },
        .dispatch_family = null,
        .overload_index = 0,
        .signature_hash = 0,
    };

    // Add overloads
    try family.addOverload(&func1);
    try family.addOverload(&func2);

    // Test family properties
    try std.testing.expect(family.getOverloadCount() == 2);
    try std.testing.expect(!family.isSingleFunction());
    try std.testing.expectEqualStrings(family.name, "add");

    // Test function linkage
    try std.testing.expect(func1.isInFamily());
    try std.testing.expect(func1.dispatch_family == family);
    try std.testing.expect(func1.overload_index == 0);
    try std.testing.expect(func2.overload_index == 1);
}

test "DispatchFamilyRegistry operations" {
    var registry = DispatchFamilyRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Create test function
    var func = FuncDecl{
        .name = "test_func",
        .parameter_types = "i32",
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

    // Register function
    try registry.registerFunction(&func);

    // Test registry properties
    try std.testing.expect(registry.getFamilyCount() == 1);
    try std.testing.expect(registry.getTotalOverloads() == 1);

    // Test family retrieval
    const family = registry.getFamily("test_func").?;
    try std.testing.expectEqualStrings(family.name, "test_func");
    try std.testing.expect(family.isSingleFunction());

    // Test validation
    try registry.validateAllFamilies();
}

test "Signature conflict detection" {
    var family = try DispatchFamily.init(std.testing.allocator, "conflict_test");
    defer family.deinit();

    var func1 = FuncDecl{
        .name = "conflict_test",
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

    var func2 = FuncDecl{
        .name = "conflict_test",
        .parameter_types = "i32,i32", // Same signature - should conflict
        .return_type = "f64", // Different return type
        .visibility = .public,
        .module_path = "",
        .source_location = SourceLocation{
            .file = "test.jan",
            .line = 5,
            .column = 1,
            .start_byte = 50,
            .end_byte = 60,
        },
        .dispatch_family = null,
        .overload_index = 0,
        .signature_hash = 0,
    };

    // First function should succeed
    try family.addOverload(&func1);

    // Second function should fail due to signature conflict
    try std.testing.expectError(error.ConflictingSignature, family.addOverload(&func2));
}

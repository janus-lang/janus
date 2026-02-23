// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const Type = @import("type_registry.zig").Type;
const TypeId = @import("type_registry.zig").TypeId;

/// ConversionMethod defines how a conversion is performed
pub const ConversionMethod = union(enum) {
    builtin_cast,
    trait_method: TraitMethod,
    constructor: Constructor,

    pub const TraitMethod = struct {
        trait_name: []const u8,
        method_name: []const u8,
    };

    pub const Constructor = struct {
        type_name: []const u8,
        constructor_name: []const u8,
    };
};

/// Conversion represents an explicit type conversion
pub const Conversion = struct {
    from: TypeId,
    to: TypeId,
    cost: u32,
    is_lossy: bool,
    method: ConversionMethod,
    syntax_template: []const u8,

    pub const NONE = Conversion{
        .from = TypeId.INVALID,
        .to = TypeId.INVALID,
        .cost = 0,
        .is_lossy = false,
        .method = .builtin_cast,
        .syntax_template = "{}",
    };

    pub fn none() Conversion {
        return NONE;
    }

    pub fn generateSyntax(self: *const Conversion, value_text: []const u8, allocator: Allocator) ![]const u8 {
        return switch (self.method) {
            .builtin_cast => std.fmt.allocPrint(allocator, "{s} as {s}", .{ value_text, self.getTargetTypeName() }),
            .trait_method => |trait| std.fmt.allocPrint(allocator, "{s}.{s}()", .{ value_text, trait.method_name }),
            .constructor => |ctor| std.fmt.allocPrint(allocator, "{s}({s})", .{ ctor.type_name, value_text }),
        };
    }

    fn getTargetTypeName(self: *const Conversion) []const u8 {
        return switch (self.to.id) {
            1 => "i32",
            2 => "f64",
            3 => "bool",
            4 => "string",
            else => "unknown",
        };
    }
};

/// ConversionPath represents a sequence of conversions
pub const ConversionPath = struct {
    conversions: []Conversion,
    total_cost: u32,
    is_lossy: bool,
    allocator: Allocator,
    is_freed: bool,

    pub fn init(allocator: Allocator) ConversionPath {
        return ConversionPath{
            .conversions = &[_]Conversion{},
            .total_cost = 0,
            .is_lossy = false,
            .allocator = allocator,
            .is_freed = false,
        };
    }

    pub fn deinit(self: *ConversionPath) void {
        if (!self.is_freed and self.conversions.len > 0) {
            self.allocator.free(self.conversions);
            self.is_freed = true;
        }
    }

    pub fn clone(self: *const ConversionPath, allocator: Allocator) !ConversionPath {
        const cloned_conversions = try allocator.dupe(Conversion, self.conversions);
        return ConversionPath{
            .conversions = cloned_conversions,
            .total_cost = self.total_cost,
            .is_lossy = self.is_lossy,
            .allocator = allocator,
            .is_freed = false,
        };
    }

    pub fn addConversion(self: *ConversionPath, conversion: Conversion) !void {
        const new_conversions = try self.allocator.realloc(self.conversions, self.conversions.len + 1);
        new_conversions[new_conversions.len - 1] = conversion;
        self.conversions = new_conversions;
        self.total_cost += conversion.cost;
        self.is_lossy = self.is_lossy or conversion.is_lossy;
    }
};

/// ConversionRegistry manages explicit type conversions
pub const ConversionRegistry = struct {
    allocator: Allocator,
    conversions: std.HashMap(ConversionKey, Conversion, ConversionKeyContext, std.hash_map.default_max_load_percentage),

    const ConversionKey = struct {
        from: TypeId,
        to: TypeId,

        pub fn hash(self: ConversionKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&self.from.id));
            hasher.update(std.mem.asBytes(&self.to.id));
            return hasher.final();
        }

        pub fn equals(self: ConversionKey, other: ConversionKey) bool {
            return self.from.equals(other.from) and self.to.equals(other.to);
        }
    };

    const ConversionKeyContext = struct {
        pub fn hash(self: @This(), key: ConversionKey) u64 {
            _ = self;
            return key.hash();
        }

        pub fn eql(self: @This(), a: ConversionKey, b: ConversionKey) bool {
            _ = self;
            return a.equals(b);
        }
    };

    pub fn init(allocator: Allocator) ConversionRegistry {
        var registry = ConversionRegistry{
            .allocator = allocator,
            .conversions = std.HashMap(ConversionKey, Conversion, ConversionKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
        };

        // Register built-in conversions
        registry.registerBuiltinConversions() catch unreachable;

        return registry;
    }

    pub fn deinit(self: *ConversionRegistry) void {
        self.conversions.deinit();
    }

    fn registerBuiltinConversions(self: *ConversionRegistry) !void {
        // i32 -> f64 (safe, moderate cost)
        try self.registerConversion(Conversion{
            .from = TypeId.I32,
            .to = TypeId.F64,
            .cost = 5,
            .is_lossy = false,
            .method = .builtin_cast,
            .syntax_template = "{} as f64",
        });

        // f64 -> i32 (lossy, high cost)
        try self.registerConversion(Conversion{
            .from = TypeId.F64,
            .to = TypeId.I32,
            .cost = 10,
            .is_lossy = true,
            .method = .builtin_cast,
            .syntax_template = "{} as i32",
        });

        // bool -> i32 (explicit, moderate cost)
        try self.registerConversion(Conversion{
            .from = TypeId.BOOL,
            .to = TypeId.I32,
            .cost = 7,
            .is_lossy = false,
            .method = .builtin_cast,
            .syntax_template = "{} as i32",
        });

        // i32 -> bool (explicit, moderate cost)
        try self.registerConversion(Conversion{
            .from = TypeId.I32,
            .to = TypeId.BOOL,
            .cost = 7,
            .is_lossy = false,
            .method = .builtin_cast,
            .syntax_template = "{} as bool",
        });
    }

    pub fn registerConversion(self: *ConversionRegistry, conversion: Conversion) !void {
        const key = ConversionKey{
            .from = conversion.from,
            .to = conversion.to,
        };
        try self.conversions.put(key, conversion);
    }

    pub fn findExplicitConversion(self: *const ConversionRegistry, from: TypeId, to: TypeId) ?Conversion {
        const key = ConversionKey{ .from = from, .to = to };
        return self.conversions.get(key);
    }

    pub fn findConversionPath(
        self: *const ConversionRegistry,
        from_types: []const TypeId,
        to_types: []const TypeId,
        allocator: Allocator,
    ) !?ConversionPath {
        if (from_types.len != to_types.len) return null;

        // Pre-allocate conversions array to avoid realloc issues with arena
        var conversions = try std.ArrayList(Conversion).initCapacity(allocator, from_types.len);
        var total_cost: u32 = 0;
        var is_lossy = false;

        for (from_types, to_types) |from, to| {
            if (from.equals(to)) {
                // No conversion needed
                conversions.appendAssumeCapacity(Conversion.none());
                continue;
            }

            // Look for explicit conversion
            const conversion = self.findExplicitConversion(from, to) orelse {
                // No conversion available
                conversions.deinit();
                return null;
            };

            conversions.appendAssumeCapacity(conversion);
            total_cost += conversion.cost;
            if (conversion.is_lossy) is_lossy = true;
        }

        return ConversionPath{
            .conversions = try conversions.toOwnedSlice(),
            .total_cost = total_cost,
            .is_lossy = is_lossy,
            .allocator = allocator,
            .is_freed = false,
        };
    }

    pub fn getAvailableConversions(self: *const ConversionRegistry, from: TypeId, allocator: Allocator) ![]TypeId {
        var available: std.ArrayList(TypeId) = .empty;

        var iterator = self.conversions.iterator();
        while (iterator.next()) |entry| {
            if (entry.key_ptr.from.equals(from)) {
                try available.append(entry.key_ptr.to);
            }
        }

        return try available.toOwnedSlice(alloc);
    }

    pub fn registerTraitConversion(
        self: *ConversionRegistry,
        from: TypeId,
        to: TypeId,
        trait_name: []const u8,
        method_name: []const u8,
        cost: u32,
        is_lossy: bool,
    ) !void {
        const conversion = Conversion{
            .from = from,
            .to = to,
            .cost = cost,
            .is_lossy = is_lossy,
            .method = ConversionMethod{
                .trait_method = ConversionMethod.TraitMethod{
                    .trait_name = trait_name,
                    .method_name = method_name,
                },
            },
            .syntax_template = "{}.{}()",
        };

        try self.registerConversion(conversion);
    }
};

// Tests
test "ConversionRegistry basic operations" {
    var registry = ConversionRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Test built-in conversions
    const i32_to_f64 = registry.findExplicitConversion(TypeId.I32, TypeId.F64).?;
    try std.testing.expect(i32_to_f64.cost == 5);
    try std.testing.expect(!i32_to_f64.is_lossy);

    const f64_to_i32 = registry.findExplicitConversion(TypeId.F64, TypeId.I32).?;
    try std.testing.expect(f64_to_i32.cost == 10);
    try std.testing.expect(f64_to_i32.is_lossy);

    // Test non-existent conversion
    const no_conversion = registry.findExplicitConversion(TypeId.STRING, TypeId.I32);
    try std.testing.expect(no_conversion == null);
}

test "ConversionPath creation" {
    var registry = ConversionRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const from_types = [_]TypeId{ TypeId.I32, TypeId.F64 };
    const to_types = [_]TypeId{ TypeId.F64, TypeId.I32 };

    var path = (try registry.findConversionPath(from_types[0..], to_types[0..], std.testing.allocator)).?;
    defer path.deinit();

    try std.testing.expect(path.conversions.len == 2);
    try std.testing.expect(path.total_cost == 15); // 5 + 10
    try std.testing.expect(path.is_lossy); // f64 -> i32 is lossy
}

test "ConversionPath with no conversion needed" {
    var registry = ConversionRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const from_types = [_]TypeId{TypeId.I32};
    const to_types = [_]TypeId{TypeId.I32};

    var path = (try registry.findConversionPath(from_types[0..], to_types[0..], std.testing.allocator)).?;
    defer path.deinit();

    try std.testing.expect(path.conversions.len == 1);
    try std.testing.expect(path.total_cost == 0);
    try std.testing.expect(!path.is_lossy);
}

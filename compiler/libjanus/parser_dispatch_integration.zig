// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const DispatchFamily = @import("dispatch_family.zig").DispatchFamily;
const DispatchFamilyRegistry = @import("dispatch_family.zig").DispatchFamilyRegistry;
const FuncDecl = @import("dispatch_family.zig").FuncDecl;
const SourceLocation = @import("dispatch_family.zig").SourceLocation;

/// Parser integration for dispatch families
pub const ParserDispatchIntegration = struct {
    family_registry: DispatchFamilyRegistry,
    current_module_path: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, module_path: []const u8) ParserDispatchIntegration {
        return ParserDispatchIntegration{
            .family_registry = DispatchFamilyRegistry.init(allocator),
            .current_module_path = module_path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ParserDispatchIntegration) void {
        self.family_registry.deinit();
    }

    /// Process a function declaration during parsing
    pub fn processFunctionDeclaration(
        self: *ParserDispatchIntegration,
        func_name: []const u8,
        param_types: []const u8,
        return_type: []const u8,
        visibility: FuncDecl.VisibilityLevel,
        source_loc: SourceLocation,
    ) !*FuncDecl {
        // Create function declaration
        const func_decl = try self.allocator.create(FuncDecl);
        func_decl.* = FuncDecl{
            .name = try self.allocator.dupe(u8, func_name),
            .parameter_types = try self.allocator.dupe(u8, param_types),
            .return_type = try self.allocator.dupe(u8, return_type),
            .visibility = visibility,
            .module_path = try self.allocator.dupe(u8, self.current_module_path),
            .source_location = source_loc,
            .dispatch_family = null,
            .overload_index = 0,
            .signature_hash = 0,
        };

        // Register with dispatch family
        try self.family_registry.registerFunction(func_decl);

        return func_decl;
    }

    /// Check if a function name represents a dispatch family
    pub fn isDispatchFamily(self: *const ParserDispatchIntegration, func_name: []const u8) bool {
        if (self.family_registry.getFamily(func_name)) |family| {
            return !family.isSingleFunction();
        }
        return false;
    }

    /// Get family information for diagnostics
    pub fn getFamilyInfo(self: *const ParserDispatchIntegration, func_name: []const u8) ?FamilyInfo {
        const family = self.family_registry.getFamily(func_name) orelse return null;

        return FamilyInfo{
            .name = family.name,
            .overload_count = family.getOverloadCount(),
            .is_single_function = family.isSingleFunction(),
            .has_ambiguities = family.hasAmbiguities(),
            .min_arity = family.family_metadata.min_arity,
            .max_arity = family.family_metadata.max_arity,
        };
    }

    pub const FamilyInfo = struct {
        name: []const u8,
        overload_count: u32,
        is_single_function: bool,
        has_ambiguities: bool,
        min_arity: u32,
        max_arity: u32,
    };

    /// Validate all families for conflicts and ambiguities
    pub fn validateFamilies(self: *const ParserDispatchIntegration) !ValidationResult {
        var result = ValidationResult{
            .is_valid = true,
            .conflicts = std.ArrayList(ConflictInfo).init(self.allocator),
            .ambiguities = std.ArrayList(AmbiguityInfo).init(self.allocator),
        };

        // Validate registry
        self.family_registry.validateAllFamilies() catch |err| {
            result.is_valid = false;

            if (err == error.ConflictingSignatures) {
                // Collect detailed conflict information
                try self.collectConflictInfo(&result);
            }
        };

        // Check for ambiguities
        try self.collectAmbiguityInfo(&result);

        return result;
    }

    fn collectConflictInfo(self: *const ParserDispatchIntegration, result: *ValidationResult) !void {
        const families = try self.family_registry.getAllFamilies(self.allocator);
        defer self.allocator.free(families);

        for (families) |family| {
            const overloads = family.getAllOverloads();

            for (overloads, 0..) |func1, i| {
                for (overloads[i + 1 ..]) |func2| {
                    if (family.signaturesConflict(func1, func2)) {
                        try result.conflicts.append(ConflictInfo{
                            .family_name = family.name,
                            .func1_location = func1.source_location,
                            .func2_location = func2.source_location,
                            .conflict_type = .identical_signature,
                        });
                    }
                }
            }
        }
    }

    fn collectAmbiguityInfo(self: *const ParserDispatchIntegration, result: *ValidationResult) !void {
        const families = try self.family_registry.getAllFamilies(self.allocator);
        defer self.allocator.free(families);

        for (families) |family| {
            if (family.hasAmbiguities()) {
                try result.ambiguities.append(AmbiguityInfo{
                    .family_name = family.name,
                    .overload_count = family.getOverloadCount(),
                    .ambiguity_type = .potential_runtime_ambiguity,
                });
            }
        }
    }

    pub const ValidationResult = struct {
        is_valid: bool,
        conflicts: std.ArrayList(ConflictInfo),
        ambiguities: std.ArrayList(AmbiguityInfo),

        pub fn deinit(self: *ValidationResult) void {
            self.conflicts.deinit();
            self.ambiguities.deinit();
        }
    };

    pub const ConflictInfo = struct {
        family_name: []const u8,
        func1_location: SourceLocation,
        func2_location: SourceLocation,
        conflict_type: ConflictType,

        pub const ConflictType = enum {
            identical_signature,
            ambiguous_overload,
        };
    };

    pub const AmbiguityInfo = struct {
        family_name: []const u8,
        overload_count: u32,
        ambiguity_type: AmbiguityType,

        pub const AmbiguityType = enum {
            potential_runtime_ambiguity,
            unresolvable_overload,
        };
    };

    /// Generate dispatch table information for code generation
    pub fn generateDispatchTables(self: *const ParserDispatchIntegration) !DispatchTableInfo {
        const families = try self.family_registry.getAllFamilies(self.allocator);

        var table_info = DispatchTableInfo{
            .families = families,
            .total_families = @intCast(families.len),
            .total_overloads = self.family_registry.getTotalOverloads(),
            .single_function_families = 0,
            .multi_function_families = 0,
        };

        // Calculate statistics
        for (families) |family| {
            if (family.isSingleFunction()) {
                table_info.single_function_families += 1;
            } else {
                table_info.multi_function_families += 1;
            }
        }

        return table_info;
    }

    pub const DispatchTableInfo = struct {
        families: []const *DispatchFamily,
        total_families: u32,
        total_overloads: u32,
        single_function_families: u32,
        multi_function_families: u32,

        pub fn deinit(self: *DispatchTableInfo, allocator: Allocator) void {
            allocator.free(self.families);
        }

        pub fn getDispatchRatio(self: *const DispatchTableInfo) f32 {
            if (self.total_families == 0) return 0.0;
            return @as(f32, @floatFromInt(self.multi_function_families)) /
                @as(f32, @floatFromInt(self.total_families));
        }
    };

    /// Get registry statistics for debugging
    pub fn getRegistryStats(self: *const ParserDispatchIntegration) RegistryStats {
        return RegistryStats{
            .family_count = self.family_registry.getFamilyCount(),
            .total_overloads = self.family_registry.getTotalOverloads(),
            .module_path = self.current_module_path,
        };
    }

    pub const RegistryStats = struct {
        family_count: u32,
        total_overloads: u32,
        module_path: []const u8,
    };
};

/// AST node extensions for dispatch integration
pub const DispatchASTExtensions = struct {
    /// Enhanced function call node with dispatch information
    pub const CallExpr = struct {
        function_name: []const u8,
        arguments: []Expr,
        source_location: SourceLocation,

        // Dispatch integration fields
        target_family: ?*DispatchFamily,
        resolved_overload: ?*FuncDecl,
        dispatch_method: DispatchMethod,

        pub const DispatchMethod = enum {
            static_resolved, // Resolved at compile time
            dynamic_dispatch, // Requires runtime dispatch
            unresolved, // Not yet resolved
        };

        pub fn isStaticallyResolved(self: *const CallExpr) bool {
            return self.dispatch_method == .static_resolved and self.resolved_overload != null;
        }

        pub fn requiresDynamicDispatch(self: *const CallExpr) bool {
            return self.dispatch_method == .dynamic_dispatch;
        }
    };

    /// Placeholder for expression types
    pub const Expr = struct {
        // Simplified expression representation
        expr_type: ExprType,

        pub const ExprType = enum {
            literal,
            identifier,
            call,
        };
    };

    /// Enhanced function declaration node
    pub const FunctionDeclAST = struct {
        base_decl: FuncDecl,
        body: ?[]Stmt,

        // Dispatch integration
        is_overload: bool,
        family_reference: ?*DispatchFamily,

        pub fn attachToDispatchFamily(self: *FunctionDeclAST, family: *DispatchFamily) !void {
            try self.base_decl.attachToFamily(family);
            self.family_reference = family;
            self.is_overload = !family.isSingleFunction();
        }
    };

    /// Placeholder for statement types
    pub const Stmt = struct {
        stmt_type: StmtType,

        pub const StmtType = enum {
            expression,
            return_stmt,
            assignment,
        };
    };
};

// Tests
test "ParserDispatchIntegration basic functionality" {
    var integration = ParserDispatchIntegration.init(std.testing.allocator, "test_module");
    defer integration.deinit();

    const source_loc = SourceLocation{
        .file = "test.jan",
        .line = 1,
        .column = 1,
        .start_byte = 0,
        .end_byte = 10,
    };

    // Process function declarations
    const func1 = try integration.processFunctionDeclaration(
        "add",
        "i32,i32",
        "i32",
        .public,
        source_loc,
    );

    const func2 = try integration.processFunctionDeclaration(
        "add",
        "f64,f64",
        "f64",
        .public,
        source_loc,
    );

    // Test family detection
    try std.testing.expect(integration.isDispatchFamily("add"));

    // Test family info
    const family_info = integration.getFamilyInfo("add").?;
    try std.testing.expect(family_info.overload_count == 2);
    try std.testing.expect(!family_info.is_single_function);

    // Test registry stats
    const stats = integration.getRegistryStats();
    try std.testing.expect(stats.family_count == 1);
    try std.testing.expect(stats.total_overloads == 2);

    // Cleanup
    integration.allocator.destroy(func1);
    integration.allocator.destroy(func2);
}

test "Validation and conflict detection" {
    var integration = ParserDispatchIntegration.init(std.testing.allocator, "test_module");
    defer integration.deinit();

    const source_loc = SourceLocation{
        .file = "test.jan",
        .line = 1,
        .column = 1,
        .start_byte = 0,
        .end_byte = 10,
    };

    // Add valid functions
    const func1 = try integration.processFunctionDeclaration(
        "test_func",
        "i32",
        "i32",
        .public,
        source_loc,
    );

    const func2 = try integration.processFunctionDeclaration(
        "test_func",
        "f64",
        "f64",
        .public,
        source_loc,
    );

    // Validate families
    var validation_result = try integration.validateFamilies();
    defer validation_result.deinit();

    try std.testing.expect(validation_result.is_valid);
    try std.testing.expect(validation_result.conflicts.items.len == 0);

    // Cleanup
    integration.allocator.destroy(func1);
    integration.allocator.destroy(func2);
}

test "Dispatch table generation" {
    var integration = ParserDispatchIntegration.init(std.testing.allocator, "test_module");
    defer integration.deinit();

    const source_loc = SourceLocation{
        .file = "test.jan",
        .line = 1,
        .column = 1,
        .start_byte = 0,
        .end_byte = 10,
    };

    // Add functions
    const func1 = try integration.processFunctionDeclaration("single", "i32", "i32", .public, source_loc);
    const func2 = try integration.processFunctionDeclaration("multi", "i32", "i32", .public, source_loc);
    const func3 = try integration.processFunctionDeclaration("multi", "f64", "f64", .public, source_loc);

    // Generate dispatch tables
    var table_info = try integration.generateDispatchTables();
    defer table_info.deinit(std.testing.allocator);

    try std.testing.expect(table_info.total_families == 2);
    try std.testing.expect(table_info.total_overloads == 3);
    try std.testing.expect(table_info.single_function_families == 1);
    try std.testing.expect(table_info.multi_function_families == 1);

    const dispatch_ratio = table_info.getDispatchRatio();
    try std.testing.expect(dispatch_ratio == 0.5); // 1 multi-function family out of 2 total

    // Cleanup
    integration.allocator.destroy(func1);
    integration.allocator.destroy(func2);
    integration.allocator.destroy(func3);
}

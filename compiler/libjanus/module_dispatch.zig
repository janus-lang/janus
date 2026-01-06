// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;

/// Module identifier and metadata
pub const ModuleInfo = struct {
    id: u32,
    name: []const u8,
    path: []const u8,
    version: Version,
    dependencies: []const ModuleDependency,
    exports: []const ExportedSignature,
    imports: []const ImportedSignature,
    is_loaded: bool,
    load_timestamp: i64,

    pub const Version = struct {
        major: u32,
        minor: u32,
        patch: u32,

        pub fn format(self: Version, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{}.{}.{}", .{ self.major, self.minor, self.patch });
        }
    };

    pub const ModuleDependency = struct {
        module_name: []const u8,
        version_constraint: VersionConstraint,
        is_optional: bool,

        pub const VersionConstraint = union(enum) {
            exact: Version,
            minimum: Version,
            range: struct { min: Version, max: Version },
            any,
        };
    };

    pub fn format(self: ModuleInfo, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Module({s} v{} at {s})", .{ self.name, self.version, self.path });
        if (self.is_loaded) {
            try writer.print(" [loaded]", .{});
        }
    }
};

/// Exported signature from a module
pub const ExportedSignature = struct {
    signature_name: []const u8,
    module_id: u32,
    implementations: []const *const SignatureAnalyzer.Implementation,
    visibility: Visibility,
    export_name: ?[]const u8, // Custom export name if different from signature name

    pub const Visibility = enum {
        public, // Exported to all modules
        protected, // Exported only to dependent modules
        internal, // Not exported (module-internal only)
    };

    pub fn format(self: ExportedSignature, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("export {s}", .{self.signature_name});
        if (self.export_name) |name| {
            try writer.print(" as {s}", .{name});
        }
        try writer.print(" ({} impls, {})", .{ self.implementations.len, self.visibility });
    }
};

/// Imported signature into a module
pub const ImportedSignature = struct {
    signature_name: []const u8,
    source_module_id: u32,
    local_name: ?[]const u8, // Local alias if different from original name
    import_mode: ImportMode,
    conflict_resolution: ConflictResolution,

    pub const ImportMode = enum {
        qualified, // module.signature_name
        unqualified, // signature_name (direct import)
        selective, // Import specific implementations only
    };

    pub const ConflictResolution = enum {
        fail_on_conflict, // Fail on conflicts
        prefer_local, // Local implementations take precedence
        prefer_imported, // Imported implementations take precedence
        merge, // Merge all implementations
    };

    pub fn format(self: ImportedSignature, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("import {s}", .{self.signature_name});
        if (self.local_name) |name| {
            try writer.print(" as {s}", .{name});
        }
        try writer.print(" ({})", .{self.import_mode});
    }
};

/// Cross-module dispatch conflict
pub const ModuleConflict = struct {
    signature_name: []const u8,
    conflicting_modules: []const ConflictingModule,
    conflict_type: ConflictType,
    resolution_strategy: ?ConflictResolution,

    pub const ConflictingModule = struct {
        module_id: u32,
        module_name: []const u8,
        implementations: []const *const SignatureAnalyzer.Implementation,
        import_priority: u32,
    };

    pub const ConflictType = enum {
        signature_name_collision,
        implementation_ambiguity,
        version_incompatibility,
        circular_dependency,
    };

    pub const ConflictResolution = enum {
        manual_qualification,
        priority_based,
        merge_compatible,
        exclude_module,
    };

    pub fn format(self: ModuleConflict, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Conflict: {s} ({}) between {} modules", .{ self.signature_name, self.conflict_type, self.conflicting_modules.len });
    }
};

/// Qualified function call for disambiguation
pub const QualifiedCall = struct {
    module_name: []const u8,
    signature_name: []const u8,
    target_implementation: ?*const SignatureAnalyzer.Implementation,
    bypass_dispatch: bool,

    pub fn format(self: QualifiedCall, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}::{s}", .{ self.module_name, self.signature_name });
        if (self.bypass_dispatch) {
            try writer.print(" (direct)", .{});
        }
    }
};

/// Merged dispatch table for cross-module signatures
pub const MergedDispatchTable = struct {
    allocator: Allocator,
    implementations: ArrayList(*const SignatureAnalyzer.Implementation),
    priority_order: []const u32,
    is_consistent: bool,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .implementations = ArrayList(*const SignatureAnalyzer.Implementation).init(allocator),
            .priority_order = &.{},
            .is_consistent = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.implementations.deinit();
        self.allocator.free(self.priority_order);
    }

    pub fn buildFromImplementations(
        self: *Self,
        impls: []const *const SignatureAnalyzer.Implementation,
        module_priority_order: []const u32,
    ) !void {
        // Clear existing data
        self.implementations.clearAndFree();
        self.allocator.free(self.priority_order);

        // Copy implementations
        for (impls) |impl| {
            try self.implementations.append(impl);
        }

        // Copy priority order
        self.priority_order = try self.allocator.dupe(u32, module_priority_order);

        // Sort implementations by module priority and specificity
        try self.sortByPriority();

        // Check for consistency
        self.is_consistent = self.checkConsistency();
    }

    fn sortByPriority(self: *Self) !void {
        // Sort implementations based on module priority and specificity
        const Context = struct {
            priority_order: []const u32,

            pub fn lessThan(ctx: @This(), a: *const SignatureAnalyzer.Implementation, b: *const SignatureAnalyzer.Implementation) bool {
                // First sort by module priority
                const a_priority = ctx.getModulePriority(a.function_id.module);
                const b_priority = ctx.getModulePriority(b.function_id.module);

                if (a_priority != b_priority) {
                    return a_priority < b_priority;
                }

                // Then by specificity (higher specificity first)
                return a.specificity_rank > b.specificity_rank;
            }

            fn getModulePriority(ctx: @This(), module_name: []const u8) u32 {
                // Find module priority in the order list
                for (ctx.priority_order, 0..) |module_id, i| {
                    _ = module_id; // TODO: Map module_id to module_name
                    _ = module_name;
                    return @as(u32, @intCast(i));
                }
                return std.math.maxInt(u32); // Unknown modules get lowest priority
            }
        };

        const context = Context{ .priority_order = self.priority_order };
        std.mem.sort(*const SignatureAnalyzer.Implementation, self.implementations.items, context, Context.lessThan);
    }

    fn checkConsistency(self: *Self) bool {
        // Check for conflicting implementations with same specificity
        for (self.implementations.items, 0..) |impl_a, i| {
            for (self.implementations.items[i + 1 ..]) |impl_b| {
                if (impl_a.specificity_rank == impl_b.specificity_rank) {
                    // Same specificity from different modules - potential conflict
                    if (!std.mem.eql(u8, impl_a.function_id.module, impl_b.function_id.module)) {
                        return false;
                    }
                }
            }
        }
        return true;
    }
};

/// Dispatch consistency report
pub const DispatchConsistencyReport = struct {
    allocator: Allocator,
    inconsistencies: ArrayList(Inconsistency),

    const Self = @This();

    pub const Inconsistency = struct {
        type: InconsistencyType,
        signature_name: []const u8,
        module_id: u32,
        description: []const u8,
    };

    pub const InconsistencyType = enum {
        missing_module,
        unloaded_module,
        unresolved_conflict,
        circular_dependency,
        version_mismatch,
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .inconsistencies = ArrayList(Inconsistency).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.inconsistencies.items) |inconsistency| {
            self.allocator.free(inconsistency.description);
        }
        self.inconsistencies.deinit();
    }

    pub fn addInconsistency(self: *Self, inconsistency: Inconsistency) !void {
        const owned_inconsistency = Inconsistency{
            .type = inconsistency.type,
            .signature_name = inconsistency.signature_name,
            .module_id = inconsistency.module_id,
            .description = try self.allocator.dupe(u8, inconsistency.description),
        };
        try self.inconsistencies.append(owned_inconsistency);
    }

    pub fn hasInconsistencies(self: *Self) bool {
        return self.inconsistencies.items.len > 0;
    }

    pub fn format(self: DispatchConsistencyReport, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Dispatch Consistency Report: {} inconsistencies found\n", .{self.inconsistencies.items.len});
        for (self.inconsistencies.items) |inconsistency| {
            try writer.print("  - {}: {} (module {}): {s}\n", .{
                inconsistency.type,
                inconsistency.signature_name,
                inconsistency.module_id,
                inconsistency.description,
            });
        }
    }
};

/// Cross-module multiple dispatch system
pub const ModuleDispatcher = struct {
    allocator: Allocator,
    type_registry: *const TypeRegistry,
    signature_analyzer: *const SignatureAnalyzer,
    specificity_analyzer: *SpecificityAnalyzer,

    // Module management
    modules: std.AutoHashMap(u32, ModuleInfo),
    module_name_to_id: std.StringHashMap(u32),
    next_module_id: u32,

    // Cross-module signatures
    global_signatures: std.StringHashMap(CrossModuleSignature),
    module_exports: std.AutoHashMap(u32, ArrayList(ExportedSignature)),
    module_imports: std.AutoHashMap(u32, ArrayList(ImportedSignature)),

    // Conflict tracking
    active_conflicts: ArrayList(ModuleConflict),
    conflict_resolutions: std.StringHashMap(ModuleConflict.ConflictResolution),

    // Qualified call cache
    qualified_call_cache: std.StringHashMap(QualifiedCall),

    // INTEGRATION: Compression support for cross-module dispatch tables
    dispatch_table_optimizer: @import("dispatch_table_optimizer.zig").DispatchTableOptimizer,
    compression_config: @import("dispatch_table_optimizer.zig").DispatchTableOptimizer.OptimizationConfig,
    compressed_dispatch_tables: std.StringHashMap(*@import("optimized_dispatch_tables.zig").OptimizedDispatchTable),

    const CrossModuleSignature = struct {
        signature_name: []const u8,
        participating_modules: ArrayList(u32),
        merged_implementations: ArrayList(*const SignatureAnalyzer.Implementation),
        resolution_order: []const u32, // Module priority order
        is_ambiguous: bool,
    };

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        type_registry: *const TypeRegistry,
        signature_analyzer: *const SignatureAnalyzer,
        specificity_analyzer: *SpecificityAnalyzer,
    ) Self {
        return Self{
            .allocator = allocator,
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
            .modules = std.AutoHashMap(u32, ModuleInfo).init(allocator),
            .module_name_to_id = std.StringHashMap(u32).init(allocator),
            .next_module_id = 1,
            .global_signatures = std.StringHashMap(CrossModuleSignature).init(allocator),
            .module_exports = std.AutoHashMap(u32, ArrayList(ExportedSignature)).init(allocator),
            .module_imports = std.AutoHashMap(u32, ArrayList(ImportedSignature)).init(allocator),
            .active_conflicts = ArrayList(ModuleConflict).init(allocator),
            .conflict_resolutions = std.StringHashMap(ModuleConflict.ConflictResolution).init(allocator),
            .qualified_call_cache = std.StringHashMap(QualifiedCall).init(allocator),
            // INTEGRATION: Initialize compression system
            .dispatch_table_optimizer = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer.init(allocator),
            .compression_config = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer.OptimizationConfig.default(),
            .compressed_dispatch_tables = std.StringHashMap(*@import("optimized_dispatch_tables.zig").OptimizedDispatchTable).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // INTEGRATION: Clean up compression system
        var compressed_iter = self.compressed_dispatch_tables.iterator();
        while (compressed_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.compressed_dispatch_tables.deinit();
        self.dispatch_table_optimizer.deinit();

        // Clean up modules
        var module_iter = self.modules.iterator();
        while (module_iter.next()) |entry| {
            self.freeModuleInfo(entry.value_ptr);
        }
        self.modules.deinit();
        self.module_name_to_id.deinit();

        // Clean up global signatures
        var sig_iter = self.global_signatures.iterator();
        while (sig_iter.next()) |entry| {
            self.freeCrossModuleSignature(entry.value_ptr);
        }
        self.global_signatures.deinit();

        // Clean up exports and imports
        var export_iter = self.module_exports.iterator();
        while (export_iter.next()) |entry| {
            for (entry.value_ptr.items) |*exported_sig| {
                self.freeExportedSignature(exported_sig);
            }
            entry.value_ptr.deinit();
        }
        self.module_exports.deinit();

        var import_iter = self.module_imports.iterator();
        while (import_iter.next()) |entry| {
            for (entry.value_ptr.items) |*imported_sig| {
                self.freeImportedSignature(imported_sig);
            }
            entry.value_ptr.deinit();
        }
        self.module_imports.deinit();

        // Clean up conflicts
        for (self.active_conflicts.items) |*conflict| {
            self.freeModuleConflict(conflict);
        }
        self.active_conflicts.deinit();
        self.conflict_resolutions.deinit();
        self.qualified_call_cache.deinit();
    }

    /// Register a new module
    pub fn registerModule(
        self: *Self,
        name: []const u8,
        path: []const u8,
        version: ModuleInfo.Version,
        dependencies: []const ModuleInfo.ModuleDependency,
    ) !u32 {
        const module_id = self.next_module_id;
        self.next_module_id += 1;

        const module_info = ModuleInfo{
            .id = module_id,
            .name = try self.allocator.dupe(u8, name),
            .path = try self.allocator.dupe(u8, path),
            .version = version,
            .dependencies = try self.allocator.dupe(ModuleInfo.ModuleDependency, dependencies),
            .exports = &.{},
            .imports = &.{},
            .is_loaded = false,
            .load_timestamp = std.time.timestamp(),
        };

        try self.modules.put(module_id, module_info);
        try self.module_name_to_id.put(try self.allocator.dupe(u8, name), module_id);
        try self.module_exports.put(module_id, ArrayList(ExportedSignature).init(self.allocator));
        try self.module_imports.put(module_id, ArrayList(ImportedSignature).init(self.allocator));

        return module_id;
    }

    /// Export a signature from a module
    pub fn exportSignature(
        self: *Self,
        module_id: u32,
        signature_name: []const u8,
        implementations: []const *const SignatureAnalyzer.Implementation,
        visibility: ExportedSignature.Visibility,
        export_name: ?[]const u8,
    ) !void {
        var exports = self.module_exports.get(module_id) orelse return error.ModuleNotFound;

        const exported_sig = ExportedSignature{
            .signature_name = try self.allocator.dupe(u8, signature_name),
            .module_id = module_id,
            .implementations = try self.allocator.dupe(*const SignatureAnalyzer.Implementation, implementations),
            .visibility = visibility,
            .export_name = if (export_name) |name| try self.allocator.dupe(u8, name) else null,
        };

        try exports.append(exported_sig);

        // Update global signature registry
        try self.updateGlobalSignature(signature_name, module_id, implementations);
    }

    /// Import a signature into a module
    pub fn importSignature(
        self: *Self,
        target_module_id: u32,
        source_module_id: u32,
        signature_name: []const u8,
        local_name: ?[]const u8,
        import_mode: ImportedSignature.ImportMode,
        conflict_resolution: ImportedSignature.ConflictResolution,
    ) !void {
        var imports = self.module_imports.get(target_module_id) orelse return error.ModuleNotFound;

        // Verify the source module exports this signature
        if (!try self.moduleExportsSignature(source_module_id, signature_name)) {
            return error.SignatureNotExported;
        }

        const imported_sig = ImportedSignature{
            .signature_name = try self.allocator.dupe(u8, signature_name),
            .source_module_id = source_module_id,
            .local_name = if (local_name) |name| try self.allocator.dupe(u8, name) else null,
            .import_mode = import_mode,
            .conflict_resolution = conflict_resolution,
        };

        try imports.append(imported_sig);

        // Check for conflicts
        try self.checkImportConflicts(target_module_id, &imported_sig);
    }

    /// Resolve cross-module dispatch
    pub fn resolveCrossModuleDispatch(
        self: *Self,
        calling_module_id: u32,
        signature_name: []const u8,
        argument_types: []const TypeId,
        qualified_call: ?QualifiedCall,
    ) !?*const SignatureAnalyzer.Implementation {
        // Handle qualified calls first
        if (qualified_call) |qual_call| {
            return try self.resolveQualifiedCall(&qual_call, argument_types);
        }

        // Get all available implementations for this signature
        const available_impls = try self.getAvailableImplementations(calling_module_id, signature_name);
        defer self.allocator.free(available_impls);

        if (available_impls.len == 0) return null;

        // Use specificity analysis to select the best implementation
        var result = try self.specificity_analyzer.findMostSpecific(available_impls, argument_types);
        defer result.deinit(self.allocator);

        switch (result) {
            .unique => |impl| return impl,
            .ambiguous => {
                // Check if we have conflict resolution rules
                if (self.conflict_resolutions.get(signature_name)) |resolution| {
                    return try self.applyConflictResolution(resolution, available_impls, argument_types);
                }
                return null; // Ambiguous without resolution
            },
            .no_match => return null,
        }
    }

    /// Create a qualified call
    pub fn createQualifiedCall(
        self: *Self,
        module_name: []const u8,
        signature_name: []const u8,
        bypass_dispatch: bool,
    ) !QualifiedCall {
        const cache_key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ module_name, signature_name });
        defer self.allocator.free(cache_key);

        if (self.qualified_call_cache.get(cache_key)) |cached| {
            return cached;
        }

        const module_id = self.module_name_to_id.get(module_name) orelse return error.ModuleNotFound;

        // Find the target implementation if bypassing dispatch
        var target_impl: ?*const SignatureAnalyzer.Implementation = null;
        if (bypass_dispatch) {
            target_impl = try self.findDirectImplementation(module_id, signature_name);
        }

        const qualified_call = QualifiedCall{
            .module_name = try self.allocator.dupe(u8, module_name),
            .signature_name = try self.allocator.dupe(u8, signature_name),
            .target_implementation = target_impl,
            .bypass_dispatch = bypass_dispatch,
        };

        try self.qualified_call_cache.put(try self.allocator.dupe(u8, cache_key), qualified_call);
        return qualified_call;
    }

    /// Get all active conflicts
    pub fn getActiveConflicts(self: *Self) []const ModuleConflict {
        return self.active_conflicts.items;
    }

    /// Resolve a conflict manually
    pub fn resolveConflict(
        self: *Self,
        signature_name: []const u8,
        resolution: ModuleConflict.ConflictResolution,
    ) !void {
        try self.conflict_resolutions.put(try self.allocator.dupe(u8, signature_name), resolution);

        // Remove from active conflicts
        for (self.active_conflicts.items, 0..) |conflict, i| {
            if (std.mem.eql(u8, conflict.signature_name, signature_name)) {
                _ = self.active_conflicts.swapRemove(i);
                break;
            }
        }
    }

    /// Get module information
    pub fn getModuleInfo(self: *Self, module_id: u32) ?*const ModuleInfo {
        return self.modules.getPtr(module_id);
    }

    /// Get module ID by name
    pub fn getModuleId(self: *Self, module_name: []const u8) ?u32 {
        return self.module_name_to_id.get(module_name);
    }

    /// List all registered modules
    pub fn getAllModules(self: *Self) ![]const ModuleInfo {
        var modules = ArrayList(ModuleInfo).init(self.allocator);
        defer modules.deinit();

        var iter = self.modules.iterator();
        while (iter.next()) |entry| {
            try modules.append(entry.value_ptr.*);
        }

        return self.allocator.dupe(ModuleInfo, modules.items);
    }

    /// Load a module and update dispatch tables incrementally
    pub fn loadModule(self: *Self, module_id: u32) !void {
        var module_info = self.modules.getPtr(module_id) orelse return error.ModuleNotFound;

        if (module_info.is_loaded) {
            return; // Already loaded
        }

        // Mark as loaded
        module_info.is_loaded = true;
        module_info.load_timestamp = std.time.timestamp();

        // Update dispatch tables for all signatures this module participates in
        try self.updateDispatchTablesForModule(module_id);

        // Resolve any conflicts that may have been introduced
        try self.resolveModuleLoadConflicts(module_id);
    }

    /// Unload a module and update dispatch tables
    pub fn unloadModule(self: *Self, module_id: u32) !void {
        var module_info = self.modules.getPtr(module_id) orelse return error.ModuleNotFound;

        if (!module_info.is_loaded) {
            return; // Already unloaded
        }

        // Remove from global signatures
        try self.removeModuleFromGlobalSignatures(module_id);

        // Mark as unloaded
        module_info.is_loaded = false;

        // Update dispatch tables
        try self.updateDispatchTablesAfterUnload(module_id);
    }

    /// Hot-reload a module with dispatch table regeneration
    pub fn hotReloadModule(self: *Self, module_id: u32, new_exports: []const ExportedSignature) !void {
        // First unload the old version
        try self.unloadModule(module_id);

        // Clear old exports
        if (self.module_exports.getPtr(module_id)) |exports| {
            for (exports.items) |*exported_sig| {
                self.freeExportedSignature(exported_sig);
            }
            exports.clearAndFree();
        }

        // Add new exports
        var exports = self.module_exports.get(module_id) orelse return error.ModuleNotFound;
        for (new_exports) |new_export| {
            const exported_sig = ExportedSignature{
                .signature_name = try self.allocator.dupe(u8, new_export.signature_name),
                .module_id = module_id,
                .implementations = try self.allocator.dupe(*const SignatureAnalyzer.Implementation, new_export.implementations),
                .visibility = new_export.visibility,
                .export_name = if (new_export.export_name) |name| try self.allocator.dupe(u8, name) else null,
            };
            try exports.append(exported_sig);

            // Update global signature registry
            try self.updateGlobalSignature(new_export.signature_name, module_id, new_export.implementations);
        }

        // Reload the module
        try self.loadModule(module_id);
    }

    /// Merge dispatch tables efficiently for cross-module signature groups
    pub fn mergeDispatchTables(self: *Self, signature_name: []const u8) !MergedDispatchTable {
        const global_sig = self.global_signatures.get(signature_name) orelse return error.SignatureNotFound;

        var merged_table = MergedDispatchTable.init(self.allocator);
        errdefer merged_table.deinit();

        // Collect all implementations from participating modules
        var all_implementations = ArrayList(*const SignatureAnalyzer.Implementation).init(self.allocator);
        defer all_implementations.deinit();

        for (global_sig.participating_modules.items) |module_id| {
            const module_info = self.modules.get(module_id) orelse continue;
            if (!module_info.is_loaded) continue;

            const exports = self.module_exports.get(module_id) orelse continue;
            for (exports.items) |exported_sig| {
                if (std.mem.eql(u8, exported_sig.signature_name, signature_name)) {
                    for (exported_sig.implementations) |impl| {
                        try all_implementations.append(impl);
                    }
                }
            }
        }

        // Build merged dispatch table with priority ordering
        try merged_table.buildFromImplementations(all_implementations.items, global_sig.resolution_order);

        return merged_table;
    }

    /// INTEGRATION: Create and compress cross-module dispatch table
    pub fn createCompressedDispatchTable(self: *Self, signature_name: []const u8) !*@import("optimized_dispatch_tables.zig").OptimizedDispatchTable {
        // Check if already compressed
        if (self.compressed_dispatch_tables.get(signature_name)) |existing| {
            return existing;
        }

        const global_sig = self.global_signatures.get(signature_name) orelse return error.SignatureNotFound;

        // Collect all implementations and create type signature
        var all_implementations = ArrayList(*const SignatureAnalyzer.Implementation).init(self.allocator);
        defer all_implementations.deinit();

        var type_signature = ArrayList(TypeId).init(self.allocator);
        defer type_signature.deinit();

        for (global_sig.participating_modules.items) |module_id| {
            const module_info = self.modules.get(module_id) orelse continue;
            if (!module_info.is_loaded) continue;

            const exports = self.module_exports.get(module_id) orelse continue;
            for (exports.items) |exported_sig| {
                if (std.mem.eql(u8, exported_sig.signature_name, signature_name)) {
                    for (exported_sig.implementations) |impl| {
                        try all_implementations.append(impl);

                        // Build type signature from first implementation
                        if (type_signature.items.len == 0) {
                            for (impl.param_type_ids) |type_id| {
                                try type_signature.append(type_id);
                            }
                        }
                    }
                }
            }
        }

        // Create optimized dispatch table
        const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
        var table = try self.allocator.create(OptimizedDispatchTable);
        table.* = try OptimizedDispatchTable.init(self.allocator, signature_name, type_signature.items);

        // Add all implementations to the table
        for (all_implementations.items) |impl| {
            try table.addImplementation(impl);
        }

        // Apply compression optimization
        _ = try self.dispatch_table_optimizer.optimizeTable(table, self.compression_config);

        // Store the compressed table
        try self.compressed_dispatch_tables.put(try self.allocator.dupe(u8, signature_name), table);

        return table;
    }

    /// INTEGRATION: Configure compression settings for cross-module dispatch
    pub fn configureCompression(self: *Self, config: @import("dispatch_table_optimizer.zig").DispatchTableOptimizer.OptimizationConfig) void {
        self.compression_config = config;
    }

    /// INTEGRATION: Get compression statistics for all cross-module dispatch tables
    pub fn getCompressionReport(self: *Self, writer: anytype) !void {
        try writer.print("Cross-Module Dispatch Compression Report\n");
        try writer.print("=======================================\n\n");

        var total_original: usize = 0;
        var total_compressed: usize = 0;
        var table_count: u32 = 0;

        var iter = self.compressed_dispatch_tables.iterator();
        while (iter.next()) |entry| {
            const signature_name = entry.key_ptr.*;
            const table = entry.value_ptr.*;

            if (table.getCompressionStats()) |stats| {
                try writer.print("Signature '{}': {}\n", .{ signature_name, stats });
                total_original += stats.original_bytes;
                total_compressed += stats.compressed_bytes;
                table_count += 1;
            }
        }

        if (table_count > 0) {
            const overall_ratio = @as(f32, @floatFromInt(total_compressed)) / @as(f32, @floatFromInt(total_original));
            try writer.print("\nOverall: {} tables, {} -> {} bytes ({d:.1}% compression)\n", .{
                table_count,
                total_original,
                total_compressed,
                overall_ratio * 100.0,
            });
        }

        // Include optimizer statistics
        try writer.print("\n");
        try self.dispatch_table_optimizer.generateOptimizationReport(writer);
    }

    /// Check dispatch consistency after module operations
    pub fn checkDispatchConsistency(self: *Self) !DispatchConsistencyReport {
        var report = DispatchConsistencyReport.init(self.allocator);
        errdefer report.deinit();

        // Check all global signatures for consistency
        var sig_iter = self.global_signatures.iterator();
        while (sig_iter.next()) |entry| {
            const signature_name = entry.key_ptr.*;
            const global_sig = entry.value_ptr;

            // Verify all participating modules are consistent
            for (global_sig.participating_modules.items) |module_id| {
                const module_info = self.modules.get(module_id) orelse {
                    try report.addInconsistency(.{
                        .type = .missing_module,
                        .signature_name = signature_name,
                        .module_id = module_id,
                        .description = "Module referenced in global signature but not found",
                    });
                    continue;
                };

                if (!module_info.is_loaded) {
                    try report.addInconsistency(.{
                        .type = .unloaded_module,
                        .signature_name = signature_name,
                        .module_id = module_id,
                        .description = "Module participating in signature but not loaded",
                    });
                }
            }

            // Check for unresolved conflicts
            if (global_sig.is_ambiguous and !self.conflict_resolutions.contains(signature_name)) {
                try report.addInconsistency(.{
                    .type = .unresolved_conflict,
                    .signature_name = signature_name,
                    .module_id = 0,
                    .description = "Signature has ambiguous implementations without resolution",
                });
            }
        }

        return report;
    }

    /// Update global signature registry
    fn updateGlobalSignature(
        self: *Self,
        signature_name: []const u8,
        module_id: u32,
        implementations: []const *const SignatureAnalyzer.Implementation,
    ) !void {
        var global_sig = self.global_signatures.get(signature_name) orelse CrossModuleSignature{
            .signature_name = try self.allocator.dupe(u8, signature_name),
            .participating_modules = ArrayList(u32).init(self.allocator),
            .merged_implementations = ArrayList(*const SignatureAnalyzer.Implementation).init(self.allocator),
            .resolution_order = &.{},
            .is_ambiguous = false,
        };

        // Add module if not already participating
        var already_participating = false;
        for (global_sig.participating_modules.items) |existing_module| {
            if (existing_module == module_id) {
                already_participating = true;
                break;
            }
        }

        if (!already_participating) {
            try global_sig.participating_modules.append(module_id);
        }

        // Add implementations
        for (implementations) |impl| {
            try global_sig.merged_implementations.append(impl);
        }

        // Check for ambiguity
        if (global_sig.merged_implementations.items.len > 1) {
            global_sig.is_ambiguous = try self.checkSignatureAmbiguity(&global_sig);
        }

        try self.global_signatures.put(try self.allocator.dupe(u8, signature_name), global_sig);
    }

    /// Check if a module exports a signature
    fn moduleExportsSignature(self: *Self, module_id: u32, signature_name: []const u8) !bool {
        const exports = self.module_exports.get(module_id) orelse return false;

        for (exports.items) |exported_sig| {
            if (std.mem.eql(u8, exported_sig.signature_name, signature_name)) {
                return true;
            }
        }

        return false;
    }

    /// Check for import conflicts
    fn checkImportConflicts(self: *Self, module_id: u32, imported_sig: *const ImportedSignature) !void {
        const imports = self.module_imports.get(module_id) orelse return;

        // Check for name conflicts with existing imports
        for (imports.items) |existing_import| {
            const existing_name = existing_import.local_name orelse existing_import.signature_name;
            const new_name = imported_sig.local_name orelse imported_sig.signature_name;

            if (std.mem.eql(u8, existing_name, new_name) and
                existing_import.source_module_id != imported_sig.source_module_id)
            {
                try self.recordConflict(imported_sig.signature_name, &[_]u32{ existing_import.source_module_id, imported_sig.source_module_id });
            }
        }
    }

    /// Record a module conflict
    fn recordConflict(self: *Self, signature_name: []const u8, conflicting_module_ids: []const u32) !void {
        var conflicting_modules = ArrayList(ModuleConflict.ConflictingModule).init(self.allocator);
        defer conflicting_modules.deinit();

        for (conflicting_module_ids, 0..) |module_id, i| {
            const module_info = self.modules.get(module_id) orelse continue;

            try conflicting_modules.append(ModuleConflict.ConflictingModule{
                .module_id = module_id,
                .module_name = module_info.name,
                .implementations = &.{}, // Simplified
                .import_priority = @as(u32, @intCast(i)),
            });
        }

        const conflict = ModuleConflict{
            .signature_name = try self.allocator.dupe(u8, signature_name),
            .conflicting_modules = try self.allocator.dupe(ModuleConflict.ConflictingModule, conflicting_modules.items),
            .conflict_type = .signature_name_collision,
            .resolution_strategy = null,
        };

        try self.active_conflicts.append(conflict);
    }

    /// Get available implementations for a signature in a module context
    fn getAvailableImplementations(
        self: *Self,
        calling_module_id: u32,
        signature_name: []const u8,
    ) ![]SignatureAnalyzer.Implementation {
        var implementations = ArrayList(SignatureAnalyzer.Implementation).init(self.allocator);

        // Get local implementations first
        // This would integrate with the signature analyzer to get local implementations

        // Get imported implementations
        const imports = self.module_imports.get(calling_module_id) orelse return implementations.toOwnedSlice();

        for (imports.items) |import| {
            const import_name = import.local_name orelse import.signature_name;
            if (std.mem.eql(u8, import_name, signature_name)) {
                const source_exports = self.module_exports.get(import.source_module_id) orelse continue;

                for (source_exports.items) |exported_sig| {
                    if (std.mem.eql(u8, exported_sig.signature_name, import.signature_name)) {
                        for (exported_sig.implementations) |impl| {
                            try implementations.append(impl.*);
                        }
                    }
                }
            }
        }

        return implementations.toOwnedSlice();
    }

    /// Resolve a qualified call
    fn resolveQualifiedCall(
        self: *Self,
        qualified_call: *const QualifiedCall,
        argument_types: []const TypeId,
    ) !?*const SignatureAnalyzer.Implementation {
        if (qualified_call.bypass_dispatch) {
            return qualified_call.target_implementation;
        }

        const module_id = self.module_name_to_id.get(qualified_call.module_name) orelse return null;
        const available_impls = try self.getAvailableImplementations(module_id, qualified_call.signature_name);
        defer self.allocator.free(available_impls);

        if (available_impls.len == 0) return null;

        var result = try self.specificity_analyzer.findMostSpecific(available_impls, argument_types);
        defer result.deinit(self.allocator);

        switch (result) {
            .unique => |impl| return impl,
            .ambiguous => return null,
            .no_match => return null,
        }
    }

    /// Find direct implementation for bypass dispatch
    fn findDirectImplementation(
        self: *Self,
        module_id: u32,
        signature_name: []const u8,
    ) !?*const SignatureAnalyzer.Implementation {
        const exports = self.module_exports.get(module_id) orelse return null;

        for (exports.items) |exported_sig| {
            if (std.mem.eql(u8, exported_sig.signature_name, signature_name)) {
                if (exported_sig.implementations.len > 0) {
                    return exported_sig.implementations[0]; // Return first implementation for direct call
                }
            }
        }

        return null;
    }

    /// Apply conflict resolution strategy
    fn applyConflictResolution(
        self: *Self,
        resolution: ModuleConflict.ConflictResolution,
        implementations: []const SignatureAnalyzer.Implementation,
        argument_types: []const TypeId,
    ) !?*const SignatureAnalyzer.Implementation {
        _ = self;
        _ = resolution;
        _ = argument_types;

        // Simplified implementation - return first available
        if (implementations.len > 0) {
            return &implementations[0];
        }

        return null;
    }

    /// Check if a signature is ambiguous across modules
    fn checkSignatureAmbiguity(self: *Self, global_sig: *const CrossModuleSignature) !bool {
        _ = self;

        // Simplified ambiguity check - more than one implementation is potentially ambiguous
        return global_sig.merged_implementations.items.len > 1;
    }

    /// Free module info memory
    fn freeModuleInfo(self: *Self, module_info: *ModuleInfo) void {
        self.allocator.free(module_info.name);
        self.allocator.free(module_info.path);
        self.allocator.free(module_info.dependencies);
    }

    /// Free cross-module signature memory
    fn freeCrossModuleSignature(self: *Self, sig: *CrossModuleSignature) void {
        self.allocator.free(sig.signature_name);
        sig.participating_modules.deinit();
        sig.merged_implementations.deinit();
        self.allocator.free(sig.resolution_order);
    }

    /// Free exported signature memory
    fn freeExportedSignature(self: *Self, exported_sig: *ExportedSignature) void {
        self.allocator.free(exported_sig.signature_name);
        self.allocator.free(exported_sig.implementations);
        if (exported_sig.export_name) |name| {
            self.allocator.free(name);
        }
    }

    /// Free imported signature memory
    fn freeImportedSignature(self: *Self, imported_sig: *ImportedSignature) void {
        self.allocator.free(imported_sig.signature_name);
        if (imported_sig.local_name) |name| {
            self.allocator.free(name);
        }
    }

    /// Free module conflict memory
    fn freeModuleConflict(self: *Self, conflict: *ModuleConflict) void {
        self.allocator.free(conflict.signature_name);
        self.allocator.free(conflict.conflicting_modules);
    }

    /// Update dispatch tables when a module is loaded
    fn updateDispatchTablesForModule(self: *Self, module_id: u32) !void {
        const exports = self.module_exports.get(module_id) orelse return;

        // Update global signatures for each exported signature
        for (exports.items) |exported_sig| {
            try self.updateGlobalSignature(exported_sig.signature_name, module_id, exported_sig.implementations);
        }

        // Invalidate qualified call cache for affected signatures
        try self.invalidateQualifiedCallCache(module_id);
    }

    /// Update dispatch tables after a module is unloaded
    fn updateDispatchTablesAfterUnload(self: *Self, module_id: u32) !void {
        // Remove module from all global signatures
        var sig_iter = self.global_signatures.iterator();
        while (sig_iter.next()) |entry| {
            const global_sig = entry.value_ptr;

            // Remove module from participating modules
            for (global_sig.participating_modules.items, 0..) |participating_module, i| {
                if (participating_module == module_id) {
                    _ = global_sig.participating_modules.swapRemove(i);
                    break;
                }
            }

            // Remove implementations from this module
            var impl_i: usize = 0;
            while (impl_i < global_sig.merged_implementations.items.len) {
                const impl = global_sig.merged_implementations.items[impl_i];
                if (std.mem.eql(u8, impl.function_id.module, self.getModuleName(module_id) orelse "")) {
                    _ = global_sig.merged_implementations.swapRemove(impl_i);
                } else {
                    impl_i += 1;
                }
            }
        }

        // Invalidate qualified call cache
        try self.invalidateQualifiedCallCache(module_id);
    }

    /// Remove module from global signatures
    fn removeModuleFromGlobalSignatures(self: *Self, module_id: u32) !void {
        const exports = self.module_exports.get(module_id) orelse return;

        for (exports.items) |exported_sig| {
            if (self.global_signatures.getPtr(exported_sig.signature_name)) |global_sig| {
                // Remove module from participating modules
                for (global_sig.participating_modules.items, 0..) |participating_module, i| {
                    if (participating_module == module_id) {
                        _ = global_sig.participating_modules.swapRemove(i);
                        break;
                    }
                }

                // Remove implementations from this module
                var impl_i: usize = 0;
                while (impl_i < global_sig.merged_implementations.items.len) {
                    const impl = global_sig.merged_implementations.items[impl_i];
                    if (std.mem.eql(u8, impl.function_id.module, self.getModuleName(module_id) orelse "")) {
                        _ = global_sig.merged_implementations.swapRemove(impl_i);
                    } else {
                        impl_i += 1;
                    }
                }

                // Update ambiguity status
                global_sig.is_ambiguous = try self.checkSignatureAmbiguity(global_sig);
            }
        }
    }

    /// Resolve conflicts that may arise from module loading
    fn resolveModuleLoadConflicts(self: *Self, module_id: u32) !void {
        const exports = self.module_exports.get(module_id) orelse return;

        for (exports.items) |exported_sig| {
            if (self.global_signatures.get(exported_sig.signature_name)) |global_sig| {
                if (global_sig.is_ambiguous) {
                    // Check if we have a resolution strategy
                    if (!self.conflict_resolutions.contains(exported_sig.signature_name)) {
                        // Record new conflict
                        const conflicting_modules = try self.getConflictingModules(exported_sig.signature_name);
                        defer self.allocator.free(conflicting_modules);

                        try self.recordConflict(exported_sig.signature_name, conflicting_modules);
                    }
                }
            }
        }
    }

    /// Get conflicting modules for a signature
    fn getConflictingModules(self: *Self, signature_name: []const u8) ![]u32 {
        const global_sig = self.global_signatures.get(signature_name) orelse return &.{};

        var conflicting = ArrayList(u32).init(self.allocator);
        defer conflicting.deinit();

        // Find modules with implementations of the same specificity
        var specificity_map = std.AutoHashMap(u32, ArrayList(u32)).init(self.allocator);
        defer {
            var iter = specificity_map.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            specificity_map.deinit();
        }

        for (global_sig.merged_implementations.items) |impl| {
            const module_id = self.getModuleIdByName(impl.function_id.module) orelse continue;

            var modules_for_specificity = specificity_map.get(impl.specificity_rank) orelse ArrayList(u32).init(self.allocator);
            try modules_for_specificity.append(module_id);
            try specificity_map.put(impl.specificity_rank, modules_for_specificity);
        }

        // Find specificities with multiple modules
        var iter = specificity_map.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.items.len > 1) {
                for (entry.value_ptr.items) |module_id| {
                    try conflicting.append(module_id);
                }
            }
        }

        return self.allocator.dupe(u32, conflicting.items);
    }

    /// Invalidate qualified call cache for a module
    fn invalidateQualifiedCallCache(self: *Self, module_id: u32) !void {
        const module_name = self.getModuleName(module_id) orelse return;

        var keys_to_remove = ArrayList([]const u8).init(self.allocator);
        defer keys_to_remove.deinit();

        var cache_iter = self.qualified_call_cache.iterator();
        while (cache_iter.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.mem.startsWith(u8, key, module_name) and std.mem.indexOf(u8, key, "::") != null) {
                try keys_to_remove.append(key);
            }
        }

        for (keys_to_remove.items) |key| {
            _ = self.qualified_call_cache.remove(key);
        }
    }

    /// Get module name by ID
    fn getModuleName(self: *Self, module_id: u32) ?[]const u8 {
        const module_info = self.modules.get(module_id) orelse return null;
        return module_info.name;
    }

    /// Get module ID by name
    fn getModuleIdByName(self: *Self, module_name: []const u8) ?u32 {
        return self.module_name_to_id.get(module_name);
    }
};

// Tests
test "ModuleDispatcher module registration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    // Register a module
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const module_id = try dispatcher.registerModule("test_module", "/path/to/module", version, &.{});

    // Verify module registration
    const module_info = dispatcher.getModuleInfo(module_id);
    try testing.expect(module_info != null);
    try testing.expectEqualStrings("test_module", module_info.?.name);
    try testing.expectEqualStrings("/path/to/module", module_info.?.path);
    try testing.expectEqual(@as(u32, 1), module_info.?.version.major);

    // Test module lookup by name
    const found_id = dispatcher.getModuleId("test_module");
    try testing.expect(found_id != null);
    try testing.expectEqual(module_id, found_id.?);
}

test "ModuleDispatcher signature export and import" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Register two modules
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const module_a = try dispatcher.registerModule("module_a", "/path/a", version, &.{});
    const module_b = try dispatcher.registerModule("module_b", "/path/b", version, &.{});

    // Create a mock implementation
    const impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test_func", .module = "module_a", .id = 1 },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(impl.param_type_ids);

    // Export signature from module A
    const implementations = [_]*const SignatureAnalyzer.Implementation{&impl};
    try dispatcher.exportSignature(module_a, "test_func", &implementations, .public, null);

    // Import signature into module B
    try dispatcher.importSignature(module_b, module_a, "test_func", null, .unqualified, .merge);

    // Verify the import was successful
    const arg_types = [_]TypeId{int_type};
    const result = try dispatcher.resolveCrossModuleDispatch(module_b, "test_func", &arg_types, null);
    try testing.expect(result != null);
    try testing.expectEqualStrings("test_func", result.?.function_id.name);
}

test "ModuleDispatcher qualified calls" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Register a module
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const module_id = try dispatcher.registerModule("math_module", "/path/math", version, &.{});

    // Create a mock implementation
    const impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "add", .module = "math_module", .id = 1 },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{ int_type, int_type }),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(impl.param_type_ids);

    // Export the signature
    const implementations = [_]*const SignatureAnalyzer.Implementation{&impl};
    try dispatcher.exportSignature(module_id, "add", &implementations, .public, null);

    // Create a qualified call
    const qualified_call = try dispatcher.createQualifiedCall("math_module", "add", false);

    try testing.expectEqualStrings("math_module", qualified_call.module_name);
    try testing.expectEqualStrings("add", qualified_call.signature_name);
    try testing.expectEqual(false, qualified_call.bypass_dispatch);

    // Test qualified dispatch resolution
    const arg_types = [_]TypeId{ int_type, int_type };
    const result = try dispatcher.resolveCrossModuleDispatch(module_id, "add", &arg_types, qualified_call);
    try testing.expect(result != null);
}

test "ModuleDispatcher conflict detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    // Register three modules
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const module_a = try dispatcher.registerModule("module_a", "/path/a", version, &.{});
    const module_b = try dispatcher.registerModule("module_b", "/path/b", version, &.{});
    const module_c = try dispatcher.registerModule("module_c", "/path/c", version, &.{});

    // Import the same signature from two different modules into module C
    // This should create a conflict
    try dispatcher.importSignature(module_c, module_a, "conflicting_func", null, .unqualified, .fail_on_conflict);
    try dispatcher.importSignature(module_c, module_b, "conflicting_func", null, .unqualified, .fail_on_conflict);

    // Check that conflicts were detected
    const conflicts = dispatcher.getActiveConflicts();
    try testing.expect(conflicts.len > 0);

    // Resolve the conflict
    try dispatcher.resolveConflict("conflicting_func", .priority_based);

    // Verify conflict was resolved
    const remaining_conflicts = dispatcher.getActiveConflicts();
    try testing.expect(remaining_conflicts.len == 0);
}

test "ModuleDispatcher module listing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    // Register multiple modules
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    _ = try dispatcher.registerModule("module_1", "/path/1", version, &.{});
    _ = try dispatcher.registerModule("module_2", "/path/2", version, &.{});
    _ = try dispatcher.registerModule("module_3", "/path/3", version, &.{});

    // Get all modules
    const all_modules = try dispatcher.getAllModules();
    defer allocator.free(all_modules);

    try testing.expectEqual(@as(usize, 3), all_modules.len);

    // Verify module names
    var found_modules = std.StringHashMap(bool).init(allocator);
    defer found_modules.deinit();

    for (all_modules) |module| {
        try found_modules.put(module.name, true);
    }

    try testing.expect(found_modules.contains("module_1"));
    try testing.expect(found_modules.contains("module_2"));
    try testing.expect(found_modules.contains("module_3"));
}

test "ModuleDispatcher formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test ModuleInfo formatting
    const version = ModuleInfo.Version{ .major = 2, .minor = 1, .patch = 3 };
    const module_info = ModuleInfo{
        .id = 1,
        .name = "test_module",
        .path = "/test/path",
        .version = version,
        .dependencies = &.{},
        .exports = &.{},
        .imports = &.{},
        .is_loaded = true,
        .load_timestamp = 1234567890,
    };

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{module_info});
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "test_module") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "2.1.3") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "loaded") != null);

    // Test QualifiedCall formatting
    buffer.clearRetainingCapacity();
    const qualified_call = QualifiedCall{
        .module_name = "math",
        .signature_name = "add",
        .target_implementation = null,
        .bypass_dispatch = true,
    };

    try std.fmt.format(buffer.writer(), "{}", .{qualified_call});
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "math::add") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "direct") != null);
}
test "ModuleDispatcher module loading and unloading" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Register a module
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const module_id = try dispatcher.registerModule("test_module", "/path/to/module", version, &.{});

    // Create and export an implementation
    const impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "test_func",
            .module = "test_module",
            .id = 1,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(impl.param_type_ids);

    const implementations = [_]*const SignatureAnalyzer.Implementation{&impl};
    try dispatcher.exportSignature(module_id, "test_func", &implementations, .public, null);

    // Initially module should not be loaded
    const module_info_before = dispatcher.getModuleInfo(module_id).?;
    try testing.expect(!module_info_before.is_loaded);

    // Load the module
    try dispatcher.loadModule(module_id);

    // Verify module is now loaded
    const module_info_after = dispatcher.getModuleInfo(module_id).?;
    try testing.expect(module_info_after.is_loaded);
    try testing.expect(module_info_after.load_timestamp > 0);

    // Unload the module
    try dispatcher.unloadModule(module_id);

    // Verify module is unloaded
    const module_info_unloaded = dispatcher.getModuleInfo(module_id).?;
    try testing.expect(!module_info_unloaded.is_loaded);
}

test "ModuleDispatcher hot reloading" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Register a module
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const module_id = try dispatcher.registerModule("test_module", "/path/to/module", version, &.{});

    // Create initial implementation
    const impl1 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "test_func",
            .module = "test_module",
            .id = 1,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(impl1.param_type_ids);

    const initial_implementations = [_]*const SignatureAnalyzer.Implementation{&impl1};
    try dispatcher.exportSignature(module_id, "test_func", &initial_implementations, .public, null);
    try dispatcher.loadModule(module_id);

    // Create new implementation for hot reload
    const impl2 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "test_func_v2",
            .module = "test_module",
            .id = 2,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 150,
    };
    defer allocator.free(impl2.param_type_ids);

    const new_export = ExportedSignature{
        .signature_name = "test_func_v2",
        .module_id = module_id,
        .implementations = &[_]*const SignatureAnalyzer.Implementation{&impl2},
        .visibility = .public,
        .export_name = null,
    };

    // Hot reload with new exports
    try dispatcher.hotReloadModule(module_id, &[_]ExportedSignature{new_export});

    // Verify module is loaded and has new exports
    const module_info = dispatcher.getModuleInfo(module_id).?;
    try testing.expect(module_info.is_loaded);
}

test "MergedDispatchTable functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Create test implementations
    const impl1 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "test_func",
            .module = "module_a",
            .id = 1,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(impl1.param_type_ids);

    const impl2 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "test_func",
            .module = "module_b",
            .id = 2,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 150, // Higher specificity
    };
    defer allocator.free(impl2.param_type_ids);

    // Create merged dispatch table
    var merged_table = MergedDispatchTable.init(allocator);
    defer merged_table.deinit();

    const implementations = [_]*const SignatureAnalyzer.Implementation{ &impl1, &impl2 };
    const priority_order = [_]u32{ 1, 2 }; // Module IDs in priority order

    try merged_table.buildFromImplementations(&implementations, &priority_order);

    // Verify table was built correctly
    try testing.expectEqual(@as(usize, 2), merged_table.implementations.items.len);
    try testing.expectEqual(@as(usize, 2), merged_table.priority_order.len);

    // Higher specificity implementation should be first after sorting
    try testing.expectEqual(@as(u32, 150), merged_table.implementations.items[0].specificity_rank);
    try testing.expectEqual(@as(u32, 100), merged_table.implementations.items[1].specificity_rank);
}

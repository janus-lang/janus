// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Semantic Core - The Complete Soul of the Compiler
//!
//! This module integrates all semantic analysis components into a unified
//! system that transforms syntactic ASTDB into semantically-aware database.
//! It orchestrates symbol resolution, type inference, and semantic validation
//! to provide complete semantic understanding.
//!
//! The Semantic Trinity:
//! - Symbol Table & Resolver (Foundation - Every identifier → declaration)
//! - Type System & Inference (Heart & Brain - Every expression → type)
//! - Semantic Validator (Guardian - Every rule → enforcement)

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const astdb = @import("astdb");
const symbol_table = @import("symbol_table.zig");
const symbol_resolver = @import("symbol_resolver.zig");
const type_system = @import("type_system.zig");
const type_inference = @import("type_inference.zig");
const semantic_validator = @import("semantic_validator.zig");

const UnitId = astdb.UnitId;
const NodeId = astdb.NodeId;
const SymbolId = symbol_table.SymbolId;
const TypeId = type_system.TypeId;

/// Complete Semantic Analysis System
pub const SemanticCore = struct {
    allocator: Allocator,
    astdb: *astdb.ASTDBSystem,

    /// The Semantic Trinity
    symbol_table: *symbol_table.SymbolTable,
    symbol_resolver: *symbol_resolver.SymbolResolver,
    type_system: *type_system.TypeSystem,
    type_inference: *type_inference.TypeInference,
    semantic_validator: *semantic_validator.SemanticValidator,

    /// Current analysis profile
    profile: semantic_validator.Profile,

    /// Analysis statistics
    stats: SemanticStats = .{},

    pub const SemanticStats = struct {
        units_analyzed: u32 = 0,
        symbols_resolved: u32 = 0,
        types_inferred: u32 = 0,
        validations_performed: u32 = 0,
        errors_found: u32 = 0,
        total_analysis_time_ms: f64 = 0.0,
    };

    pub fn init(allocator: Allocator, astdb_instance: *astdb.ASTDBSystem, analysis_profile: semantic_validator.Profile) !*SemanticCore {
        const core = try allocator.create(SemanticCore);

        // Initialize the semantic trinity
        const symbol_tbl = try symbol_table.SymbolTable.init(allocator);
        const symbol_res = try symbol_resolver.SymbolResolver.init(allocator, astdb_instance, symbol_tbl);
        const type_sys = try type_system.TypeSystem.init(allocator);
        const type_inf = try type_inference.TypeInference.init(allocator, type_sys, symbol_tbl, astdb_instance);
        const validator = try semantic_validator.SemanticValidator.init(allocator, astdb_instance, symbol_tbl, type_sys, type_inf, analysis_profile);

        core.* = SemanticCore{
            .allocator = allocator,
            .astdb = astdb_instance,
            .symbol_table = symbol_tbl,
            .symbol_resolver = symbol_res,
            .type_system = type_sys,
            .type_inference = type_inf,
            .semantic_validator = validator,
            .profile = analysis_profile,
        };

        return core;
    }

    pub fn deinit(self: *SemanticCore) void {
        self.semantic_validator.deinit();
        self.type_inference.deinit();
        self.type_system.deinit();
        self.symbol_resolver.deinit();
        self.symbol_table.deinit();

        self.allocator.destroy(self);
    }

    /// Perform complete semantic analysis on a compilation unit
    pub fn analyzeUnit(self: *SemanticCore, unit_id: UnitId) !void {
        const start_time = std.time.nanoTimestamp();

        // Phase 1: Symbol Resolution (Foundation)
        try self.symbol_resolver.resolveUnit(unit_id);
        const symbol_stats = self.symbol_resolver.getStatistics();
        self.stats.symbols_resolved += symbol_stats.references_resolved;

        // Phase 2: Type Inference (Brain)
        try self.type_inference.inferUnit(unit_id);
        const inference_stats = self.type_inference.getStatistics();
        self.stats.types_inferred += inference_stats.constraints_solved;

        // Phase 3: Semantic Validation (Guardian)
        try self.semantic_validator.validateUnit(unit_id);
        const validation_stats = self.semantic_validator.getStatistics();
        self.stats.validations_performed += validation_stats.nodes_validated;
        self.stats.errors_found += validation_stats.errors_found;

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        self.stats.total_analysis_time_ms += duration_ms;
        self.stats.units_analyzed += 1;
    }

    /// Get semantic information for a symbol at position
    pub fn getSemanticInfo(self: *SemanticCore, uri: []const u8, line: u32, column: u32) !?SemanticInfo {
        // Find node at position
        const node_id = try self.findNodeAtPosition(uri, line, column);
        if (node_id == null) return null;

        // Get symbol information
        const symbol_id = self.astdb.getNodeSymbol(node_id.?) orelse return null;
        const symbol = self.symbol_table.getSymbol(symbol_id) orelse return null;

        // Get type information
        const type_id = symbol.type_id orelse self.type_system.primitives.unknown;
        const type_info = self.type_system.getType(type_id);

        return SemanticInfo{
            .symbol_name = self.symbol_table.symbol_interner.getString(symbol.name),
            .symbol_kind = symbol.kind,
            .type_id = type_id,
            .type_signature = try self.formatType(type_info),
            .definition_span = symbol.declaration_span,
            .visibility = symbol.visibility,
        };
    }

    /// Get all semantic errors for a compilation unit
    pub fn getSemanticErrors(self: *SemanticCore, unit_id: UnitId) ![]SemanticError {
        _ = unit_id; // TODO: Filter errors by unit

        var errors = ArrayList(SemanticError).init(self.allocator);

        // Collect symbol resolution errors
        const symbol_diagnostics = self.symbol_resolver.getDiagnostics();
        for (symbol_diagnostics) |diag| {
            try errors.append(SemanticError{
                .kind = switch (diag.kind) {
                    .undefined_symbol => .undefined_symbol,
                    .duplicate_declaration => .duplicate_declaration,
                    .inaccessible_symbol => .inaccessible_symbol,
                    .shadowed_declaration => .shadowed_declaration,
                },
                .message = try self.allocator.dupe(u8, diag.message),
                .span = diag.span,
                .suggestions = try self.allocator.dupe([]const u8, diag.suggestions),
            });
        }

        // Collect validation errors
        const validation_errors = self.semantic_validator.getErrors();
        for (validation_errors) |error_item| {
            try errors.append(SemanticError{
                .kind = switch (error_item.kind) {
                    .profile_violation => .profile_violation,
                    .use_before_definition => .use_before_definition,
                    .missing_return => .missing_return,
                    else => .semantic_constraint,
                },
                .message = try self.allocator.dupe(u8, error_item.message),
                .span = error_item.span,
                .suggestions = try self.allocator.dupe([]const u8, error_item.suggestions),
            });
        }

        return errors.toOwnedSlice();
    }

    /// Get comprehensive semantic statistics
    pub fn getStatistics(self: *SemanticCore) SemanticStats {
        return self.stats;
    }

    // Helper types and methods

    pub const SemanticInfo = struct {
        symbol_name: []const u8,
        symbol_kind: symbol_table.Symbol.SymbolKind,
        type_id: TypeId,
        type_signature: []const u8,
        definition_span: symbol_table.SourceSpan,
        visibility: symbol_table.Symbol.Visibility,
    };

    pub const SemanticError = struct {
        kind: ErrorKind,
        message: []const u8,
        span: symbol_table.SourceSpan,
        suggestions: [][]const u8,

        pub const ErrorKind = enum {
            undefined_symbol,
            duplicate_declaration,
            inaccessible_symbol,
            shadowed_declaration,
            profile_violation,
            use_before_definition,
            missing_return,
            semantic_constraint,
        };
    };

    fn findNodeAtPosition(self: *SemanticCore, uri: []const u8, line: u32, column: u32) !?NodeId {
        // TODO: Implement position-to-node mapping
        _ = self;
        _ = uri;
        _ = line;
        _ = column;
        return null;
    }

    fn formatType(self: *SemanticCore, type_info: ?*type_system.TypeSystem.Type) ![]const u8 {
        if (type_info == null) return try self.allocator.dupe(u8, "unknown");

        return switch (type_info.?.*) {
            .primitive => |prim| try self.allocator.dupe(u8, @tagName(prim)),
            .function => |func| try std.fmt.allocPrint(self.allocator, "fn({}) -> {}", .{ func.parameters.len, @intFromEnum(func.return_type) }),
            .array => |array| try std.fmt.allocPrint(self.allocator, "[{}]{}", .{ switch (array.size) {
                .fixed => |size| size,
                .dynamic => 0,
                .inferred => 0,
            }, @intFromEnum(array.element_type) }),
            else => try self.allocator.dupe(u8, "complex_type"),
        };
    }
};

// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Type Inference Error Diagnostics
//!
//! This module provides error reporting for type inference failures,
//! integrating with the ErrorManager to generate helpful diagnostics.

const std = @import("std");
const astdb = @import("astdb_core");
const TypeSystem = @import("type_system.zig").TypeSystem;
const ErrorManager = @import("error_manager.zig").ErrorManager;
const source_span_utils = @import("source_span_utils.zig");

const TypeId = @import("type_system.zig").TypeId;
const NodeId = astdb.NodeId;
const UnitId = astdb.UnitId;
const SourceSpan = source_span_utils.SourceSpan;
const SourcePosition = source_span_utils.SourcePosition;

/// Type inference diagnostic reporter
pub const TypeInferenceDiagnostics = struct {
    error_manager: *ErrorManager,
    type_system: *TypeSystem,
    astdb: *astdb.AstDB,
    unit_id: UnitId,

    pub fn init(
        error_manager: *ErrorManager,
        type_system: *TypeSystem,
        astdb_instance: *astdb.AstDB,
        unit_id: UnitId,
    ) TypeInferenceDiagnostics {
        return TypeInferenceDiagnostics{
            .error_manager = error_manager,
            .type_system = type_system,
            .astdb = astdb_instance,
            .unit_id = unit_id,
        };
    }

    /// Report type mismatch error (legacy - uses unknown context)
    pub fn reportTypeMismatch(
        self: *TypeInferenceDiagnostics,
        expected: TypeId,
        actual: TypeId,
        node_id: NodeId,
    ) !void {
        try self.reportTypeMismatchWithContext(expected, actual, node_id, null, .unknown, null);
    }

    /// Report type mismatch with context information
    /// - context: WHERE the mismatch occurred (assignment, argument, return, etc.)
    /// - declaration_node_id: Optional node pointing to WHY the expected type was required
    /// - extra_note: Optional additional note (e.g., "argument 2 of function `foo`")
    pub fn reportTypeMismatchWithContext(
        self: *TypeInferenceDiagnostics,
        expected: TypeId,
        actual: TypeId,
        node_id: NodeId,
        declaration_node_id: ?NodeId,
        context: ErrorManager.InferenceContext,
        extra_note: ?[]const u8,
    ) !void {
        const expected_name = try self.getTypeName(expected);
        defer self.error_manager.allocator.free(expected_name);

        const actual_name = try self.getTypeName(actual);
        defer self.error_manager.allocator.free(actual_name);

        const primary_span = self.getNodeSpan(node_id);
        const declaration_span = if (declaration_node_id) |decl_id| self.getNodeSpan(decl_id) else null;

        _ = try self.error_manager.reportTypeMismatchWithContext(
            expected_name,
            actual_name,
            primary_span,
            declaration_span,
            context,
            extra_note,
        );
    }

    /// Report invalid operator error
    pub fn reportInvalidOperator(
        self: *TypeInferenceDiagnostics,
        operator: []const u8,
        left_type: TypeId,
        right_type: TypeId,
        node_id: NodeId,
    ) !void {
        const left_name = try self.getTypeName(left_type);
        defer self.error_manager.allocator.free(left_name);

        const right_name = try self.getTypeName(right_type);
        defer self.error_manager.allocator.free(right_name);

        const message = try std.fmt.allocPrint(
            self.error_manager.allocator,
            "Invalid operator '{s}' for types '{s}' and '{s}'",
            .{ operator, left_name, right_name },
        );

        const span = self.getNodeSpan(node_id);

        _ = try self.error_manager.reportError(
            .type_system,
            "E004",
            message,
            span,
        );
    }

    /// Report array type mismatch using context-aware reporting
    pub fn reportArrayTypeMismatch(
        self: *TypeInferenceDiagnostics,
        expected: TypeId,
        actual: TypeId,
        element_index: usize,
        node_id: NodeId,
    ) !void {
        const note = try std.fmt.allocPrint(
            self.error_manager.allocator,
            "element at index {} of array literal",
            .{element_index},
        );
        defer self.error_manager.allocator.free(note);

        try self.reportTypeMismatchWithContext(
            expected,
            actual,
            node_id,
            null,
            .array_element,
            note,
        );
    }

    /// Report match arm type mismatch using context-aware reporting
    pub fn reportMatchArmMismatch(
        self: *TypeInferenceDiagnostics,
        expected: TypeId,
        actual: TypeId,
        arm_index: usize,
        node_id: NodeId,
    ) !void {
        const note = try std.fmt.allocPrint(
            self.error_manager.allocator,
            "arm {} of match expression",
            .{arm_index},
        );
        defer self.error_manager.allocator.free(note);

        try self.reportTypeMismatchWithContext(
            expected,
            actual,
            node_id,
            null,
            .match_arm,
            note,
        );
    }

    /// Report non-boolean condition error
    pub fn reportNonBooleanCondition(
        self: *TypeInferenceDiagnostics,
        actual: TypeId,
        node_id: NodeId,
        context: []const u8,
    ) !void {
        const actual_name = try self.getTypeName(actual);
        defer self.error_manager.allocator.free(actual_name);

        const message = try std.fmt.allocPrint(
            self.error_manager.allocator,
            "{s} condition must be boolean, found '{s}'",
            .{ context, actual_name },
        );

        const span = self.getNodeSpan(node_id);

        _ = try self.error_manager.reportError(
            .type_system,
            "E007",
            message,
            span,
        );
    }

    /// Get type name for display
    fn getTypeName(self: *TypeInferenceDiagnostics, type_id: TypeId) ![]const u8 {
        const type_info = self.type_system.getTypeInfo(type_id);

        return switch (type_info.kind) {
            .primitive => |prim| try std.fmt.allocPrint(
                self.error_manager.allocator,
                "{s}",
                .{@tagName(prim)},
            ),
            .array => |arr| blk: {
                const elem_name = try self.getTypeName(arr.element_type);
                defer self.error_manager.allocator.free(elem_name);

                break :blk try std.fmt.allocPrint(
                    self.error_manager.allocator,
                    "[{s}; {}]",
                    .{ elem_name, arr.size },
                );
            },
            .slice => |slice| blk: {
                const elem_name = try self.getTypeName(slice.element_type);
                defer self.error_manager.allocator.free(elem_name);

                break :blk try std.fmt.allocPrint(
                    self.error_manager.allocator,
                    "[{s}]",
                    .{elem_name},
                );
            },
            .range => |range| blk: {
                const elem_name = try self.getTypeName(range.element_type);
                defer self.error_manager.allocator.free(elem_name);

                const op = if (range.is_inclusive) ".." else "..<";
                break :blk try std.fmt.allocPrint(
                    self.error_manager.allocator,
                    "Range[{s}] ({s})",
                    .{ elem_name, op },
                );
            },
            .function => try std.fmt.allocPrint(
                self.error_manager.allocator,
                "function",
                .{},
            ),
            else => try std.fmt.allocPrint(
                self.error_manager.allocator,
                "<unknown>",
                .{},
            ),
        };
    }

    /// Get source span for a node
    fn getNodeSpan(self: *TypeInferenceDiagnostics, node_id: NodeId) SourceSpan {
        const node = self.astdb.getNode(self.unit_id, node_id) orelse {
            return SourceSpan{
                .start = SourcePosition{ .line = 0, .column = 0, .offset = 0 },
                .end = SourcePosition{ .line = 0, .column = 0, .offset = 0 },
                .file_path = "<unknown>",
            };
        };

        // Get token information
        const first_token = self.astdb.getToken(self.unit_id, node.first_token) orelse {
            return SourceSpan{
                .start = SourcePosition{ .line = 0, .column = 0, .offset = 0 },
                .end = SourcePosition{ .line = 0, .column = 0, .offset = 0 },
                .file_path = "<unknown>",
            };
        };

        const last_token = self.astdb.getToken(self.unit_id, node.last_token) orelse first_token;

        return SourceSpan{
            .start = SourcePosition{
                .line = first_token.span.line,
                .column = first_token.span.column,
                .offset = first_token.span.start,
            },
            .end = SourcePosition{
                .line = last_token.span.line,
                .column = last_token.span.column + @as(u32, @intCast(last_token.span.end - last_token.span.start)),
                .offset = last_token.span.end,
            },
            .file_path = "<source>", // TODO: Get actual file path from ASTDB
        };
    }
};

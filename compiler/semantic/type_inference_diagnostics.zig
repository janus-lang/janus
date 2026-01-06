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
    
    /// Report type mismatch error
    pub fn reportTypeMismatch(
        self: *TypeInferenceDiagnostics,
        expected: TypeId,
        actual: TypeId,
        node_id: NodeId,
    ) !void {
        const expected_name = try self.getTypeName(expected);
        defer self.error_manager.allocator.free(expected_name);
        
        const actual_name = try self.getTypeName(actual);
        defer self.error_manager.allocator.free(actual_name);
        
        const span = self.getNodeSpan(node_id);
        
        _ = try self.error_manager.reportTypeMismatch(
            expected_name,
            actual_name,
            span,
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
    
    /// Report array type mismatch
    pub fn reportArrayTypeMismatch(
        self: *TypeInferenceDiagnostics,
        expected: TypeId,
        actual: TypeId,
        element_index: usize,
        node_id: NodeId,
    ) !void {
        const expected_name = try self.getTypeName(expected);
        defer self.error_manager.allocator.free(expected_name);
        
        const actual_name = try self.getTypeName(actual);
        defer self.error_manager.allocator.free(actual_name);
        
        const message = try std.fmt.allocPrint(
            self.error_manager.allocator,
            "Array element {} has type '{s}', but expected '{s}'",
            .{ element_index, actual_name, expected_name },
        );
        
        const span = self.getNodeSpan(node_id);
        
        _ = try self.error_manager.reportError(
            .type_system,
            "E005",
            message,
            span,
        );
    }
    
    /// Report match arm type mismatch
    pub fn reportMatchArmMismatch(
        self: *TypeInferenceDiagnostics,
        expected: TypeId,
        actual: TypeId,
        arm_index: usize,
        node_id: NodeId,
    ) !void {
        const expected_name = try self.getTypeName(expected);
        defer self.error_manager.allocator.free(expected_name);
        
        const actual_name = try self.getTypeName(actual);
        defer self.error_manager.allocator.free(actual_name);
        
        const message = try std.fmt.allocPrint(
            self.error_manager.allocator,
            "Match arm {} returns '{s}', but expected '{s}'",
            .{ arm_index, actual_name, expected_name },
        );
        
        const span = self.getNodeSpan(node_id);
        
        _ = try self.error_manager.reportError(
            .type_system,
            "E006",
            message,
            span,
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

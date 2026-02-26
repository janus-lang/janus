// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Control Flow Analysis for Janus Language
//!
//! This module implements control flow analysis including:
//! - Unreachable code detection (after return/break/continue)
//! - Return path validation (ensuring all paths return a value)
//! - Dead code elimination warnings
//!
//! Part of the Monastery Sprint - :min Profile Implementation

const std = @import("std");
const astdb = @import("astdb_core");
const AstDB = astdb.AstDB;
const NodeId = astdb.NodeId;
const UnitId = astdb.UnitId;

/// Control flow analysis result
pub const ControlFlowResult = enum {
    /// Normal flow continues
    continues,
    /// Flow terminates (return/break/continue)
    terminates,
    /// Flow may or may not terminate (conditional)
    maybe_terminates,
};

/// Control flow analyzer
pub const ControlFlowAnalyzer = struct {
    astdb: *AstDB,
    unit_id: UnitId,
    allocator: std.mem.Allocator,

    /// Unreachable code warnings
    unreachable_nodes: std.ArrayList(NodeId),

    /// Missing return errors
    missing_returns: std.ArrayList(NodeId),

    pub fn init(allocator: std.mem.Allocator, astdb_system: *AstDB, unit_id: UnitId) ControlFlowAnalyzer {
        return ControlFlowAnalyzer{
            .astdb = astdb_system,
            .unit_id = unit_id,
            .allocator = allocator,
            .unreachable_nodes = .empty,
            .missing_returns = .empty,
        };
    }

    pub fn deinit(self: *ControlFlowAnalyzer) void {
        self.unreachable_nodes.deinit();
        self.missing_returns.deinit();
    }

    /// Analyze control flow for a function
    pub fn analyzeFunction(self: *ControlFlowAnalyzer, func_node_id: NodeId) !void {
        const func_node = self.astdb.getNode(self.unit_id, func_node_id) orelse return;

        if (func_node.kind != .func_decl) return;

        // Get function body (last child is typically the body)
        const children = self.astdb.getChildren(self.unit_id, func_node_id);
        if (children.len == 0) return;

        // Analyze the body
        const result = try self.analyzeNode(children[children.len - 1]);

        // Check if function needs to return a value
        // TODO: Get return type from function signature
        // For now, we'll assume functions with explicit return statements need to return
        _ = result;
    }

    /// Analyze a single node and return its control flow behavior
    fn analyzeNode(self: *ControlFlowAnalyzer, node_id: NodeId) !ControlFlowResult {
        const node = self.astdb.getNode(self.unit_id, node_id) orelse return .continues;

        switch (node.kind) {
            .return_stmt => {
                // Return always terminates
                return .terminates;
            },
            .break_stmt, .continue_stmt => {
                // Break/continue terminate current block
                return .terminates;
            },
            .block_stmt => {
                return try self.analyzeBlock(node_id);
            },
            .if_stmt => {
                return try self.analyzeIf(node_id);
            },
            .match_stmt => {
                return try self.analyzeMatch(node_id);
            },
            .postfix_when => {
                // Postfix when may or may not execute
                return .maybe_terminates;
            },
            .postfix_unless => {
                // Postfix unless may or may not execute (inverse of when)
                return .maybe_terminates;
            },
            else => {
                // Most statements continue normally
                return .continues;
            },
        }
    }

    /// Analyze a block of statements
    fn analyzeBlock(self: *ControlFlowAnalyzer, block_id: NodeId) !ControlFlowResult {
        const children = self.astdb.getChildren(self.unit_id, block_id);

        var terminated = false;

        for (children, 0..) |child_id, i| {
            if (terminated) {
                // Code after termination is unreachable
                try self.unreachable_nodes.append(child_id);
                continue;
            }

            const result = try self.analyzeNode(child_id);

            if (result == .terminates) {
                terminated = true;

                // Check if there are more statements after this
                if (i + 1 < children.len) {
                    // Mark remaining statements as unreachable
                    for (children[i + 1 ..]) |unreachable_id| {
                        try self.unreachable_nodes.append(unreachable_id);
                    }
                }

                return .terminates;
            }
        }

        return if (terminated) .terminates else .continues;
    }

    /// Analyze an if statement
    fn analyzeIf(self: *ControlFlowAnalyzer, if_id: NodeId) !ControlFlowResult {
        const children = self.astdb.getChildren(self.unit_id, if_id);

        // If statement structure: [cond, ..., then_block, else_block?]
        // We need to find the blocks
        // For now, simplified: check if all branches terminate

        var all_terminate = true;
        var any_terminate = false;

        for (children) |child_id| {
            const child = self.astdb.getNode(self.unit_id, child_id) orelse continue;

            if (child.kind == .block_stmt) {
                const result = try self.analyzeNode(child_id);

                if (result == .terminates) {
                    any_terminate = true;
                } else {
                    all_terminate = false;
                }
            }
        }

        // If all branches terminate, the if terminates
        // If some branches terminate, it maybe terminates
        if (all_terminate and any_terminate) {
            return .terminates;
        } else if (any_terminate) {
            return .maybe_terminates;
        } else {
            return .continues;
        }
    }

    /// Analyze a match statement
    fn analyzeMatch(self: *ControlFlowAnalyzer, match_id: NodeId) !ControlFlowResult {
        const children = self.astdb.getChildren(self.unit_id, match_id);

        // Match statement structure: [expr, match_arm, match_arm, ...]
        // Check if all arms terminate

        var all_terminate = true;
        var any_terminate = false;
        var has_arms = false;

        for (children) |child_id| {
            const child = self.astdb.getNode(self.unit_id, child_id) orelse continue;

            if (child.kind == .match_arm) {
                has_arms = true;

                // Get arm children (pattern, guard, body)
                const arm_children = self.astdb.getChildren(self.unit_id, child_id);
                if (arm_children.len > 0) {
                    // Last child is the body
                    const body_id = arm_children[arm_children.len - 1];
                    const result = try self.analyzeNode(body_id);

                    if (result == .terminates) {
                        any_terminate = true;
                    } else {
                        all_terminate = false;
                    }
                }
            }
        }

        // If all arms terminate, the match terminates
        if (has_arms and all_terminate) {
            return .terminates;
        } else if (any_terminate) {
            return .maybe_terminates;
        } else {
            return .continues;
        }
    }

    /// Get unreachable code warnings
    pub fn getUnreachableNodes(self: *ControlFlowAnalyzer) []const NodeId {
        return self.unreachable_nodes.items;
    }

    /// Get missing return errors
    pub fn getMissingReturns(self: *ControlFlowAnalyzer) []const NodeId {
        return self.missing_returns.items;
    }
};

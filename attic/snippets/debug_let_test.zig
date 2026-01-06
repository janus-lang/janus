const std = @import("std");
const astdb_core = @import("astdb_core");
const parser = @import("libjanus").parser;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create ASTDB system
    var astdb_system = try astdb_core.AstDB.init(allocator, true);
    defer astdb_system.deinit();

    // Test the exact source from the failing test
    const source = "let x: i32 = 42;";

    // Tokenize
    const tokenization_result = try parser.tokenizeIntoSnapshot(&astdb_system, source);
    std.debug.print("Token count: {}\n", .{tokenization_result.token_count});

    // Parse
    try parser.parseTokensIntoNodes(&astdb_system);

    // Debug output
    if (astdb_system.units.items.len > 0) {
        const unit = astdb_system.units.items[0];
        std.debug.print("Unit has {} nodes\n", .{unit.nodes.len});

        for (unit.nodes, 0..) |node, i| {
            std.debug.print("Node[{}]: {} (child_lo={}, child_hi={})\n", .{ i, node.kind, node.child_lo, node.child_hi });
        }

        // Look for let_stmt specifically
        for (unit.nodes, 0..) |node, i| {
            if (node.kind == astdb_core.AstNode.NodeKind.let_stmt) {
                std.debug.print("FOUND let_stmt at index {}: child_lo={}, child_hi={}\n", .{ i, node.child_lo, node.child_hi });

                // Print its children
                var child_idx = node.child_lo;
                while (child_idx < node.child_hi) : (child_idx += 1) {
                    const child = unit.nodes[child_idx];
                    std.debug.print("  Child[{}]: {}\n", .{ child_idx, child.kind });
                }
            }
        }
    }
}

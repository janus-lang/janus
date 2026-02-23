// Cluster parser additions (to be merged into janus_parser.zig)
// NOTE: Provided as reference; integrate manually if desired.

fn parseActorDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const first_token: astdb_core.TokenId = @enumFromInt(parser.current);
    _ = parser.advance(); // consume 'actor'
    _ = try parser.consume(.identifier); // actor name

    // Optional do/end block
    try parser.consume(.do_);
    var block_children: std.ArrayList(astdb_core.NodeId) = .empty;
    defer block_children.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &block_children);
    _ = try parser.consume(.end);

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    for (block_children.items) |child| {
        try parser.edges.append(parser.allocator, child);
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{ .kind = .actor_decl, .first_token = first_token, .last_token = @enumFromInt(parser.current), .child_lo = child_lo, .child_hi = child_hi };
}

fn parseGrainDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const first_token: astdb_core.TokenId = @enumFromInt(parser.current);
    _ = parser.advance(); // consume 'grain'
    _ = try parser.consume(.identifier);
    try parser.consume(.do_);
    var block_children: std.ArrayList(astdb_core.NodeId) = .empty;
    defer block_children.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &block_children);
    _ = try parser.consume(.end);

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    for (block_children.items) |child| {
        try parser.edges.append(parser.allocator, child);
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{ .kind = .grain_decl, .first_token = first_token, .last_token = @enumFromInt(parser.current), .child_lo = child_lo, .child_hi = child_hi };
}

fn parseGenServerDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const first_token: astdb_core.TokenId = @enumFromInt(parser.current);
    _ = parser.advance(); // consume 'genserver'
    _ = try parser.consume(.identifier);
    try parser.consume(.do_);
    var block_children: std.ArrayList(astdb_core.NodeId) = .empty;
    defer block_children.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &block_children);
    _ = try parser.consume(.end);

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    for (block_children.items) |child| {
        try parser.edges.append(parser.allocator, child);
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{ .kind = .genserver_decl, .first_token = first_token, .last_token = @enumFromInt(parser.current), .child_lo = child_lo, .child_hi = child_hi };
}

fn parseSupervisorDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const first_token: astdb_core.TokenId = @enumFromInt(parser.current);
    _ = parser.advance(); // consume 'supervisor'
    _ = try parser.consume(.identifier);
    // Optional: parse attributes until 'do'
    while (!parser.match(.do_) and !parser.match(.eof)) {
        _ = parser.advance();
    }
    try parser.consume(.do_);

    var block_children: std.ArrayList(astdb_core.NodeId) = .empty;
    defer block_children.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &block_children);
    _ = try parser.consume(.end);

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    for (block_children.items) |child| {
        try parser.edges.append(parser.allocator, child);
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{ .kind = .supervisor_decl, .first_token = first_token, .last_token = @enumFromInt(parser.current), .child_lo = child_lo, .child_hi = child_hi };
}

fn parseReceiveStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const first_token: astdb_core.TokenId = @enumFromInt(parser.current);
    _ = parser.advance(); // consume 'receive'

    try parser.consume(.do_);
    var block_children: std.ArrayList(astdb_core.NodeId) = .empty;
    defer block_children.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &block_children);
    _ = try parser.consume(.end);

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    for (block_children.items) |child| {
        try parser.edges.append(parser.allocator, child);
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{ .kind = .receive_stmt, .first_token = first_token, .last_token = @enumFromInt(parser.current), .child_lo = child_lo, .child_hi = child_hi };
}

// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - Database Module
// Demonstrates tri-signature pattern: same name, rising capability across profiles

const std = @import("std");
const Context = @import("context.zig").Context;
const Capability = @import("capabilities.zig");

/// Database errors
pub const DbError = error{
    ConnectionFailed,
    QueryFailed,
    InvalidQuery,
    CapabilityRequired,
    ContextCancelled,
    TransactionFailed,
    OutOfMemory,
};

/// Database row representation
pub const Row = struct {
    columns: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Row {
        return Row{
            .columns = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Row) void {
        var iter = self.columns.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.columns.deinit();
    }

    pub fn set(self: *Row, column: []const u8, value: []const u8) !void {
        const owned_column = try self.allocator.dupe(u8, column);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.columns.put(owned_column, owned_value);
    }

    pub fn get(self: *const Row, column: []const u8) ?[]const u8 {
        return self.columns.get(column);
    }
};

/// Query result set
pub const ResultSet = struct {
    rows: std.ArrayList(Row),
    affected_rows: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResultSet {
        return ResultSet{
            .rows = .empty,
            .affected_rows = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ResultSet) void {
        for (self.rows.items) |*row| {
            row.deinit();
        }
        self.rows.deinit();
    }

    pub fn add_row(self: *ResultSet, row: Row) !void {
        try self.rows.append(row);
    }

    pub fn get_row(self: *const ResultSet, index: usize) ?*const Row {
        if (index >= self.rows.items.len) return null;
        return &self.rows.items[index];
    }

    pub fn row_count(self: *const ResultSet) usize {
        return self.rows.items.len;
    }
};

// =============================================================================
// TRI-SIGNATURE PATTERN: Same name, rising capability
// =============================================================================

/// :min profile - Simple synchronous database query
/// Available in: min, go, full
pub fn query_min(sql: []const u8, allocator: std.mem.Allocator) DbError!ResultSet {
    // Simple implementation for :min profile
    // No context, no capabilities, just basic functionality

    if (sql.len == 0) return DbError.InvalidQuery;

    // Mock implementation for demonstration
    var result = ResultSet.init(allocator);

    // Create mock row
    var row = Row.init(allocator);
    try row.set("profile", "min");
    try row.set("query", sql);
    try row.set("timestamp", "2025-08-25T12:00:00Z");

    try result.add_row(row);
    result.affected_rows = 1;

    return result;
}

/// :go profile - Context-aware database query with cancellation
/// Available in: go, full
pub fn query_go(sql: []const u8, ctx: Context, allocator: std.mem.Allocator) DbError!ResultSet {
    // Enhanced implementation with context support
    // Includes timeout, cancellation, structured error handling

    if (sql.len == 0) return DbError.InvalidQuery;

    // Check context for cancellation/timeout
    if (ctx.is_done()) return DbError.ContextCancelled;

    // Mock implementation with context awareness
    var result = ResultSet.init(allocator);

    // Create mock row with context info
    var row = Row.init(allocator);
    try row.set("profile", "go");
    try row.set("query", sql);
    try row.set("context_active", if (ctx.is_done()) "false" else "true");

    if (ctx.deadline_remaining_ms()) |remaining| {
        const remaining_str = try std.fmt.allocPrint(allocator, "{d}", .{remaining});
        defer allocator.free(remaining_str);
        try row.set("deadline_remaining_ms", remaining_str);
    } else {
        try row.set("deadline_remaining_ms", "none");
    }

    try result.add_row(row);
    result.affected_rows = 1;

    return result;
}

/// :full profile - Capability-gated database query with security
/// Available in: full only
pub fn query_full(sql: []const u8, cap: Capability.Database, allocator: std.mem.Allocator) DbError!ResultSet {
    // Full implementation with capability-based security
    // Explicit permission required, audit trails, effect tracking

    if (sql.len == 0) return DbError.InvalidQuery;

    // Validate capability
    const operation = if (std.mem.startsWith(u8, std.ascii.lowerString(allocator, sql) catch sql, "select")) "db.read" else "db.write";
    if (!cap.allows_operation(operation)) return DbError.CapabilityRequired;

    // Audit capability usage
    Capability.audit_capability_usage(cap, operation);

    // Mock implementation with capability validation
    var result = ResultSet.init(allocator);

    // Create mock row with capability info
    var row = Row.init(allocator);
    try row.set("profile", "full");
    try row.set("query", sql);
    try row.set("capability_id", cap.id());
    try row.set("operation", operation);
    try row.set("audit_logged", "true");

    try result.add_row(row);
    result.affected_rows = 1;

    return result;
}

// =============================================================================
// TRANSACTION OPERATIONS: Tri-signature pattern for transactions
// =============================================================================

/// Transaction handle
pub const Transaction = struct {
    id: []const u8,
    committed: bool,
    allocator: std.mem.Allocator,

    pub fn init(id: []const u8, allocator: std.mem.Allocator) !Transaction {
        return Transaction{
            .id = try allocator.dupe(u8, id),
            .committed = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Transaction) void {
        self.allocator.free(self.id);
    }

    pub fn commit(self: *Transaction) DbError!void {
        if (self.committed) return DbError.TransactionFailed;
        self.committed = true;
        std.log.info("Transaction {s} committed", .{self.id});
    }

    pub fn rollback(self: *Transaction) DbError!void {
        if (self.committed) return DbError.TransactionFailed;
        std.log.info("Transaction {s} rolled back", .{self.id});
    }
};

/// :min profile - Simple transaction
pub fn begin_transaction_min(allocator: std.mem.Allocator) DbError!Transaction {
    const tx_id = try std.fmt.allocPrint(allocator, "tx_min_{d}", .{std.time.milliTimestamp()});
    defer allocator.free(tx_id);

    return Transaction.init(tx_id, allocator);
}

/// :go profile - Context-aware transaction
pub fn begin_transaction_go(ctx: Context, allocator: std.mem.Allocator) DbError!Transaction {
    if (ctx.is_done()) return DbError.ContextCancelled;

    const tx_id = try std.fmt.allocPrint(allocator, "tx_go_{d}", .{std.time.milliTimestamp()});
    defer allocator.free(tx_id);

    return Transaction.init(tx_id, allocator);
}

/// :full profile - Capability-gated transaction
pub fn begin_transaction_full(cap: Capability.Database, allocator: std.mem.Allocator) DbError!Transaction {
    if (!cap.allows_operation("db.transaction")) return DbError.CapabilityRequired;

    // Audit capability usage
    Capability.audit_capability_usage(cap, "db.transaction");

    const tx_id = try std.fmt.allocPrint(allocator, "tx_full_{s}_{d}", .{ cap.id(), std.time.milliTimestamp() });
    defer allocator.free(tx_id);

    return Transaction.init(tx_id, allocator);
}

// =============================================================================
// PROFILE-AWARE DISPATCH: Single entry point, profile-specific behavior
// =============================================================================

/// Universal query function - dispatches to profile-specific implementation
pub fn query(args: anytype) DbError!ResultSet {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info != .Struct) {
        @compileError("query requires struct arguments");
    }

    const fields = args_info.Struct.fields;

    // Dispatch based on argument signature
    if (fields.len == 2) {
        // :min profile: query(.{ .sql = sql, .allocator = allocator })
        return query_min(args.sql, args.allocator);
    } else if (fields.len == 3 and @hasField(ArgsType, "ctx")) {
        // :go profile: query(.{ .sql = sql, .ctx = ctx, .allocator = allocator })
        return query_go(args.sql, args.ctx, args.allocator);
    } else if (fields.len == 3 and @hasField(ArgsType, "cap")) {
        // :full profile: query(.{ .sql = sql, .cap = cap, .allocator = allocator })
        return query_full(args.sql, args.cap, args.allocator);
    } else {
        @compileError("Invalid arguments for query - check profile requirements");
    }
}

/// Universal begin_transaction function - dispatches to profile-specific implementation
pub fn begin_transaction(args: anytype) DbError!Transaction {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info != .Struct) {
        @compileError("begin_transaction requires struct arguments");
    }

    const fields = args_info.Struct.fields;

    // Dispatch based on argument signature
    if (fields.len == 1) {
        // :min profile: begin_transaction(.{ .allocator = allocator })
        return begin_transaction_min(args.allocator);
    } else if (fields.len == 2 and @hasField(ArgsType, "ctx")) {
        // :go profile: begin_transaction(.{ .ctx = ctx, .allocator = allocator })
        return begin_transaction_go(args.ctx, args.allocator);
    } else if (fields.len == 2 and @hasField(ArgsType, "cap")) {
        // :full profile: begin_transaction(.{ .cap = cap, .allocator = allocator })
        return begin_transaction_full(args.cap, args.allocator);
    } else {
        @compileError("Invalid arguments for begin_transaction - check profile requirements");
    }
}

// =============================================================================
// CONVENIENCE WRAPPERS: Profile-specific convenience functions
// =============================================================================

/// Convenience wrapper for :min profile
pub fn execute(sql: []const u8, allocator: std.mem.Allocator) DbError!ResultSet {
    return query(.{ .sql = sql, .allocator = allocator });
}

/// Convenience wrapper for :go profile
pub fn execute_with_context(sql: []const u8, ctx: Context, allocator: std.mem.Allocator) DbError!ResultSet {
    return query(.{ .sql = sql, .ctx = ctx, .allocator = allocator });
}

/// Convenience wrapper for :full profile
pub fn execute_with_capability(sql: []const u8, cap: Capability.Database, allocator: std.mem.Allocator) DbError!ResultSet {
    return query(.{ .sql = sql, .cap = cap, .allocator = allocator });
}

// =============================================================================
// HIGHER-LEVEL OPERATIONS: Common database patterns
// =============================================================================

/// Insert operation with automatic SQL generation
pub fn insert(table: []const u8, data: std.StringHashMap([]const u8), args: anytype) DbError!ResultSet {
    const allocator = switch (@TypeOf(args)) {
        @TypeOf(.{ .allocator = @as(std.mem.Allocator, undefined) }) => args.allocator,
        @TypeOf(.{ .ctx = @as(Context, undefined), .allocator = @as(std.mem.Allocator, undefined) }) => args.allocator,
        @TypeOf(.{ .cap = @as(Capability.Database, undefined), .allocator = @as(std.mem.Allocator, undefined) }) => args.allocator,
        else => @compileError("Invalid arguments for insert"),
    };

    // Generate INSERT SQL
    var columns: std.ArrayList([]const u8) = .empty;
    defer columns.deinit();
    var values: std.ArrayList([]const u8) = .empty;
    defer values.deinit();

    var iter = data.iterator();
    while (iter.next()) |entry| {
        try columns.append(entry.key_ptr.*);
        try values.append(entry.value_ptr.*);
    }

    // Build SQL string (simplified for demo)
    const sql = try std.fmt.allocPrint(allocator, "INSERT INTO {s} VALUES (...)", .{table});
    defer allocator.free(sql);

    // Dispatch to appropriate query function
    return query(args);
}

/// Select operation with WHERE clause
pub fn select(table: []const u8, where_clause: ?[]const u8, args: anytype) DbError!ResultSet {
    const allocator = switch (@TypeOf(args)) {
        @TypeOf(.{ .allocator = @as(std.mem.Allocator, undefined) }) => args.allocator,
        @TypeOf(.{ .ctx = @as(Context, undefined), .allocator = @as(std.mem.Allocator, undefined) }) => args.allocator,
        @TypeOf(.{ .cap = @as(Capability.Database, undefined), .allocator = @as(std.mem.Allocator, undefined) }) => args.allocator,
        else => @compileError("Invalid arguments for select"),
    };

    // Generate SELECT SQL
    const sql = if (where_clause) |where|
        try std.fmt.allocPrint(allocator, "SELECT * FROM {s} WHERE {s}", .{ table, where })
    else
        try std.fmt.allocPrint(allocator, "SELECT * FROM {s}", .{table});
    defer allocator.free(sql);

    // Create new args with generated SQL
    const query_args = switch (@TypeOf(args)) {
        @TypeOf(.{ .allocator = @as(std.mem.Allocator, undefined) }) => .{ .sql = sql, .allocator = args.allocator },
        @TypeOf(.{ .ctx = @as(Context, undefined), .allocator = @as(std.mem.Allocator, undefined) }) => .{ .sql = sql, .ctx = args.ctx, .allocator = args.allocator },
        @TypeOf(.{ .cap = @as(Capability.Database, undefined), .allocator = @as(std.mem.Allocator, undefined) }) => .{ .sql = sql, .cap = args.cap, .allocator = args.allocator },
        else => unreachable,
    };

    return query(query_args);
}

// =============================================================================
// TESTS: Behavior parity across profiles
// =============================================================================

test "query tri-signature pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test :min profile
    {
        var result = try query_min("SELECT * FROM users", allocator);
        defer result.deinit();

        try testing.expect(result.row_count() == 1);
        const row = result.get_row(0).?;
        try testing.expectEqualStrings("min", row.get("profile").?);
    }

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        var result = try query_go("SELECT * FROM users", mock_ctx, allocator);
        defer result.deinit();

        try testing.expect(result.row_count() == 1);
        const row = result.get_row(0).?;
        try testing.expectEqualStrings("go", row.get("profile").?);
        try testing.expectEqualStrings("true", row.get("context_active").?);
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.Database.init("test-db-cap", "postgresql://localhost/test", allocator);
        defer mock_cap.deinit();

        var result = try query_full("SELECT * FROM users", mock_cap, allocator);
        defer result.deinit();

        try testing.expect(result.row_count() == 1);
        const row = result.get_row(0).?;
        try testing.expectEqualStrings("full", row.get("profile").?);
        try testing.expectEqualStrings("test-db-cap", row.get("capability_id").?);
    }
}

test "transaction tri-signature pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test :min profile
    {
        var tx = try begin_transaction_min(allocator);
        defer tx.deinit();

        try testing.expect(!tx.committed);
        try tx.commit();
        try testing.expect(tx.committed);
    }

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        var tx = try begin_transaction_go(mock_ctx, allocator);
        defer tx.deinit();

        try testing.expect(!tx.committed);
        try tx.commit();
        try testing.expect(tx.committed);
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.Database.init("test-db-cap", "postgresql://localhost/test", allocator);
        defer mock_cap.deinit();

        // Grant transaction permission
        try mock_cap.base.grant_permission("db.transaction");

        var tx = try begin_transaction_full(mock_cap, allocator);
        defer tx.deinit();

        try testing.expect(!tx.committed);
        try tx.commit();
        try testing.expect(tx.committed);
    }
}

test "profile-aware dispatch" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test dispatch to :min implementation
    {
        var result = try query(.{ .sql = "SELECT 1", .allocator = allocator });
        defer result.deinit();

        try testing.expect(result.row_count() == 1);
        const row = result.get_row(0).?;
        try testing.expectEqualStrings("min", row.get("profile").?);
    }

    // Test transaction dispatch to :min implementation
    {
        var tx = try begin_transaction(.{ .allocator = allocator });
        defer tx.deinit();

        try testing.expect(!tx.committed);
    }
}

test "higher-level operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test select operation
    {
        var result = try select("users", "id = 1", .{ .allocator = allocator });
        defer result.deinit();

        try testing.expect(result.row_count() == 1);
    }

    // Test select without WHERE clause
    {
        var result = try select("users", null, .{ .allocator = allocator });
        defer result.deinit();

        try testing.expect(result.row_count() == 1);
    }
}

test "capability validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cap = Capability.Database.init("restricted-db", "postgresql://localhost/test", allocator);
    defer cap.deinit();

    // Remove write permission
    cap.base.revoke_permission("db.write");

    // Should succeed for read operation
    var result = try query_full("SELECT * FROM users", cap, allocator);
    defer result.deinit();

    // Should fail for write operation
    try testing.expectError(DbError.CapabilityRequired, query_full("INSERT INTO users VALUES (1)", cap, allocator));
}

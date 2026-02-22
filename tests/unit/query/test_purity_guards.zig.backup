// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Unit Test: Query Purity Guards System
// Task 2.3: Static guard rails and runtime sentinels for query purity

const std = @import("std");
const testing = std.testing;

// Query purity violation error
const QueryPurityError = error{
    ImpureOperation,
    UnauthorizedIO,
    NetworkAccess,
    FileSystemAccess,
    EnvironmentAccess,
    OutOfMemory,
};

// Diagnostic codes for query purity violations
const DiagnosticCode = enum {
    Q1001, // Query impurity detected
    Q1002, // Unauthorized I/O operation
    Q1003, // Network access in query
    Q1004, // File system access in query
    Q1005, // Environment access in query
};

// Purity guard context for runtime checking
const PurityGuard = struct {
    debug_mode: bool,
    violations: std.ArrayList(PurityViolation),
    allocator: std.mem.Allocator,

    const PurityViolation = struct {
        code: DiagnosticCode,
        operation: []const u8,
        location: []const u8,
        suggestion: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, debug_mode: bool) PurityGuard {
        return PurityGuard{
            .debug_mode = debug_mode,
            .violations = std.ArrayList(PurityViolation).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PurityGuard) void {
        self.violations.deinit();
    }

    // Check for I/O operations (static analysis simulation)
    pub fn checkIOOperation(self: *PurityGuard, operation: []const u8, location: []const u8) QueryPurityError!void {
        if (std.mem.indexOf(u8, operation, "file_read") != null or
            std.mem.indexOf(u8, operation, "file_write") != null or
            std.mem.indexOf(u8, operation, "network_request") != null)
        {
            const violation = PurityViolation{
                .code = DiagnosticCode.Q1001,
                .operation = operation,
                .location = location,
                .suggestion = "Move I/O to dependent query boundary or use authorized query context",
            };

            try self.violations.append(violation);

            if (self.debug_mode) {
                return QueryPurityError.ImpureOperation;
            }
        }
    }

    // Check for network operations
    pub fn checkNetworkOperation(self: *PurityGuard, operation: []const u8, location: []const u8) QueryPurityError!void {
        if (std.mem.indexOf(u8, operation, "http") != null or
            std.mem.indexOf(u8, operation, "tcp") != null or
            std.mem.indexOf(u8, operation, "udp") != null)
        {
            const violation = PurityViolation{
                .code = DiagnosticCode.Q1003,
                .operation = operation,
                .location = location,
                .suggestion = "Network operations not allowed in queries - use external data source",
            };

            try self.violations.append(violation);

            if (self.debug_mode) {
                return QueryPurityError.NetworkAccess;
            }
        }
    }

    // Check for environment access
    pub fn checkEnvironmentAccess(self: *PurityGuard, operation: []const u8, location: []const u8) QueryPurityError!void {
        if (std.mem.indexOf(u8, operation, "getenv") != null or
            std.mem.indexOf(u8, operation, "env_var") != null)
        {
            const violation = PurityViolation{
                .code = DiagnosticCode.Q1005,
                .operation = operation,
                .location = location,
                .suggestion = "Environment access not allowed in queries - pass values as parameters",
            };

            try self.violations.append(violation);

            if (self.debug_mode) {
                return QueryPurityError.EnvironmentAccess;
            }
        }
    }

    pub fn hasViolations(self: *const PurityGuard) bool {
        return self.violations.items.len > 0;
    }

    pub fn getViolations(self: *const PurityGuard) []const PurityViolation {
        return self.violations.items;
    }
};

// Simulated query execution context
const QueryContext = struct {
    purity_guard: *PurityGuard,
    query_name: []const u8,

    pub fn executeOperation(self: *QueryContext, operation: []const u8) QueryPurityError!void {
        // Use a simple static location for testing
        const location = self.query_name;

        try self.purity_guard.checkIOOperation(operation, location);
        try self.purity_guard.checkNetworkOperation(operation, location);
        try self.purity_guard.checkEnvironmentAccess(operation, location);
    }
};

test "Purity guard detects I/O violations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var guard = PurityGuard.init(allocator, true); // Debug mode enabled
    defer guard.deinit();

    var context = QueryContext{
        .purity_guard = &guard,
        .query_name = "test_query",
    };

    // Test file I/O detection
    try testing.expectError(QueryPurityError.ImpureOperation, context.executeOperation("file_read('/etc/passwd')"));
    try testing.expectError(QueryPurityError.ImpureOperation, context.executeOperation("file_write('/tmp/output')"));

    // Verify violations were recorded
    try testing.expect(guard.hasViolations());
    const violations = guard.getViolations();
    try testing.expectEqual(@as(usize, 2), violations.len);
    try testing.expectEqual(DiagnosticCode.Q1001, violations[0].code);
    try testing.expectEqual(DiagnosticCode.Q1001, violations[1].code);
}

test "Purity guard detects network violations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var guard = PurityGuard.init(allocator, true);
    defer guard.deinit();

    var context = QueryContext{
        .purity_guard = &guard,
        .query_name = "network_query",
    };

    // Test network operation detection
    try testing.expectError(QueryPurityError.NetworkAccess, context.executeOperation("http_get('https://api.example.com')"));
    try testing.expectError(QueryPurityError.NetworkAccess, context.executeOperation("tcp_connect('localhost:8080')"));

    // Verify violations were recorded
    try testing.expect(guard.hasViolations());
    const violations = guard.getViolations();
    try testing.expectEqual(@as(usize, 2), violations.len);
    try testing.expectEqual(DiagnosticCode.Q1003, violations[0].code);
    try testing.expectEqual(DiagnosticCode.Q1003, violations[1].code);
}

test "Purity guard detects environment access violations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var guard = PurityGuard.init(allocator, true);
    defer guard.deinit();

    var context = QueryContext{
        .purity_guard = &guard,
        .query_name = "env_query",
    };

    // Test environment access detection
    try testing.expectError(QueryPurityError.EnvironmentAccess, context.executeOperation("getenv('HOME')"));
    try testing.expectError(QueryPurityError.EnvironmentAccess, context.executeOperation("env_var('PATH')"));

    // Verify violations were recorded
    try testing.expect(guard.hasViolations());
    const violations = guard.getViolations();
    try testing.expectEqual(@as(usize, 2), violations.len);
    try testing.expectEqual(DiagnosticCode.Q1005, violations[0].code);
    try testing.expectEqual(DiagnosticCode.Q1005, violations[1].code);
}

test "Purity guard allows pure operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var guard = PurityGuard.init(allocator, true);
    defer guard.deinit();

    var context = QueryContext{
        .purity_guard = &guard,
        .query_name = "pure_query",
    };

    // Test pure operations (should not throw errors)
    try context.executeOperation("string_concat('hello', 'world')");
    try context.executeOperation("math_add(1, 2)");
    try context.executeOperation("array_filter(items, predicate)");
    try context.executeOperation("type_check(node, expected_type)");

    // Verify no violations were recorded
    try testing.expect(!guard.hasViolations());
    try testing.expectEqual(@as(usize, 0), guard.getViolations().len);
}

test "Purity guard non-debug mode records violations without throwing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var guard = PurityGuard.init(allocator, false); // Debug mode disabled
    defer guard.deinit();

    var context = QueryContext{
        .purity_guard = &guard,
        .query_name = "production_query",
    };

    // In non-debug mode, violations are recorded but don't throw errors
    try context.executeOperation("file_read('/etc/passwd')");
    try context.executeOperation("http_get('https://api.example.com')");
    try context.executeOperation("getenv('HOME')");

    // Verify violations were recorded
    try testing.expect(guard.hasViolations());
    const violations = guard.getViolations();
    try testing.expectEqual(@as(usize, 3), violations.len);

    // Check that different violation types were recorded
    var q1001_count: u32 = 0;
    var q1003_count: u32 = 0;
    var q1005_count: u32 = 0;

    for (violations) |violation| {
        switch (violation.code) {
            .Q1001 => q1001_count += 1,
            .Q1003 => q1003_count += 1,
            .Q1005 => q1005_count += 1,
            else => {},
        }
    }

    try testing.expectEqual(@as(u32, 1), q1001_count);
    try testing.expectEqual(@as(u32, 1), q1003_count);
    try testing.expectEqual(@as(u32, 1), q1005_count);
}

test "Purity guard provides actionable suggestions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var guard = PurityGuard.init(allocator, false);
    defer guard.deinit();

    var context = QueryContext{
        .purity_guard = &guard,
        .query_name = "suggestion_test",
    };

    try context.executeOperation("file_read('/config.json')");

    const violations = guard.getViolations();
    try testing.expectEqual(@as(usize, 1), violations.len);

    const violation = violations[0];
    try testing.expect(std.mem.indexOf(u8, violation.suggestion, "Move I/O to dependent query boundary") != null);
    try testing.expect(std.mem.indexOf(u8, violation.operation, "file_read") != null);
    try testing.expect(std.mem.indexOf(u8, violation.location, "suggestion_test") != null);
}

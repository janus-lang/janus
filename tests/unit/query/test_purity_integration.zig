// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Query Purity System with Q1001 Diagnostic Emission
// Task 2.3: Complete purity guard system with diagnostic emission

const std = @import("std");
const testing = std.testing;

// Import the purity guard system (in a real implementation, this would be a separate module)
const QueryPurityError = error{
    ImpureOperation,
    UnauthorizedIO,
    NetworkAccess,
    FileSystemAccess,
    EnvironmentAccess,
    OutOfMemory,
};

const DiagnosticCode = enum {
    Q1001, // Query impurity detected
    Q1002, // Unauthorized I/O operation
    Q1003, // Network access in query
    Q1004, // File system access in query
    Q1005, // Environment access in query
};

// Diagnostic emission system
const Diagnostic = struct {
    code: DiagnosticCode,
    message: []const u8,
    location: []const u8,
    suggestion: []const u8,
    severity: Severity,

    const Severity = enum {
        err,
        warning,
        info,
    };
};

// Query execution engine with purity enforcement
const QueryEngine = struct {
    allocator: std.mem.Allocator,
    debug_mode: bool,
    diagnostics: std.ArrayList(Diagnostic),

    pub fn init(allocator: std.mem.Allocator, debug_mode: bool) QueryEngine {
        return QueryEngine{
            .allocator = allocator,
            .debug_mode = debug_mode,
            .diagnostics = .empty,
        };
    }

    pub fn deinit(self: *QueryEngine) void {
        self.diagnostics.deinit();
    }

    // Execute a query with purity checking
    pub fn executeQuery(self: *QueryEngine, query_name: []const u8, operations: []const []const u8) QueryPurityError!void {
        for (operations) |operation| {
            try self.checkOperationPurity(query_name, operation);
        }
    }

    // Check operation purity and emit diagnostics
    fn checkOperationPurity(self: *QueryEngine, query_name: []const u8, operation: []const u8) QueryPurityError!void {
        // Check for various impure operations
        if (self.isFileOperation(operation)) {
            try self.emitDiagnostic(.Q1001, "Query impurity detected: file system access", query_name, "Move I/O to dependent query boundary or use authorized query context");
            if (self.debug_mode) return QueryPurityError.ImpureOperation;
        }

        if (self.isNetworkOperation(operation)) {
            try self.emitDiagnostic(.Q1003, "Query impurity detected: network access", query_name, "Network operations not allowed in queries - use external data source");
            if (self.debug_mode) return QueryPurityError.NetworkAccess;
        }

        if (self.isEnvironmentOperation(operation)) {
            try self.emitDiagnostic(.Q1005, "Query impurity detected: environment access", query_name, "Environment access not allowed in queries - pass values as parameters");
            if (self.debug_mode) return QueryPurityError.EnvironmentAccess;
        }
    }

    fn isFileOperation(self: *QueryEngine, operation: []const u8) bool {
        _ = self;
        return std.mem.indexOf(u8, operation, "file_") != null or
            std.mem.indexOf(u8, operation, "read_file") != null or
            std.mem.indexOf(u8, operation, "write_file") != null;
    }

    fn isNetworkOperation(self: *QueryEngine, operation: []const u8) bool {
        _ = self;
        return std.mem.indexOf(u8, operation, "http") != null or
            std.mem.indexOf(u8, operation, "tcp") != null or
            std.mem.indexOf(u8, operation, "network") != null;
    }

    fn isEnvironmentOperation(self: *QueryEngine, operation: []const u8) bool {
        _ = self;
        return std.mem.indexOf(u8, operation, "getenv") != null or
            std.mem.indexOf(u8, operation, "env_") != null;
    }

    fn emitDiagnostic(self: *QueryEngine, code: DiagnosticCode, message: []const u8, location: []const u8, suggestion: []const u8) QueryPurityError!void {
        const diagnostic = Diagnostic{
            .code = code,
            .message = message,
            .location = location,
            .suggestion = suggestion,
            .severity = .err,
        };

        try self.diagnostics.append(diagnostic);
    }

    pub fn getDiagnostics(self: *const QueryEngine) []const Diagnostic {
        return self.diagnostics.items;
    }

    pub fn hasErrors(self: *const QueryEngine) bool {
        for (self.diagnostics.items) |diag| {
            if (diag.severity == .err) return true;
        }
        return false;
    }
};

test "Query engine emits Q1001 for file operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = QueryEngine.init(allocator, true);
    defer engine.deinit();

    const operations = [_][]const u8{
        "file_read('/etc/passwd')",
        "write_file('/tmp/output.txt')",
    };

    // Should fail in debug mode
    try testing.expectError(QueryPurityError.ImpureOperation, engine.executeQuery("test_query", &operations));

    // Check diagnostics were emitted
    const diagnostics = engine.getDiagnostics();
    try testing.expectEqual(@as(usize, 1), diagnostics.len); // Only first operation before error
    try testing.expectEqual(DiagnosticCode.Q1001, diagnostics[0].code);
    try testing.expect(std.mem.indexOf(u8, diagnostics[0].message, "file system access") != null);
    try testing.expect(std.mem.indexOf(u8, diagnostics[0].suggestion, "Move I/O to dependent query boundary") != null);
}

test "Query engine emits Q1003 for network operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = QueryEngine.init(allocator, true);
    defer engine.deinit();

    const operations = [_][]const u8{
        "http_get('https://api.example.com')",
    };

    try testing.expectError(QueryPurityError.NetworkAccess, engine.executeQuery("network_query", &operations));

    const diagnostics = engine.getDiagnostics();
    try testing.expectEqual(@as(usize, 1), diagnostics.len);
    try testing.expectEqual(DiagnosticCode.Q1003, diagnostics[0].code);
    try testing.expect(std.mem.indexOf(u8, diagnostics[0].message, "network access") != null);
}

test "Query engine emits Q1005 for environment operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = QueryEngine.init(allocator, true);
    defer engine.deinit();

    const operations = [_][]const u8{
        "getenv('HOME')",
    };

    try testing.expectError(QueryPurityError.EnvironmentAccess, engine.executeQuery("env_query", &operations));

    const diagnostics = engine.getDiagnostics();
    try testing.expectEqual(@as(usize, 1), diagnostics.len);
    try testing.expectEqual(DiagnosticCode.Q1005, diagnostics[0].code);
    try testing.expect(std.mem.indexOf(u8, diagnostics[0].message, "environment access") != null);
}

test "Query engine allows pure operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = QueryEngine.init(allocator, true);
    defer engine.deinit();

    const operations = [_][]const u8{
        "string_concat('hello', 'world')",
        "math_add(1, 2)",
        "type_check(node, expected_type)",
        "symbol_lookup('function_name')",
    };

    // Should succeed without errors
    try engine.executeQuery("pure_query", &operations);

    // No diagnostics should be emitted
    try testing.expectEqual(@as(usize, 0), engine.getDiagnostics().len);
    try testing.expect(!engine.hasErrors());
}

test "Query engine production mode records all violations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = QueryEngine.init(allocator, false); // Production mode
    defer engine.deinit();

    const operations = [_][]const u8{
        "file_read('/config.json')",
        "http_get('https://api.service.com')",
        "getenv('API_KEY')",
        "string_concat('hello', 'world')", // Pure operation
        "write_file('/tmp/cache.dat')",
    };

    // Should succeed in production mode (no throwing)
    try engine.executeQuery("mixed_query", &operations);

    // All violations should be recorded
    const diagnostics = engine.getDiagnostics();
    try testing.expectEqual(@as(usize, 4), diagnostics.len); // 4 impure operations

    // Check diagnostic codes
    var q1001_count: u32 = 0;
    var q1003_count: u32 = 0;
    var q1005_count: u32 = 0;

    for (diagnostics) |diag| {
        switch (diag.code) {
            .Q1001 => q1001_count += 1,
            .Q1003 => q1003_count += 1,
            .Q1005 => q1005_count += 1,
            else => {},
        }
    }

    try testing.expectEqual(@as(u32, 2), q1001_count); // file_read + write_file
    try testing.expectEqual(@as(u32, 1), q1003_count); // http_get
    try testing.expectEqual(@as(u32, 1), q1005_count); // getenv

    try testing.expect(engine.hasErrors());
}

test "Diagnostic format and content validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = QueryEngine.init(allocator, false);
    defer engine.deinit();

    const operations = [_][]const u8{
        "file_read('/sensitive/data.json')",
    };

    try engine.executeQuery("diagnostic_test", &operations);

    const diagnostics = engine.getDiagnostics();
    try testing.expectEqual(@as(usize, 1), diagnostics.len);

    const diag = diagnostics[0];

    // Validate diagnostic structure
    try testing.expectEqual(DiagnosticCode.Q1001, diag.code);
    try testing.expectEqual(Diagnostic.Severity.err, diag.severity);

    // Validate message content
    try testing.expect(std.mem.indexOf(u8, diag.message, "Query impurity detected") != null);
    try testing.expect(std.mem.indexOf(u8, diag.message, "file system access") != null);

    // Validate location
    try testing.expect(std.mem.indexOf(u8, diag.location, "diagnostic_test") != null);

    // Validate suggestion
    try testing.expect(std.mem.indexOf(u8, diag.suggestion, "Move I/O to dependent query boundary") != null);
    try testing.expect(std.mem.indexOf(u8, diag.suggestion, "authorized query context") != null);
}

// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - Capabilities Module
// Available in :full profile for capability-based security

const std = @import("std");

/// Base capability trait - all capabilities implement this interface
pub const Capability = struct {
    id_value: []const u8,
    permissions: std.StringHashMap(bool),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(cap_id: []const u8, allocator: std.mem.Allocator) Self {
        return Self{
            .id_value = cap_id,
            .permissions = std.StringHashMap(bool).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn id(self: Self) []const u8 {
        return self.id_value;
    }

    pub fn has_permission(self: Self, permission: []const u8) bool {
        return self.permissions.get(permission) orelse false;
    }

    pub fn grant_permission(self: *Self, permission: []const u8) !void {
        // Store permission key by reference; callers should pass stable strings.
        try self.permissions.put(permission, true);
    }

    pub fn revoke_permission(self: *Self, permission: []const u8) void {
        _ = self.permissions.remove(permission);
    }

    pub fn deinit(self: *Self) void {
        self.permissions.deinit();
    }
};

/// Network HTTP capability - controls HTTP access
pub const NetHttp = struct {
    base: Capability,
    allowed_hosts: std.ArrayList([]const u8),
    allowed_schemes: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(cap_id: []const u8, allocator: std.mem.Allocator) Self {
        var cap = Self{
            .base = Capability.init(cap_id, allocator),
            .allowed_hosts = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .allowed_schemes = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
        };

        // Default permissions for HTTP capability
        cap.base.grant_permission("http.get") catch unreachable;
        cap.base.grant_permission("http.post") catch unreachable;

        // Default allowed schemes
        cap.allowed_schemes.append(allocator.dupe(u8, "http") catch unreachable) catch unreachable;
        cap.allowed_schemes.append(allocator.dupe(u8, "https") catch unreachable) catch unreachable;

        return cap;
    }

    pub fn id(self: Self) []const u8 {
        return self.base.id();
    }

    pub fn allows_url(self: Self, url: []const u8) bool {
        // Simple URL validation for demo
        if (url.len == 0) return false;

        // Check scheme
        var scheme_allowed = false;
        for (self.allowed_schemes.items) |scheme| {
            if (std.mem.startsWith(u8, url, scheme)) {
                scheme_allowed = true;
                break;
            }
        }

        if (!scheme_allowed) return false;

        // If no specific hosts are configured, allow all
        if (self.allowed_hosts.items.len == 0) return true;

        // Check if URL contains allowed host
        for (self.allowed_hosts.items) |host| {
            if (std.mem.indexOf(u8, url, host) != null) {
                return true;
            }
        }

        return false;
    }

    pub fn allows_server_port(self: Self, port: []const u8) bool {
        // Check if capability allows serving on this port
        _ = self;

        // For demo, allow common development ports
        return std.mem.eql(u8, port, ":8080") or
            std.mem.eql(u8, port, ":3000") or
            std.mem.eql(u8, port, ":8000");
    }

    pub fn allows_path_access(self: Self, path: []const u8) bool {
        // Check if capability allows access to this path
        _ = self;

        // For :full profile demo, only allow /public paths and root paths
        return std.mem.eql(u8, path, "/") or
            std.mem.eql(u8, path, "/about") or
            std.mem.startsWith(u8, path, "/public/");
    }

    pub fn allowed_paths(self: Self) []const u8 {
        // Return description of allowed paths for logging
        _ = self;
        return "/public/* (capability-restricted)";
    }

    pub fn allow_host(self: *Self, host: []const u8) !void {
        try self.allowed_hosts.append(try self.base.allocator.dupe(u8, host));
    }

    pub fn allow_scheme(self: *Self, scheme: []const u8) !void {
        try self.allowed_schemes.append(try self.base.allocator.dupe(u8, scheme));
    }

    pub fn deinit(self: *Self) void {
        for (self.allowed_hosts.items) |host| {
            self.base.allocator.free(host);
        }
        self.allowed_hosts.deinit(self.base.allocator);

        for (self.allowed_schemes.items) |scheme| {
            self.base.allocator.free(scheme);
        }
        self.allowed_schemes.deinit(self.base.allocator);

        self.base.deinit();
    }
};

/// File system capability - controls file access
pub const FileSystem = struct {
    base: Capability,
    allowed_paths: std.ArrayList([]const u8),
    read_only: bool,

    const Self = @This();

    pub fn init(cap_id: []const u8, allocator: std.mem.Allocator) Self {
        var cap = Self{
            .base = Capability.init(cap_id, allocator),
            .allowed_paths = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .read_only = false,
        };

        // Default permissions
        cap.base.grant_permission("fs.read") catch unreachable;
        cap.base.grant_permission("fs.write") catch unreachable;

        return cap;
    }

    pub fn id(self: Self) []const u8 {
        return self.base.id();
    }

    pub fn allows_path(self: Self, path: []const u8) bool {
        if (self.allowed_paths.items.len == 0) return true;

        for (self.allowed_paths.items) |allowed_path| {
            if (std.mem.startsWith(u8, path, allowed_path)) {
                return true;
            }
        }

        return false;
    }

    pub fn allows_write(self: Self) bool {
        return !self.read_only and self.base.has_permission("fs.write");
    }

    pub fn allow_path(self: *Self, path: []const u8) !void {
        try self.allowed_paths.append(try self.base.allocator.dupe(u8, path));
    }

    pub fn set_read_only(self: *Self, read_only: bool) void {
        self.read_only = read_only;
        if (read_only) {
            self.base.revoke_permission("fs.write");
        } else {
            self.base.grant_permission("fs.write") catch unreachable;
        }
    }

    pub fn deinit(self: *Self) void {
        for (self.allowed_paths.items) |path| {
            self.base.allocator.free(path);
        }
        self.allowed_paths.deinit(self.base.allocator);
        self.base.deinit();
    }
};

/// Database capability - controls database access
pub const Database = struct {
    base: Capability,
    connection_string: []const u8,
    max_connections: u32,

    const Self = @This();

    pub fn init(cap_id: []const u8, connection_string: []const u8, allocator: std.mem.Allocator) Self {
        var cap = Self{
            .base = Capability.init(cap_id, allocator),
            .connection_string = allocator.dupe(u8, connection_string) catch unreachable,
            .max_connections = 10,
        };

        // Default permissions
        cap.base.grant_permission("db.read") catch unreachable;
        cap.base.grant_permission("db.write") catch unreachable;

        return cap;
    }

    pub fn id(self: Self) []const u8 {
        return self.base.id();
    }

    pub fn allows_operation(self: Self, operation: []const u8) bool {
        return self.base.has_permission(operation);
    }

    pub fn set_max_connections(self: *Self, max: u32) void {
        self.max_connections = max;
    }

    pub fn deinit(self: *Self) void {
        self.base.allocator.free(self.connection_string);
        self.base.deinit();
    }
};

/// Capability factory functions
/// Network bind capability - controls socket binding
pub const NetBind = struct {
    base: Capability,
    allowed_ports: std.ArrayList(u16),

    const Self = @This();

    pub fn init(cap_id: []const u8, allocator: std.mem.Allocator) Self {
        var cap = Self{
            .base = Capability.init(cap_id, allocator),
            .allowed_ports = std.ArrayList(u16).initCapacity(allocator, 3) catch unreachable,
        };

        // Default permissions for bind capability
        cap.base.grant_permission("net.bind") catch unreachable;

        // Default allowed ports (development ports)
        cap.allowed_ports.append(8080) catch unreachable;
        cap.allowed_ports.append(3000) catch unreachable;
        cap.allowed_ports.append(8000) catch unreachable;

        return cap;
    }

    pub fn id(self: Self) []const u8 {
        return self.base.id();
    }

    pub fn allows_bind_address(self: Self, address: anytype) bool {
        _ = self;
        _ = address;
        // For demo, allow all addresses
        return true;
    }

    pub fn deinit(self: *Self) void {
        self.allowed_ports.deinit(self.base.allocator);
        self.base.deinit();
    }
};

pub fn create_net_http_capability(id: []const u8, allocator: std.mem.Allocator) NetHttp {
    return NetHttp.init(id, allocator);
}

pub fn create_net_bind_capability(id: []const u8, allocator: std.mem.Allocator) NetBind {
    return NetBind.init(id, allocator);
}

pub fn create_fs_capability(id: []const u8, allocator: std.mem.Allocator) FileSystem {
    return FileSystem.init(id, allocator);
}

pub fn create_db_capability(id: []const u8, connection_string: []const u8, allocator: std.mem.Allocator) Database {
    return Database.init(id, connection_string, allocator);
}

/// Capability validation utilities
pub fn validate_capability(cap: anytype) bool {
    // Generic capability validation
    const cap_id = cap.id();
    return cap_id.len > 0;
}

pub fn audit_capability_usage(cap: anytype, operation: []const u8) void {
    // Audit trail for capability usage (would integrate with logging system)
    _ = cap;
    _ = operation;
    // std.log.info("Capability {} used for operation: {}", .{ cap.id(), operation });
}

// Tests
test "NetHttp capability" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cap = NetHttp.init("test-http-cap", allocator);
    defer cap.deinit();

    // Test URL validation
    try testing.expect(cap.allows_url("https://example.com"));
    try testing.expect(cap.allows_url("http://api.test.com"));
    try testing.expect(!cap.allows_url("ftp://files.com"));
    try testing.expect(!cap.allows_url(""));

    // Test host restrictions
    try cap.allow_host("example.com");
    try testing.expect(cap.allows_url("https://example.com/api"));

    // Test permissions
    try testing.expect(cap.base.has_permission("http.get"));
    try testing.expect(cap.base.has_permission("http.post"));
    try testing.expect(!cap.base.has_permission("http.delete"));
}

test "FileSystem capability" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cap = FileSystem.init("test-fs-cap", allocator);
    defer cap.deinit();

    // Test path validation
    try testing.expect(cap.allows_path("/any/path")); // No restrictions by default

    // Add path restriction
    try cap.allow_path("/home/user");
    try testing.expect(cap.allows_path("/home/user/file.txt"));
    try testing.expect(!cap.allows_path("/etc/passwd"));

    // Test read-only mode
    try testing.expect(cap.allows_write());
    cap.set_read_only(true);
    try testing.expect(!cap.allows_write());
}

test "Database capability" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cap = Database.init("test-db-cap", "postgresql://localhost:5432/test", allocator);
    defer cap.deinit();

    // Test operations
    try testing.expect(cap.allows_operation("db.read"));
    try testing.expect(cap.allows_operation("db.write"));
    try testing.expect(!cap.allows_operation("db.admin"));

    // Test connection limits
    try testing.expect(cap.max_connections == 10);
    cap.set_max_connections(5);
    try testing.expect(cap.max_connections == 5);
}

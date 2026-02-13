// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Router Implementation
//!
//! Pattern-based routing for namespace messaging.
//! Supports wildcards: `app.*`, `service.*.backend`, `sensor.+.reading`

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const transport = @import("transport.zig");
const envelope = @import("envelope.zig");

const Path = types.Path;
const Pattern = types.Pattern;
const Segment = types.Segment;
const Transport = transport.Transport;

/// Route entry mapping pattern to transport
pub const Route = struct {
    const Self = @This();

    pattern: Pattern,
    transport: *Transport,
    priority: u32, // Higher = more specific

    pub fn init(allocator: Allocator, pattern_str: []const u8, trans: *Transport) !Self {
        const pattern = try Pattern.parse(allocator, pattern_str);
        return .{
            .pattern = pattern,
            .transport = trans,
            .priority = @intCast(pattern.segments.len),
        };
    }

    /// Check if this route matches a given path
    pub fn matches(self: Self, path: Path) bool {
        return self.pattern.matchesPath(path);
    }
};

/// Router for namespace messages
pub const Router = struct {
    const Self = @This();

    allocator: Allocator,
    local_routes: std.ArrayList(Route),
    network_routes: std.ArrayList(Route),
    default_transport: ?*Transport,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .local_routes = .empty,
            .network_routes = .empty,
            .default_transport = null,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.local_routes.items) |*rt| {
            rt.pattern.deinit();
        }
        self.local_routes.deinit(self.allocator);

        for (self.network_routes.items) |*rt| {
            rt.pattern.deinit();
        }
        self.network_routes.deinit(self.allocator);
    }

    /// Add a local route (same-process)
    pub fn addLocalRoute(self: *Self, pattern: []const u8, trans: *Transport) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const new_route = try Route.init(self.allocator, pattern, trans);
        try self.local_routes.append(self.allocator, new_route);
        self.sortRoutes(&self.local_routes);
    }

    /// Add a network route (remote)
    pub fn addNetworkRoute(self: *Self, pattern: []const u8, trans: *Transport) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const new_route = try Route.init(self.allocator, pattern, trans);
        try self.network_routes.append(self.allocator, new_route);
        self.sortRoutes(&self.network_routes);
    }

    /// Set default transport for unmatched paths
    pub fn setDefault(self: *Self, trans: *Transport) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.default_transport = trans;
    }

    /// Route a message to the appropriate transport
    /// First checks local routes, then network routes, then default
    pub fn route(self: *Self, path: Path) ?*Transport {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check local routes first (higher priority for same-process)
        if (self.findMatch(&self.local_routes, path)) |trans| {
            return trans;
        }

        // Check network routes
        if (self.findMatch(&self.network_routes, path)) |trans| {
            return trans;
        }

        // Fall back to default
        return self.default_transport;
    }

    /// Find matching transport in route list
    fn findMatch(self: Self, routes: *const std.ArrayList(Route), path: Path) ?*Transport {
        _ = self;
        for (routes.items) |rt| {
            if (rt.matches(path)) {
                return rt.transport;
            }
        }
        return null;
    }

    /// Sort routes by priority (most specific first)
    fn sortRoutes(self: Self, routes: *std.ArrayList(Route)) void {
        _ = self;
        std.sort.block(Route, routes.items, {}, struct {
            pub fn lessThan(_: void, a: Route, b: Route) bool {
                return a.priority > b.priority;
            }
        }.lessThan);
    }
};

/// Pattern matching engine
pub const PatternMatcher = struct {
    /// Match a path against a pattern
    /// Pattern segments:
    /// - `*` matches zero or more segments
    /// - `+` matches exactly one segment
    /// - literal must match exactly
    pub fn matches(pattern: Pattern, path: Path) bool {
        return matchSegments(pattern.segments, path.segments);
    }

    fn matchSegments(pattern_segs: []Segment, path_segs: []Segment) bool {
        var pi: usize = 0; // pattern index
        var pai: usize = 0; // path index

        while (pi < pattern_segs.len and pai < path_segs.len) {
            const pseg = pattern_segs[pi];

            switch (pseg) {
                .multi_wildcard => {
                    // `*` matches remaining segments
                    if (pi == pattern_segs.len - 1) {
                        // `*` at end matches everything
                        return true;
                    }
                    // `*` in middle - try all possibilities
                    return matchWithWildcard(pattern_segs[pi + 1 ..], path_segs[pai..]);
                },
                .single_wildcard => {
                    // `+` matches exactly one segment
                    pi += 1;
                    pai += 1;
                },
                .literal => |lit| {
                    if (pai >= path_segs.len) return false;
                    switch (path_segs[pai]) {
                        .literal => |plit| {
                            if (!std.mem.eql(u8, lit, plit)) return false;
                        },
                        else => return false,
                    }
                    pi += 1;
                    pai += 1;
                },
            }
        }

        // Both must be exhausted (or pattern ends with `*`)
        if (pi < pattern_segs.len) {
            // Check if remaining pattern segments are all `*`
            for (pattern_segs[pi..]) |seg| {
                if (seg != .multi_wildcard) return false;
            }
            return true;
        }

        return pai == path_segs.len;
    }

    fn matchWithWildcard(remaining_pattern: []Segment, remaining_path: []Segment) bool {
        // Try matching remaining pattern at each position
        for (0..remaining_path.len + 1) |skip| {
            if (matchSegments(remaining_pattern, remaining_path[skip..])) {
                return true;
            }
        }
        return false;
    }
};

// Tests
const testing = std.testing;

test "Pattern matching - exact match" {
    const allocator = testing.allocator;

    var pattern = try Pattern.parse(allocator, "app/service/backend");
    defer pattern.deinit();

    var path = try Path.parse(allocator, "app/service/backend");
    defer path.deinit();

    try testing.expect(PatternMatcher.matches(pattern, path));
}

test "Pattern matching - single wildcard" {
    const allocator = testing.allocator;

    var pattern = try Pattern.parse(allocator, "app/+/backend");
    defer pattern.deinit();

    var path = try Path.parse(allocator, "app/service/backend");
    defer path.deinit();

    try testing.expect(PatternMatcher.matches(pattern, path));

    var path2 = try Path.parse(allocator, "app/api/backend");
    defer path2.deinit();

    try testing.expect(PatternMatcher.matches(pattern, path2));
}

test "Pattern matching - multi wildcard" {
    const allocator = testing.allocator;

    var pattern = try Pattern.parse(allocator, "app/*");
    defer pattern.deinit();

    var path = try Path.parse(allocator, "app/service/backend/config");
    defer path.deinit();

    try testing.expect(PatternMatcher.matches(pattern, path));

    var path2 = try Path.parse(allocator, "app");
    defer path2.deinit();

    try testing.expect(PatternMatcher.matches(pattern, path2));
}

test "Pattern matching - no match" {
    const allocator = testing.allocator;

    var pattern = try Pattern.parse(allocator, "app/service/backend");
    defer pattern.deinit();

    var path = try Path.parse(allocator, "app/service/frontend");
    defer path.deinit();

    try testing.expect(!PatternMatcher.matches(pattern, path));
}

test "Router - local routing" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var mem_transport = try transport.MemoryTransport.init(allocator);
    defer mem_transport.deinit();

    var trans_ptr: Transport = .{ .memory = &mem_transport };

    try router.addLocalRoute("app/service/*", &trans_ptr);

    var path = try Path.parse(allocator, "app/service/backend");
    defer path.deinit();

    const result = router.route(path);
    try testing.expect(result != null);
}

test "Router - priority ordering" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var mem1 = try transport.MemoryTransport.init(allocator);
    defer mem1.deinit();
    var trans1: Transport = .{ .memory = &mem1 };

    var mem2 = try transport.MemoryTransport.init(allocator);
    defer mem2.deinit();
    var trans2: Transport = .{ .memory = &mem2 };

    // Add less specific first
    try router.addLocalRoute("app/*", &trans1);
    // Add more specific second
    try router.addLocalRoute("app/service/backend", &trans2);

    var path = try Path.parse(allocator, "app/service/backend");
    defer path.deinit();

    // Should route to more specific (trans2)
    const result = router.route(path);
    try testing.expect(result != null);
    try testing.expect(result == &trans2);
}

// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Router Implementation
//!
//! Pattern-based routing for namespace messaging.
//! Supports wildcards: `app.*`, `service.*.backend`, `sensor.+.reading`
//!
//! Retained Values (RFC-0500 §3.5):
//! - MQTT-style last-known-value delivery
//! - Lamport clock-based conflict resolution
//! - LRU eviction with configurable limits

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const transport = @import("transport.zig");
const envelope = @import("envelope.zig");

const Path = types.Path;
const Pattern = types.Pattern;
const Segment = types.Segment;
const Transport = transport.Transport;
const RetainedValueCache = types.RetainedValueCache;
const PublishOptions = types.PublishOptions;

/// Default max retained values per namespace
pub const DEFAULT_MAX_RETAINED = 1000;

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

/// Subscription entry with retained value delivery support
pub const Subscription = struct {
    const Self = @This();

    pattern: Pattern,
    callback: *const fn (*anyopaque, Path, []const u8) void,
    context: *anyopaque,
    wants_retained: bool,

    pub fn init(
        pattern: Pattern,
        callback: *const fn (*anyopaque, Path, []const u8) void,
        context: *anyopaque,
        wants_retained: bool,
    ) Self {
        return .{
            .pattern = pattern,
            .callback = callback,
            .context = context,
            .wants_retained = wants_retained,
        };
    }

    pub fn deinit(self: *Self) void {
        self.pattern.deinit();
    }
};

/// Router for namespace messages with retained value support
pub const Router = struct {
    const Self = @This();

    allocator: Allocator,
    local_routes: std.ArrayList(Route),
    network_routes: std.ArrayList(Route),
    default_transport: ?*Transport,
    retained_cache: RetainedValueCache,
    subscriptions: std.ArrayList(Subscription),
    lamport_clock: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator) Self {
        return initWithCapacity(allocator, DEFAULT_MAX_RETAINED);
    }

    pub fn initWithCapacity(allocator: Allocator, max_retained: usize) Self {
        return .{
            .allocator = allocator,
            .local_routes = .empty,
            .network_routes = .empty,
            .default_transport = null,
            .retained_cache = RetainedValueCache.init(allocator, max_retained),
            .subscriptions = .empty,
            .lamport_clock = std.atomic.Value(u64).init(0),
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

        for (self.subscriptions.items) |*sub| {
            sub.deinit();
        }
        self.subscriptions.deinit(self.allocator);

        self.retained_cache.deinit();
    }

    /// Get next Lamport clock value
    pub fn nextLamportClock(self: *Self) u64 {
        return self.lamport_clock.fetchAdd(1, .monotonic);
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

    // =========================================================================
    // Retained Value Support (RFC-0500 §3.5)
    // =========================================================================

    /// Publish with options including retain flag and Lamport clock
    pub fn publishWithOptions(
        self: *Self,
        path: Path,
        envelope_data: []const u8,
        opts: PublishOptions,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Update Lamport clock if provided, otherwise use internal
        const clock = if (opts.lamport_clock > 0) opts.lamport_clock else self.nextLamportClock();

        // Store retained value if retain flag is set
        if (opts.retain) {
            try self.retained_cache.updateRetained(
                path,
                envelope_data,
                clock,
                opts.ttl_seconds,
            );
        }

        // Notify matching subscribers (mutex is held, notifySubscribers will unlock/lock)
        try self.notifySubscribers(path, envelope_data);
    }

    /// Subscribe to a pattern with optional immediate retained value delivery
    /// RFC-0500 §3.5: "Subscribe delivers retained values immediately"
    pub fn subscribeWithRetained(
        self: *Self,
        pattern: Pattern,
        callback: *const fn (*anyopaque, Path, []const u8) void,
        context: *anyopaque,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Create subscription
        const sub = Subscription.init(pattern, callback, context, true);
        try self.subscriptions.append(self.allocator, sub);

        // Deliver matching retained values immediately
        try self.deliverRetainedValues(pattern, callback, context);
    }

    /// Subscribe without retained value delivery
    pub fn subscribe(self: *Self, pattern: Pattern, callback: *const fn (*anyopaque, Path, []const u8) void, context: *anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const sub = Subscription.init(pattern, callback, context, false);
        try self.subscriptions.append(self.allocator, sub);
    }

    /// Deliver retained values matching pattern to a callback
    fn deliverRetainedValues(
        self: *Self,
        pattern: Pattern,
        callback: *const fn (*anyopaque, Path, []const u8) void,
        context: *anyopaque,
    ) !void {
        // Unlock during callback to avoid deadlock
        self.mutex.unlock();
        defer self.mutex.lock();

        const retained_values = try self.retained_cache.matching(pattern, self.allocator);
        defer {
            for (retained_values) |*rv| {
                rv.deinit(self.allocator);
            }
            self.allocator.free(retained_values);
        }

        for (retained_values) |rv| {
            // Clone path for the callback (callback takes ownership)
            const path_str = try rv.path.toString(self.allocator);
            const path_clone = try Path.parse(self.allocator, path_str);

            callback(context, path_clone, rv.envelope_data);
        }
    }

    /// Notify all subscribers matching a path
    fn notifySubscribers(self: *Self, path: Path, envelope_data: []const u8) !void {
        // Unlock during callbacks
        self.mutex.unlock();
        defer self.mutex.lock();

        for (self.subscriptions.items) |sub| {
            if (sub.pattern.matchesPath(path)) {
                // Clone path for callback
                const path_str = try path.toString(self.allocator);
                const path_clone = try Path.parse(self.allocator, path_str);
                errdefer path_clone.deinit();

                sub.callback(sub.context, path_clone, envelope_data);
            }
        }
    }

    /// Get a retained value by path (returns null if not found or expired)
    pub fn getRetained(self: *Self, path: Path) ?types.RetainedValue {
        return self.retained_cache.getOrEvict(path);
    }

    /// Update a retained value directly (for external Lamport clock sources)
    pub fn updateRetained(
        self: *Self,
        path: Path,
        envelope_data: []const u8,
        lamport_clock: u64,
        ttl_seconds: ?u64,
    ) !void {
        try self.retained_cache.updateRetained(path, envelope_data, lamport_clock, ttl_seconds);
    }

    /// Remove a retained value
    pub fn removeRetained(self: *Self, path: Path) void {
        self.retained_cache.remove(path);
    }

    /// Get count of retained values
    pub fn retainedCount(self: *Self) usize {
        return self.retained_cache.count();
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

// =========================================================================
// Test Callback Types and Contexts
// =========================================================================

const TestDeliveryContext = struct {
    allocator: Allocator,
    received: std.ArrayList(DeliveryRecord),

    const DeliveryRecord = struct {
        path: Path,
        data: []const u8,
    };

    fn init(allocator: Allocator) @This() {
        return .{
            .allocator = allocator,
            .received = .empty,
        };
    }

    fn deinit(self: *@This()) void {
        for (self.received.items) |*item| {
            item.path.deinit();
            self.allocator.free(item.data);
        }
        self.received.deinit(self.allocator);
    }

    fn callback(ctx: *anyopaque, path: Path, data: []const u8) void {
        const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
        const path_clone = path;
        const data_copy = self.allocator.dupe(u8, data) catch return;
        self.received.append(self.allocator, .{ .path = path_clone, .data = data_copy }) catch return;
    }
};

// =========================================================================
// Tests
// =========================================================================

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

// =========================================================================
// Retained Value Tests (RFC-0500 §3.5)
// =========================================================================

test "Router - publishWithOptions retains value" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var path = try Path.parse(allocator, "sensor/berlin/temp");
    defer path.deinit();

    const payload = "temperature: 22.5";

    // Publish with retain flag
    try router.publishWithOptions(path, payload, .{
        .retain = true,
        .lamport_clock = 5,
    });

    // Verify retained
    try testing.expectEqual(@as(usize, 1), router.retainedCount());

    // Retrieve retained value
    var retained = router.getRetained(path);
    try testing.expect(retained != null);
    if (retained) |*rv| {
        try testing.expectEqualStrings(payload, rv.envelope_data);
        try testing.expectEqual(@as(u64, 5), rv.lamport_clock);
        rv.deinit(allocator);
    }
}

test "Router - publish without retain does not store" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var path = try Path.parse(allocator, "sensor/berlin/temp");
    defer path.deinit();

    // Publish without retain flag
    try router.publishWithOptions(path, "temp: 20", .{
        .retain = false,
    });

    try testing.expectEqual(@as(usize, 0), router.retainedCount());
}

test "Router - subscribeWithRetained delivers immediately" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    // First, publish a retained value
    var path = try Path.parse(allocator, "sensor/berlin/temp");
    defer path.deinit();
    try router.publishWithOptions(path, "temp: 25.0", .{
        .retain = true,
        .lamport_clock = 1,
    });

    var ctx = TestDeliveryContext.init(allocator);
    defer ctx.deinit();

    // Subscribe with pattern matching the retained value
    // Note: pattern ownership is transferred to subscription, don't deinit
    const pattern = try Pattern.parse(allocator, "sensor/+/temp");
    try router.subscribeWithRetained(pattern, TestDeliveryContext.callback, &ctx);

    // Should have received the retained value immediately
    try testing.expectEqual(@as(usize, 1), ctx.received.items.len);
    try testing.expectEqualStrings("temp: 25.0", ctx.received.items[0].data);
}

test "Router - subscribeWithRetained delivers multiple matching values" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    // Publish multiple retained values
    var path1 = try Path.parse(allocator, "sensor/berlin/temp");
    defer path1.deinit();
    try router.publishWithOptions(path1, "temp: 20", .{ .retain = true, .lamport_clock = 1 });

    var path2 = try Path.parse(allocator, "sensor/berlin/humidity");
    defer path2.deinit();
    try router.publishWithOptions(path2, "hum: 60", .{ .retain = true, .lamport_clock = 1 });

    var path3 = try Path.parse(allocator, "sensor/london/temp");
    defer path3.deinit();
    try router.publishWithOptions(path3, "temp: 15", .{ .retain = true, .lamport_clock = 1 });

    var ctx = TestDeliveryContext.init(allocator);
    defer ctx.deinit();

    // Subscribe to all Berlin sensors
    // Note: pattern ownership is transferred to subscription, don't deinit
    const pattern = try Pattern.parse(allocator, "sensor/berlin/+");
    try router.subscribeWithRetained(pattern, TestDeliveryContext.callback, &ctx);

    // Should have received 2 values (berlin/temp and berlin/humidity)
    try testing.expectEqual(@as(usize, 2), ctx.received.items.len);
}

test "Router - Lamport clock auto-increment" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    const clock1 = router.nextLamportClock();
    const clock2 = router.nextLamportClock();
    const clock3 = router.nextLamportClock();

    try testing.expect(clock2 > clock1);
    try testing.expect(clock3 > clock2);
}

test "Router - Lamport clock conflict resolution" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var path = try Path.parse(allocator, "sensor/berlin/temp");
    defer path.deinit();

    // Update with clock 10
    try router.updateRetained(path, "temp: 20", 10, null);

    // Try to update with lower clock (should be rejected - value stays at temp: 20)
    try router.updateRetained(path, "temp: 30", 5, null);

    var retained = router.getRetained(path);
    try testing.expect(retained != null);
    if (retained) |*rv| {
        try testing.expectEqualStrings("temp: 20", rv.envelope_data);
        try testing.expectEqual(@as(u64, 10), rv.lamport_clock);
        rv.deinit(allocator);
    }

    // Update with higher clock (should succeed)
    try router.updateRetained(path, "temp: 25", 15, null);

    var retained2 = router.getRetained(path);
    try testing.expect(retained2 != null);
    if (retained2) |*rv| {
        try testing.expectEqualStrings("temp: 25", rv.envelope_data);
        try testing.expectEqual(@as(u64, 15), rv.lamport_clock);
        rv.deinit(allocator);
    }
}

test "Router - remove retained value" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var path = try Path.parse(allocator, "sensor/berlin/temp");
    defer path.deinit();

    try router.updateRetained(path, "temp: 20", 1, null);
    try testing.expectEqual(@as(usize, 1), router.retainedCount());

    router.removeRetained(path);
    try testing.expectEqual(@as(usize, 0), router.retainedCount());

    // Verify retained value is gone
    try testing.expect(router.getRetained(path) == null);
}

test "Router - max retained limit enforced" {
    const allocator = testing.allocator;

    // Create router with max 3 retained values
    var router = Router.initWithCapacity(allocator, 3);
    defer router.deinit();

    // Add 5 values
    for (0..5) |i| {
        var buf: [32]u8 = undefined;
        const path_str = std.fmt.bufPrint(&buf, "sensor/{d}", .{i}) catch continue;
        var path = try Path.parse(allocator, path_str);
        defer path.deinit();
        try router.updateRetained(path, "data", @intCast(i), null);
    }

    // Should only have 3 (most recent due to LRU eviction)
    try testing.expectEqual(@as(usize, 3), router.retainedCount());
}

test "Router - getOrEvict updates access time" {
    const allocator = testing.allocator;

    var router = Router.initWithCapacity(allocator, 2);
    defer router.deinit();

    var path1 = try Path.parse(allocator, "sensor/a");
    defer path1.deinit();
    var path2 = try Path.parse(allocator, "sensor/b");
    defer path2.deinit();

    try router.updateRetained(path1, "data1", 1, null);
    try router.updateRetained(path2, "data2", 2, null);

    // Access path1 to make it more recent
    _ = router.getRetained(path1);

    // Add path3 - should evict path2 (least recently used)
    var path3 = try Path.parse(allocator, "sensor/c");
    defer path3.deinit();
    try router.updateRetained(path3, "data3", 3, null);

    // path1 should still be there, path2 should be evicted
    try testing.expect(router.getRetained(path1) != null);
    try testing.expect(router.getRetained(path2) == null);
    try testing.expect(router.getRetained(path3) != null);
}

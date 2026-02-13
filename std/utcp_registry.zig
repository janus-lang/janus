// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const rsp1 = @import("rsp1");
pub const cluster = @import("rsp1_cluster");

pub const WriteCapability = struct {};
pub const MaintenanceCapability = struct {}; // optional, if you want to gate maint ops separately

/// ManualFn: produce a JSON OBJECT slice describing a container
pub const ManualFn = *const fn (ctx: *const anyopaque, alloc: std.mem.Allocator) anyerror![]const u8;

/// BLAKE3-based lease cryptography for signature verification
pub const LeaseCrypto = struct {
    /// Sign a lease with BLAKE3 keyed hash
    pub fn signLease(
        secret_key: *const [32]u8,
        group_name: []const u8,
        entry_name: []const u8,
        ttl_ns: i128,
        deadline_ns: i128,
        out_signature: *[32]u8,
    ) void {
        const data = std.fmt.comptimePrint("{s}:{s}:{d}:{d}", .{ group_name, entry_name, ttl_ns, deadline_ns });
        std.crypto.hash.Blake3.hash(data, out_signature, .{ .key = secret_key });
    }

    /// Verify a lease signature
    pub fn verifySignature(
        secret_key: *const [32]u8,
        group_name: []const u8,
        entry_name: []const u8,
        ttl_ns: i128,
        deadline_ns: i128,
        signature: *const [32]u8,
    ) bool {
        var expected_sig: [32]u8 = undefined;
        signLease(secret_key, group_name, entry_name, ttl_ns, deadline_ns, &expected_sig);
        return std.mem.eql(u8, &expected_sig, signature);
    }
};

/// Backpressure metrics for registry health monitoring
pub const BackpressureMetrics = struct {
    total_entries: usize = 0, // Total entries currently registered
    purged_since_reset: u64 = 0, // Total ghosts purged since metrics reset
    total_heartbeats: u64 = 0, // Total heartbeat calls processed
    failed_heartbeats: u64 = 0, // Failed heartbeat attempts (signature verification)
    avg_ttl_remaining_ns: i128 = 0, // Average TTL remaining across all entries (nanoseconds)
    max_ttl_remaining_ns: i128 = 0, // Maximum TTL remaining
    min_ttl_remaining_ns: i128 = std.math.maxInt(i128), // Minimum TTL remaining
    metrics_reset_time_ns: i128 = 0, // When metrics were last reset

    pub fn reset(self: *BackpressureMetrics) void {
        self.total_entries = 0;
        self.purged_since_reset = 0;
        self.total_heartbeats = 0;
        self.failed_heartbeats = 0;
        self.avg_ttl_remaining_ns = 0;
        self.max_ttl_remaining_ns = 0;
        self.min_ttl_remaining_ns = std.math.maxInt(i128);
        self.metrics_reset_time_ns = std.time.nanoTimestamp();
    }

    pub fn updateTtlStats(self: *BackpressureMetrics, ttl_remaining_ns: i128, entry_count: usize) void {
        if (entry_count == 0) return;

        self.avg_ttl_remaining_ns = @divTrunc(ttl_remaining_ns, @as(i128, @intCast(entry_count)));
        self.max_ttl_remaining_ns = @max(self.max_ttl_remaining_ns, ttl_remaining_ns);
        self.min_ttl_remaining_ns = @min(self.min_ttl_remaining_ns, ttl_remaining_ns);
    }

    pub fn recordHeartbeat(self: *BackpressureMetrics, success: bool) void {
        self.total_heartbeats += 1;
        if (!success) {
            self.failed_heartbeats += 1;
        }
    }

    pub fn recordPurged(self: *BackpressureMetrics, count: u64) void {
        self.purged_since_reset += count;
    }
};

const Entry = struct {
    name: []u8, // owned entry name
    ctx: *const anyopaque, // borrowed pointer to the live instance
    manual_fn: ManualFn, // type-erased adapter to .utcpManual()

    // Lease / TTL
    ttl_ns: i128, // requested time-to-live in nanoseconds
    deadline_ns: i128, // absolute expiry (monotonic clock)

    // Crypto
    signature: [32]u8, // BLAKE3 signature of the lease
    heartbeat_count: u64, // number of heartbeat extensions
};

const Group = struct {
    name: []u8, // owned group name
    entries: std.ArrayList(Entry), // owns entry names
    quota_max_entries: usize = 0, // max entries allowed (0 = unlimited)
    quota_violations: u64 = 0, // count of quota violations for this group

    fn init(alloc: std.mem.Allocator, name: []const u8) !Group {
        const copy = try alloc.alloc(u8, name.len);
        @memcpy(copy, name);
        return .{
            .name = copy,
            .entries = std.ArrayList(Entry){},
            .quota_max_entries = 0,
            .quota_violations = 0,
        };
    }

    fn deinit(self: *Group, alloc: std.mem.Allocator) void {
        for (self.entries.items) |e| alloc.free(e.name);
        self.entries.deinit(alloc);
        alloc.free(self.name);
        self.* = undefined;
    }

    /// Check if adding an entry would exceed quota
    fn wouldExceedQuota(self: *const Group) bool {
        return self.quota_max_entries > 0 and self.entries.items.len >= self.quota_max_entries;
    }

    /// Count active (non-expired) entries for quota purposes
    fn activeEntryCount(self: *const Group, now_ns: i128) usize {
        var count: usize = 0;
        for (self.entries.items) |e| {
            if (e.deadline_ns > now_ns) {
                count += 1;
            }
        }
        return count;
    }

    /// Check if adding an entry would exceed quota (active entries only)
    fn wouldExceedQuotaActive(self: *const Group, now_ns: i128) bool {
        return self.quota_max_entries > 0 and self.activeEntryCount(now_ns) >= self.quota_max_entries;
    }
};

/// Capsule-aware, thread-safe namespaced registry with TTL-based lifecycle
pub fn UtcpRegistryNsSyncLease(comptime UseSpinLock: bool) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        verifier: rsp1.LeaseVerifier,
        groups: std.ArrayList(Group),
        metrics: BackpressureMetrics,

        // Optional cluster replication hook (Raft-lite prototype)
        replicator: ?cluster.Replicator = null,

        // Namespace quotas: maximum entries allowed per group
        max_entries_per_group: usize = 1024,

        // Lock choice per capsule workload
        lock_mutex: if (UseSpinLock) void else std.Thread.Mutex = if (UseSpinLock) {} else .{},
        lock_spin: if (UseSpinLock) std.Thread.SpinLock else void = if (UseSpinLock) .{} else {},

        // Background maintenance
        maint_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        maint_period_ns: i128 = 0,
        maint_thread: ?std.Thread = null,

        pub fn init(alloc: std.mem.Allocator, secret_key: [32]u8) Self {
            var metrics = BackpressureMetrics{};
            metrics.reset();
            return .{
                .alloc = alloc,
                .verifier = rsp1.LeaseVerifier.init(.{ .key = secret_key, .id = 1 }),
                .groups = std.ArrayList(Group){},
                .metrics = metrics,
                .max_entries_per_group = 1024,
            };
        }

        pub fn initWithVerifier(alloc: std.mem.Allocator, v: rsp1.LeaseVerifier) Self {
            var metrics = BackpressureMetrics{};
            metrics.reset();
            return .{
                .alloc = alloc,
                .verifier = v,
                .groups = std.ArrayList(Group){},
                .metrics = metrics,
                .max_entries_per_group = 1024,
            };
        }

        pub fn attachReplicator(self: *Self, rep: cluster.Replicator) void {
            self.replicator = rep;
        }

        /// Configure the maximum number of entries per group (namespace quota).
        /// A value of 0 disables new registrations (no entries allowed).
        pub fn setNamespaceQuota(self: *Self, max_entries: usize) void {
            self.max_entries_per_group = max_entries;
        }

        /// Get current backpressure metrics snapshot (thread-safe)
        pub fn getMetrics(self: *Self) BackpressureMetrics {
            self.lock();
            defer self.unlock();
            return self.getMetricsUnlocked();
        }

        /// Internal: compute metrics assuming lock is held
        fn getMetricsUnlocked(self: *Self) BackpressureMetrics {
            var total_entries: usize = 0;
            var total_ttl_remaining: i128 = 0;
            const now = Self.nowNs();

            for (self.groups.items) |g| {
                for (g.entries.items) |e| {
                    if (e.deadline_ns > now) {
                        total_entries += 1;
                        total_ttl_remaining += e.deadline_ns - now;
                    }
                }
            }

            var metrics = self.metrics;
            metrics.total_entries = total_entries;
            metrics.updateTtlStats(total_ttl_remaining, total_entries);
            return metrics;
        }

        /// Reset metrics counters
        pub fn resetMetrics(self: *Self, cap: WriteCapability) void {
            _ = cap;
            self.lock();
            defer self.unlock();
            self.metrics.reset();
        }

        pub fn deinit(self: *Self) void {
            self.stopMaintainer(.{}) catch {};
            self.lock();
            defer self.unlock();

            for (self.groups.items) |*g| g.deinit(self.alloc);
            self.groups.deinit(self.alloc);
        }

        inline fn lock(self: *Self) void {
            if (UseSpinLock) self.lock_spin.lock() else self.lock_mutex.lock();
        }
        inline fn unlock(self: *Self) void {
            if (UseSpinLock) self.lock_spin.unlock() else self.lock_mutex.unlock();
        }

        pub fn findGroup(self: *Self, name: []const u8) ?*Group {
            for (self.groups.items) |*g| if (std.mem.eql(u8, g.name, name)) return g;
            return null;
        }

        fn ensureGroup(self: *Self, name: []const u8) !*Group {
            if (self.findGroup(name)) |g| return g;
            const g = try Group.init(self.alloc, name);
            try self.groups.append(self.alloc, g);
            return &self.groups.items[self.groups.items.len - 1];
        }

        fn nowNs() i128 {
            return std.time.nanoTimestamp(); // monotonic
        }

        fn calcDeadline(now_ns: i128, ttl_ns: i128) i128 {
            return now_ns + ttl_ns;
        }

        /// Register with a lease (TTL). Mutation requires WriteCapability.
        /// If entry exists, we renew/replace lease and context.
        pub fn registerLease(
            self: *Self,
            group_name: []const u8,
            entry_name: []const u8,
            ctx: *const anyopaque,
            manual_fn: ManualFn,
            ttl_seconds: u64,
            cap: WriteCapability,
        ) !void {
            _ = cap;
            self.lock();
            defer self.unlock();

            var g = try self.ensureGroup(group_name);

            const ttl_ns: i128 = @as(i128, ttl_seconds) * std.time.ns_per_s;
            const now = Self.nowNs();
            const deadline = Self.calcDeadline(now, ttl_ns);

            // Create RSP-1 signature for this lease (heartbeat_count = 0)
            var signature: [32]u8 = undefined;
            self.verifier.sign(group_name, entry_name, ttl_ns, 0, &signature);

            // If exists → update in-place
            for (g.entries.items) |*e| {
                if (std.mem.eql(u8, e.name, entry_name)) {
                    // Replicate mutation after validation
                    if (self.replicator) |rep| {
                        const payload = try std.json.Stringify.valueAlloc(self.alloc, .{
                            .op = "registerLease",
                            .group = group_name,
                            .name = entry_name,
                            .ttl_seconds = ttl_seconds,
                        }, .{ .whitespace = .minified });
                        defer self.alloc.free(payload);
                        const committed = rep.call(rep.ctx, payload) catch false;
                        if (!committed) return error.ClusterQuorumFailed;
                    }
                    e.ctx = ctx;
                    e.manual_fn = manual_fn;
                    e.ttl_ns = ttl_ns;
                    e.deadline_ns = deadline;
                    e.signature = signature;
                    e.heartbeat_count = 0;
                    return;
                }
            }

            // Enforce namespace quota: attempt to purge expired entries first within group
            {
                var i: usize = 0;
                while (i < g.entries.items.len) {
                    if (g.entries.items[i].deadline_ns <= now) {
                        self.alloc.free(g.entries.items[i].name);
                        _ = g.entries.orderedRemove(i);
                        continue;
                    }
                    i += 1;
                }
            }
            if (g.entries.items.len >= self.max_entries_per_group) {
                return error.NamespaceQuotaExceeded;
            }

            // Replicate creation after validation
            if (self.replicator) |rep| {
                const payload = try std.json.Stringify.valueAlloc(self.alloc, .{
                    .op = "registerLease",
                    .group = group_name,
                    .name = entry_name,
                    .ttl_seconds = ttl_seconds,
                }, .{ .whitespace = .minified });
                defer self.alloc.free(payload);
                const committed = rep.call(rep.ctx, payload) catch false;
                if (!committed) return error.ClusterQuorumFailed;
            }

            // Else own entry_name and append
            const name_copy = try self.alloc.alloc(u8, entry_name.len);
            @memcpy(name_copy, entry_name);

            try g.entries.append(self.alloc, .{
                .name = name_copy,
                .ctx = ctx,
                .manual_fn = manual_fn,
                .ttl_ns = ttl_ns,
                .deadline_ns = deadline,
                .signature = signature,
                .heartbeat_count = 0,
            });
        }

        /// Heartbeat: extend deadline by new TTL (idempotent). Requires WriteCapability.
        /// Returns true if successful, false if signature verification fails.
        pub fn heartbeat(
            self: *Self,
            group_name: []const u8,
            entry_name: []const u8,
            new_ttl_seconds: u64,
            cap: WriteCapability,
        ) !bool {
            _ = cap;
            self.lock();
            defer self.unlock();

            if (self.findGroup(group_name)) |g| {
                for (g.entries.items) |*e| {
                    if (std.mem.eql(u8, e.name, entry_name)) {
                        // Verify current signature before allowing heartbeat
                        if (!self.verifier.verify(group_name, entry_name, e.ttl_ns, e.heartbeat_count, &e.signature)) {
                            self.metrics.recordHeartbeat(false);
                            return false; // Signature verification failed
                        }

                        // Update lease with new TTL
                        const new_ttl_ns: i128 = @as(i128, new_ttl_seconds) * std.time.ns_per_s;
                        const now = Self.nowNs();
                        const new_deadline = Self.calcDeadline(now, new_ttl_ns);

                        // Replicate heartbeat after validation
                        if (self.replicator) |rep| {
                            const payload = try std.json.Stringify.valueAlloc(self.alloc, .{
                                .op = "heartbeat",
                                .group = group_name,
                                .name = entry_name,
                                .ttl_seconds = new_ttl_seconds,
                            }, .{ .whitespace = .minified });
                            defer self.alloc.free(payload);
                            const committed = rep.call(rep.ctx, payload) catch false;
                            if (!committed) return false;
                        }

                        // Increment heartbeat and sign new state
                        e.heartbeat_count += 1;
                        self.verifier.sign(group_name, entry_name, new_ttl_ns, e.heartbeat_count, &e.signature);

                        e.ttl_ns = new_ttl_ns;
                        e.deadline_ns = new_deadline;

                        self.metrics.recordHeartbeat(true);
                        return true;
                    }
                }
            }
            self.metrics.recordHeartbeat(false);
            return false;
        }

        /// Renew: change TTL and push deadline. Requires WriteCapability.
        pub fn renewLease(
            self: *Self,
            group_name: []const u8,
            entry_name: []const u8,
            ttl_ns: i128,
            cap: WriteCapability,
        ) bool {
            _ = cap;
            self.lock();
            defer self.unlock();

            if (self.findGroup(group_name)) |g| {
                for (g.entries.items) |*e| {
                    if (std.mem.eql(u8, e.name, entry_name)) {
                        e.ttl_ns = ttl_ns;
                        e.deadline_ns = Self.calcDeadline(Self.nowNs(), ttl_ns);
                        return true;
                    }
                }
            }
            return false;
        }

        /// Remove a single entry immediately. Requires WriteCapability.
        pub fn unregisterIn(self: *Self, group_name: []const u8, entry_name: []const u8, cap: WriteCapability) bool {
            _ = cap;
            self.lock();
            defer self.unlock();

            if (self.findGroup(group_name)) |g| {
                var i: usize = 0;
                while (i < g.entries.items.len) : (i += 1) {
                    if (std.mem.eql(u8, g.entries.items[i].name, entry_name)) {
                        self.alloc.free(g.entries.items[i].name);
                        _ = g.entries.orderedRemove(i);
                        return true;
                    }
                }
            }
            return false;
        }

        /// Remove a whole group. Requires WriteCapability.
        pub fn unregisterGroup(self: *Self, group_name: []const u8, cap: WriteCapability) bool {
            _ = cap;
            self.lock();
            defer self.unlock();

            var i: usize = 0;
            while (i < self.groups.items.len) : (i += 1) {
                if (std.mem.eql(u8, self.groups.items[i].name, group_name)) {
                    self.groups.items[i].deinit(self.alloc);
                    _ = self.groups.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        /// Purge all expired entries. Requires maintenance capability (or WriteCapability).
        pub fn purgeExpired(self: *Self) void {
            self.lock();
            defer self.unlock();

            const now = Self.nowNs();
            var purged_count: u64 = 0;

            var g_idx: usize = 0;
            while (g_idx < self.groups.items.len) {
                var g = &self.groups.items[g_idx];

                var i: usize = 0;
                while (i < g.entries.items.len) {
                    if (g.entries.items[i].deadline_ns <= now) {
                        self.alloc.free(g.entries.items[i].name);
                        _ = g.entries.orderedRemove(i);
                        purged_count += 1;
                        continue;
                    }
                    i += 1;
                }

                // Optionally remove empty groups:
                if (g.entries.items.len == 0) {
                    g.deinit(self.alloc);
                    _ = self.groups.orderedRemove(g_idx);
                    continue;
                }

                g_idx += 1;
            }

            // Record purged entries in metrics
            if (purged_count > 0) {
                self.metrics.recordPurged(purged_count);
            }
        }

        /// Build namespaced UTCP document; purges stale entries on the way.
        pub fn buildManual(self: *Self, alloc: std.mem.Allocator) ![]u8 {
            // Opportunistic purge before read
            self.purgeExpired();

            self.lock();
            defer self.unlock();

            var out = std.ArrayList(u8){};
            errdefer out.deinit(alloc);
            const w = out.writer(alloc);

            const now = Self.nowNs();
            const metrics = self.getMetricsUnlocked();

            try w.writeAll("{\"utcp_version\":\"1.0.0\",\"registry_time_ns\":");
            try std.fmt.format(w, "{}", .{now});
            try w.writeAll(",\"backpressure_metrics\":{");

            // Add metrics to output
            try w.writeAll("\"total_entries\":");
            try std.fmt.format(w, "{}", .{metrics.total_entries});
            try w.writeAll(",\"purged_since_reset\":");
            try std.fmt.format(w, "{}", .{metrics.purged_since_reset});
            try w.writeAll(",\"total_heartbeats\":");
            try std.fmt.format(w, "{}", .{metrics.total_heartbeats});
            try w.writeAll(",\"failed_heartbeats\":");
            try std.fmt.format(w, "{}", .{metrics.failed_heartbeats});
            try w.writeAll(",\"avg_ttl_remaining_ns\":");
            try std.fmt.format(w, "{}", .{metrics.avg_ttl_remaining_ns});
            try w.writeAll(",\"max_ttl_remaining_ns\":");
            try std.fmt.format(w, "{}", .{metrics.max_ttl_remaining_ns});
            try w.writeAll(",\"min_ttl_remaining_ns\":");
            try std.fmt.format(w, "{}", .{metrics.min_ttl_remaining_ns});
            try w.writeAll(",\"metrics_reset_time_ns\":");
            try std.fmt.format(w, "{}", .{metrics.metrics_reset_time_ns});
            try w.writeAll("},\"groups\":{");

            var first_group = true;
            for (self.groups.items) |g| {
                if (!first_group) try w.writeByte(',');
                first_group = false;

                try w.writeByte('"');
                try w.writeAll(g.name);
                try w.writeAll("\":[");

                var first_entry = true;
                for (g.entries.items) |e| {
                    // If a lease will expire in the past by the time we serialize, skip
                    if (e.deadline_ns <= now) continue;

                    const manual = try e.manual_fn(e.ctx, alloc);
                    defer alloc.free(manual);

                    if (!first_entry) try w.writeByte(',');
                    first_entry = false;

                    // Start with the container's manual
                    try w.writeAll(manual);

                    // Remove the closing } and add lease metadata
                    if (manual.len > 0 and manual[manual.len - 1] == '}') {
                        // Remove the closing brace temporarily
                        try w.writeByte(',');
                        try w.writeAll("\"lease_deadline\":");
                        try std.fmt.format(w, "{}", .{e.deadline_ns});
                        try w.writeAll(",\"heartbeat_count\":");
                        try std.fmt.format(w, "{}", .{e.heartbeat_count});
                        try w.writeAll(",\"signature\":\"");
                        for (e.signature) |b| {
                            try std.fmt.format(w, "{x:0>2}", .{b});
                        }
                        try w.writeAll("\"}");
                    }
                }

                try w.writeAll("]");
            }

            try w.writeAll("}}");
            return try out.toOwnedSlice(self.alloc);
        }

        /// Background purger thread: wake every period and purge.
        pub fn startMaintainer(self: *Self, period_ns: i128, cap: MaintenanceCapability) !void {
            _ = cap;
            if (self.maint_running.swap(true, .seq_cst)) return; // already running
            self.maint_period_ns = period_ns;
            self.maint_thread = try std.Thread.spawn(.{}, maintLoop, .{self});
        }

        pub fn stopMaintainer(self: *Self, cap: MaintenanceCapability) !void {
            _ = cap;
            if (!self.maint_running.swap(false, .seq_cst)) return; // not running
            if (self.maint_thread) |t| {
                t.join();
                self.maint_thread = null;
            }
        }

        fn maintLoop(self: *Self) !void {
            while (self.maint_running.load(.seq_cst)) {
                self.purgeExpired();
                // sleep for period
                if (self.maint_period_ns > 0) {
                    std.time.sleep(@intCast(self.maint_period_ns));
                } else {
                    // default 1s
                    std.time.sleep(1_000_000_000);
                }
            }
        }

        /// RSP-1: rotate epoch key (accept active + previous during grace window)
        pub fn rotateKey(self: *Self, new_key: rsp1.EpochKey) void {
            self.verifier.rotate(new_key);
        }
    };
}

/// Generic manual adapter (unchanged, single helper for all concrete types)
pub fn makeManualAdapter(comptime T: type) ManualFn {
    return struct {
        fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
            const p = @as(*const T, @ptrCast(@alignCast(ctx)));
            return p.utcpManual(alloc);
        }
    }.call;
}

// Export the registry as the standard UTCP registry with Mutex (default)
pub const Registry = UtcpRegistryNsSyncLease(false);

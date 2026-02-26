// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! L2 Session Manager - Sovereign Agent Coordination
//! 
//! Implements session state machine with heartbeat timeout logic
//! for the Libertaria Protocol's L2 layer.

const std = @import("std");
const time = std.time;

/// Session states following the Libertaria State Machine
pub const SessionState = enum {
    /// Initial handshake in progress
    handshake,
    /// Active session with healthy heartbeats
    active,
    /// Missed heartbeat, in grace period
    degraded,
    /// Session terminated
    closed,
};

/// Heartbeat configuration parameters
pub const HeartbeatConfig = struct {
    /// Expected interval between heartbeats (ms)
    interval_ms: i64 = 30000, // 30 seconds default
    /// Grace period after missed heartbeat (ms)
    grace_period_ms: i64 = 10000, // 10 seconds default
    /// Number of consecutive missed heartbeats before degradation
    max_missed: u32 = 3,
};

/// Session metadata and state tracking
pub const Session = struct {
    /// Unique session identifier
    id: [32]u8,
    /// Current session state
    state: SessionState,
    /// Creation timestamp (ms since epoch)
    created_at: i64,
    /// Last received heartbeat timestamp
    last_heartbeat: i64,
    /// Consecutive missed heartbeats
    missed_count: u32,
    /// Heartbeat configuration
    config: HeartbeatConfig,
    /// Allocator for dynamic resources
    allocator: std.mem.Allocator,

    /// Initialize a new session
    pub fn init(allocator: std.mem.Allocator, id: [32]u8, config: HeartbeatConfig) !Session {
        const now = time.milliTimestamp();
        return Session{
            .id = id,
            .state = .handshake,
            .created_at = now,
            .last_heartbeat = now,
            .missed_count = 0,
            .config = config,
            .allocator = allocator,
        };
    }

    /// Record a received heartbeat
    pub fn recordHeartbeat(self: *Session) void {
        const now = time.milliTimestamp();
        self.last_heartbeat = now;
        self.missed_count = 0;
        
        // Transition from degraded back to active
        if (self.state == .degraded) {
            self.state = .active;
        }
    }

    /// Check if heartbeat is overdue
    pub fn isHeartbeatOverdue(self: *Session) bool {
        const now = time.milliTimestamp();
        const elapsed = now - self.last_heartbeat;
        return elapsed > self.config.interval_ms;
    }

    /// Check if grace period has expired
    pub fn isGracePeriodExpired(self: *Session) bool {
        const now = time.milliTimestamp();
        const elapsed = now - self.last_heartbeat;
        const grace_threshold = self.config.interval_ms + self.config.grace_period_ms;
        return elapsed > grace_threshold;
    }

    /// Process heartbeat timeout logic
    /// Returns true if state transitioned
    pub fn processTimeout(self: *Session) bool {
        const old_state = self.state;
        
        switch (self.state) {
            .active => {
                if (self.isHeartbeatOverdue()) {
                    self.missed_count += 1;
                    if (self.missed_count >= self.config.max_missed) {
                        self.state = .degraded;
                    }
                }
            },
            .degraded => {
                if (self.isGracePeriodExpired()) {
                    self.state = .closed;
                }
            },
            .handshake, .closed => {
                // No timeout processing in terminal states
            },
        }
        
        return self.state != old_state;
    }

    /// Close the session gracefully
    pub fn close(self: *Session) void {
        self.state = .closed;
    }

    /// Get time until next expected heartbeat (ms)
    pub fn timeUntilNextHeartbeat(self: *Session) i64 {
        const now = time.milliTimestamp();
        const next_expected = self.last_heartbeat + self.config.interval_ms;
        return next_expected - now;
    }

    /// Get session age (ms)
    pub fn getAge(self: *Session) i64 {
        const now = time.milliTimestamp();
        return now - self.created_at;
    }
};

/// Session manager for handling multiple concurrent sessions
pub const SessionManager = struct {
    /// Active sessions keyed by session ID
    sessions: std.AutoHashMap([32]u8, Session),
    /// Default heartbeat configuration
    default_config: HeartbeatConfig,
    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: HeartbeatConfig) SessionManager {
        return SessionManager{
            .sessions = std.AutoHashMap([32]u8, Session).init(allocator),
            .default_config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SessionManager) void {
        self.sessions.deinit();
    }

    /// Create a new session
    pub fn createSession(self: *SessionManager, id: [32]u8) !void {
        const session = try Session.init(self.allocator, id, self.default_config);
        try self.sessions.put(id, session);
    }

    /// Get session by ID
    pub fn getSession(self: *SessionManager, id: [32]u8) ?*Session {
        return self.sessions.getPtr(id);
    }

    /// Remove a session
    pub fn removeSession(self: *SessionManager, id: [32]u8) void {
        _ = self.sessions.remove(id);
    }

    /// Process timeouts for all active sessions
    /// Returns count of state transitions
    pub fn processAllTimeouts(self: *SessionManager) usize {
        var transition_count: usize = 0;
        var iter = self.sessions.valueIterator();
        
        while (iter.next()) |session| {
            if (session.processTimeout()) {
                transition_count += 1;
            }
        }
        
        return transition_count;
    }

    /// Clean up closed sessions
    pub fn cleanupClosedSessions(self: *SessionManager) void {
        var to_remove: std.ArrayList([32]u8) = .empty;
        defer to_remove.deinit();
        
        var iter = self.sessions.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.state == .closed) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }
        
        for (to_remove.items) |id| {
            _ = self.sessions.remove(id);
        }
    }

    /// Get count of sessions in each state
    pub fn getStateCounts(self: *SessionManager) StateCounts {
        var counts = StateCounts{};
        var iter = self.sessions.valueIterator();
        
        while (iter.next()) |session| {
            switch (session.state) {
                .handshake => counts.handshake += 1,
                .active => counts.active += 1,
                .degraded => counts.degraded += 1,
                .closed => counts.closed += 1,
            }
        }
        
        return counts;
    }
};

/// Session state counts for monitoring
pub const StateCounts = struct {
    handshake: usize = 0,
    active: usize = 0,
    degraded: usize = 0,
    closed: usize = 0,
};

// Scenario-003.1: Session timeout handling
test "Session transitions to degraded after max missed heartbeats" {
    const allocator = std.testing.allocator;
    var id: [32]u8 = undefined;
    @memcpy(&id, "test-session-id-001---------------");
    
    var config = HeartbeatConfig{
        .interval_ms = 100, // 100ms for testing
        .grace_period_ms = 50,
        .max_missed = 2,
    };
    
    var session = try Session.init(allocator, id, config);
    session.state = .active;
    
    // Simulate time passing without heartbeats
    std.time.sleep(150 * time.ns_per_ms); // 150ms > interval
    
    _ = session.processTimeout();
    try std.testing.expect(session.missed_count == 1);
    try std.testing.expect(session.state == .active);
    
    std.time.sleep(150 * time.ns_per_ms); // Another 150ms
    
    _ = session.processTimeout();
    try std.testing.expect(session.missed_count == 2);
    try std.testing.expect(session.state == .degraded);
}

// Scenario-003.2: Recovery from degraded state
test "Session recovers from degraded on heartbeat" {
    const allocator = std.testing.allocator;
    var id: [32]u8 = undefined;
    @memcpy(&id, "test-session-id-002---------------");
    
    var config = HeartbeatConfig{
        .interval_ms = 100,
        .grace_period_ms = 50,
        .max_missed = 1,
    };
    
    var session = try Session.init(allocator, id, config);
    session.state = .degraded;
    
    // Record heartbeat should restore to active
    session.recordHeartbeat();
    try std.testing.expect(session.state == .active);
    try std.testing.expect(session.missed_count == 0);
}

// Scenario-003.3: Grace period expiration
test "Session closes after grace period expires" {
    const allocator = std.testing.allocator;
    var id: [32]u8 = undefined;
    @memcpy(&id, "test-session-id-003---------------");
    
    var config = HeartbeatConfig{
        .interval_ms = 50,
        .grace_period_ms = 100, // 100ms grace
        .max_missed = 1,
    };
    
    var session = try Session.init(allocator, id, config);
    session.state = .degraded;
    session.last_heartbeat = time.milliTimestamp() - 200; // 200ms ago
    
    _ = session.processTimeout();
    try std.testing.expect(session.state == .closed);
}

// Scenario-003.4: Session manager timeout processing
test "SessionManager processes timeouts for all sessions" {
    const allocator = std.testing.allocator;
    var manager = SessionManager.init(allocator, HeartbeatConfig{
        .interval_ms = 50,
        .grace_period_ms = 25,
        .max_missed = 1,
    });
    defer manager.deinit();
    
    // Create two sessions
    var id1: [32]u8 = undefined;
    var id2: [32]u8 = undefined;
    @memcpy(&id1, "test-session-001------------------");
    @memcpy(&id2, "test-session-002------------------");
    
    try manager.createSession(id1);
    try manager.createSession(id2);
    
    // Set both to active
    if (manager.getSession(id1)) |s| s.state = .active;
    if (manager.getSession(id2)) |s| s.state = .active;
    
    // Wait for timeout
    std.time.sleep(100 * time.ns_per_ms);
    
    const transitions = manager.processAllTimeouts();
    try std.testing.expect(transitions >= 2);
    
    const counts = manager.getStateCounts();
    try std.testing.expect(counts.degraded >= 2);
}

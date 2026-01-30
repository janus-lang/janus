// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Budget types for CBC-MN scheduler
//!
//! Budgets are abstract resource units that gate task execution.
//! A task yields when any budget component reaches zero.
//!
//! See: SPEC-021 Section 3 (Budget Model)

const std = @import("std");

/// Budget represents resource allocation for a task.
/// All components are non-negative; zero means exhausted.
pub const Budget = struct {
    /// Operation count (abstract instruction units)
    ops: u32 = 10_000,

    /// Memory allocation budget (bytes)
    memory: usize = 1024 * 1024, // 1MB default

    /// Child task spawn limit
    spawn_count: u16 = 0, // Children can't spawn by default

    /// Channel send/recv operations
    channel_ops: u16 = 100,

    /// System call budget (I/O operations)
    syscalls: u16 = 10,

    /// Check if any budget component is exhausted
    pub fn isExhausted(self: Budget) bool {
        return self.ops == 0 or self.memory == 0;
    }

    /// Check if spawn budget is exhausted
    pub fn canSpawn(self: Budget) bool {
        return self.spawn_count > 0;
    }

    /// Decrement budget by cost, returns true if successful
    pub fn decrement(self: *Budget, cost: BudgetCost) bool {
        if (self.ops < cost.ops) return false;
        if (self.memory < cost.memory) return false;
        if (self.spawn_count < cost.spawn_count) return false;
        if (self.channel_ops < cost.channel_ops) return false;
        if (self.syscalls < cost.syscalls) return false;

        self.ops -= cost.ops;
        self.memory -= cost.memory;
        self.spawn_count -= cost.spawn_count;
        self.channel_ops -= cost.channel_ops;
        self.syscalls -= cost.syscalls;
        return true;
    }

    /// Add budget (for recharge)
    pub fn add(self: *Budget, amount: Budget) void {
        self.ops +|= amount.ops;
        self.memory +|= amount.memory;
        self.spawn_count +|= amount.spawn_count;
        self.channel_ops +|= amount.channel_ops;
        self.syscalls +|= amount.syscalls;
    }

    /// Clamp budget to maximum limits
    pub fn clamp(self: *Budget, max: Budget) void {
        self.ops = @min(self.ops, max.ops);
        self.memory = @min(self.memory, max.memory);
        self.spawn_count = @min(self.spawn_count, max.spawn_count);
        self.channel_ops = @min(self.channel_ops, max.channel_ops);
        self.syscalls = @min(self.syscalls, max.syscalls);
    }

    /// Default budget for :service profile
    pub fn serviceDefault() Budget {
        return .{
            .ops = 100_000,
            .memory = 10 * 1024 * 1024, // 10MB
            .spawn_count = 100,
            .channel_ops = 1000,
            .syscalls = 100,
        };
    }

    /// Default budget for :cluster profile (actors)
    pub fn clusterDefault() Budget {
        return .{
            .ops = 1_000_000,
            .memory = 100 * 1024 * 1024, // 100MB
            .spawn_count = 1000,
            .channel_ops = 10_000,
            .syscalls = 1000,
        };
    }

    /// Minimal budget for child tasks
    pub fn childDefault() Budget {
        return .{
            .ops = 10_000,
            .memory = 1024 * 1024, // 1MB
            .spawn_count = 0, // Children can't spawn
            .channel_ops = 100,
            .syscalls = 10,
        };
    }

    /// Zero budget (exhausted)
    pub fn zero() Budget {
        return .{
            .ops = 0,
            .memory = 0,
            .spawn_count = 0,
            .channel_ops = 0,
            .syscalls = 0,
        };
    }
};

/// Cost of operations that consume budget
pub const BudgetCost = struct {
    ops: u32 = 1,
    memory: usize = 0,
    spawn_count: u16 = 0,
    channel_ops: u16 = 0,
    syscalls: u16 = 0,

    /// Single operation (loop iteration, function call)
    pub const OP: BudgetCost = .{ .ops = 1 };

    /// Spawn a child task
    pub const SPAWN: BudgetCost = .{ .ops = 1, .spawn_count = 1 };

    /// Channel send or receive
    pub const CHANNEL_OP: BudgetCost = .{ .ops = 1, .channel_ops = 1 };

    /// System call (file/network I/O)
    pub const SYSCALL: BudgetCost = .{ .ops = 1, .syscalls = 1 };

    /// Memory allocation
    pub fn allocation(size: usize) BudgetCost {
        return .{ .ops = 1, .memory = size };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Budget: decrement succeeds with sufficient budget" {
    var budget = Budget.serviceDefault();
    const initial_ops = budget.ops;

    const success = budget.decrement(BudgetCost.OP);

    try std.testing.expect(success);
    try std.testing.expectEqual(initial_ops - 1, budget.ops);
}

test "Budget: decrement fails when exhausted" {
    var budget = Budget.zero();

    const success = budget.decrement(BudgetCost.OP);

    try std.testing.expect(!success);
}

test "Budget: isExhausted detects zero ops" {
    var budget = Budget.serviceDefault();
    budget.ops = 0;

    try std.testing.expect(budget.isExhausted());
}

test "Budget: canSpawn checks spawn_count" {
    var budget = Budget.childDefault();
    try std.testing.expect(!budget.canSpawn()); // Children can't spawn

    budget.spawn_count = 1;
    try std.testing.expect(budget.canSpawn());
}

test "Budget: add saturates on overflow" {
    var budget = Budget{
        .ops = std.math.maxInt(u32) - 10,
        .memory = 0,
        .spawn_count = 0,
        .channel_ops = 0,
        .syscalls = 0,
    };

    budget.add(.{ .ops = 100 });

    // Should saturate, not overflow
    try std.testing.expectEqual(std.math.maxInt(u32), budget.ops);
}

test "Budget: clamp limits to maximum" {
    var budget = Budget.clusterDefault();
    const max = Budget.childDefault();

    budget.clamp(max);

    try std.testing.expectEqual(max.ops, budget.ops);
    try std.testing.expectEqual(max.memory, budget.memory);
}

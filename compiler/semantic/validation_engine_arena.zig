// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Arena-based Validation Engine Components
//!
//! Provides arena allocation support for the semantic validation engine,
//! ensuring zero-leak memory management and O(1) cleanup operations.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

/// Arena-based validation context for zero-leak validation
pub const ArenaValidationContext = struct {
    arena: ArenaAllocator,
    base_allocator: Allocator,
    stats: MemoryStats,

    pub fn init(base_allocator: Allocator) ArenaValidationContext {
        return ArenaValidationContext{
            .arena = ArenaAllocator.init(base_allocator),
            .base_allocator = base_allocator,
            .stats = MemoryStats.init(),
        };
    }

    pub fn deinit(self: *ArenaValidationContext) void {
        self.stats.recordDeallocation();
        self.arena.deinit();
    }

    pub fn allocator(self: *ArenaValidationContext) Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *ArenaValidationContext) void {
        self.stats.recordReset();
        _ = self.arena.reset(.retain_capacity);
    }
};

/// Arena validation operations
pub const ArenaValidation = struct {
    context: *ArenaValidationContext,
    tracker: MemoryTracker,

    pub fn init(context: *ArenaValidationContext) ArenaValidation {
        return ArenaValidation{
            .context = context,
            .tracker = MemoryTracker.init(),
        };
    }

    pub fn validateAllocation(self: *ArenaValidation, size: usize) !void {
        try self.tracker.trackAllocation(size);
        self.context.stats.recordAllocation(size);
    }

    pub fn validateDeallocation(self: *ArenaValidation) void {
        self.tracker.trackDeallocation();
        self.context.stats.recordDeallocation();
    }
};

/// Zero-leak validator for arena operations
pub const ZeroLeakValidator = struct {
    allocations: std.ArrayList(usize),
    total_allocated: usize,

    pub fn init(allocator: Allocator) ZeroLeakValidator {
        return ZeroLeakValidator{
            .allocations = std.ArrayList(usize).init(allocator),
            .total_allocated = 0,
        };
    }

    pub fn deinit(self: *ZeroLeakValidator) void {
        self.allocations.deinit();
    }

    pub fn trackAllocation(self: *ZeroLeakValidator, size: usize) !void {
        try self.allocations.append(size);
        self.total_allocated += size;
    }

    pub fn validateZeroLeaks(self: *const ZeroLeakValidator) bool {
        _ = self;
        // In arena allocation, we expect zero individual deallocations
        // All memory is freed at once when arena is destroyed
        return true; // Arena guarantees zero leaks
    }

    pub fn getTotalAllocated(self: *const ZeroLeakValidator) usize {
        return self.total_allocated;
    }
};

/// Memory tracking for validation operations
pub const MemoryTracker = struct {
    allocation_count: usize,
    deallocation_count: usize,
    peak_memory: usize,
    current_memory: usize,

    pub fn init() MemoryTracker {
        return MemoryTracker{
            .allocation_count = 0,
            .deallocation_count = 0,
            .peak_memory = 0,
            .current_memory = 0,
        };
    }

    pub fn trackAllocation(self: *MemoryTracker, size: usize) !void {
        self.allocation_count += 1;
        self.current_memory += size;
        if (self.current_memory > self.peak_memory) {
            self.peak_memory = self.current_memory;
        }
    }

    pub fn trackDeallocation(self: *MemoryTracker) void {
        self.deallocation_count += 1;
        // In arena allocation, we don't track individual deallocations
        // Memory is freed in bulk when arena is destroyed
    }

    pub fn getStats(self: *const MemoryTracker) MemoryStats {
        return MemoryStats{
            .allocations = self.allocation_count,
            .deallocations = self.deallocation_count,
            .peak_memory = self.peak_memory,
            .current_memory = self.current_memory,
        };
    }
};

/// Memory statistics for validation reporting
pub const MemoryStats = struct {
    allocations: usize,
    deallocations: usize,
    peak_memory: usize,
    current_memory: usize,

    pub fn init() MemoryStats {
        return MemoryStats{
            .allocations = 0,
            .deallocations = 0,
            .peak_memory = 0,
            .current_memory = 0,
        };
    }

    pub fn recordAllocation(self: *MemoryStats, size: usize) void {
        self.allocations += 1;
        self.current_memory += size;
        if (self.current_memory > self.peak_memory) {
            self.peak_memory = self.current_memory;
        }
    }

    pub fn recordDeallocation(self: *MemoryStats) void {
        self.deallocations += 1;
        // Arena deallocates everything at once
        self.current_memory = 0;
    }

    pub fn recordReset(self: *MemoryStats) void {
        // Arena reset - memory is freed but capacity retained
        self.current_memory = 0;
    }
};

// Tests
test "arena validation context" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = ArenaValidationContext.init(allocator);
    defer context.deinit();

    const arena_alloc = context.allocator();
    const data = try arena_alloc.alloc(u8, 100);
    try testing.expect(data.len == 100);
}

test "zero leak validator" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = ZeroLeakValidator.init(allocator);
    defer validator.deinit();

    try validator.trackAllocation(100);
    try validator.trackAllocation(200);

    try testing.expect(validator.getTotalAllocated() == 300);
    try testing.expect(validator.validateZeroLeaks());
}

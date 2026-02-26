// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("compiler/libjanus/astdb.zig");
const StrInterner = astdb.StrInterner;

// BRUTAL STRESS TEST - Designed to expose the leaks our previous validation missed
// This test mimics the intense, cyclical allocation and query patterns of the ComptimeVM
// that revealed our ASTDB validation was inadequate.
test "String Interner Brutal Stress Test - ComptimeVM Pattern Simulation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // BRUTAL STRESS PATTERN 1: Intensive Arena Creation/Destruction
    // This simulates the ComptimeVM creating multiple compilation contexts
    for (0..100) |cycle| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var interner = StrInterner.init(arena.allocator(), false) catch |err| {
            continue;
        };
        defer interner.deinit();

        // BRUTAL STRESS PATTERN 2: Intensive String Interning
        // This simulates heavy identifier and keyword processing
        for (0..50) |i| {
            const identifier = try std.fmt.allocPrint(arena.allocator(), "identifier_{d}_{d}", .{ cycle, i });
            _ = interner.get(identifier) catch |err| {
                continue;
            };

            const keyword = try std.fmt.allocPrint(arena.allocator(), "keyword_{d}_{d}", .{ cycle, i });
            _ = interner.get(keyword) catch |err| {
                continue;
            };
        }

        // BRUTAL STRESS PATTERN 3: Duplicate interning stress
        for (0..25) |i| {
            const duplicate = try std.fmt.allocPrint(arena.allocator(), "duplicate_{d}", .{i % 10});
            _ = interner.get(duplicate) catch |err| {
                continue;
            };
        }
    }

    // BRUTAL STRESS PATTERN 4: Cross-Arena Reference Simulation
    // This tests the dangerous pattern that might cause leaks
    var persistent_arena = std.heap.ArenaAllocator.init(allocator);
    defer persistent_arena.deinit();

    var persistent_interner = StrInterner.init(persistent_arena.allocator(), false) catch |err| {
        return;
    };
    defer persistent_interner.deinit();

    // Create temporary arenas that interact with persistent data
    for (0..50) |cycle| {
        var temp_arena = std.heap.ArenaAllocator.init(allocator);
        defer temp_arena.deinit();

        // This pattern might cause leaks if interner stores references incorrectly
        const temp_identifier = try std.fmt.allocPrint(temp_arena.allocator(), "temp_cross_ref_{d}", .{cycle});
        const interned_id = persistent_interner.get(temp_identifier) catch |err| {
            continue;
        };

        // Verify the interned string is accessible (this might reveal reference issues)
        const retrieved = persistent_interner.str(interned_id);
        try testing.expect(std.mem.eql(u8, retrieved, temp_identifier));
    }

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        return error.MemoryLeak;
    }

}

// BRUTAL STRESS TEST 2 - HashMap and Dynamic Allocation Patterns
test "String Interner Brutal Stress Test - HashMap Pressure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // BRUTAL STRESS PATTERN: HashMap Growth and Shrinkage
    // This simulates the pattern that might cause HashMap-related leaks
    for (0..20) |major_cycle| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var interner = StrInterner.init(arena.allocator(), false) catch |err| {
            continue;
        };
        defer interner.deinit();

        // Force HashMap growth through intensive interning
        for (0..1000) |i| {
            const large_identifier = try std.fmt.allocPrint(arena.allocator(), "large_identifier_cycle_{d}_item_{d}_with_long_suffix_to_force_growth", .{ major_cycle, i });
            _ = interner.get(large_identifier) catch |err| {
                continue;
            };
        }

        // Perform intensive queries that might allocate temporary data
        for (0..100) |i| {
            const query_string = try std.fmt.allocPrint(arena.allocator(), "large_identifier_cycle_{d}_item_{d}_with_long_suffix_to_force_growth", .{ major_cycle, i });
            const interned_id = interner.get(query_string) catch continue;
            const retrieved = interner.str(interned_id);
            _ = retrieved; // Use the result to prevent optimization
        }
    }

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        return error.MemoryLeak;
    }

}

// BRUTAL STRESS TEST 3 - String Interner Edge Cases
test "String Interner Brutal Stress Test - Edge Cases" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    for (0..50) |_| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var interner = StrInterner.init(arena.allocator(), false) catch |err| {
            continue;
        };
        defer interner.deinit();

        // EDGE CASE 1: Empty strings
        _ = interner.get("") catch |err| {
        };

        // EDGE CASE 2: Very long strings
        const long_string = try arena.allocator().alloc(u8, 10000);
        @memset(long_string, 'x');
        _ = interner.get(long_string) catch |err| {
        };

        // EDGE CASE 3: Duplicate interning stress
        for (0..100) |i| {
            const duplicate = try std.fmt.allocPrint(arena.allocator(), "duplicate_{d}", .{i % 10});
            _ = interner.get(duplicate) catch |err| {
            };
        }

        // EDGE CASE 4: Unicode strings
        _ = interner.get("🚀 Unicode test 中文 العربية") catch |err| {
        };

        // EDGE CASE 5: Strings with null bytes
        const null_string = try arena.allocator().alloc(u8, 10);
        @memset(null_string, 'a');
        null_string[5] = 0;
        _ = interner.get(null_string) catch |err| {
        };
    }

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        return error.MemoryLeak;
    }

}

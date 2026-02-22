// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("janus_lib");
const tokenizer = janus.tokenizer;

// Use Init for Zig 0.16 compatibility (provides arena)
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    
    // Use the args from Init
    var iter = std.process.Args.iterate(init.minimal.args);
    
    _ = iter.next(); // skip argv[0]
    
    const iter_count = if (iter.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1000;

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch seed = 12345;
        break :blk seed;
    });
    const rand = prng.random();

    var timer = try std.time.Timer.start();
    var success_count: usize = 0;
    var failure_count: usize = 0;

    std.debug.print("Running {d} fuzz iterations...\n", .{iter_count});

    for (0..iter_count) |i| {
        // Generate random input: 0-256 bytes of printable ASCII + random bytes
        const input_len = rand.uintAtMost(usize, 256);
        const input = try allocator.alloc(u8, input_len);
        defer allocator.free(input);

        for (input) |*byte| {
            if (rand.boolean()) {
                // Printable ASCII
                byte.* = 32 + rand.uintAtMost(u8, 94); // 32-126
            } else {
                // Random byte
                byte.* = rand.uintAtMost(u8, 255);
            }
        }

        // Feed to tokenizer
        var tok = tokenizer.Tokenizer.init(allocator, input);
        defer tok.deinit();

        const result = tok.tokenize() catch |err| {
            if (err != error.UnexpectedToken) {
                // Non-parser errors are interesting
                std.debug.print("Iteration {d}: Unexpected tokenizer error: {}\n", .{ i, err });
                failure_count += 1;
                continue;
            }
            // Parser errors are expected for random input
            success_count += 1;
            continue;
        };

        // Check that we can iterate over tokens without crash
        for (result) |token| {
            _ = token; // Touch to ensure no use-after-free
        }

        success_count += 1;
    }

    const elapsed = timer.read();
    const ms = @as(f64, @floatFromInt(elapsed)) / 1_000_000.0;
    std.debug.print("Fuzz complete: {d} iterations in {d:.2}ms ({d:.0} iter/sec)\n" ++
        "Success: {d}, Failures: {d} (non-parser errors)\n", .{ iter_count, ms, @as(f64, @floatFromInt(iter_count)) / ms, success_count, failure_count });
}

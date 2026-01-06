// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const pipeline = @import("pipeline");
const fs = std.fs;

test "Forge Cycle: Compile and Run Hello World (Real Example)" {
    const allocator = std.testing.allocator;

    // 1. Locate source file
    // We assume CWD is project root (set in build.zig)
    const source_rel_path = "examples/hello.jan";
    const source_path = try fs.cwd().realpathAlloc(allocator, source_rel_path);
    defer allocator.free(source_path);

    // 2. Prepare output path
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_path = try fs.path.join(allocator, &[_][]const u8{ tmp_path, "hello" });
    defer allocator.free(output_path);

    std.debug.print("\nCompiling: {s}\nOutput: {s}\n", .{ source_path, output_path });

    // 3. Initialize pipeline
    var pipe = pipeline.Pipeline.init(allocator, .{
        .source_path = source_path,
        .output_path = output_path,
        .emit_llvm_ir = true,
        .verbose = true,
    });

    // 4. Compile
    var result = try pipe.compile();
    defer result.deinit(allocator);

    // 5. Verify and Run
    const run_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{result.executable_path},
    });
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);

    // Check exit code
    switch (run_result.term) {
        .Exited => |code| try std.testing.expectEqual(code, 0),
        else => {
            std.debug.print("Process terminated unexpectedly: {any}\n", .{run_result.term});
            return error.ProcessFailed;
        },
    }

    // "Hello, Janus!" is in examples/hello.jan (verified via failure)
    const expected_output = "Hello, Janus!\n";

    // Trim potential carriage returns
    const trimmed_output = std.mem.trimRight(u8, run_result.stdout, "\r\n");
    const trimmed_expected = std.mem.trimRight(u8, expected_output, "\r\n");

    try std.testing.expectEqualStrings(trimmed_expected, trimmed_output);
}

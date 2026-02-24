// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const pipeline = @import("pipeline");
const compat_fs = @import("compat_fs");

test "Forge Cycle: Compile and Run Hello World (Real Example)" {
    const allocator = testing.allocator;
    const io = testing.io;

    // 1. Locate source file (CWD is project root set in build.zig)
    const source_path = try compat_fs.realpathAlloc(allocator, "examples/hello.jan");
    defer allocator.free(source_path);

    // 2. Prepare output path
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(tmp_path);

    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "hello" });
    defer allocator.free(output_path);

    // 3. Locate runtime directory (for scheduler support)
    const runtime_dir = try compat_fs.realpathAlloc(allocator, "runtime");
    defer allocator.free(runtime_dir);

    // 4. Initialize pipeline (pass testing.io for subprocess spawning)
    var pipe = pipeline.Pipeline.init(allocator, .{
        .source_path = source_path,
        .output_path = output_path,
        .emit_llvm_ir = true,
        .verbose = true,
        .runtime_dir = runtime_dir,
        .io = io,
    });

    // 5. Compile
    var result = try pipe.compile();
    defer result.deinit(allocator);

    // 6. Verify and Run
    const run_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{result.executable_path},
    });
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);

    // Check exit code
    switch (run_result.term) {
        .exited => |code| try testing.expectEqual(code, 0),
        else => {
            return error.ProcessFailed;
        },
    }

    // "Hello, Janus!" is in examples/hello.jan
    const expected_output = "Hello, Janus!\n";

    // Trim potential carriage returns
    const trimmed_output = std.mem.trim(u8, run_result.stdout, "\r\n");
    const trimmed_expected = std.mem.trim(u8, expected_output, "\r\n");

    try testing.expectEqualStrings(trimmed_expected, trimmed_output);
}

// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

const proto = @import("graft_proto");
const caps = @import("std_caps");

test "graft proto print_line succeeds with capability" {
    var cap = caps.Capability.init("stderr", testing.allocator);
    defer cap.deinit();
    try proto.print_line(&cap, testing.allocator, "Hello from graft");
}

// No explicit negative test for typed capability (null not allowed at type level)

test "graft proto error conversion invalid argument" {
    var cap = caps.Capability.init("stderr", testing.allocator);
    defer cap.deinit();
    // empty message triggers InvalidArgument via underlying C-ABI (len==0 → rc=1)
    try testing.expectError(proto.GraftError.InvalidArgument, proto.print_line_checked(&cap, testing.allocator, "", 0));
}

test "graft proto error conversion foreign error" {
    var cap = caps.Capability.init("stderr", testing.allocator);
    defer cap.deinit();
    try testing.expectError(proto.GraftError.ForeignError, proto.print_line_checked(&cap, testing.allocator, "hi", 2));
}

test "graft proto allocator-injected greeting and free" {
    var cap = caps.Capability.init("stdout", testing.allocator);
    defer cap.deinit();
    var owned = try proto.make_greeting(&cap, testing.allocator, "Janus");
    defer owned.deinit();
    try testing.expectEqualStrings("Hello, Janus", owned.slice());
}

test "graft proto allocator-injected invalid argument" {
    var cap = caps.Capability.init("stdout", testing.allocator);
    defer cap.deinit();
    try testing.expectError(proto.GraftError.InvalidArgument, proto.make_greeting(&cap, testing.allocator, ""));
}

test "graft proto read_file owned buffer and free" {
    var fs = caps.FileSystem.init("fs", testing.allocator);
    defer fs.deinit();
    const fname = "tmp_graft_read.txt";
    // Create a test file
    var file = try std.fs.cwd().createFile(fname, .{ .truncate = true });
    defer file.close();
    const data = "Hello Buf";
    try file.writeAll(data);
    // Read via graft
    var owned = try proto.read_file(&fs, testing.allocator, fname);
    defer owned.deinit();
    try testing.expectEqualStrings(data, owned.slice());
    // Cleanup
    try std.fs.cwd().deleteFile(fname);
}

test "graft proto read_file invalid and missing" {
    var fs2 = caps.FileSystem.init("fs", testing.allocator);
    defer fs2.deinit();
    try testing.expectError(proto.GraftError.InvalidArgument, proto.read_file(&fs2, testing.allocator, ""));
    try testing.expectError(proto.GraftError.ForeignError, proto.read_file(&fs2, testing.allocator, "no_such_file_12345.txt"));
}

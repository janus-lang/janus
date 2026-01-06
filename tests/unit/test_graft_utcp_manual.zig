// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const manuals = @import("graft_manuals");

test "UTCP manual exposes std.graft.proto endpoints" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var container = manuals.GraftProtoContainer{};
    const manual = try container.utcpManual(gpa.allocator());
    defer gpa.allocator().free(manual);

    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "std.graft.proto"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "print_line"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "make_greeting"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "read_file"));
}

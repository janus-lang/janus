// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

const std = @import("std");
const Using = @import("mem/using.zig").Using;

const Dummy = struct { count: *usize };
fn dummyDrop(d: *Dummy) void {
    d.count.* += 1;
}

test "using drops exactly once" {
    var drops: usize = 0;
    var u = Using(Dummy, dummyDrop).init(.{ .count = &drops });
    defer u.drop();

    // early drop is idempotent
    u.drop();
    try std.testing.expectEqual(@as(usize, 1), drops);
}

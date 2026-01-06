// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() void {
    var b = std.io.BufferedReader(4096).init(std.fs.stdin().reader());
    const reader = b.reader();
    _ = reader;
}

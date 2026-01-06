// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() !void {
    const stdin_file = std.fs.File.stdin();
    var reader = stdin_file.reader();
    _ = reader;
}

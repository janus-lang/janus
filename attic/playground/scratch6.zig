// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() void {}

comptime {
    inline for (std.meta.declarations(std.io)) |decl| {
        @compileLog(decl.name);
    }
}

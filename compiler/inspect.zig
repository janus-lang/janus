// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Sovereign Index: Janus Inspector
//
// This is the public API for the introspection tooling.
// All internal implementation details reside in the `inspect/` folder.

pub const Inspector = @import("inspect/core.zig").Inspector;
pub const InspectOptions = @import("inspect/core.zig").InspectOptions;
pub const InspectFormat = @import("inspect/core.zig").InspectFormat;

test {
    _ = @import("inspect/test_inspect.zig");
}

// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Compatibility wrapper: expose core ASTDB as 'astdb.zig' for modules that import it
pub const core = @import("core.zig");

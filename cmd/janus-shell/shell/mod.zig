// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Janus Shell module exports
//!
//! This module provides the public API for the Janus Shell implementation.

pub const Shell = @import("../shell.zig").Shell;
pub const Profile = @import("../types.zig").Profile;
pub const ShellConfig = @import("../types.zig").ShellConfig;
pub const ShellError = @import("../types.zig").ShellError;

// Re-export core types for convenience
pub const types = @import("../types.zig");
pub const parser = @import("../parser.zig");
pub const executor = @import("../executor.zig");
pub const builtins = @import("../builtins.zig");
pub const capabilities = @import("../capabilities.zig");
pub const diagnostics = @import("../diagnostics.zig");

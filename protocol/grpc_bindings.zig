// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// gRPC transport is now the only transport. Bindings are always enabled.
pub const enabled: bool = true;

// Only include C headers here. The generated gRPC C++ stubs are bridged via
// a C shim (protocol/c_shim/oracle_c_api.h), to keep @cImport in C mode.
pub const c = @cImport({
    @cInclude("oracle_c_api.h");
});

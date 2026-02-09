// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus :service Profile - Standard Library
//!
//! CBC-MN Scheduler + HTTP + NS-Msg for concurrent services
//! Production-ready as of 2026-02-09

const std = @import("std");
pub const scheduler = @import("../runtime/scheduler/scheduler.zig");
pub const http = @import("net/http.zig");
pub const ns_msg = @import("../../src/service/ns_msg.zig");

pub usingnamespace scheduler;
pub usingnamespace http;
pub usingnamespace ns_msg;

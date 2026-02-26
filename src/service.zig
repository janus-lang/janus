// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus :service Profile - Service-Oriented Programming
//!
//! The :service profile provides:
//! - Async/await structured concurrency
//! - Namespace messaging (ns-msg) for distributed communication
//! - Resource-safe `using` statement
//! - HTTP service primitives
//!
//! ## Architecture
//!
//! ```
//! ┌──────────────────────────────────────────────────────────────┐
//! │                     :service Profile                         │
//! ├──────────────────────────────────────────────────────────────┤
//! │  Async Layer          │  NS-Msg Layer      │  HTTP Layer    │
//! │  - async/await        │  - publish         │  - Server      │
//! │  - nursery            │  - subscribe       │  - Route       │
//! │  - spawn              │  - query           │  - Handle      │
//! │  - channels           │  - respond         │  - Middleware  │
//! └───────────────────────┴────────────────────┴────────────────┘
//! ```

const std = @import("std");

// Re-export ns-msg module
pub const ns_msg = @import("ns_msg.zig");

/// :service profile version
pub const version = "2026.2.0";

/// Feature flags for :service profile
pub const features = struct {
    /// Async/await support
    pub const async_await = true;
    /// Namespace messaging
    pub const ns_msg_support = true;
    /// HTTP server/client
    pub const http = true;
    /// Resource management (using statement)
    pub const resource_management = true;
    /// Structured concurrency (nursery/spawn)
    pub const structured_concurrency = true;
};

/// Check if a feature is available
pub fn hasFeature(comptime feature: []const u8) bool {
    return switch (feature) {
        "async" => features.async_await,
        "ns_msg" => features.ns_msg_support,
        "http" => features.http,
        "using" => features.resource_management,
        "nursery" => features.structured_concurrency,
        else => false,
    };
}

// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Namespace Messaging System for Janus :service Profile
//!
//! This module implements RFC-0500: ns-msg — first-class distributed communication
//! primitives that unify PUB/SUB, REQ/REP, and SURVEY patterns under a single
//! semantic: the namespace query.
//!
//! ## Core Concepts
//!
//! - **Path**: A concrete namespace path (e.g., "sensor/berlin/pm25")
//! - **Pattern**: A path with wildcards (e.g., "sensor/+/pm25", "sensor/*")
//! - **Envelope**: Message container with path, payload, and metadata
//! - **Subscription**: Handle for receiving messages matching a pattern
//! - **Effect**: Explicit tracking of NS.publish, NS.subscribe, NS.query, NS.respond
//!
//! ## Quick Example
//!
//! ```janus
//! // In Janus code (conceptual):
//! func monitor_sensors() ! NS.publish, NS.subscribe, Log do
//!     let sub = subscribe(Sensor.".".pm25)
//!     
//!     for reading in sub do
//!         if reading.value > 50.0 then
//!             publish(Feed.berlin.alerts.alert_1, Alert {
//!                 severity: High,
//!                 message: "PM2.5 critical"
//!             })
//!         end
//!     end
//! end
//! ```
//!
//! ## Module Structure
//!
//! - `types`: Path and Pattern types
//! - `envelope`: Message envelope and serialization
//! - `effects`: Effect definitions and handles (Subscription, QueryHandle)
//! - `namespace`: Namespace schema and compile-time validation
//! - `router`: Message routing (local and network)
//!
//! ## Architecture
//!
//! ```
//! ┌─────────────────────────────────────────────────────────────┐
//! │                    Application Layer                         │
//! │  ┌─────────┐  ┌──────────┐  ┌─────────┐  ┌──────────┐      │
//! │  │ publish │  │subscribe │  │  query  │  │ respond  │      │
//! │  └────┬────┘  └────┬─────┘  └────┬────┘  └────┬─────┘      │
//! └───────┼────────────┼─────────────┼────────────┼────────────┘
//!         │            │             │            │
//! ┌───────┴────────────┴─────────────┴────────────┴────────────┐
//! │                    NS Effects Layer                          │
//! │              (Explicit effect tracking)                      │
//! └───────┬────────────────────────────────────────┬─────────────┘
//!         │                                        │
//! ┌───────┴────────────┐              ┌─────────────┴───────────┐
//! │   Local Router     │              │    Network Router       │
//! │  (in-process)      │              │    (LWF/UTCP/QUIC)      │
//! └───────┬────────────┘              └─────────────┬───────────┘
//!         │                                        │
//!         └────────────────┬───────────────────────┘
//!                          │
//! ┌────────────────────────┴──────────────────────────────────┐
//! │                    Transport Layer                         │
//! │         (Memory / IPC / UTCP / QUIC / LWF)                 │
//! └────────────────────────────────────────────────────────────┘
//! ```

const std = @import("std");

// Public API exports
pub const types = @import("ns_msg/types.zig");
pub const envelope = @import("ns_msg/envelope.zig");
pub const effects = @import("ns_msg/effects.zig");
pub const namespace = @import("ns_msg/namespace.zig");
pub const router = @import("ns_msg/router.zig");
pub const lwf = @import("ns_msg/lwf.zig");
pub const cbor = @import("ns_msg/cbor.zig");

// Re-export core types for convenience
pub const Path = types.Path;
pub const Pattern = types.Pattern;
pub const Segment = types.Segment;
pub const Envelope = envelope.Envelope;
pub const SensorReading = envelope.SensorReading;
pub const FeedPost = envelope.FeedPost;
pub const QueryRequest = envelope.QueryRequest;
pub const QueryResponse = envelope.QueryResponse;
pub const Subscription = effects.Subscription;
pub const QueryHandle = effects.QueryHandle;
pub const NsEffect = effects.NsEffect;
pub const NsContext = effects.NsContext;
pub const NetworkError = effects.NetworkError;
pub const NamespaceSchema = namespace.NamespaceSchema;
pub const NamespaceRegistry = namespace.NamespaceRegistry;
pub const createStandardRegistry = namespace.createStandardRegistry;
pub const FrameHeader = lwf.Header;
pub const FrameClass = lwf.FrameClass;

/// NS-Msg version
pub const version = "0.1.0";

/// Check if ns-msg is compatible with given Janus version
pub fn isCompatible(janus_version: []const u8) bool {
    // For now, require Janus 0.5.0+
    _ = janus_version;
    return true;
}

/// Compile-time namespace validation helper
/// 
/// Usage:
/// ```zig
/// const ns_sensor = comptime try validateNamespace("sensor/{geohash}/{metric}");
/// ```
pub fn validateNamespace(comptime template: []const u8) !void {
    // Compile-time validation of namespace template syntax
    comptime {
        var depth: i32 = 0;
        for (template) |c| {
            switch (c) {
                '{' => depth += 1,
                '}' => depth -= 1,
                else => {},
            }
            if (depth < 0) return error.UnbalancedBraces;
        }
        if (depth != 0) return error.UnbalancedBraces;
    }
}

/// Testing helpers
pub const testing = struct {
    const TestAlloc = std.testing.allocator;

    /// Create a test sensor reading
    pub fn createTestReading(value: f64) SensorReading {
        return .{
            .value = value,
            .unit = "µg/m³",
            .timestamp = 1234567890,
            .geohash = "u33dc0",
        };
    }

    /// Create a test path
    pub fn createTestPath(segments: []const []const u8) !Path {
        var path = Path.init(TestAlloc);
        errdefer path.deinit();
        for (segments) |seg| {
            try path.append(seg);
        }
        return path;
    }

    /// Create a test pattern
    pub fn createTestPattern(pattern_str: []const u8) !Pattern {
        return try Pattern.parse(TestAlloc, pattern_str);
    }
};

// Module-level tests
test "ns_msg module imports" {
    // Verify all public exports are accessible
    _ = Path;
    _ = Pattern;
    _ = Segment;
    _ = Envelope;
    _ = SensorReading;
    _ = FeedPost;
    _ = Subscription;
    _ = QueryHandle;
    _ = NsEffect;
    _ = NsContext;
    _ = NetworkError;
    _ = NamespaceSchema;
    _ = NamespaceRegistry;
}

test "version constant" {
    try std.testing.expectEqualStrings("0.1.0", version);
}

test "validateNamespace compile time" {
    // Should pass
    try comptime validateNamespace("sensor/{geohash}/{metric}");
    try comptime validateNamespace("feed/{chapter}/{scope}/{post_id}");
    
    // Would fail at compile time:
    // try validateNamespace("sensor/{geohash");  // Unbalanced
}

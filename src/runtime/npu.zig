// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus NPU Runtime Module
//!
//! Main entry point for NPU-native runtime functionality.
//! Integrates device detection, memory management, and J-IR execution.

const std = @import("std");
const device = @import("npu/device.zig");

/// Main NPU runtime module - integrates device detection with Janus systems
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    devices: []device.Device,

    pub fn init(allocator: std.mem.Allocator) !Runtime {
        const devices = try device.detectDevices(allocator);

        return Runtime{
            .allocator = allocator,
            .devices = devices,
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.allocator.free(self.devices);
    }

    /// Get the best available device for auto-selection
    pub fn getAutoDevice(self: *Runtime) ?device.Device {
        return device.getAutoDevice(self.devices);
    }

    /// Check if APU capability is available
    pub fn hasApuCapability(self: *Runtime) bool {
        for (self.devices) |dev| {
            if (dev.hasCapability(.Apu)) return true;
        }
        return false;
    }
};

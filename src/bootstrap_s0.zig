// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// S0 bootstrap gate controller. Centralizes the on/off switch that the
// parser, semantic analyzer, and CLI consult to determine whether the
// minimal S0 surface should be enforced.

const std = @import("std");

pub const Gate = struct {
    var enabled: ?bool = null;

    pub fn isEnabled() bool {
        if (enabled == null) {
            enabled = detectFromEnv();
        }
        return enabled.?;
    }

    pub fn set(enable: bool) void {
        enabled = enable;
    }

    pub fn scoped(enable: bool) Scoped {
        const prev = enabled;
        enabled = enable;
        return .{ .prev = prev.? };
    }

    pub const Scoped = struct {
        prev: bool,
        active: bool = true,

        pub fn done(self: *Scoped) void {
            if (!self.active) return;
            Gate.enabled = self.prev;
            self.active = false;
        }

        pub fn deinit(self: *Scoped) void {
            self.done();
        }
    };
};

pub fn isEnabled() bool {
    return Gate.isEnabled();
}

pub fn set(enable: bool) void {
    Gate.set(enable);
}

pub fn scoped(enable: bool) Gate.Scoped {
    return Gate.scoped(enable);
}

pub fn detectFromEnv() bool {
    const env = std.posix.getenv("JANUS_BOOTSTRAP_S0") orelse return true;
    return parseBool(env, true);
}

pub fn parse(value: []const u8, fallback: bool) bool {
    return parseBool(value, fallback);
}

fn parseBool(str: []const u8, default: bool) bool {
    if (str.len == 0) return default;

    if (str.len == 1) {
        const c = std.ascii.toLower(str[0]);
        return switch (c) {
            '1', 't', 'y' => true,
            '0', 'f', 'n' => false,
            else => default,
        };
    }

    if (eqIgnoreCase(str, "true") or eqIgnoreCase(str, "yes") or eqIgnoreCase(str, "on")) return true;
    if (eqIgnoreCase(str, "false") or eqIgnoreCase(str, "no") or eqIgnoreCase(str, "off")) return false;
    return default;
}

fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |lhs, rhs| {
        if (std.ascii.toLower(lhs) != std.ascii.toLower(rhs)) return false;
    }
    return true;
}

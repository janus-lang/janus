// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

pub fn Using(comptime T: type, comptime dropFn: fn (*T) void) type {
    return struct {
        value: ?T,
        dropped: bool = false,

        pub fn init(value: T) @This() {
            return .{ .value = value, .dropped = false };
        }

        pub fn drop(self: *@This()) void {
            if (self.dropped) return;
            if (self.value) |*val| {
                dropFn(val);
            }
            self.value = null;
            self.dropped = true;
        }

        pub fn get(self: *const @This()) *const T {
            return &self.value.?;
        }

        pub fn getMut(self: *@This()) *T {
            return &self.value.?;
        }
    };
}

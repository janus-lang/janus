// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Kernel Registry — device support and simple cost model

const std = @import("std");
const jir = @import("tensor_jir.zig");
const rt = @import("tensor_runtime.zig");

pub const OpKind = jir.OpKind;
pub const DeviceKind = rt.DeviceKind;

pub const KernelRegistry = struct {
    /// Return whether an op is supported on a device
    pub fn supports(self: *const KernelRegistry, kind: OpKind, dev: DeviceKind) bool {
        _ = self;
        return switch (dev) {
            .apu => switch (kind) {
                .Matmul, .Conv2D, .Relu, .Gelu, .Add, .Mul, .ReduceSum, .Transpose, .Reshape, .Concat, .Split, .BatchNorm => true,
                else => false,
            },
            .npu => switch (kind) {
                .Matmul, .Conv2D, .Relu, .Gelu, .Add, .Mul, .ReduceSum, .Transpose, .Reshape, .Concat, .Split, .BatchNorm => true,
                else => false,
            },
            .gpu => switch (kind) {
                .Matmul, .Conv2D, .Relu, .Add, .Mul, .Transpose, .Reshape => true,
                else => false,
            },
            .cpu => true, // CPU has scalar fallback for everything
        };
    }

    /// Crude cost model: lower is better. Device preference: NPU < GPU < CPU
    pub fn estimateCost(self: *const KernelRegistry, kind: OpKind, dev: DeviceKind) u32 {
        _ = self;
        _ = kind;
        return switch (dev) {
            .apu => 0,
            .npu => 1,
            .gpu => 5,
            .cpu => 20,
        };
    }
};

// Tests
const testing = std.testing;

test "registry supports compute on npu" {
    var reg = KernelRegistry{};
    try testing.expect(reg.supports(.Matmul, .npu));
    try testing.expect(reg.supports(.Relu, .npu));
    try testing.expect(reg.supports(.Matmul, .cpu));
}

// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// NPU Backend - Sovereign Index
// Doctrine: PANOPTICUM (All-seeing architecture where one folder reveals all)
//
// This file IS the public API for the NPU backend.
// Internal implementation details live in npu_backend/ folder.

/// NPU Simulator - Validates semantic correctness of tensor/SSM operations
pub const Simulator = @import("npu_backend/simulator.zig").NPUSimulator;

/// MLIR Emitter - Production backend for TPU/NPU execution
pub const MLIREmitter = @import("npu_backend/mlir_emitter.zig").MLIREmitter;
pub const MLIRModule = @import("npu_backend/mlir_emitter.zig").MLIRModule;

/// Validation result from NPU simulation
pub const ValidationResult = @import("npu_backend/simulator.zig").ValidationResult;

/// Re-export types for convenience
pub const TensorOp = @import("npu_backend/simulator.zig").TensorOp;

test {
    // Run all NPU backend tests
    _ = @import("npu_backend/test_simulator.zig");
    _ = @import("npu_backend/test_mlir_emitter.zig");
}

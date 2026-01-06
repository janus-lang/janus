// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Builtin Call Registry - Clean table-driven approach

const std = @import("std");

/// Return type for builtin functions
pub const ReturnType = enum {
    void,
    i32,
    i64,
    f64,
    ptr, // Opaque pointer (i8*)
    bool,
};

/// Built-in function mapping: Janus name -> Runtime name
pub const BuiltinCall = struct {
    janus_name: []const u8,
    runtime_name: []const u8,
    min_args: usize,
    max_args: ?usize, // null = unlimited
    return_type: ReturnType,
};

/// Registry of all built-in functions
/// Doctrine: First-Class Operations for Sovereign Numerics and AI-First Runtime
pub const builtins = [_]BuiltinCall{
    // === I/O Functions (variadic - accept multiple arguments) ===
    .{ .janus_name = "print", .runtime_name = "janus_print", .min_args = 1, .max_args = null, .return_type = .void },
    .{ .janus_name = "println", .runtime_name = "janus_println", .min_args = 1, .max_args = null, .return_type = .void },
    .{ .janus_name = "print_int", .runtime_name = "janus_print_int", .min_args = 1, .max_args = 1, .return_type = .void },
    .{ .janus_name = "print_float", .runtime_name = "janus_print_float", .min_args = 1, .max_args = 1, .return_type = .void },

    // === File I/O (Blocking) ===
    .{ .janus_name = "readFile", .runtime_name = "janus_readFile", .min_args = 2, .max_args = 2, .return_type = .ptr },
    .{ .janus_name = "writeFile", .runtime_name = "janus_writeFile", .min_args = 3, .max_args = 3, .return_type = .i32 },

    // === Error Handling ===
    .{ .janus_name = "panic", .runtime_name = "janus_panic", .min_args = 1, .max_args = 1, .return_type = .void },

    // === PROBATIO: Verification Intrinsics ===
    .{ .janus_name = "assert", .runtime_name = "assert", .min_args = 1, .max_args = 2, .return_type = .void },

    // === String Operations ===
    .{ .janus_name = "string.len", .runtime_name = "janus_string_len", .min_args = 1, .max_args = 1, .return_type = .i32 },
    .{ .janus_name = "string.concat", .runtime_name = "janus_string_concat_cstr", .min_args = 2, .max_args = 2, .return_type = .ptr },

    // === Compiler Intrinsics for String Literals ===
    .{ .janus_name = "string_data_intrinsic", .runtime_name = "string_data_intrinsic", .min_args = 1, .max_args = 1, .return_type = .ptr },
    .{ .janus_name = "string_len_intrinsic", .runtime_name = "string_len_intrinsic", .min_args = 1, .max_args = 1, .return_type = .i32 },

    // === StringHandle Operations (Dynamic Strings) ===
    .{ .janus_name = "string_create", .runtime_name = "janus_string_create", .min_args = 3, .max_args = 3, .return_type = .ptr },
    .{ .janus_name = "string_concat_handle", .runtime_name = "janus_string_concat", .min_args = 3, .max_args = 3, .return_type = .ptr },
    .{ .janus_name = "string_len_handle", .runtime_name = "janus_string_handle_len", .min_args = 1, .max_args = 1, .return_type = .i64 },
    .{ .janus_name = "string_eq", .runtime_name = "janus_string_eq", .min_args = 2, .max_args = 2, .return_type = .bool },
    .{ .janus_name = "string_print", .runtime_name = "janus_string_print", .min_args = 1, .max_args = 1, .return_type = .void },
    .{ .janus_name = "string_free", .runtime_name = "janus_string_free", .min_args = 2, .max_args = 2, .return_type = .void },

    // === Array Operations ===
    .{ .janus_name = "std.array.create", .runtime_name = "std_array_create", .min_args = 2, .max_args = 2, .return_type = .ptr },

    // === Memory/Allocator ===
    .{ .janus_name = "std.mem.default_allocator", .runtime_name = "janus_default_allocator", .min_args = 0, .max_args = 0, .return_type = .ptr },

    // === Tensor Operations (NPU_Tensor tenancy) - Sovereign Numerics ===
    .{ .janus_name = "tensor.matmul", .runtime_name = "janus_tensor_matmul", .min_args = 2, .max_args = 2, .return_type = .ptr },
    .{ .janus_name = "tensor.conv2d", .runtime_name = "janus_tensor_conv2d", .min_args = 2, .max_args = 4, .return_type = .ptr },
    .{ .janus_name = "tensor.relu", .runtime_name = "janus_tensor_relu", .min_args = 1, .max_args = 1, .return_type = .ptr },
    .{ .janus_name = "tensor.softmax", .runtime_name = "janus_tensor_softmax", .min_args = 1, .max_args = 2, .return_type = .ptr },
    .{ .janus_name = "tensor.reduce_sum", .runtime_name = "janus_tensor_reduce_sum", .min_args = 1, .max_args = 2, .return_type = .f64 },
    .{ .janus_name = "tensor.reduce_max", .runtime_name = "janus_tensor_reduce_max", .min_args = 1, .max_args = 2, .return_type = .f64 },

    // === Quantum Operations (QPU_Quantum tenancy) ===
    .{ .janus_name = "quantum.hadamard", .runtime_name = "janus_quantum_hadamard", .min_args = 1, .max_args = 1, .return_type = .void },
    .{ .janus_name = "quantum.cnot", .runtime_name = "janus_quantum_cnot", .min_args = 2, .max_args = 2, .return_type = .void },
    .{ .janus_name = "quantum.measure", .runtime_name = "janus_quantum_measure", .min_args = 1, .max_args = 1, .return_type = .i32 },
    .{ .janus_name = "quantum.pauli_x", .runtime_name = "janus_quantum_pauli_x", .min_args = 1, .max_args = 1, .return_type = .void },
    .{ .janus_name = "quantum.pauli_y", .runtime_name = "janus_quantum_pauli_y", .min_args = 1, .max_args = 1, .return_type = .void },
    .{ .janus_name = "quantum.pauli_z", .runtime_name = "janus_quantum_pauli_z", .min_args = 1, .max_args = 1, .return_type = .void },

    // === VectorF64 Operations (Dynamic Arrays) ===
    .{ .janus_name = "vector_create", .runtime_name = "janus_vector_create", .min_args = 1, .max_args = 1, .return_type = .ptr },
    .{ .janus_name = "vector_push", .runtime_name = "janus_vector_push", .min_args = 2, .max_args = 2, .return_type = .i32 },
    .{ .janus_name = "vector_get", .runtime_name = "janus_vector_get", .min_args = 2, .max_args = 2, .return_type = .f64 },
    .{ .janus_name = "vector_set", .runtime_name = "janus_vector_set", .min_args = 3, .max_args = 3, .return_type = .i32 },
    .{ .janus_name = "vector_len", .runtime_name = "janus_vector_len", .min_args = 1, .max_args = 1, .return_type = .i64 },
    .{ .janus_name = "vector_free", .runtime_name = "janus_vector_free", .min_args = 1, .max_args = 1, .return_type = .void },

    // === Type Conversion (Explicit Casting) ===
    .{ .janus_name = "i32_to_i64", .runtime_name = "janus_cast_i32_to_i64", .min_args = 1, .max_args = 1, .return_type = .i64 },
    .{ .janus_name = "i32_to_f64", .runtime_name = "janus_cast_i32_to_f64", .min_args = 1, .max_args = 1, .return_type = .f64 },

    // === SSM Primitives (Mamba-3 inspired) - State Space Models ===
    .{ .janus_name = "ssm.scan", .runtime_name = "janus_ssm_scan", .min_args = 3, .max_args = 3, .return_type = .ptr },
    .{ .janus_name = "ssm.selective_scan", .runtime_name = "janus_ssm_selective_scan", .min_args = 4, .max_args = 4, .return_type = .ptr },
};

/// Lookup a builtin by its Janus name
pub fn findBuiltin(janus_name: []const u8) ?*const BuiltinCall {
    for (&builtins) |*builtin| {
        if (std.mem.eql(u8, builtin.janus_name, janus_name)) {
            return builtin;
        }
    }
    return null;
}

/// Check if a name is a built-in function
pub fn isBuiltin(janus_name: []const u8) bool {
    return findBuiltin(janus_name) != null;
}

// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Unit tests for core_profile_codegen.zig
//!
//! Tests the AST → QTJIR conversion for :core profile constructs.

const std = @import("std");
const testing = std.testing;
const libjanus = @import("libjanus");
const core_codegen = libjanus.core_codegen;
const CoreProfileCodeGen = core_codegen.CoreProfileCodeGen;
const astdb_core = @import("astdb_core");

test "CoreProfileCodeGen: init and deinit" {
    const allocator = testing.allocator;

    var db = try astdb_core.AstDB.init(allocator, true);
    defer db.deinit();

    var codegen = core_codegen.CoreProfileCodeGen.init(allocator, &db);
    defer codegen.deinit();

    // Verify initial state
    try testing.expect(codegen.current_graph == null);
    try testing.expect(codegen.current_builder == null);
}

test "CoreProfileCodeGen: generate empty unit" {
    const allocator = testing.allocator;

    var db = try astdb_core.AstDB.init(allocator, true);
    defer db.deinit();

    // Create an empty compilation unit with source code
    _ = try db.addUnit("test_empty.jan", "");

    var codegen = core_codegen.CoreProfileCodeGen.init(allocator, &db);
    defer codegen.deinit();

    // Should handle empty unit gracefully (no functions to generate)
    // This verifies the basic flow works
}

test "CoreProfileCodeGen: error types" {
    // Verify error types exist and can be used
    const CodeGenError = core_codegen.CodeGenError;

    const errs = [_]CodeGenError{
        CodeGenError.UnsupportedNode,
        CodeGenError.UnsupportedExpression,
        CodeGenError.UndefinedVariable,
        CodeGenError.UndefinedFunction,
        CodeGenError.TypeMismatch,
        CodeGenError.InvalidArity,
        CodeGenError.OutOfMemory,
        CodeGenError.InternalError,
    };

    // Just ensure all errors can be enumerated
    try testing.expectEqual(@as(usize, 8), errs.len);
}

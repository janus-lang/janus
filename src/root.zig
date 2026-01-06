// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! libjanus - The Janus Language Compiler Core Library
//!
//! This is the main entry point for libjanus, providing a reusable API
//! for tokenization, parsing, semantic analysis, IR generation, and codegen.
//! All Janus tools (CLI, daemon, LSP) use this library as their foundation.

const std = @import("std");
const testing = std.testing;

// Core libjanus module (imported via build system as named module 'janus_lib')
const lib = @import("janus_lib");

// Re-export main API functions from libjanus
pub const api = lib;
pub const tokenize = api.tokenize;
pub const parse_root = api.parse_root;
pub const analyze = api.analyze;
pub const analyzeWithASTDB = api.analyzeWithASTDB;
pub const analyzeLegacy = api.analyzeLegacy;

// Revolutionary ASTDB system
pub const astdb = @import("../compiler/libjanus/astdb.zig");

// Type system for external access
pub const Type = @import("../compiler/libjanus/semantic.zig").Type;
pub const generateIR = api.generateIR;

// Legacy compatibility (will be removed after MVC milestone)
pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

test "libjanus API integration" {
    const allocator = testing.allocator;

    // Test tokenization and parsing via public API
    const input = "func main() { print(\"Hello, Janus!\") }";
    const tokens = try tokenize(input, allocator);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);

    // Test parsing via public API
    const root = try parse_root(input, allocator);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
    }

    try testing.expect(root.kind == .Root);

    // Test semantic analysis (legacy compatibility)
    try analyzeLegacy(root);
}

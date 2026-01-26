// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Example Zig module for native integration testing
//! This demonstrates how Janus can call Zig functions natively during bootstrap.

const std = @import("std");

/// Add two integers - exported for C linkage
pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}

/// Multiply two integers - exported for C linkage
pub export fn multiply(a: i32, b: i32) i32 {
    return a * b;
}

/// Square a number - exported for C linkage
pub export fn square(x: i32) i32 {
    return x * x;
}

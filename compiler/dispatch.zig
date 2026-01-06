// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Sovereign Dispatch Index — The Canonical Facade
//
// This file provides a clean API surface for the dispatch subsystem,
// hiding the historical scatter of 85+ dispatch-related files.
// Full reorganization is tracked in: .kiro/specs/_FUTURE/repo-hygiene/
//
// Usage:
//   const dispatch = @import("compiler/dispatch.zig");
//   const resolver = dispatch.semantic.resolveGeneric(...);

const std = @import("std");

// ============================================================================
// BLESSED EXPORTS — The Sovereign API
// ============================================================================

/// Semantic Dispatch: Bounded generics with effect filtering (DISP-001)
/// Location: compiler/libjanus/semantic/dispatch.zig
pub const semantic = @import("libjanus/semantic/dispatch.zig");

/// Codegen Dispatch Strategy: Runtime vs compile-time dispatch selection
/// Location: compiler/libjanus/passes/codegen/dispatch_strategy.zig
pub const codegen_strategy = @import("libjanus/passes/codegen/dispatch_strategy.zig");

/// LLVM Dispatch: Low-level dispatch table emission
/// Location: compiler/libjanus/passes/codegen/llvm/dispatch.zig
pub const llvm = @import("libjanus/passes/codegen/llvm/dispatch.zig");

/// Dispatch Table Manager: Compression and caching
/// Location: compiler/libjanus/dispatch_table_manager.zig
pub const table_manager = @import("libjanus/dispatch_table_manager.zig");

/// Dispatch Errors: Error types for dispatch resolution
/// Location: compiler/libjanus/dispatch_errors.zig
pub const errors = @import("libjanus/dispatch_errors.zig");

// ============================================================================
// INTERNAL — Do not use directly (pending repo hygiene)
// ============================================================================

// The following are NOT re-exported intentionally:
// - dispatch_benchmarks.zig (dev-only)
// - dispatch_visualizer.zig (debug-only)
// - dispatch_profiler.zig (perf-only)
// - *_test.zig files
// - attic/obsolete/* files

// ============================================================================
// SELF-TEST
// ============================================================================

test "dispatch facade smoke test" {
    // Verify semantic dispatch is accessible
    _ = semantic.DispatchError;
    
    // Note: Other imports may fail if files don't exist yet
    // This is expected until repo hygiene is complete
}

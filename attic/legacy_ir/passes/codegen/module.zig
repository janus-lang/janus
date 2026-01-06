// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Codegen Module - Exports for LLVM Dispatch Codegen
//!
//! This module provides a clean interface for the LLVM codegen components

pub const llvm_dispatch_codegen = @import("llvm/dispatch.zig");
const types = @import("types.zig");
const dispatch_strategy = @import("dispatch_strategy.zig");

// Re-export main types for easy access
pub const DispatchCodegen = llvm_dispatch_codegen.DispatchCodegen;
pub const CallSite = types.CallSite;
pub const Strategy = types.Strategy;
pub const OutputFmt = llvm_dispatch_codegen.OutputFmt;
pub const IRRef = types.IRRef;
pub const FamilyId = types.FamilyId;
// Re-export the real, advanced selector (remove stale stub alias)
pub const AdvancedStrategySelector = dispatch_strategy.AdvancedStrategySelector;
pub const OptimizationTracker = llvm_dispatch_codegen.OptimizationTracker;

// Re-export codegen functions and types
pub const CodegenOptions = @import("codegen.zig").CodegenOptions;
pub const checkLLVMTools = @import("codegen.zig").checkLLVMTools;
pub const generateExecutable = @import("codegen.zig").generateExecutable;
pub const generateExecutableFromJanusIR = @import("codegen.zig").generateExecutableFromJanusIR;
pub const generateExecutableWithSource = @import("codegen.zig").generateExecutableWithSource;

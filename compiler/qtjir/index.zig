// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR Module - Public API

// Panopticum Doctrine: All files in this folder are exposed via this Sovereign Index.
// Internal implementation details remain hidden.

pub const graph = @import("graph.zig");
pub const lower = @import("lower.zig");
pub const llvm_emitter = @import("llvm_emitter.zig");
pub const extern_registry = @import("extern_registry.zig");

// Re-export core types
pub const QTJIRGraph = graph.QTJIRGraph;
pub const IRBuilder = graph.IRBuilder;
pub const IRNode = graph.IRNode;
pub const OpCode = graph.OpCode;
pub const Tenancy = graph.Tenancy;
pub const Level = graph.Level;
pub const ConstantValue = graph.ConstantValue;

// Export lowering function
pub const lowerUnit = lower.lowerUnit;
pub const lowerUnitWithExterns = lower.lowerUnitWithExterns;
pub const LoweringResult = lower.LoweringResult;

// Export emitter
pub const LLVMEmitter = llvm_emitter.LLVMEmitter;

// Export external function registry for native Zig integration
pub const ExternRegistry = extern_registry.ExternRegistry;
pub const ExternFnSig = extern_registry.ExternFnSig;

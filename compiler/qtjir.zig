// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Sovereign Index: QTJIR
// Panopticum Facade

const idx = @import("qtjir/index.zig");

pub const graph = idx.graph;
pub const lower = idx.lower;
pub const llvm_emitter = idx.llvm_emitter;

pub const QTJIRGraph = idx.QTJIRGraph;
pub const IRBuilder = idx.IRBuilder;
pub const IRNode = idx.IRNode;
pub const OpCode = idx.OpCode;
pub const Tenancy = idx.Tenancy;
pub const Level = idx.Level;
pub const ConstantValue = idx.ConstantValue;

pub const lowerUnit = idx.lowerUnit;
pub const LLVMEmitter = idx.LLVMEmitter;

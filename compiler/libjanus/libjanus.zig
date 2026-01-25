// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! libjanus - The Brain of the Compiler
//! This module consolidates all core compiler components into a single,
//! authoritative import surface for the rest of the Janus project.

pub const std = @import("std");

// Core ASTDB architecture
pub const astdb = @import("libjanus_astdb");

// Re-export commonly used ASTDB types for direct access
pub const ASTDBSystem = astdb.ASTDBSystem;
pub const Snapshot = astdb.Snapshot;
pub const QueryEngine = astdb.QueryEngine;
pub const QueryParser = astdb.QueryParser;
pub const QueryResult = astdb.QueryResult;
pub const Predicate = astdb.Predicate;
pub const TokenId = astdb.TokenId;
pub const RefId = astdb.RefId;
pub const UnitId = astdb.UnitId;
pub const SourceSpan = astdb.SourceSpan;
pub const NodeId = astdb.NodeId;
pub const DeclId = astdb.DeclId;
pub const AstNode = astdb.AstNode;
// Re-export core ASTDB types
const core_astdb = @import("astdb_core");
pub const CoreSnapshot = core_astdb.Snapshot;
pub const CoreNodeId = core_astdb.NodeId;

// Tokenizer
pub const tokenizer = @import("janus_tokenizer");

// Parser - Revolutionary ASTDB Architecture
pub const parser = @import("janus_parser");

// Semantic Analysis
pub const semantic = @import("libjanus_semantic.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// CANONICAL IR SYSTEM: QTJIR
// ═══════════════════════════════════════════════════════════════════════════════
// The Janus compiler uses QTJIR (Quantum-Tensor Janus IR) as the canonical IR.
// Import via: const qtjir = @import("qtjir");
//
// DO NOT use legacy ir.zig - it has been moved to attic/legacy_ir/
// See: compiler/qtjir.zig for the sovereign index
// See: compiler/qtjir/README.md for developer guide
// ═══════════════════════════════════════════════════════════════════════════════

// Tensor Graph IR (J‑IR) - specialized tensor operations
pub const tensor_jir = @import("tensor_jir.zig");
pub const tensor_builder = @import("tensor_builder.zig");
pub const tensor_fusion = @import("tensor_fusion.zig");
pub const tensor_quant = @import("tensor_quant.zig");
pub const tensor_tile = @import("tensor_tile.zig");
pub const tensor_backend = @import("tensor_backend.zig");
pub const tensor_backend_onnx = @import("tensor_backend_onnx.zig");
pub const tensor_runtime = @import("tensor_runtime.zig");
pub const tensor_kernel_registry = @import("tensor_kernel_registry.zig");
pub const tensor_device_dispatch = @import("tensor_device_dispatch.zig");
pub const tensor_capsule = @import("tensor_capsule.zig");
pub const tensor_debug = @import("tensor_debug.zig");
pub const tensor_profiler = @import("tensor_profiler.zig");
pub const tensor_cid = @import("tensor_cid.zig");
pub const tensor_compile = @import("tensor_compile.zig");
pub const build_cache = @import("incremental/build_cache.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// CODE GENERATION: Use QTJIR Pipeline
// ═══════════════════════════════════════════════════════════════════════════════
// Legacy codegen (passes/codegen/) has been moved to attic/legacy_ir/
// Use the QTJIR-based pipeline in src/pipeline.zig for compilation:
//   const pipeline = @import("pipeline");
//   var p = pipeline.Pipeline.init(allocator, options);
//   const result = try p.compile();
// ═══════════════════════════════════════════════════════════════════════════════

// Ledger system
pub const ledger = @import("ledger.zig");

// Public API for external consumption
pub const api = @import("api.zig");

// Re-export API functions and types
pub const checkLLVMTools = api.checkLLVMTools;
pub const CodegenOptions = api.CodegenOptions;
pub const compileToExecutable = api.compileToExecutable;
pub const compileToExecutableWithOptions = api.compileToExecutableWithOptions;
pub const generateExecutableFromJanusIR = api.generateExecutableFromJanusIR;
pub const blake3Hash = api.blake3Hash;
pub const contentIdToHex = api.contentIdToHex;
pub const hexToContentId = api.hexToContentId;
pub const normalizeArchive = api.normalizeArchive;
pub const initializeCAS = api.initializeCAS;
pub const createCAS = api.createCAS;

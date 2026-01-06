// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Project
// Copyright (c) 2026 Self Sovereign Society Foundation
// Licensed under the LSL-1.0. See LICENSE file in the project root.

//! Minimal libjanus public API - scaffold
//! Exposes small wrappers for tokenizer, parser and semantic stubs so the
//! rest of the project can start depending on these symbols.

const std = @import("std");
const libjanus = @import("libjanus.zig");

// Legacy imports removed - codegen moved to attic/legacy_ir/
// const Dispatch = @import("passes/codegen/dispatch_strategy.zig");
// const llvm_text = @import("passes/codegen/llvm.zig");

/// DEPRECATED:  Legacy semantic analysis stub - not used
/// Use QTJIR pipeline via src/pipeline.zig instead
pub fn runSema(
    alloc: std.mem.Allocator,
    db: anytype,
    diags: anytype,
) !void {
    _ = alloc;
    _ = db;
    _ = diags;
    @compileError("DEPRECATED: Use QTJIR-based semantic analysis via src/pipeline.zig");
}

// Import Lexer and Parser for the placeholder implementations
const Lexer = libjanus.tokenizer.Lexer;
const Parser = libjanus.parser.Parser;

// Public API for external consumption
pub const astdb = libjanus.astdb;
pub const tokenizer = libjanus.tokenizer;
pub const parser = libjanus.parser;
pub const semantic = libjanus.semantic;
// NOTE: ir.zig is DEPRECATED - use QTJIR via @import("qtjir") or src/pipeline.zig
// NOTE: codegen is DEPRECATED - use src/pipeline.zig directly
pub const CAS = libjanus.ledger.cas;
pub const Manifest = libjanus.ledger.manifest;
pub const KDLParser = libjanus.ledger.kdl_parser;
// JSONParser has been replaced by the new janus.serde framework
// which provides SIMD acceleration and capability-gated operations
pub const Transport = libjanus.ledger.transport;
pub const Resolver = libjanus.ledger.resolver;

// Re-export ASTDB types for golden tools
pub const ASTDBSystem = libjanus.astdb.ASTDBSystem;
pub const NodeId = libjanus.astdb.NodeId;
pub const TokenId = libjanus.astdb.TokenId;
pub const DeclId = libjanus.astdb.DeclId;
pub const ScopeId = libjanus.astdb.ScopeId;
pub const RefId = libjanus.astdb.RefId;
pub const UnitId = libjanus.astdb.UnitId;
pub const CID = libjanus.astdb.CID;
pub const CIDOpts = libjanus.astdb.CIDOpts;
pub const Snapshot = libjanus.astdb.Snapshot;
pub const NodeKind = libjanus.astdb.NodeKind;
pub const SourceSpan = libjanus.astdb.Span; // Use the canonical Span from ASTDB
pub const QueryEngine = libjanus.astdb.query.QueryEngine;
pub const Predicate = libjanus.astdb.query.Predicate;

pub fn compileIntoDb(
    alloc: std.mem.Allocator,
    src: []const u8,
    diags: *std.ArrayList(astdb.Diagnostic),
    db: *astdb.AstDb,
) ?astdb.NodeId {
    var lx = Lexer.init(alloc, src) catch return null;
    defer lx.deinit();
    var ps = Parser.init(alloc, &lx, diags) catch return null;
    defer ps.deinit();

    const ast = ps.parse() orelse return null;
    return db.insert(ast) catch return null;
}

/// DEPRECATED: Use src/pipeline.zig instead
pub fn compileAndCodegen(
    alloc: std.mem.Allocator,
    src: []const u8,
    diags: anytype,
    db: anytype,
    strategy: anytype,
) !void {
    _ = alloc;
    _ = src;
    _ = diags;
    _ = db;
    _ = strategy;
    @compileError("DEPRECATED: Use src/pipeline.zig instead.");
}

// Re-export tokenizer and parser modules for downstream tools
// These are already exposed via `libjanus.tokenizer` and `libjanus.parser`
// pub const tokenizer = libjanus.tokenizer;
// pub const parser = libjanus.parser;

pub export fn add(a: i32, b: i32) i32 {
    // placeholder implementation retained for compatibility
    return a + b;
}

// Tokenize input bytes and return token slice (shallow wrapper).
pub fn tokenize(input: []const u8, allocator: std.mem.Allocator) ![]libjanus.tokenizer.Token {
    var tok = libjanus.tokenizer.Tokenizer.init(allocator, input);
    defer tok.deinit();
    return tok.tokenize();
}

// Revolutionary ASTDB parsing - return immutable snapshot
// Caller provides an allocator (e.g., std.heap.page_allocator or similar).
pub fn parse_root(input: []const u8, allocator: std.mem.Allocator) !*libjanus.parser.Snapshot {
    var tok = libjanus.tokenizer.Tokenizer.init(allocator, input);
    defer tok.deinit();
    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    var p = libjanus.parser.Parser.init(allocator);
    defer p.deinit();
    return p.parseWithSource(input);
}

// Revolutionary semantic analysis with ASTDB integration
pub fn analyzeWithASTDB(astdb_system: *libjanus.astdb.ASTDBSystem, allocator: std.mem.Allocator) !libjanus.semantic.SemanticGraph {
    return libjanus.semantic.analyzeWithASTDB(astdb_system, allocator, .min);
}

// Revolutionary ASTDB semantic analysis
pub fn analyze(snapshot: *const libjanus.parser.Snapshot, allocator: std.mem.Allocator) !libjanus.semantic.SemanticGraph {
    _ = snapshot; // TODO: Implement ASTDB semantic analysis
    // For now, create a temporary ASTDB system
    var astdb_system = try libjanus.astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();
    return libjanus.semantic.analyzeWithASTDB(&astdb_system, allocator, .min);
}

// Legacy analyze function (no-op for compatibility)
pub fn analyzeLegacy(root: *libjanus.parser.Node) !void {
    return libjanus.semantic.analyzeLegacy(root);
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEPRECATED LEGACY IR API
// ═══════════════════════════════════════════════════════════════════════════════
// These functions are DEPRECATED. Use the QTJIR-based pipeline instead:
//   const pipeline = @import("pipeline");
//   var p = pipeline.Pipeline.init(allocator, options);
//   const result = try p.compile();
// ═══════════════════════════════════════════════════════════════════════════════

/// DEPRECATED: Use src/pipeline.zig with QTJIR instead
pub fn generateIR(snapshot: *const libjanus.parser.Snapshot, semantic_graph: *const libjanus.semantic.SemanticGraph, allocator: std.mem.Allocator) !void {
    _ = snapshot;
    _ = semantic_graph;
    _ = allocator;
    @compileError("DEPRECATED: generateIR uses legacy ir.zig. Use QTJIR via src/pipeline.zig instead.");
}

/// DEPRECATED: Use QTJIR llvm_emitter instead
pub fn generateLLVM(ir_module: anytype, allocator: std.mem.Allocator) ![]u8 {
    _ = ir_module;
    _ = allocator;
    @compileError("DEPRECATED: generateLLVM uses legacy ir.zig. Use qtjir.llvm_emitter instead.");
}

/// Codegen options for compilation pipeline
pub const CodegenOptions = struct {
    opt_level: []const u8 = "-O0",
    safety_checks: bool = true,
    profile: []const u8 = ":min",
    target_triple: []const u8 = "x86_64-unknown-linux-gnu",
};

/// DEPRECATED: Use src/pipeline.zig instead
pub fn generateExecutableWithOptions(ir_module: anytype, output_path: []const u8, allocator: std.mem.Allocator, options: CodegenOptions) !void {
    _ = ir_module;
    _ = output_path;
    _ = allocator;
    _ = options;
    @compileError("DEPRECATED: Use src/pipeline.zig with QTJIR instead.");
}

/// DEPRECATED: Use src/pipeline.zig instead
pub fn generateExecutableWithSource(ir_module: anytype, output_path: []const u8, source: []const u8, allocator: std.mem.Allocator, options: CodegenOptions) !void {
    _ = ir_module;
    _ = output_path;
    _ = source;
    _ = allocator;
    _ = options;
    @compileError("DEPRECATED: Use src/pipeline.zig with QTJIR instead.");
}

/// Check if LLVM tools (llc, clang) are available on the system
pub fn checkLLVMTools(allocator: std.mem.Allocator) bool {
    // Simple check: try to run llc --version
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "llc", "--version" },
    }) catch return false;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
    return result.term == .Exited and result.term.Exited == 0;
}

// Attempt to access the tensor J-IR graph from the current compilation pipeline.
// This is a forward-compatible hook: returns null when tensor extraction is not integrated.
pub fn getTensorGraphIfAvailable(
    snapshot: *const libjanus.parser.Snapshot,
    semantic_graph: *const libjanus.semantic.SemanticGraph,
    allocator: std.mem.Allocator,
) ?*const libjanus.tensor_jir.Graph {
    _ = snapshot;
    _ = semantic_graph;
    _ = allocator;
    // Not yet wired: J-IR extraction to be integrated into pipeline.
    // Keep stable API surface so CLI can switch to real graph automatically once available.
    return null;
}

/// DEPRECATED: Tensor graphs are extracted via QTJIR lowering, not legacy IR
pub fn getTensorGraphIfAvailableFromIR(ir_module: anytype) ?*const libjanus.tensor_jir.Graph {
    _ = ir_module;
    return null; // Legacy IR no longer supports tensor graph extraction
}

/// DEPRECATED: Use src/pipeline.Pipeline instead
pub fn compileToExecutable(source: []const u8, output_path: []const u8, allocator: std.mem.Allocator) !void {
    _ = source;
    _ = output_path;
    _ = allocator;
    @compileError("DEPRECATED: Use src/pipeline.Pipeline instead of legacy API.");
}

/// DEPRECATED: Use src/pipeline.Pipeline instead
pub fn compileToExecutableWithOptions(source: []const u8, output_path: []const u8, allocator: std.mem.Allocator, options: CodegenOptions) !void {
    _ = source;
    _ = output_path;
    _ = allocator;
    _ = options;
    @compileError("DEPRECATED: Use src/pipeline.Pipeline instead of legacy API.");
}

/// DEPRECATED: Emit LLVM IR using QTJIR pipeline instead
pub fn emitLLVMFromSource(source: []const u8, out_ll_path: []const u8, allocator: std.mem.Allocator) !void {
    _ = source;
    _ = out_ll_path;
    _ = allocator;
    @compileError("DEPRECATED: Use qtjir.llvm_emitter instead of legacy llvm_text codegen.");
}

/// DEPRECATED: Use src/pipeline.Pipeline instead
fn compileMinProfileWithASTDB(source: []const u8, output_path: []const u8, allocator: std.mem.Allocator) !void {
    _ = source;
    _ = output_path;
    _ = allocator;
    @compileError("DEPRECATED: Use src/pipeline.Pipeline instead.");
}

// ===== JANUS LEDGER API =====

// Initialize Content-Addressed Storage
pub fn initializeCAS(cas_root: []const u8) !void {
    return libjanus.ledger.cas.initializeCAS(cas_root);
}

// Create CAS instance
pub fn createCAS(root_path: []const u8, allocator: std.mem.Allocator) libjanus.ledger.cas.CAS {
    return libjanus.ledger.cas.CAS.init(root_path, allocator);
}

// Calculate BLAKE2b hash of data (using BLAKE3 name for API compatibility)
pub fn blake3Hash(data: []const u8) libjanus.ledger.cas.ContentId {
    return libjanus.ledger.cas.blake3Hash(data);
}

// Convert ContentId to hex string
pub fn contentIdToHex(content_id: libjanus.ledger.cas.ContentId, allocator: std.mem.Allocator) ![]u8 {
    return libjanus.ledger.cas.contentIdToHex(content_id, allocator);
}

// Parse hex string to ContentId
pub fn hexToContentId(hex: []const u8) !libjanus.ledger.cas.ContentId {
    return libjanus.ledger.cas.hexToContentId(hex);
}

// Normalize archive for reproducible hashing
pub fn normalizeArchive(archive_data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return libjanus.ledger.cas.normalizeArchive(archive_data, allocator);
}
// ===== MANIFEST PARSING API =====

// Parse janus.pkg manifest from KDL
pub fn parseManifest(kdl_input: []const u8, allocator: std.mem.Allocator) !libjanus.ledger.manifest.Manifest {
    return libjanus.ledger.kdl_parser.parseManifest(kdl_input, allocator);
}

// Parse JANUS.lock lockfile from JSON
// TODO: Integrate with new serde framework for SIMD acceleration
pub fn parseLockfile(json_input: []const u8, allocator: std.mem.Allocator) !libjanus.ledger.manifest.Lockfile {
    var json_parser = std.json.Parser.init(allocator, false);
    defer json_parser.deinit();

    var tree = try json_parser.parse(json_input);
    defer tree.deinit();

    const lockfile = libjanus.ledger.manifest.Lockfile.init(allocator);
    // TODO: Populate lockfile from JSON tree

    return lockfile;
}

// Serialize lockfile to JSON
// TODO: Integrate with new serde framework for SIMD acceleration
pub fn serializeLockfile(lockfile: *const libjanus.ledger.manifest.Lockfile, allocator: std.mem.Allocator) ![]u8 {
    _ = lockfile;
    // Placeholder: integrate serde once available; return minimal JSON for now
    return try allocator.dupe(u8, "{}");
}

// Create empty manifest
pub fn createManifest(allocator: std.mem.Allocator) libjanus.ledger.manifest.Manifest {
    return libjanus.ledger.manifest.Manifest.init(allocator);
}

// Create empty lockfile
pub fn createLockfile(allocator: std.mem.Allocator) libjanus.ledger.manifest.Lockfile {
    return libjanus.ledger.manifest.Lockfile.init(allocator);
}
// ===== TRANSPORT LAYER API =====

// Create default transport registry
pub fn createTransportRegistry(allocator: std.mem.Allocator) !libjanus.ledger.transport.TransportRegistry {
    return libjanus.ledger.transport.createDefaultRegistry(allocator);
}

// Fetch content from URL
pub fn fetchContent(registry: *const libjanus.ledger.transport.TransportRegistry, url: []const u8, allocator: std.mem.Allocator) !libjanus.ledger.transport.FetchResult {
    return registry.fetch(url, allocator);
}

// Fetch content with integrity verification
pub fn fetchContentWithVerification(
    registry: *const libjanus.ledger.transport.TransportRegistry,
    url: []const u8,
    expected_content_id: ?libjanus.ledger.cas.ContentId,
    allocator: std.mem.Allocator,
) !libjanus.ledger.transport.FetchResult {
    return libjanus.ledger.transport.fetchWithVerification(registry, url, expected_content_id, allocator);
}

// Check if git is available for git+https transport
pub fn checkGitAvailable(allocator: std.mem.Allocator) bool {
    return libjanus.ledger.transport.checkGitAvailable(allocator);
}
// ===== DEPENDENCY RESOLVER API =====

// Create dependency resolver
pub fn createResolver(cas_root: []const u8, allocator: std.mem.Allocator) !libjanus.ledger.resolver.Resolver {
    return libjanus.ledger.resolver.Resolver.init(cas_root, allocator);
}

// Add a new dependency
pub fn addDependency(
    resolver_instance: *libjanus.ledger.resolver.Resolver,
    package_name: []const u8,
    source: libjanus.ledger.manifest.PackageRef.Source,
    capabilities: []const libjanus.ledger.manifest.Capability,
    is_dev: bool,
) !libjanus.ledger.resolver.ResolutionResult {
    return resolver_instance.addDependency(package_name, source, capabilities, is_dev);
}

// Update all dependencies
pub fn updateDependencies(resolver_instance: *libjanus.ledger.resolver.Resolver) !libjanus.ledger.resolver.ResolutionResult {
    return resolver_instance.updateDependencies();
}

// Prompt for capability changes
pub fn promptCapabilityChanges(changes: []const libjanus.ledger.resolver.CapabilityChange, writer: anytype) !bool {
    return libjanus.ledger.resolver.Resolver.promptCapabilityChanges(changes, writer);
}

// Save lockfile
pub fn saveLockfile(resolver_instance: *libjanus.ledger.resolver.Resolver, lockfile: *const libjanus.ledger.manifest.Lockfile) !void {
    return resolver_instance.saveLockfile(lockfile);
}

test "parser named args tests" {
    _ = @import("tests/parser_named_args_tests.zig");
}
test ":npu tensor integration tests" {
    _ = @import("tests/tensor_integration_tests.zig");
}
// -------- Global Config (scoped) --------
pub const Config = struct {
    npu_enabled: bool = false,
};

var g_config: Config = .{};

pub fn setNpuEnabled(on: bool) void {
    g_config.npu_enabled = on;
}

pub fn isNpuEnabled() bool {
    return g_config.npu_enabled;
}

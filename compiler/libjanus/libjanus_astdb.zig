// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// ASTDB - AST-as-Database Architecture
// Task 1: AST Persistence Layer - Complete implementation
// Requirements: SPEC-astdb-query.md

// Immutable snapshots - CORE ASTDB version
pub const snapshot = @import("astdb_core");

// Core types and IDs - migrated to core_astdb
pub const StrId = snapshot.StrId;
pub const NodeId = snapshot.NodeId;
pub const TokenId = snapshot.TokenId;
pub const DeclId = snapshot.DeclId;
pub const ScopeId = snapshot.ScopeId;
pub const RefId = snapshot.RefId;
pub const DiagId = snapshot.DiagId;
pub const TypeId = snapshot.TypeId;
pub const UnitId = snapshot.UnitId;
pub const Scope = snapshot.Scope;
pub const Decl = snapshot.Decl;
pub const SourceSpan = snapshot.SourceSpan;

// Invalid ID constants
pub const INVALID_SCOPE_ID = snapshot.INVALID_SCOPE_ID;

// Legacy IDs module for compatibility during migration
pub const ids = @import("astdb/ids.zig");
pub const CID = ids.CID;

// String interning - GRANITE-SOLID version
pub const interner = @import("astdb/granite_interner.zig");
pub const StrInterner = interner.StrInterner;
pub const Snapshot = snapshot.Snapshot;
pub const NodeKind = snapshot.AstNode.NodeKind;
pub const NodeRow = snapshot.AstNode; // AstNode is the row type
pub const AstNode = snapshot.AstNode; // Compatibility alias
pub const TokenKind = snapshot.Token.TokenKind;
pub const TokenRow = snapshot.Token; // Token is the row type
pub const Token = snapshot.Token; // Compatibility alias
pub const DeclKind = snapshot.Decl.DeclKind;
pub const Span = snapshot.SourceSpan; // SourceSpan is the span type

// Canonicalization and CID computation
pub const canon = @import("astdb/canon.zig");
pub const Canon = canon.Canon;

pub const cid = @import("astdb/libjanus_cid.zig");
pub const CIDOpts = cid.CIDOpts;
pub const CIDCache = cid.CIDCache;
pub const CIDValidator = cid.CIDValidator;
pub const CIDUtils = cid.CIDUtils;
pub const cidOf = cid.cidOf;
pub const cidOfNode = cid.cidOfNode;
pub const cidOfDecl = cid.cidOfDecl;

// Query engine - TODO: Fix import path
pub const query = @import("astdb/query.zig");
pub const QueryEngine = query.QueryEngine;
pub const QueryResult = query.QueryResult;
pub const Predicate = query.Predicate;
pub const Diagnostic = query.Diagnostic;

pub const query_parser = @import("astdb/query_parser.zig");
pub const QueryParser = query_parser.QueryParser;
pub const QueryParseError = query_parser.QueryParseError;

// Accessor layer - Semantic schema abstraction (Layer 2)
pub const accessors = @import("astdb/accessors.zig");
pub const node_view = @import("astdb/node_view.zig");

// Convenience re-exports
pub const computeCID = canon.computeCID;

const CoreASTDB = @import("astdb_core");
pub const ASTDBSystem = CoreASTDB.AstDB;
// Compatibility alias for older tests expecting `AstDB` under `api.astdb`
pub const AstDB = CoreASTDB.AstDB;

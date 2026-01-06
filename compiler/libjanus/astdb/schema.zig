// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// ASTDB supplemental schema for query + semantic layers.
// TODO(autointegration): Replace placeholder fields with true semantic data.

const std = @import("std");
const core = @import("../../astdb/core.zig");
const node_view_mod = @import("node_view.zig");
const ids = @import("ids.zig");

pub const CID = ids.CID;
pub const SourceSpan = core.SourceSpan;

pub const Visibility = enum {
    public,
    private,
    protected,
};

pub const SymbolType = enum {
    variable,
    function,
    type,
    module,
    constant,
    parameter,
    field,
    method,
};

pub const Symbol = struct {
    name: []const u8,
    definition_cid: CID,
    symbol_type: SymbolType,
    visibility: Visibility,
    location: SourceSpan,
};

pub const SymbolTable = struct {
    symbols: []Symbol,
};

pub const SourceLocation = SourceSpan;

pub const TypeInfo = struct {
    type_name: []const u8,
    type_cid: ?CID,
    is_mutable: bool,
    is_optional: bool,
    generic_params: []TypeInfo,
};

pub const TypeDefinition = struct {
    name: []const u8,
    fields: []Field,
    methods: []Method,

    pub const Field = struct {
        name: []const u8,
        field_type: TypeInfo,
        definition_cid: CID,
        source_location: SourceLocation,
        visibility: Visibility,
    };

    pub const Method = struct {
        name: []const u8,
        definition_cid: CID,
        source_location: SourceLocation,
        visibility: Visibility,
    };
};

pub const ModuleRegistry = struct {
    modules: []ModuleEntry,

    pub const ModuleEntry = struct {
        name: []const u8,
        definition_cid: CID,
    };
};

pub const SymbolInfo = struct {
    name: []const u8,
    definition_cid: CID,
    symbol_type: SymbolType,
    visibility: Visibility,
    location: SourceLocation,
};

// Legacy AstNode struct removed - use NodeView API directly
// The fromView() function below provides compatibility for gradual migration

pub const EffectsInfo = struct {
    effects: [][]const u8,
    capabilities_required: [][]const u8,
    capabilities_granted: [][]const u8,
    is_pure: bool,
    is_deterministic: bool,
    memory_effects: MemoryEffects,
    io_effects: IOEffects,

    pub const MemoryEffects = enum {
        none,
        read,
        write,
    };

    pub const IOEffects = enum {
        none,
        read_write,
    };
};

pub const DefinitionInfo = struct {
    location: SourceLocation,
    definition_cid: CID,
    definition_type: DefinitionType,
    symbol_name: []const u8,
    containing_scope: CID,
    visibility: Visibility,
    is_builtin: bool,

    pub const DefinitionType = enum {
        variable_definition,
        function_definition,
        type_definition,
        module_definition,
        constant_definition,
        parameter_definition,
        field_definition,
        method_definition,
        self_defining,
    };
};

pub const HoverInfo = struct {
    text: []const u8,
    markdown: []const u8,
    signature: ?[]const u8,
    documentation: ?[]const u8,
    type_info: ?TypeInfo,
    examples: [][]const u8,
    related_links: []Link,

    pub const Link = struct {
        title: []const u8,
        url: []const u8,
        description: ?[]const u8,
    };
};

pub const DispatchInfo = struct {
    selected_function: []const u8,
    function_cid: CID,
    dispatch_strategy: DispatchStrategy,
    specificity_score: u32,
    is_ambiguous: bool,
    candidates: []DispatchCandidate,

    pub const DispatchStrategy = enum {
        static_dispatch,
        dynamic_dispatch,
        inline_dispatch,
        virtual_dispatch,
    };

    pub const DispatchCandidate = struct {
        name: []const u8,
        cid: CID,
        specificity: u32,
    };
};

pub const IRInfo = struct {
    ir_cid: CID,
    dependencies: []CID,
    optimization_level: u8,
};

// Legacy AstNode struct and helper functions removed - use NodeView API directly
// The schema now provides semantic types for queries without legacy AST structures

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Semantic Engine API Reference

This document provides detailed API documentation for all semantic engine components.

## Symbol Table API

### SymbolTable

The core symbol table provides hierarchical symbol management with efficient name interning.

```zig
pub const SymbolTable = struct {
    pub fn init(allocator: Allocator) SymbolTable
    pub fn deinit(self: *SymbolTable) void
    pub fn enterScope(self: *SymbolTable, scope_kind: ScopeKind) !ScopeId
    pub fn exitScope(self: *SymbolTable) void
    pub fn declareSymbol(self: *SymbolTable, name: []const u8, symbol_info: SymbolInfo) !SymbolId
    pub fn lookupSymbol(self: *SymbolTable, name: []const u8) ?SymbolId
    pub fn getSymbolInfo(self: *SymbolTable, symbol_id: SymbolId) *SymbolInfo
    pub fn getCurrentScope(self: *SymbolTable) ScopeId
    pub fn getScopeInfo(self: *SymbolTable, scope_id: ScopeId) *ScopeInfo
};
```

#### Types

```zig
pub const ScopeKind   global,
    module,
    function,
    block,
    loop,
    conditional,
};

pub const SymbolKind = enum {
    variable,
    function,
    type,
    module,
    constant,
    parameter,
};

pub const Visibility = enum {
    private,
    module,
    public,
};

pub const SymbolInfo = struct {
    kind: SymbolKind,
    visibility: Visibility,
    type_id: ?TypeId,
    declaration_node: NodeId,
    module_id: ModuleId,
    flags: SymbolFlags,
};
```

#### Usage Example

```zig
var symbol_table = SymbolTable.init(allocator);
defer symbol_table.deinit();

// Enter a function scope
const func_scope = try symbol_table.enterScope(.function);

// Declare a parameter
const param_id = try symbol_table.declareSymbol("x", .{
    .kind = .parameter,
    .visibility = .private,
    .type_id = i32_type_id,
    .declaration_node = node_id,
    .module_id = current_module,
    .flags = .{},
});

// Look up the symbol
if (symbol_table.lookupSymbol("x")) |symbol_id| {
    const symbol_info = symbol_table.getSymbolInfo(symbol_id);
    // Use symbol_info...
}

symbol_table.exitScope();
```

## Type System API

### TypeSystem

Provides canonical type representation with O(1) operations.

```zig
pub const TypeSystem = struct {
    pub fn init(allocator: Allocator) TypeSystem
    pub fn deinit(self: *TypeSystem) void
    pub fn getCanonicalType(self: *TypeSystem, type_desc: TypeDescriptor) TypeId
    pub fn areTypesCompatible(self: *TypeSystem, from: TypeId, to: TypeId) bool
    pub fn getTypeInfo(self: *TypeSystem, type_id: TypeId) *TypeInfo
    pub fn createFunctionType(self: *TypeSystem, params: []TypeId, return_type: TypeId) TypeId
    pub fn createStructType(self: *TypeSystem, fields: []FieldInfo) TypeId
    pub fn createArrayType(self: *TypeSystem, element_type: TypeId, size: ?u32) TypeId
    pub fn getTypeSize(self: *TypeSystem, type_id: TypeId) ?u32
    pub fn getTypeAlignment(self: *TypeSystem, type_id: TypeId) ?u32
};
```

#### Types

```zig
pub const TypeKind = enum {
    primitive,
    struct_type,
    function,
    array,
    pointer,
    optional,
    generic,
    variant,
};

pub const PrimitiveType = enum {
    void,
    bool,
    i8, i16, i32, i64,
    u8, u16, u32, u64,
    f32, f64,
    string,
    char,
};

pub const TypeDescriptor = union(TypeKind) {
    primitive: PrimitiveType,
    struct_type: StructDescriptor,
    function: FunctionDescriptor,
    array: ArrayDescriptor,
    pointer: PointerDescriptor,
    optional: OptionalDescriptor,
    generic: GenericDescriptor,
    variant: VariantDescriptor,
};

pub const TypeInfo = struct {
    kind: TypeKind,
    canonical_hash: u64,
    size: ?u32,
    alignment: ?u32,
    data: TypeData,
};
```

#### Usage Example

```zig
var type_system = TypeSystem.init(allocator);
defer type_system.deinit();

// Create primitive types
const i32_type = type_system.getCanonicalType(.{ .primitive = .i32 });
const f64_type = type_system.getCanonicalType(.{ .primitive = .f64 });

// Create function type: (i32, i32) -> i32
const params = [_]TypeId{ i32_type, i32_type };
const func_type = type_system.createFunctionType(&params, i32_type);

// Check type compatibility
const compatible = type_system.areTypesCompatible(i32_type, i32_type); // true
const incompatible = type_system.areTypesCompatible(i32_type, f64_type); // false

// Get type information
const type_info = type_system.getTypeInfo(i32_type);
const size = type_info.size; // 4 bytes
```

## Type Inference API

### TypeInference

Constraint-based type inference with unification algorithm.

```zig
pub const TypeInference = struct {
    pub fn init(allocator: Allocator, type_system: *TypeSystem) TypeInference
    pub fn deinit(self: *TypeInference) void
    pub fn inferExpression(self: *TypeInference, expr: *AstNode) !TypeId
    pub fn unifyTypes(self: *TypeInference, type1: TypeId, type2: TypeId) !TypeId
    pub fn addConstraint(self: *TypeInference, constraint: TypeConstraint) !void
    pub fn solveConstraints(self: *TypeInference) !void
    pub fn getInferredType(self: *TypeInference, node_id: NodeId) ?TypeId
    pub fn clearConstraints(self: *TypeInference) void
};
```

#### Types

```zig
pub const TypeConstraint = union(enum) {
    equality: EqualityConstraint,
    compatibility: CompatibilityConstraint,
    callable: CallableConstraint,
    indexable: IndexableConstraint,
};

pub const EqualityConstraint = struct {
    left: TypeId,
    right: TypeId,
    location: SourceSpan,
};

pub const InferenceError = error {
    TypeMismatch,
    AmbiguousType,
    RecursiveType,
    UnresolvedConstraint,
    IncompatibleTypes,
};
```

#### Usage Example

```zig
var type_inference = TypeInference.init(allocator, &type_system);
defer type_inference.deinit();

// Infer type of an expression
const expr_type = try type_inference.inferExpression(expr_node);

// Add explicit constraint
try type_inference.addConstraint(.{
    .equality = .{
        .left = var_type,
        .right = expr_type,
        .location = source_span,
    }
});

// Solve all constraints
try type_inference.solveConstraints();

// Get final inferred type
if (type_inference.getInferredType(node_id)) |inferred_type| {
    // Use inferred type...
}
```

## Validation Engine API

### ValidationEngine

Multi-pass semantic validation with profile enforcement.

```zig
pub const ValidationEngine = struct {
    pub fn init(allocator: Allocator, context: ValidationContext) ValidationEngine
    pub fn deinit(self: *ValidationEngine) void
    pub fn validateModule(self: *ValidationEngine, module: *AstNode) !ValidationResult
    pub fn validateExpression(self: *ValidationEngine, expr: *AstNode) !void
    pub fn validateStatement(self: *ValidationEngine, stmt: *AstNode) !void
    pub fn enforceProfile(self: *ValidationEngine, profile: LanguageProfile) void
    pub fn addDiagnostic(self: *ValidationEngine, diagnostic: Diagnostic) void
    pub fn getDiagnostics(self: *ValidationEngine) []const Diagnostic
    pub fn clearDiagnostics(self: *ValidationEngine) void
};
```

#### Types

```zig
pub const LanguageProfile = enum {
    core,      // Basic language subset (Teaching/Scripting)
    service,   // Backend Services
    cluster,   // Distributed Logic
    compute,   // NPU/GPU Kernels
    sovereign, // Systems Programming
};

pub const ValidationContext = struct {
    allocator: Allocator,
    profile: LanguageProfile,
    strict_mode: bool,
    symbol_table: *SymbolTable,
    type_system: *TypeSystem,
    type_inference: *TypeInference,
};

pub const ValidationResult = struct {
    success: bool,
    diagnostics: []Diagnostic,
    validated_nodes: u32,
    errors: u32,
    warnings: u32,
};

pub const DiagnosticKind = enum {
    error,
    warning,
    info,
    hint,
};

pub const Diagnostic = struct {
    kind: DiagnosticKind,
    message: []const u8,
    location: SourceSpan,
    suggestions: []Suggestion,
    related: []RelatedInfo,
};
```

#### Usage Example

```zig
const context = ValidationContext{
    .allocator = allocator,
    .profile = .service,
    .strict_mode = true,
    .symbol_table = &symbol_table,
    .type_system = &type_system,
    .type_inference = &type_inference,
};

var validator = ValidationEngine.init(allocator, context);
defer validator.deinit();

// Validate a module
const result = try validator.validateModule(module_node);

if (!result.success) {
    const diagnostics = validator.getDiagnostics();
    for (diagnostics) |diagnostic| {
        std.debug.print("{s}: {s}\n", .{
            @tagName(diagnostic.kind),
            diagnostic.message,
        });
    }
}
```

## Symbol Resolver API

### SymbolResolver

Multi-pass symbol resolution with scoping and visibility rules.

```zig
pub const SymbolResolver = struct {
    pub fn init(allocator: Allocator, symbol_table: *SymbolTable) SymbolResolver
    pub fn deinit(self: *SymbolResolver) void
    pub fn resolveModule(self: *SymbolResolver, module: *AstNode) !void
    pub fn resolveExpression(self: *SymbolResolver, expr: *AstNode) !void
    pub fn getResolution(self: *SymbolResolver, node_id: NodeId) ?SymbolId
    pub fn addResolution(self: *SymbolResolver, node_id: NodeId, symbol_id: SymbolId) void
    pub fn getDiagnostics(self: *SymbolResolver) []const Diagnostic
    pub fn clearResolutions(self: *SymbolResolver) void
};
```

#### Usage Example

```zig
var resolver = SymbolResolver.init(allocator, &symbol_table);
defer resolver.deinit();

// Resolve all symbols in a module
try resolver.resolveModule(module_node);

// Get resolution for specific node
if (resolver.getResolution(identifier_node_id)) |symbol_id| {
    const symbol_info = symbol_table.getSymbolInfo(symbol_id);
    // Use resolved symbol...
}

// Check for resolution errors
const diagnostics = resolver.getDiagnostics();
for (diagnostics) |diagnostic| {
    if (diagnostic.kind == .error) {
        // Handle resolution error...
    }
}
```

## Error Handling

All semantic engine APIs use Zig's error handling conventions:

### Common Error Types

```zig
pub const SemanticError = error {
    // Symbol errors
    SymbolNotFound,
    SymbolAlreadyDeclared,
    InvalidVisibility,

    // Type errors
    TypeMismatch,
    IncompatibleTypes,
    UnresolvedType,

    // Validation errors
    ProfileViolation,
    UnreachableCode,
    UninitializedVariable,

    // General errors
    OutOfMemory,
    InvalidInput,
    InternalError,
};
```

### Error Recovery

The semantic engine provides sophisticated error recovery:

```zig
// Continue analysis after errors
const result = validator.validateModule(module) catch |err| switch (err) {
    error.TypeMismatch => {
        // Add diagnostic and continue
        validator.addDiagnostic(.{
            .kind = .error,
            .message = "Type mismatch in expression",
            .location = expr_span,
            .suggestions = &[_]Suggestion{},
            .related = &[_]RelatedInfo{},
        });
        return ValidationResult{ .success = false, ... };
    },
    else => return err,
};
```

## Performance Considerations

### Memory Management

All semantic components use arena allocation for optimal performance:

```zig
// Use arena for scoped allocations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const arena_allocator = arena.allocator();

var symbol_table = SymbolTable.init(arena_allocator);
// No need to call deinit() - arena cleanup handles everything
```

### Caching and Memoization

The semantic engine aggressively caches results:

```zig
// Type operations are O(1) due to canonical hashing
const type1 = type_system.getCanonicalType(desc1);
const type2 = type_system.getCanonicalType(desc1); // Same instance returned
assert(type1 == type2);

// Symbol lookups are O(1) with string interning
const symbol1 = symbol_table.lookupSymbol("identifier");
const symbol2 = symbol_table.lookupSymbol("identifier"); // Fast hash lookup
```

### Incremental Updates

For LSP integration, use incremental validation:

```zig
// Only revalidate affected nodes
const affected_nodes = getAffectedNodes(edit_location);
for (affected_nodes) |node| {
    try validator.validateExpression(node);
}
```

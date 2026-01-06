<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->



# Janus Semantic Engine

The Janus Semantic Engine is the cognitive core of the compiler, providing comprehensive semantic analysis, type checking, and validation for Janus programs. It embodies the doctrines of Syntactic Honesty, Revealed Complexity, and Mechanism over Policy.

## Overview

The semantic engine transforms parsed AST into fully validated, type-annotated semantic information through a multi-pass analysis pipeline:

1. **Symbol Resolution** - Binds every identifier to its declaration
2. **Type Inference** - Infers types using constraint-based unification
3. **Semantic Validation** - Enforces language rules and profile constraints
4. **Diagnostic Generation** - Produces actionable error messages

## Architecture

### Core Components

- **Symbol Table** (`symbol_table.zig`) - Hierarchical symbol management with efficient name interning
- **Symbol Resolver** (`symbol_resolver.zig`) - Multi-pass identifier binding with scoping rules
- **Type System** (`type_system.zig`) - Canonical type representation with O(1) operations
- **Type Inference** (`type_inference.zig`) - Constraint-based type inference and unification
- **Validation Engine** (`validation_engine.zig`) - Profile-aware semantic validation

### Performance Characteristics

- **Symbol Lookup**: O(1) with string interning and hash tables
- **Type Operations**: O(1) with canonical hashing and deduplication
- **Semantic Queries**: O(log n) for most operations, O(1) for cached results
- **Memory Management**: Arena allocation with zero leaks

## Usage

### Basic Semantic Analysis

```zig
const std = @import("std");
const SymbolTable = @import("semantic/symbol_table.zig").SymbolTable;
const TypeSystem = @import("semantic/type_system.zig").TypeSystem;
const ValidationEngine = @import("semantic/validation_engine.zig").ValidationEngine;

pub fn analyzeProgram(allocator: std.mem.Allocator, ast: *AstNode) !void {
    // Initialize semantic components
    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var type_system = TypeSystem.init(allocator);
    defer type_system.deinit();

    var validation_engine = ValidationEngine.init(allocator, .{
        .profile = .core,
        .strict_mode = true,
    });
    defer validation_engine.deinit();

    // Perform semantic analysis
    try validation_engine.validateModule(ast);

    // Get diagnostics
    const diagnostics = validation_engine.getDiagnostics();
    for (diagnostics) |diagnostic| {
        std.debug.print("Error: {s}\n", .{diagnostic.message});
    }
}
```

### Language Profile Enforcement

The semantic engine supports different language profiles with varying feature sets:

- **:core** - Core language subset for teaching and scripting
- **:service** - Service language subset for backend services
- **:cluster** - Cluster language subset for distributed logic
- **:compute** - Compute language subset for AI/ML kernels
- **:sovereign** - Sovereign language subset for systems programming

```zig
// Configure validation for specific profile
const context = ValidationContext{
    .profile = .service,  // Enable backend service features
    .strict_mode = true,
};

var validator = ValidationEngine.init(allocator, context);
```

## Integration with LSP

The semantic engine provides real-time analysis for IDE integration:

```zig
// LSP hover information
const hover_info = try semantic_engine.getHoverInfo(position);

// Go-to-definition
const definition = try semantic_engine.getDefinition(position);

// Real-time diagnostics
const diagnostics = semantic_engine.getDiagnostics();
```

## Error Handling and Recovery

The engine provides sophisticated error recovery:

- **Precise Locations** - Character-level accuracy with source spans
- **Actionable Messages** - Clear explanations with fix suggestions
- **Error Suppression** - Prevents cascading errors from single root cause
- **Graceful Degradation** - Continues analysis even with errors

## Examples

See the `examples/semantic-engine/` directory for comprehensive examples:

- `basic_semantic_analysis.jan` - Symbol resolution and type checking
- `type_inference_showcase.jan` - Advanced type inference scenarios
- `profile_validation.jan` - Language profile enforcement

## Testing

Run the semantic engine tests:

```bash
# All semantic tests
zig build test-semantic

# Specific component tests
zig build test-symbol-table
zig build test-type-system
zig build test-validation-engine
```

## Performance Benchmarks

The semantic engine maintains excellent performance characteristics:

- **Large Programs**: 100K+ lines analyzed in <1 second
- **LSP Queries**: <10ms response time for hover/definition
- **Incremental Updates**: <100ms for typical edit-compile cycles
- **Memory Usage**: Linear growth with efficient sharing

## Contributing

When contributing to the semantic engine:

1. Maintain O(1) complexity for core operations
2. Use arena allocation for scoped lifetime management
3. Provide comprehensive error messages with suggestions
4. Add tests for both success and error cases
5. Update documentation for API changes

## Architecture Decisions

### Why Canonical Hashing?

The type system uses BLAKE3-based canonical hashing to achieve O(1) type deduplication and comparison, eliminating the O(N²) brute-force searches that plague traditional type systems.

### Why Multi-Pass Resolution?

Symbol resolution uses multiple passes to handle forward references and complex scoping scenarios while maintaining clear separation of concerns and predictable behavior.

### Why Profile-Based Validation?

Language profiles enable progressive disclosure of complexity, allowing users to start with simple subsets and gradually adopt more advanced features as needed.

## Troubleshooting

### Common Issues

**Slow semantic analysis**: Check for O(N²) algorithms in custom validation rules. Use the built-in profiling tools to identify bottlenecks.

**Memory leaks**: Ensure all semantic components use arena allocation. Run tests with leak detection enabled.

**Incorrect diagnostics**: Verify source span calculations and error recovery logic. Check that error suppression isn't hiding real issues.

### Debug Tools

```bash
# Enable semantic debugging
export JANUS_DEBUG_SEMANTIC=1

# Profile semantic performance
zig build benchmark-semantic

# Memory leak detection
zig build test-semantic -Dsanitize-memory=true
```

## Future Enhancements

- **Incremental Analysis** - Fine-grained incremental updates for large codebases
- **Parallel Validation** - Multi-threaded semantic analysis for improved performance
- **Advanced Diagnostics** - Machine learning-powered error suggestions
- **Cross-Language Analysis** - Semantic validation for foreign function interfaces

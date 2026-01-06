<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# RFC 0001: Dispatch Language Integration

- **Feature Name**: `dispatch-language-integration`
- **Start Date**: 2024-01-15
- **RFC PR**: (leave this empty)
- **Janus Issue**: (leave this empty)

## Summary

Integrate the completed multiple dispatch engine into the Janus language as a first-class feature, providing clean syntax, zero-overhead static dispatch, and comprehensive developer tooling.

## Motivation

We have built a world-class multiple dispatch engine in the lab. Now we need to make it the beating heart of Janus — not just technically excellent, but developer-beloved and production-proven.

### Why Multiple Dispatch in Janus?

1. **Syntactic Honesty**: Overloading should be explicit and transparent, not hidden behind compiler magic
2. **Performance Predictability**: Developers should know exactly when dispatch happens and what it costs
3. **Extensibility**: Libraries should be able to add overloads without modifying existing code
4. **Systems Programming**: Dispatch should have zero overhead when types are known statically

### Current State

The dispatch engine (`compiler/libjanus/`) provides:
- Zero-overhead static dispatch when types are known at compile time
- Sub-10ns runtime dispatch with intelligent caching and optimization
- Comprehensive debugging and profiling tools
- Advanced optimization including compression and JIT compilation

### What's Missing

- Language syntax for defining and using dispatch families
- Parser and AST integration
- LLVM backend integration for code generation
- Standard library adoption
- Developer tooling integration

## Detailed Design

### Language Syntax

#### Overload Definition

```janus
// Multiple implementations create a dispatch family
fn process(data: String) -> String {
    return "Processing string: " + data;
}

fn process(data: []u8) -> []u8 {
    return transform_bytes(data);
}

fn process(data: i32) -> String {
    return "Processing number: " + @toString(data);
}
```

#### Explicit Dispatch Control

```janus
// Static dispatch (compile-time resolved)
@static_dispatch
fn add(a: i32, b: i32) -> i32 { return a + b; }

// Runtime dispatch (always uses dispatch table)
@runtime_dispatch
fn format(value: anytype) -> String { ... }

// Dispatch hint (compiler chooses best strategy)
@dispatch_hint(.prefer_static)
fn compute(data: anytype) -> anytype { ... }
```

#### Dispatch Queries

```janus
// Query dispatch resolution at compile time
comptime {
    const resolution = @dispatch_query(process, .{String});
    @compileLog("process(String) resolves to:", resolution.implementation);
}

// Runtime dispatch introspection
const info = @dispatch_info(process, .{@TypeOf(data)});
std.debug.print("Dispatch took {} ns\n", .{info.resolution_time});
```

### Parser Integration

#### AST Nodes

```zig
// New AST node types
pub const DispatchFamily = struct {
    name: []const u8,
    implementations: []Implementation,
    dispatch_table: ?*OptimizedDispatchTable,
};

pub const DispatchCall = struct {
    family_name: []const u8,
    arguments: []Expression,
    resolution_strategy: ResolutionStrategy,
};

pub const ResolutionStrategy = enum {
    static,      // Compile-time resolution
    runtime,     // Always use dispatch table
    adaptive,    // Compiler chooses best strategy
};
```

#### Semantic Analysis

```zig
// Dispatch family analysis during semantic phase
pub fn analyzeDispatchFamily(sema: *Sema, family: *DispatchFamily) !void {
    // 1. Collect all implementations
    var implementations = ArrayList(Implementation).init(sema.allocator);
    for (family.implementations) |impl| {
        try implementations.append(try sema.analyzeImplementation(impl));
    }

    // 2. Check for ambiguities
    const ambiguities = try sema.checkAmbiguities(implementations.items);
    if (ambiguities.len > 0) {
        return sema.reportAmbiguousDispatch(ambiguities);
    }

    // 3. Build dispatch table
    family.dispatch_table = try sema.buildDispatchTable(implementations.items);

    // 4. Register with global dispatch registry
    try sema.dispatch_registry.registerFamily(family);
}
```

### LLVM Backend Integration

#### Static Dispatch Code Generation

```zig
// Generate direct function call for static dispatch
pub fn generateStaticDispatch(codegen: *CodeGen, call: *DispatchCall) !*llvm.Value {
    // Resolve implementation at compile time
    const impl = try codegen.resolveStaticDispatch(call);

    // Generate direct function call (zero overhead)
    return codegen.generateDirectCall(impl.function, call.arguments);
}
```

#### Runtime Dispatch Code Generation

```zig
// Generate dispatch table lookup for runtime dispatch
pub fn generateRuntimeDispatch(codegen: *CodeGen, call: *DispatchCall) !*llvm.Value {
    // Generate type hash for arguments
    const type_hash = try codegen.generateTypeHash(call.arguments);

    // Generate dispatch table lookup
    const dispatch_table = try codegen.getDispatchTable(call.family_name);
    const impl_ptr = try codegen.generateTableLookup(dispatch_table, type_hash);

    // Generate indirect function call
    return codegen.generateIndirectCall(impl_ptr, call.arguments);
}
```

### Standard Library Integration

#### Math Operations

```janus
// Replace manual type switching with clean dispatch
pub fn add(a: i8, b: i8) -> i8 { return a + b; }
pub fn add(a: i16, b: i16) -> i16 { return a + b; }
pub fn add(a: i32, b: i32) -> i32 { return a + b; }
pub fn add(a: i64, b: i64) -> i64 { return a + b; }
pub fn add(a: f32, b: f32) -> f32 { return a + b; }
pub fn add(a: f64, b: f64) -> f64 { return a + b; }

// String concatenation
pub fn add(a: String, b: String) -> String { return concat(a, b); }
pub fn add(a: []const u8, b: []const u8) -> []u8 { return concat_bytes(a, b); }
```

#### I/O Operations

```janus
// Format different types appropriately
pub fn format(value: i32) -> String { return std.fmt.parseInt(value); }
pub fn format(value: f64) -> String { return std.fmt.parseFloat(value); }
pub fn format(value: bool) -> String { return if (value) "true" else "false"; }
pub fn format(value: []const u8) -> String { return String.fromBytes(value); }

// Parse from strings with appropriate error handling
pub fn parse(comptime T: type, input: String) -> !T {
    return switch (T) {
        i32 => std.fmt.parseInt(i32, input, 10),
        f64 => std.fmt.parseFloat(f64, input),
        bool => parseBool(input),
        else => @compileError("Unsupported parse type: " ++ @typeName(T)),
    };
}
```

### Developer Tooling

#### CLI Integration

```bash
# Query dispatch families
$ janus query dispatch add
Dispatch Family: add
├── add(i32, i32) -> i32 [static, 0 overhead]
├── add(f64, f64) -> f64 [static, 0 overhead]
└── add(String, String) -> String [runtime, ~15ns]

# Profile dispatch performance
$ janus profile dispatch --live
[Live profiling enabled]
add(i32, i32): 1,247 calls/sec, 0ns dispatch overhead
format(String): 89 calls/sec, 12.3ns dispatch overhead
process([]u8): 23 calls/sec, 156.7ns dispatch overhead

# Analyze dispatch tables
$ janus analyze dispatch --memory-usage
Dispatch Table Memory Usage:
  add: 256 bytes (4 implementations)
  format: 1.2KB (12 implementations)
  process: 512 bytes (6 implementations)
Total: 1.97KB across 22 implementations
```

#### IDE Integration

```typescript
// VSCode extension features
export class JanusDispatchProvider implements vscode.HoverProvider {
    provideHover(document: vscode.TextDocument, position: vscode.Position): vscode.Hover {
        const symbol = getSymbolAtPosition(document, position);
        if (isDispatchCall(symbol)) {
            const dispatchInfo = queryDispatchInfo(symbol);
            return new vscode.Hover([
                `**Dispatch Family**: ${dispatchInfo.familyName}`,
                `**Resolution**: ${dispatchInfo.resolutionStrategy}`,
                `**Performance**: ${dispatchInfo.estimatedOverhead}`,
                `**Implementations**: ${dispatchInfo.implementationCount}`
            ]);
        }
    }
}
```

## Implementation Plan

### Phase 1: Core Integration (Month 1-2)

1. **Parser Extension**
   - Add dispatch family syntax to grammar
   - Implement AST nodes for dispatch constructs
   - Add semantic analysis for dispatch families

2. **Backend Integration**
   - Connect dispatch engine to LLVM codegen
   - Implement static dispatch code generation
   - Implement runtime dispatch code generation

3. **Basic Testing**
   - Unit tests for parser integration
   - Codegen tests for both static and runtime dispatch
   - Integration tests with simple examples

### Phase 2: Standard Library (Month 2-3)

1. **Math Operations**
   - Convert arithmetic operators to use dispatch
   - Implement proper numeric tower with dispatch
   - Performance benchmarks vs. current implementation

2. **String/Array Operations**
   - Convert string operations to use dispatch
   - Implement generic array operations with dispatch
   - Memory usage analysis and optimization

3. **I/O Operations**
   - Convert formatting functions to use dispatch
   - Implement parsing with dispatch-based error handling
   - Integration with existing I/O infrastructure

### Phase 3: Developer Experience (Month 3-4)

1. **CLI Tooling**
   - Implement `janus query dispatch` command
   - Add dispatch profiling capabilities
   - Create dispatch table analysis tools

2. **IDE Integration**
   - VSCode extension with dispatch highlighting
   - Hover information for dispatch calls
   - Interactive dispatch resolution debugging

3. **Documentation**
   - Comprehensive dispatch guide
   - Performance best practices
   - Migration guide from existing code

## Drawbacks

### Complexity
- Adds significant complexity to the language
- Developers need to understand dispatch semantics
- Potential for confusion between static and runtime dispatch

### Performance Concerns
- Runtime dispatch has inherent overhead
- Dispatch table memory usage
- Potential for performance regressions if used incorrectly

### Ecosystem Impact
- Existing code may need migration
- Library authors need to learn new patterns
- Potential fragmentation of approaches

## Rationale and Alternatives

### Why Multiple Dispatch?

**Alternative 1: Single Dispatch (like C++ virtual functions)**
- Pros: Simpler, well-understood, good performance
- Cons: Limited flexibility, requires inheritance hierarchies

**Alternative 2: Traits/Interfaces (like Rust/Go)**
- Pros: Explicit, good performance with monomorphization
- Cons: Verbose, orphan rule limitations, no runtime dispatch

**Alternative 3: Function Overloading (like C++)**
- Pros: Simple syntax, compile-time resolution
- Cons: No extensibility, limited to single module

**Why Multiple Dispatch Wins:**
- Combines flexibility of dynamic dispatch with performance of static
- Allows open extension without modifying existing code
- Provides both compile-time and runtime resolution strategies
- Enables clean, readable code without sacrificing performance

### Design Decisions

**Explicit vs. Implicit Dispatch**
- **Decision**: Make dispatch explicit in syntax
- **Rationale**: Aligns with Janus principle of syntactic honesty

**Static vs. Runtime Default**
- **Decision**: Compiler chooses best strategy by default
- **Rationale**: Optimize for performance while allowing developer control

**Dispatch Table Implementation**
- **Decision**: Use existing optimized dispatch engine
- **Rationale**: Leverage proven performance and debugging capabilities

## Prior Art

### Julia
- Excellent multiple dispatch semantics
- Performance issues due to dynamic nature
- Limited control over dispatch strategy

### Common Lisp (CLOS)
- Powerful multiple dispatch with method combinations
- Runtime-only dispatch
- Complex semantics

### Dylan
- Clean multiple dispatch syntax
- Good performance characteristics
- Limited adoption

### C++ Function Overloading
- Compile-time only
- No extensibility across modules
- Well-understood performance model

## Unresolved Questions

1. **Syntax Details**: Exact syntax for dispatch annotations and queries
2. **Error Messages**: How to present dispatch resolution errors clearly
3. **Debugging Integration**: How to integrate with existing debugger
4. **Performance Guarantees**: What performance promises can we make?
5. **Migration Path**: How to migrate existing overloaded functions?

## Future Possibilities

### AI-Guided Optimization
- Use machine learning to optimize dispatch table layouts
- Predict hot paths and pre-optimize dispatch resolution
- Automatic performance tuning based on usage patterns

### Distributed Dispatch
- Network-transparent dispatch across multiple nodes
- Load balancing based on implementation characteristics
- Fault tolerance and graceful degradation

### GPU Integration
- Automatic dispatch between CPU and GPU implementations
- Memory management for heterogeneous computing
- Performance modeling for execution target selection

---

This RFC establishes the foundation for transforming our lab-perfect dispatch engine into the beating heart of Janus. The key is maintaining our principles of syntactic honesty and performance predictability while providing the flexibility and extensibility that makes multiple dispatch powerful.

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Metadata and Comments Doctrine

## Core Principle

There is no distinction between "human documentation" and "machine-readable guides." All well-structured documentation is both. We are building a codebase where the documentation is so precise and structured that it becomes a secondary, queryable API for the code itself.

**Every file is a contract. Every header is a promise. Every assertion is a guarantee.**

## Comment Types and Their Purpose

Janus employs a hierarchical comment system where each type serves a specific purpose in the documentation ecosystem:

### 1. Module Headers (`//!`)

**Purpose**: Top-level file metadata that declares the module's purpose, requirements, and architectural promises.

**Placement**: Must be the first non-license content in every `.zig` and `.jan` file.

**Format**:
```zig
//! [Tool/Module Name] - [Task Reference]
//!
//! [Brief description of purpose and functionality]
//! [Additional context lines as needed]
//! Requirements: [Requirement IDs from specs]
//!
//! [ARCHITECTURAL ASSERTIONS - e.g., "ONLY ONE PURE INTEGRATION WITH LIBJANUS ASTDB - NO SECOND SEMANTICS"]
```

**Machine Processing**: These headers are parsed by the build system for:
- Requirement traceability verification
- Dependency analysis
- Documentation generation
- CI/CD compliance checking

### 2. Documentation Comments (`///`)

**Purpose**: Public API documentation that is extracted by the `janus doc` toolchain to generate user-facing documentation.

**Attachment**: A `///` doc comment applies to the **next item** that follows it (function, type, constant, etc.).

**Audience**: Written for **users** of your code, not implementers.

**Structure**:
```janus
/// Brief one-line description of what this does.
///
/// Longer explanation of the purpose, behavior, and usage patterns.
/// This section can span multiple paragraphs and should explain the
/// "what" and "why" rather than the "how".
///
/// **Parameters:**
///   - `param1`: Description of the first parameter
///   - `param2`: Description of the second parameter
///
/// **Returns:** Description of what is returned
///
/// **Examples:**
/// ```janus
/// let result = my_function(42, "hello");
/// ```
///
/// **Safety:** Any safety considerations or preconditions
/// **Errors:** What errors can be returned and when
func my_function(param1: i32, param2: String) -> Result[String, Error] do
    // Implementation...
end
```

### 3. Implementation Comments (`//`)

**Purpose**: Explain implementation details, algorithms, and design decisions for developers reading the code.

**Audience**: Written for **maintainers** and **contributors** to the codebase.

**Guidelines**:
- Explain **why** something is done, not **what** is being done
- Document non-obvious algorithms or optimizations
- Explain workarounds and their rationale
- Mark TODO items and technical debt

```janus
func complex_algorithm(data: []i32) -> i32 do
    // Using a two-pointer technique here because it reduces time complexity
    // from O(n²) to O(n log n) for this specific use case
    var left = 0;
    var right = data.len - 1;

    // TODO: This could be optimized further with SIMD instructions
    // See issue #123 for details
    while left < right do
        // ... implementation
    end
end
```

### 4. Architectural Comments (`// ARCHITECTURE:`)

**Purpose**: Document high-level design decisions and architectural constraints within implementation.

**Format**: Always prefixed with `// ARCHITECTURE:` for easy searching and tooling.

```janus
func parse_expression(tokens: []Token) -> AstNode do
    // ARCHITECTURE: We use recursive descent here instead of operator
    // precedence parsing to maintain consistency with the error recovery
    // strategy defined in the language specification section 4.2

    // ARCHITECTURE: Memory allocation strategy - all AST nodes use
    // the arena allocator passed in context to ensure O(1) cleanup
    var arena = context.allocator.arena();

    // ... implementation
end
```

## Header Components Deep Dive

### 1. Task Linkage

Links code directly to strategic objectives in the project roadmap.

**Format**: `//! [Component Name] - [Task Reference]`

**Examples**:
- `//! Golden CIDs Tool - Task 4.1`
- `//! ASTDB Query Engine - Task 2.1`
- `//! Memory Manager - Core Infrastructure`

**Machine Processing**: Enables automated verification that code addresses its intended purpose and maintains traceability to project goals.

### 2. Requirement Traceability

Makes success criteria machine-parsable and creates bidirectional traceability.

**Format**: `//! Requirements: [Requirement IDs]`

**Examples**:
- `//! Requirements: E-1, E-2, E-4`
- `//! Requirements: SPEC-stdlib-core, SPEC-profiles`
- `//! Requirements: SEC-001, PERF-003`

**Machine Processing**: CI scripts verify that:
- All referenced requirements exist in project specs
- Code changes align with requirement modifications
- Coverage reports show which requirements are implemented

### 3. Architectural Assertions

Document critical design decisions and constraints as enforceable promises.

**Purpose**: Provide guarantees that AI can trust and humans can enforce.

**Format**: All-caps statements that declare architectural invariants.

**Examples**:
- `//! REAL INTEGRATION WITH LIBJANUS ASTDB - NO SECOND SEMANTICS`
- `//! GRANITE-SOLID QUERY PURITY - NO I/O IN QUERY EXECUTION`
- `//! ALLOCATOR SOVEREIGNTY - EXPLICIT MEMORY LIFECYCLE CONTRACTS`
- `//! ZERO-COPY PARSING - NO INTERMEDIATE STRING ALLOCATIONS`

## Documentation Patterns by Component Type

### Tools and Utilities

```zig
//! Golden CIDs Tool - Task 4.1
//!
//! Generates golden CID references for ASTDB invariance testing
//! Inputs: list of source files; flags: --deterministic, --profile=<p>
//! Outputs: cids.json with { unit, items: [{name, cid}] }
//! Requirements: E-1, E-2, E-4
//!
//! REAL INTEGRATION WITH LIBJANUS ASTDB - NO SECOND SEMANTICS

/// Command-line interface for the golden CIDs generation tool.
///
/// This tool creates deterministic content-addressed identifiers (CIDs)
/// for source files to enable incremental compilation and change detection.
///
/// **Usage:**
/// ```bash
/// janus golden-cids src/*.jan --deterministic --profile=min
/// ```
///
/// **Output Format:**
/// The tool generates a `cids.json` file with the following structure:
/// ```json
/// {
///   "unit": "my_project",
///   "items": [
///     {"name": "main.jan", "cid": "bafk..."},
///     {"name": "lib.jan", "cid": "bafk..."}
///   ]
/// }
/// ```
pub fn main() !void {
    // Implementation...
}
```

### Library Modules

```zig
//! ASTDB Query Engine - Task 2.1
//!
//! Core query infrastructure for LSP and semantic analysis
//! Implements predicates, combinators, and memoization system
//! Requirements: E-3, E-7, E-8
//!
//! GRANITE-SOLID QUERY PURITY - NO I/O IN QUERY EXECUTION

/// A query predicate that can be evaluated against AST nodes.
///
/// Predicates are pure functions that take an AST node and return
/// a boolean result. They form the foundation of the query system
/// and can be combined using logical operators.
///
/// **Purity Guarantee:** All predicates are pure functions with no
/// side effects. They do not perform I/O, allocate memory, or
/// modify global state.
///
/// **Examples:**
/// ```janus
/// let is_function = Predicate.node_type(.function_decl);
/// let has_pub_modifier = Predicate.has_modifier(.pub);
/// let public_functions = is_function.and(has_pub_modifier);
/// ```
pub const Predicate = struct {
    // Implementation...
};
```

### Standard Library Components

```janus
//! Core Types Module - Standard Library Foundation
//!
//! Foundational types including Allocator trait, capability system, and error handling
//! Implements tri-signature pattern for profile compatibility
//! Requirements: SPEC-stdlib-core, SPEC-profiles
//!
//! ALLOCATOR SOVEREIGNTY - EXPLICIT MEMORY LIFECYCLE CONTRACTS

/// The fundamental allocator trait that all memory allocators must implement.
///
/// This trait defines the contract for memory allocation and deallocation
/// in Janus. All allocators must provide explicit, trackable memory
/// lifecycle management.
///
/// **Memory Safety:** All allocations through this interface are tracked
/// and can be verified for leaks in debug builds.
///
/// **Profile Compatibility:** This trait works across all Janus profiles
/// (:core, :service, :cluster, :sovereign) with identical semantics.
///
/// **Examples:**
/// ```janus
/// using allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
/// defer allocator.deinit();
///
/// let data = try allocator.alloc(u8, 1024);
/// // Memory automatically freed when allocator goes out of scope
/// ```
pub trait Allocator {
    /// Allocate memory for `n` items of type `T`.
    ///
    /// **Parameters:**
    ///   - `T`: The type of items to allocate
    ///   - `n`: Number of items to allocate
    ///
    /// **Returns:** A slice of allocated memory or an allocation error
    ///
    /// **Errors:**
    ///   - `OutOfMemory`: Insufficient memory available
    ///   - `InvalidSize`: Requested size is invalid (e.g., zero or too large)
    func alloc(comptime T: type, n: usize) -> AllocError![]T;

    /// Free previously allocated memory.
    ///
    /// **Safety:** The memory must have been allocated by this allocator
    /// and must not be used after this call.
    func free(memory: anytype) -> void;
}
```

## Enforcement and Tooling

### Pre-commit Hooks

The build system includes automated checks that verify:

1. **Header Compliance**: All `.zig` and `.jan` files have proper module headers
2. **Requirement Validation**: All referenced requirement IDs exist in project specs
3. **Architectural Assertion Consistency**: Assertions follow established patterns
4. **Documentation Coverage**: Public APIs have complete `///` documentation

### CI/CD Integration

Continuous integration pipelines automatically:

1. **Generate Documentation**: Extract `///` comments to build API docs
2. **Verify Traceability**: Create requirement-to-implementation mapping
3. **Check Consistency**: Validate that architectural assertions match implementation
4. **Report Coverage**: Identify undocumented public APIs

### Development Tools

The Janus toolchain provides:

1. **`janus doc`**: Generate HTML documentation from `///` comments
2. **`janus check-headers`**: Validate module header compliance
3. **`janus trace-requirements`**: Show requirement-to-code mapping
4. **`janus lint-comments`**: Check comment style and completeness

## Migration Strategy

### For New Code

All new files MUST use the complete metadata format from day one:

1. Start with the mandatory module header
2. Add `///` documentation for all public APIs
3. Use `//` comments to explain complex implementation details
4. Include `// ARCHITECTURE:` comments for design decisions

### For Existing Code

Update files incrementally in order of importance:

1. **Critical APIs**: Core interfaces and public modules first
2. **Library Components**: Standard library and shared utilities
3. **Tools and Scripts**: Command-line tools and build scripts
4. **Tests and Examples**: Test suites and example code

### Automated Assistance

Use the provided tools to help with migration:

```bash
# Generate skeleton headers for existing files
janus generate-headers src/

# Check current compliance status
janus check-headers --report

# Validate requirement references
janus trace-requirements --verify
```

## The Standard is Absolute

This metadata and comment system is the mandatory standard for every source file in the Janus project. We are not just writing code; we are creating self-describing semantic artifacts that serve both human understanding and machine processing.

The Doctrine of Metadata and Comments transforms our codebase into a living, queryable knowledge base where documentation and code exist in perfect harmony.

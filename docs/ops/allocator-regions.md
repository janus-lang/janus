<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Allocator Contexts, Regions, and Using - Compiler Integration

This document describes the compiler integration for the allocator contexts, regions, and using blocks feature in the Janus programming language.

## Overview

The feature introduces:
- **Allocator contexts** - Allocator-bound data structures
- **Region-based memory management** - Scoped arenas with automatic cleanup
- **Using blocks** - Deterministic cleanup for resources
- **Profile gating** - Different behavior in different language profiles

## Compiler Integration

### Semantic Analysis
1. **Allocator Contexts**: The semantic analyzer tracks allocator contexts and ensures they are properly passed and used.
2. **Region Escape Detection**: The analyzer performs escape analysis to prevent references to region-allocated memory from escaping the region scope.
3. **Using Blocks**: The analyzer ensures that using blocks are properly structured and that drop operations are idempotent.
4. **Profile Gating**: The analyzer enforces profile-specific rules:
   - `:core` profile: Region and using blocks are disabled
   - `:script` profile: Region and using blocks are enabled with thread-local region
   - `:service`, `:cluster`, `:sovereign` profiles: All features are available

### Effect System Integration
1. **Allocation Effects**: The compiler tracks allocation operations and adds the `allocates` effect to function signatures.
2. **Capability Tracking**: The compiler tracks required capabilities for memory operations and ensures they are available.

### Code Generation
1. **Allocator Contexts**: The code generator ensures that allocator contexts are properly passed to functions.
2. **Region Management**: The code generator implements region creation and cleanup.
3. **Using Blocks**: The code generator implements the drop logic for using blocks.

## Performance

The feature is designed to have minimal performance overhead:
- **Allocator Contexts**: Less than 1% overhead compared to explicit allocator passing
- **Region Management**: Amortized O(1) allocation and free
- **Using Blocks**: Zero overhead compared to manual drop when optimizations are enabled

## Examples

### Basic Usage
```janus
// :core profile - only basic allocator contexts
func main() {
    let alloc = Allocator.create(heap);
    let list = List.with(alloc, 10);
    // ...
}
```

### Region Usage
```janus
// :script profile - region blocks enabled
func main() {
    region temp {
        let buffer = Buffer.with(temp_allocator, 100);
        // ...
    } // buffer is automatically cleaned up
}
```

### Using Blocks
```janus
// :sovereign profile - using blocks enabled
func main() {
    using file = open_file("test.txt") {
        // use file
    } // file is automatically closed
}
```

## Migration

Existing code can be migrated by:
1. Replacing explicit allocator passing with allocator contexts
2. Replacing manual cleanup with using blocks
3. Replacing manual memory management with regions

## Tests

The feature includes comprehensive tests:
- **Semantic Analysis**: Tests for allocator contexts, region escape detection, and using blocks
- **Effect System**: Tests for allocation effects and capability tracking
- **Code Generation**: Tests for allocator contexts, region management, and using blocks
- **Performance**: Tests to ensure minimal performance overhead
- **Migration**: Tests to ensure backward compatibility

## Performance Optimizations

1. **Allocator Contexts**: Optimized to minimize overhead
2. **Region Management**: Optimized for fast allocation and cleanup
3. **Using Blocks**: Optimized for zero overhead when possible

## Documentation

- **API Documentation**: Complete API documentation for all new types and functions
- **Examples**: Comprehensive examples for all features
- **Migration Guide**: Step-by-step guide for migrating existing code
- **Performance Guide**: Guide for optimizing performance

## Error Messages

The compiler provides clear error messages for:
- **Allocator Contexts**: Missing or incorrect allocator contexts
- **Region Escape**: References to region-allocated memory escaping the region scope
- **Using Blocks**: Incorrect using block usage
- **Profile Gating**: Features not available in the current profile

## Implementation Status

- **Core Infrastructure**: Complete
- **Collections**: Complete
- **Compiler Integration**: Complete
- **Tests**: Complete
- **Documentation**: Complete
- **Performance Optimizations**: Complete

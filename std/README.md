<!--
SPDX-License-Identifier: LSL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Standard Library Core

The Janus Standard Library Core embodies our foundational doctrines in practical, usable APIs. These modules serve as the canonical examples of how Janus approaches systems programming through superior architecture rather than defensive programming.

## Modules

### `std/core.jan` - Foundational Types and Allocator Infrastructure

The core module establishes the fundamental contracts that all other modules build upon:

- **Allocator Trait**: The sovereign contract over memory regions
- **ArenaAllocator**: Append-only allocator with O(1) cleanup for fixed-lifecycle data
- **GeneralPurposeAllocator**: Traditional allocator supporting individual alloc/free cycles
- **Capability Types**: Base types for capability-based security
- **Memory Utilities**: Low-level operations that respect allocator sovereignty

### `std/io.jan` - Capability-Gated I/O Operations

The I/O module demonstrates capability-based security and explicit resource management with full POSIX compliance:

- **Capability Types**: `FileReadCapability`, `FileWriteCapability`, `StdinReadCapability`, `StdoutWriteCapability`, `StderrWriteCapability`
- **Error Types**: Rich, domain-specific errors with context (`IoError`)
- **File Operations**: All operations require explicit capabilities and allocators
- **Streaming I/O**: Zero-copy operations with explicit buffer management
- **Standard Streams**: Capability-gated access to stdin/stdout/stderr
- **POSIX Compliance**: Full support for POSIX file types, permissions, and modes
- **File Types**: Complete coverage of POSIX file types including devices, IPC, and platform-specific extensions
- **Permissions**: POSIX permission bits with setuid/setgid/sticky bit support

### `std/string.jan` - Encoding-Honest String Operations

The string module eliminates entire classes of encoding bugs through design:

- **String Type**: Explicit encoding information and allocator tracking
- **Encoding Types**: `Utf8`, `Ascii`, `Latin1`, `Bytes` with explicit semantics
- **Error Types**: Position-aware errors for debugging (`StringError`)
- **Boundary Safety**: UTF-8 operations respect codepoint boundaries
- **Zero-Copy Operations**: Slicing and iteration without unnecessary allocation
- **String Building**: Explicit allocator control for dynamic construction

### `std/time.jan` - Time and Duration Operations

The time module provides essential time utilities for the :core profile:

- **System Time**: Unix timestamps in seconds, milliseconds, microseconds, nanoseconds
- **Monotonic Time**: High-resolution clocks that never go backwards (for benchmarking)
- **Sleep Operations**: Pause execution for specified durations
- **Duration Calculations**: Convert between time units, calculate elapsed time
- **Calendar Functions**: Leap year detection, days in month, year extraction
- **Constants**: Common time units (MS_PER_SECOND, SECS_PER_DAY, etc.)

**Example Usage**:
```janus
import std.core.time

func benchmarkExample() do
    let start = time.monotonic_millis()
    
    // ... some work ...
    
    let elapsed = time.elapsed_millis(start, time.monotonic_millis())
    io.println("Operation took: " + convert.toString(elapsed) + " ms")
end
```

## Design Principles

### Allocator Sovereignty

Every function that allocates memory accepts an explicit `Allocator` parameter. This enables:

- **Arena-based patterns** for fixed-lifecycle data with O(1) cleanup
- **Individual allocation patterns** for dynamic data structures
- **Memory lifecycle congruence** between data structures and their allocators
- **Zero memory leaks** through architectural design

### Capability Security

All external resource access is gated behind explicit capabilities:

- **Compile-time enforcement** of resource access permissions
- **Auditable resource usage** through capability flow tracking
- **Principle of least privilege** through granular capability types
- **Security by design** rather than runtime checking

### Error Transparency

All failure modes are explicit in function signatures:

- **Rich error types** with context for debugging and user messages
- **Domain-specific errors** grouped by functional area
- **Error composition** through union types
- **No hidden failures** or exceptions

### Zero-Copy Bias

Operations avoid unnecessary data movement:

- **String slicing** creates views without copying
- **Buffer operations** work on provided memory
- **Iterator patterns** traverse data in-place
- **Explicit copying** when data movement is required

### Encoding Honesty

String operations are explicit about encoding assumptions:

- **Encoding information** carried in the type system
- **UTF-8 validation** with detailed error reporting
- **Boundary safety** for all string operations
- **Explicit conversion** between encodings

## Usage Patterns

### Arena-Based Processing

```janus
func processFile(arena_buffer: []u8, path: String, read_cap: FileRead) -> IoError!String do
    var arena = ArenaAllocator.init(arena_buffer);
    let alloc = arena.allocator();

    // All allocations go to arena
    let content = io.readFile(alloc, path, read_cap)?;
    let text = string.fromUtf8(alloc, content.data)?;
    let processed = processText(alloc, text)?;

    // O(1) cleanup when arena goes out of scope
    return processed;
end
```

### Capability Flow

```janus
func secureOperation(
    allocator: Allocator,
    input_path: String,
    output_path: String,
    read_cap: FileRead,
    write_cap: FileWrite
) -> (IoError | StringError)!void do
    let content = io.readFile(allocator, input_path, read_cap)?;
    defer content.deinit();

    let text = string.fromUtf8(allocator, content.data)?;
    defer text.deinit();

    let processed = processSecurely(allocator, text)?;
    defer processed.deinit();

    io.writeFile(output_path, WriteBuffer{.data = processed.bytes}, write_cap)?;
end
```

### Error Handling

```janus
func robustStringOperation(allocator: Allocator, input: []const u8) -> void do
    let result = string.fromUtf8(allocator, input) catch |err| do
        switch (err) {
            .InvalidUtf8 => |info| {
                stderr.write("Invalid UTF-8 at position {}: {:02x}\n",
                           info.position, info.bytes[0]);
                return;
            },
            .OutOfBounds => |info| {
                stderr.write("Memory allocation failed: {} bytes\n", info.length);
                return;
            }
        }
    end;
    defer result.deinit();

    // Process valid UTF-8 string...
end
```

## Testing

The `std/test_core_infrastructure.jan` file provides comprehensive validation of all core patterns:

- Allocator sovereignty compliance
- Capability gating enforcement
- Error transparency verification
- Zero-copy operation validation
- Encoding honesty confirmation

Run tests with:
```bash
janus test std/test_core_infrastructure.jan
```

## Implementation Status

This is the foundational infrastructure for the Janus Standard Library. The core types and patterns are established, with implementation details to be provided by the compiler backend through `@extern` declarations.

The modules demonstrate our architectural doctrines in concrete, usable form while remaining minimal and composable. They serve as the foundation for all higher-level functionality in the Janus ecosystem.

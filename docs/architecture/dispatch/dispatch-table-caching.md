<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Dispatch Table Caching and Serialization

This document describes the dispatch table caching and serialization system in Janus, which provides significant build performance improvements through intelligent caching of compiled dispatch tables.

## Overview

The dispatch table caching system allows the Janus compiler to serialize optimized dispatch tables to disk and reuse them across builds, dramatically reducing compilation time for incremental builds. The system includes:

- **Serialization**: Efficient binary format for storing dispatch tables
- **Cache Management**: Intelligent cache invalidation and cleanup
- **Build Integration**: Seamless integration with the build system
- **Dependency Tracking**: Automatic invalidation when dependencies change

## Architecture

### Core Components

```
┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐
│ DispatchTableSerializer │    │ BuildCacheManager    │    │ DependencyTracker   │
├─────────────────────┤    ├──────────────────────┤    ├─────────────────────┤
│ - Serialize tables  │    │ - Build sessions     │    │ - Track file deps   │
│ - Deserialize tables│    │ - Cache integration  │    │ - Invalidate cache  │
│ - Cache management  │    │ - Performance metrics│    │ - Change detection  │
│ - Format versioning │    │ - Optimization       │    │ - Dependency graph  │
└─────────────────────┘    └──────────────────────┘    └─────────────────────┘
```

### Serialization Format

The dispatch table cache uses a custom binary format optimized for fast loading:

```
┌─────────────────────────────────────────────────────────────────┐
│                        File Header                              │
├─────────────────────────────────────────────────────────────────┤
│ Magic Number (4 bytes) │ Format Version (4 bytes)              │
│ Table Hash (8 bytes)   │ Creation Timestamp (8 bytes)          │
│ Signature Name Length  │ Type Signature Length                 │
│ Entry Count           │ Optimization Type                      │
│ Compression Ratio     │ Memory Saved                           │
│ Metadata Checksum     │ Data Checksum                          │
├─────────────────────────────────────────────────────────────────┤
│                     Variable-Length Data                       │
├─────────────────────────────────────────────────────────────────┤
│ Signature Name        │ Type Signature                         │
│ Dispatch Entries      │ Decision Tree (optional)               │
│ Compression Data      │ (if compressed)                        │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

### Basic Caching

```zig
const std = @import("std");
const DispatchTableSerializer = @import("dispatch_table_serialization.zig").DispatchTableSerializer;

// Initialize serializer
var serializer = try DispatchTableSerializer.init(allocator, ".janus_cache");
defer serializer.deinit();

// Serialize a dispatch table
const cache_path = try serializer.serializeTable(dispatch_table, optimization_result);
defer allocator.free(cache_path);

// Check if table is cached
const is_cached = try serializer.isCached(dispatch_table);

// Deserialize from cache
const cache_key = try serializer.calculateCacheKey(dispatch_table);
if (try serializer.deserializeTable(cache_key, type_registry)) |cached_table| {
    defer cached_table.deinit();
    // Use cached table
}
```

### Build System Integration

```zig
const BuildCacheManager = @import("build_cache_integration.zig").BuildCacheManager;

// Initialize build cache manager
const config = try BuildCacheManager.CacheConfig.default(allocator);
var cache_manager = try BuildCacheManager.init(allocator, config);
defer cache_manager.deinit();

// Start build session
try cache_manager.startBuildSession();

// Get or build dispatch table (automatically uses cache)
const table = try cache_manager.getOrBuildDispatchTable(
    "my_function",
    type_signature,
    type_registry,
    buildDispatchTableFn
);

// End build session
try cache_manager.endBuildSession();

// Generate build report
try cache_manager.generateBuildReport(std.io.getStdOut().writer());
```

## Configuration

### Cache Configuration

```zig
const config = BuildCacheManager.CacheConfig{
    .cache_directory = ".janus_cache/dispatch_tables",
    .max_cache_size_bytes = 100 * 1024 * 1024, // 100MB
    .max_cache_age_seconds = 7 * 24 * 60 * 60, // 1 week
    .enable_compression = true,
    .enable_incremental_updates = true,
    .cache_cleanup_interval_seconds = 24 * 60 * 60, // Daily
};
```

### Environment Variables

- `JANUS_CACHE_DIR`: Override default cache directory
- `JANUS_CACHE_SIZE`: Maximum cache size in bytes
- `JANUS_CACHE_DISABLE`: Disable caching entirely
- `JANUS_CACHE_VERBOSE`: Enable verbose cache logging

## Performance Characteristics

### Serialization Performance

- **Small tables** (< 10 entries): ~50μs serialization, ~30μs deserialization
- **Medium tables** (10-100 entries): ~200μs serialization, ~100μs deserialization
- **Large tables** (100+ entries): ~1ms serialization, ~500μs deserialization

### Cache Hit Ratios

Typical cache hit ratios in real projects:

- **Clean builds**: 0% (no cache)
- **Incremental builds**: 80-95%
- **Partial rebuilds**: 60-80%
- **Full rebuilds**: 0-20%

### Build Speedup

Expected build speedup with caching enabled:

- **Small projects**: 1.5-2x faster
- **Medium projects**: 2-4x faster
- **Large projects**: 3-8x faster

## Cache Management

### Automatic Cleanup

The cache system automatically performs cleanup based on:

- **Age**: Remove entries older than configured maximum age
- **Size**: Remove least recently used entries when cache exceeds size limit
- **Validity**: Remove entries with invalid checksums or incompatible versions

### Manual Cache Operations

```bash
# Clear all cached dispatch tables
janus cache clear

# Show cache statistics
janus cache stats

# Validate cache integrity
janus cache validate

# Optimize cache layout
janus cache optimize
```

## Dependency Tracking

### File Dependencies

The system tracks dependencies at multiple levels:

1. **Source file dependencies**: Import relationships between Janus files
2. **Type dependencies**: Changes to type definitions that affect dispatch
3. **Module dependencies**: Cross-module dispatch table dependencies
4. **Build configuration**: Compiler flags and optimization settings

### Invalidation Strategy

Cache entries are invalidated when:

- Source files are modified (timestamp or content hash changes)
- Dependencies are modified (transitive invalidation)
- Type definitions change (affects dispatch resolution)
- Compiler version changes (format compatibility)
- Build configuration changes (optimization settings)

## Troubleshooting

### Common Issues

#### Cache Misses

**Symptoms**: Low cache hit ratio, slow incremental builds

**Causes**:
- Frequent changes to widely-used modules
- Unstable build configuration
- Cache size too small
- Aggressive cleanup settings

**Solutions**:
- Increase cache size limit
- Reduce cleanup frequency
- Stabilize build configuration
- Use more specific dependency tracking

#### Cache Corruption

**Symptoms**: Deserialization errors, checksum failures

**Causes**:
- Disk corruption
- Concurrent access issues
- Format version mismatches
- Incomplete writes

**Solutions**:
- Clear cache and rebuild
- Check disk health
- Ensure single build process
- Update compiler version

#### Performance Degradation

**Symptoms**: Slower builds with caching enabled

**Causes**:
- Cache directory on slow storage
- Very large cache files
- Excessive cache lookup overhead
- Network-mounted cache directory

**Solutions**:
- Move cache to faster storage (SSD)
- Reduce cache size or enable compression
- Optimize cache index structure
- Use local cache directory

### Debugging

Enable verbose logging:

```bash
export JANUS_CACHE_VERBOSE=1
janus build
```

Check cache statistics:

```zig
const stats = serializer.getStats();
std.debug.print("Cache stats: {}\n", .{stats});
```

Validate cache integrity:

```zig
try serializer.generateCacheReport(std.io.getStdOut().writer());
```

## Best Practices

### Cache Directory Location

- **Local SSD**: Best performance for single-developer workflows
- **Shared network storage**: Good for team builds with shared cache
- **RAM disk**: Fastest but volatile (lost on reboot)
- **Avoid**: Slow network drives, encrypted filesystems

### Cache Size Management

- **Small projects** (< 1000 functions): 10-50MB cache
- **Medium projects** (1000-10000 functions): 50-200MB cache
- **Large projects** (> 10000 functions): 200MB-1GB cache

### Dependency Optimization

- Minimize cross-module dependencies
- Use stable interfaces for widely-used modules
- Group related functions in the same module
- Avoid circular dependencies

### Build Configuration

- Use consistent compiler flags across builds
- Pin dependency versions in production
- Separate debug and release caches
- Use build-specific cache directories for different targets

## Implementation Details

### Serialization Format

The binary format is designed for:

- **Fast loading**: Minimal parsing required
- **Compact size**: Efficient storage with optional compression
- **Version compatibility**: Forward and backward compatibility
- **Integrity checking**: Checksums prevent corruption

### Cache Index

The cache index uses:

- **Hash-based lookup**: O(1) cache key resolution
- **LRU eviction**: Least recently used entries removed first
- **Metadata caching**: File stats cached to avoid filesystem calls
- **Batch operations**: Multiple cache operations grouped for efficiency

### Compression

Optional compression using:

- **LZ4**: Fast compression/decompression for development builds
- **Zstandard**: Better compression ratio for production builds
- **Custom**: Domain-specific compression for dispatch table patterns

## Future Enhancements

### Planned Features

- **Distributed caching**: Share cache across build machines
- **Incremental serialization**: Update cache entries without full rewrite
- **Predictive caching**: Pre-build likely-needed dispatch tables
- **Cache analytics**: Detailed performance analysis and optimization suggestions

### Research Areas

- **Machine learning**: Predict optimal cache strategies
- **Compression**: Specialized compression for dispatch table patterns
- **Parallelization**: Concurrent cache operations
- **Cloud integration**: Remote cache storage and synchronization

## Conclusion

The dispatch table caching system provides significant build performance improvements for Janus projects through intelligent serialization and cache management. By understanding the system's architecture and following best practices, developers can achieve optimal build performance while maintaining correctness and reliability.

For more information, see:

- [Multiple Dispatch System Documentation](multiple-dispatch-guide.md)
- [Build System Integration Guide](build-system-integration.md)
- [Performance Optimization Guide](dispatch-performance-guide.md)

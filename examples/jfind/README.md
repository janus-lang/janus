<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# jfind - Fast File Finder

`jfind` is the first canonical application written in Janus using the `:min` profile. It serves as both a practical file discovery utility and a reference implementation demonstrating idiomatic Janus programming patterns.

## Overview

`jfind` is designed as a fast, dependency-free replacement for the standard Unix `find` utility, optimized for the 80% of common use cases that system administrators and developers encounter daily. It showcases Janus's capability to produce high-performance system utilities while maintaining code clarity and safety.

## Features

- **Fast Directory Traversal**: Pruned depth-first search with configurable depth limits
- **Extension Filtering**: O(1) extension matching using hashsets
- **Deterministic Output**: Sorted results for reliable scripting and pipelines
- **Memory Efficient**: O(M + D) memory usage where M=matches, D=depth
- **Cross-Platform**: Works on Linux, macOS, and Windows
- **Simple Interface**: Intuitive command-line interface following Unix conventions

## Usage

```bash
# Find all files in a directory
jfind /path/to/search

# Find files containing a specific string
jfind /path/to/search "pattern"

# Filter by file extensions
jfind /path/to/search --ext=jpg,png,gif

# Limit search depth
jfind /path/to/search --max-depth=3

# Include hidden files
jfind /path/to/search --hidden

# Case-insensitive matching
jfind /path/to/search "Pattern" --ignore-case

# Skip sorting for maximum speed
jfind /path/to/search --no-sort
```

## Building

Currently, `jfind` is implemented in Janus and requires the Janus compiler. Once the Janus toolchain is complete, you can build it with:

```bash
janus build --profile=min
```

## Architecture

`jfind` demonstrates several key Janus concepts:

- **`:min` Profile Compliance**: Uses only features available in the minimal Janus profile
- **Arena Allocation**: Automatic memory management with predictable cleanup
- **Error Handling**: Explicit error types with contextual information
- **Modular Design**: Clean separation of concerns across modules
- **Performance Focus**: Algorithmic optimizations for real-world performance

## Modules

- `main.jan` - Entry point and command-line interface
- `walker.jan` - Directory traversal with pruned DFS
- `filter.jan` - High-performance file filtering
- `output.jan` - Result formatting and deterministic output

## Performance

`jfind` is designed to outperform traditional `find` for common use cases:

- **Extension Filtering**: O(1) vs O(n) pattern matching
- **Memory Usage**: Minimal memory footprint with streaming processing
- **Startup Time**: Fast startup with no unnecessary initialization
- **I/O Efficiency**: Optimized system call patterns

## Educational Value

As the first canonical Janus application, `jfind` serves as:

- **Reference Implementation**: Demonstrates idiomatic `:min` profile code
- **Learning Tool**: Shows real-world systems programming in Janus
- **Performance Example**: Illustrates how to write fast, efficient utilities
- **Testing Ground**: Validates the `:min` profile and standard library

## Status

🚧 **Under Development** - This is currently a work-in-progress implementation as part of the Janus language development. The code structure and interfaces are in place, but full functionality requires completion of the Janus standard library.

## License

Licensed under the Apache License, Version 2.0. See the license headers in individual source files for details.

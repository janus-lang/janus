#!/usr/bin/env python3

import re

# Read the build.zig file
with open('build.zig', 'r') as f:
    content = f.read()

# Remove obsolete test sections and their references
obsolete_patterns = [
    r'run_optimized_validation_tests',
    r'run_arena_validation_tests',
    r'run_validation_cache_tests',
    r'run_performance_benchmark_tests',
    r'run_arena_integration_tests',
    r'run_arena_memory_tests',
    r'run_validation_benchmarks',
    r'run_standalone_arena_tests'
]

# Remove lines containing these patterns
lines = content.split('\n')
cleaned_lines = []

skip_section = False
for line in lines:
    # Check if we should skip this line
    should_skip = False
    for pattern in obsolete_patterns:
        if pattern in line:
            should_skip = True
            break

    # Skip test sections that reference deleted files
    if any(deleted_file in line for deleted_file in [
        'validation_engine_optimized.zig',
        'validation_engine_arena.zig',
        'validation_engine_arena_integration.zig',
        'validation_cache_system.zig',
        'validation_performance_benchmark.zig',
        'test_validation_engine_arena_memory.zig',
        'test_arena_validation_standalone.zig',
        'validation_memory_benchmarks.zig',
        'test_validation_engine_simple_integration.zig'
    ]):
        should_skip = True

    if not should_skip:
        cleaned_lines.append(line)

# Write the cleaned content back
with open('build.zig', 'w') as f:
    f.write('\n'.join(cleaned_lines))

print("✅ Cleaned up build.zig")
# ArrayList Migration Script for Zig 0.16
# Auto-migrates .init(allocator) → .empty pattern
# Based on DOCTRINE_ARRAYLIST_ZIG_0.15.2.md

#!/bin/bash
set -e

echo "=== ArrayList Migration to Zig 0.16 ==="
echo ""

# Count files affected
TOTAL=$(find . -name "*.zig" -exec grep -l "\.init(.*allocator.*)" {} \; | wc -l)
echo "Files to migrate: $TOTAL"
echo ""

# Dry run first
echo "DRY RUN - Showing changes that would be made:"
echo ""

find . -name "*.zig" -exec grep -l "ArrayList.*\.init(" {} \; | head -5 | while read file; do
    echo "File: $file"
    grep -n "ArrayList.*\.init(" "$file" | head -3
    echo ""
done

echo "Run with --execute to apply changes"

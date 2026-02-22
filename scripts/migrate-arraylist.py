#!/usr/bin/env python3
"""
ArrayList Migration Script for Zig 0.16
Based on DOCTRINE_ARRAYLIST_ZIG_0.15.2.md

Patterns:
1. var list = ArrayList(T).init(alloc) → var list: ArrayList(T) = .empty
2. list.deinit() → list.deinit(alloc)
3. list.toOwnedSlice() → list.toOwnedSlice(alloc)
"""

import re
import sys
from pathlib import Path

def migrate_file(filepath):
    """Migrate a single file"""
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    
    # Pattern 1: ArrayList declaration
    # var name = std.ArrayList(Type).init(alloc)
    content = re.sub(
        r'var\s+(\w+)\s*=\s*std\.ArrayList\(([^)]+)\)\.init\(([^)]+)\)',
        r'var \1: std.ArrayList(\2) = .empty',
        content
    )
    
    # Pattern 2: errdefer deinit()
    # errdefer name.deinit() → errdefer name.deinit(alloc)
    # This is tricky - we need to know the allocator name
    # For now, use a heuristic: find the allocator parameter name
    
    # Pattern 3: toOwnedSlice()
    # return name.toOwnedSlice() → return try name.toOwnedSlice(alloc)
    content = re.sub(
        r'return\s+(\w+)\.toOwnedSlice\(\)',
        r'return try \1.toOwnedSlice(alloc)',
        content
    )
    
    if content != original:
        # Create backup
        backup = filepath + '.backup'
        with open(backup, 'w') as f:
            f.write(original)
        
        # Write migrated content
        with open(filepath, 'w') as f:
            f.write(content)
        
        return True
    return False

def main():
    if len(sys.argv) < 2:
        print("Usage: migrate-arraylist.py <file.zig>")
        sys.exit(1)
    
    filepath = sys.argv[1]
    if migrate_file(filepath):
        print(f"✅ Migrated: {filepath}")
    else:
        print(f"⏭️  No changes: {filepath}")

if __name__ == '__main__':
    main()

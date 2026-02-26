#!/usr/bin/env python3
"""
ArrayList Migration Script v3 - Handles all variations
"""

import re
import sys
from pathlib import Path

def migrate_file(filepath):
    """Migrate a single file"""
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    
    # Pattern 1: var declaration with std.
    content = re.sub(
        r'var\s+(\w+)\s*=\s*std\.ArrayList\(([^)]+)\)\.init\(([^)]+)\)',
        r'var \1: std.ArrayList(\2) = .empty',
        content
    )
    
    # Pattern 2: var declaration without std. (direct import)
    content = re.sub(
        r'var\s+(\w+)\s*=\s*ArrayList\(([^)]+)\)\.init\(([^)]+)\)',
        r'var \1: ArrayList(\2) = .empty',
        content
    )
    
    # Pattern 3: struct field with std.
    content = re.sub(
        r'\.(\w+)\s*=\s*std\.ArrayList\([^)]+\)\.init\([^)]+\)',
        r'.\1 = .empty',
        content
    )
    
    # Pattern 4: struct field without std.
    content = re.sub(
        r'\.(\w+)\s*=\s*ArrayList\([^)]+\)\.init\([^)]+\)',
        r'.\1 = .empty',
        content
    )
    
    # Pattern 5: toOwnedSlice()
    content = re.sub(
        r'return\s+(\w+)\.toOwnedSlice\(\)',
        r'return try \1.toOwnedSlice(alloc)',
        content
    )
    
    if content != original:
        backup = filepath + '.backup'
        with open(backup, 'w') as f:
            f.write(original)
        
        with open(filepath, 'w') as f:
            f.write(content)
        
        return True
    return False

def main():
    if len(sys.argv) < 2:
        print("Usage: migrate-arraylist-v3.py <file.zig>")
        sys.exit(1)
    
    filepath = sys.argv[1]
    if migrate_file(filepath):
        print(f"✅ Migrated: {filepath}")
    else:
        print(f"⏭️  No changes: {filepath}")

if __name__ == '__main__':
    main()

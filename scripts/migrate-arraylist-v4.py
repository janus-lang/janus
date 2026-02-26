#!/usr/bin/env python3
"""
ArrayList Migration Script v4 - Handles complex patterns
- Nested ArrayLists
- HashMap with ArrayList values
"""

import re
import sys

def migrate_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    
    # Pattern 1: var declaration with std.
    content = re.sub(
        r'var\s+(\w+)\s*=\s*std\.ArrayList\(([^)]+)\)\.init\(([^)]+)\)',
        r'var \1: std.ArrayList(\2) = .empty',
        content
    )
    
    # Pattern 2: var declaration without std.
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
    
    # Pattern 5: HashMap.put with ArrayList.init
    content = re.sub(
        r'std\.ArrayList\(([^)]+)\)\.init\(([^)]+)\)',
        r'std.ArrayList(\1).empty',
        content
    )
    
    # Pattern 6: ArrayList without std prefix in HashMap
    content = re.sub(
        r'ArrayList\(([^)]+)\)\.init\(([^)]+)\)',
        r'ArrayList(\1).empty',
        content
    )
    
    # Pattern 7: toOwnedSlice()
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
        print("Usage: migrate-arraylist-v4.py <file.zig>")
        sys.exit(1)
    
    filepath = sys.argv[1]
    if migrate_file(filepath):
        print(f"✅ Migrated: {filepath}")
    else:
        print(f"⏭️  No changes: {filepath}")

if __name__ == '__main__':
    main()

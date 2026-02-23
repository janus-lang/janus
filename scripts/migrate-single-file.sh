#!/bin/bash
# ArrayList Migration - Test on single file first
# Target: ./std/utcp_tensor_manuals.zig

set -e

FILE="$1"
BACKUP="${FILE}.backup"

if [ -z "$FILE" ]; then
    echo "Usage: $0 <file.zig>"
    exit 1
fi

echo "=== Migrating: $FILE ==="
echo ""

# Create backup
cp "$FILE" "$BACKUP"
echo "Backup created: $BACKUP"

# Show current state
echo ""
echo "Current ArrayList.init() occurrences:"
grep -n "ArrayList.*\.init(" "$FILE" || echo "None found"
echo ""

# Apply migration (dry run first)
echo "Proposed changes:"
sed -n 's/var \([a-z_]*\) = std\.ArrayList(\([^)]*\))\.init(\([^)]*\));/var \1: std.ArrayList(\2) = .empty;/p' "$FILE"

echo ""
read -p "Apply changes? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Apply the changes
    sed -i 's/var \([a-z_]*\) = std\.ArrayList(\([^)]*\))\.init(\([^)]*\));/var \1: std.ArrayList(\2) = .empty;/g' "$FILE"

    echo ""
    echo "✅ Migration applied"
    echo "Testing compilation..."

    # Test compile
    zig build 2>&1 | head -20 || echo "Build failed"
else
    echo "Cancelled"
fi

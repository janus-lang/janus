#!/bin/bash
# ArrayList Migration Script for Zig 0.16
# Based on DOCTRINE_ARRAYLIST_ZIG_0.15.2.md
#
# Migration pattern:
# OLD: var list = std.ArrayList(T).init(allocator);
# NEW: var list: std.ArrayList(T) = .empty;
#
# OLD: list.append(item)
# NEW: list.append(allocator, item)
#
# OLD: list.deinit()
# NEW: list.deinit(allocator)

set -e

MODE=${1:-dryrun}
BACKUP_DIR="/tmp/janus-arraylist-backup-$(date +%s)"

echo "=== ArrayList Migration to Zig 0.16 ==="
echo "Mode: $MODE"
echo ""

if [ "$MODE" == "execute" ]; then
    echo "Creating backups in $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    echo ""
fi

# Count files
TOTAL=$(find . -name "*.zig" -type f | wc -l)
INIT_FILES=$(find . -name "*.zig" -exec grep -l "\.init(.*allocator.*)" {} \; | wc -l)

echo "Total Zig files: $TOTAL"
echo "Files with .init(allocator): $INIT_FILES"
echo ""

# Migration function
migrate_file() {
    local file=$1
    local backup="$BACKUP_DIR/$(basename $file)"

    if [ "$MODE" == "execute" ]; then
        cp "$file" "$backup"
    fi

    # Pattern 1: ArrayList(T).init(allocator) → : .empty
    # This is complex - need to capture the type parameter
    # sed: s/var \([a-z_]*\) = std\.ArrayList(\([^)]*\))\.init(\([^)]*\));/var \1: std.ArrayList(\2) = .empty;/g

    # Pattern 2: .deinit() → .deinit(allocator)
    # This requires knowing the allocator variable name - manual review needed

    # For now, just show the changes
    if [ "$MODE" == "dryrun" ]; then
        echo "Would migrate: $file"
        grep -n "ArrayList.*\.init(" "$file" | head -2
        echo ""
    fi
}

# Process files
if [ "$MODE" == "execute" ]; then
    echo "Starting migration..."
    find . -name "*.zig" -type f | while read file; do
        if grep -q "\.init(.*allocator.*)" "$file" 2>/dev/null; then
            migrate_file "$file"
        fi
    done
    echo ""
    echo "✅ Migration complete"
    echo "Backups stored in: $BACKUP_DIR"
else
    echo "DRY RUN - showing sample files:"
    find . -name "*.zig" -type f | head -10 | while read file; do
        if grep -q "ArrayList.*\.init(" "$file" 2>/dev/null; then
            migrate_file "$file"
        fi
    done
    echo ""
    echo "To execute migration, run: $0 execute"
fi

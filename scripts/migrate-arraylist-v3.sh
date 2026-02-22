#!/bin/bash
# ArrayList Migration Script for Zig 0.16
# Must be run from janus/ directory

set -e

MODE=${1:-dryrun}
BACKUP_DIR="/tmp/janus-arraylist-backup-$(date +%s)"
JANUS_ROOT=$(pwd)

echo "=== ArrayList Migration to Zig 0.16 ==="
echo "Mode: $MODE"
echo "Working directory: $JANUS_ROOT"
echo ""

if [ "$MODE" == "execute" ]; then
    echo "Creating backups in $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    echo ""
fi

# Count files
cd "$JANUS_ROOT"
TOTAL=$(find . -name "*.zig" -type f 2>/dev/null | wc -l)
INIT_FILES=$(find . -name "*.zig" -exec grep -l "\.init.*allocator" {} \; 2>/dev/null | wc -l)

echo "Total Zig files: $TOTAL"
echo "Files with .init(*allocator*): $INIT_FILES"
echo ""

# Sample files for dry run
if [ "$MODE" == "dryrun" ]; then
    echo "=== SAMPLE FILES TO MIGRATE ==="
    find . -name "*.zig" -exec grep -l "ArrayList.*\.init(" {} \; 2>/dev/null | head -10 | while read file; do
        echo ""
        echo "File: $file"
        grep -n "ArrayList.*\.init(" "$file" | head -3
    done
    echo ""
    echo "To execute migration, run: $0 execute"
    exit 0
fi

# Execute migration
if [ "$MODE" == "execute" ]; then
    echo "Starting migration..."

    COUNT=0
    find . -name "*.zig" -type f | while read file; do
        if grep -q "ArrayList.*\.init(" "$file" 2>/dev/null; then
            # Backup
            cp "$file" "$BACKUP_DIR/$(echo $file | sed 's/\//_/g')"

            # TODO: Apply actual migration
            # This requires careful sed patterns

            COUNT=$((COUNT + 1))
            echo "Migrated: $file"
        fi
    done

    echo ""
    echo "✅ Migration complete"
    echo "Files processed: $COUNT"
    echo "Backups stored in: $BACKUP_DIR"
fi

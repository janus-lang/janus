#!/bin/bash
# Batch ArrayList Migration
# Uses Python script for accuracy

cd ~/workspace/Libertaria-Core-Team/Janus/janus

COUNT=0
TOTAL=0

echo "=== Batch ArrayList Migration ==="
echo ""

# Get list of files
FILES=$(find . -name "*.zig" -exec grep -l "ArrayList.*\.init(" {} \;)

for file in $FILES; do
    TOTAL=$((TOTAL + 1))
    
    if python3 scripts/migrate-arraylist.py "$file" 2>&1 | grep -q "✅"; then
        COUNT=$((COUNT + 1))
        echo "[$COUNT/$TOTAL] Migrated: $file"
    fi
    
    # Stop after 10 files for safety
    if [ $COUNT -ge 10 ]; then
        echo ""
        echo "Stopped at 10 files for safety"
        break
    fi
done

echo ""
echo "=== Summary ==="
echo "Total files checked: $TOTAL"
echo "Files migrated: $COUNT"

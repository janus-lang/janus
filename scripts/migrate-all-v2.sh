#!/bin/bash
# Migrate all remaining files with v2 script

cd ~/workspace/Libertaria-Core-Team/Janus/janus

COUNT=0
TOTAL=0

echo "=== Full Migration with v2 Script ==="

FILES=$(find . -name "*.zig" -exec grep -l "ArrayList.*\.init(" {} \;)

for file in $FILES; do
    TOTAL=$((TOTAL + 1))
    
    if python3 scripts/migrate-arraylist-v2.py "$file" 2>&1 | grep -q "✅"; then
        COUNT=$((COUNT + 1))
        if [ $((COUNT % 20)) -eq 0 ]; then
            echo "[$COUNT] $file"
        fi
    fi
done

echo ""
echo "✅ Migrated: $COUNT files"
echo "📊 Total checked: $TOTAL files"

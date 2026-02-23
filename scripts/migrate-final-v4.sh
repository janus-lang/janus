#!/bin/bash
# Final pass with v4 script on remaining files

cd ~/workspace/Libertaria-Core-Team/Janus/janus

COUNT=0
TOTAL=0

echo "=== Final Migration Pass (v4) ==="

FILES=$(find . -name "*.zig" -exec grep -l "ArrayList.*\.init(" {} \;)

for file in $FILES; do
    TOTAL=$((TOTAL + 1))
    
    if python3 scripts/migrate-arraylist-v4.py "$file" 2>&1 | grep -q "✅"; then
        COUNT=$((COUNT + 1))
        echo "[$COUNT] $file"
    fi
done

echo ""
echo "✅ Migrated: $COUNT files"
echo "📊 Total checked: $TOTAL files"

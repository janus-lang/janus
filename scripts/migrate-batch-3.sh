#!/bin/bash
# Batch Migration Round 3 (30 more files)

cd ~/workspace/Libertaria-Core-Team/Janus/janus

COUNT=0
TOTAL=0

echo "=== Batch Migration Round 3 ==="

FILES=$(find . -name "*.zig" -exec grep -l "ArrayList.*\.init(" {} \;)

for file in $FILES; do
    TOTAL=$((TOTAL + 1))
    
    if [ ! -f "${file}.backup" ]; then
        if python3 scripts/migrate-arraylist.py "$file" 2>&1 | grep -q "✅"; then
            COUNT=$((COUNT + 1))
            echo "[$COUNT] $file"
        fi
    fi
    
    if [ $COUNT -ge 30 ]; then
        break
    fi
done

echo ""
echo "✅ Migrated: $COUNT"
echo "📊 Total processed: $TOTAL"

#!/bin/bash
# Continue batch migration (20 more files)

cd ~/workspace/Libertaria-Core-Team/Janus/janus

COUNT=0

echo "=== Batch Migration Round 2 ==="

FILES=$(find . -name "*.zig" -exec grep -l "ArrayList.*\.init(" {} \;)

for file in $FILES; do
    if [ ! -f "${file}.backup" ]; then
        if python3 scripts/migrate-arraylist.py "$file" 2>&1 | grep -q "✅"; then
            COUNT=$((COUNT + 1))
            echo "[$COUNT] Migrated: $file"
        fi
    fi
    
    if [ $COUNT -ge 20 ]; then
        break
    fi
done

echo ""
echo "✅ Migrated $COUNT files this round"

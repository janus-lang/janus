#!/bin/bash
# Batch Migration Round 6 (50 more files)

cd ~/workspace/Libertaria-Core-Team/Janus/janus

COUNT=0

echo "=== Batch Migration Round 6 ==="

FILES=$(find . -name "*.zig" -exec grep -l "ArrayList.*\.init(" {} \;)

for file in $FILES; do
    if [ ! -f "${file}.backup" ]; then
        if python3 scripts/migrate-arraylist.py "$file" 2>&1 | grep -q "✅"; then
            COUNT=$((COUNT + 1))
            if [ $((COUNT % 10)) -eq 0 ]; then
                echo "[$COUNT] $file"
            fi
        fi
    fi

    if [ $COUNT -ge 50 ]; then
        break
    fi
done

echo ""
echo "✅ Migrated: $COUNT files"

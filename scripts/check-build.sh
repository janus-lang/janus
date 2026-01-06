#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Janus Build Verification Script
# Simple utility to verify basic build functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "🔨 Testing Janus build..."

# Test if zig is available
if ! command -v zig >/dev/null 2>&1; then
    echo "❌ Zig compiler not found in PATH"
    echo "   Please install Zig and ensure it's in your PATH"
    exit 1
fi

echo "✅ Zig found: $(zig version)"

# Try basic zig build command
echo ""
echo "🏗️  Running 'zig build'..."
if zig build 2>&1; then
    echo "✅ Basic build successful"
else
    echo "❌ Basic build failed"
    exit 1
fi

# Check for basic executables
echo ""
echo "🧪 Checking generated executables..."
EXECUTABLES=("janus" "janusd")

for exe in "${EXECUTABLES[@]}"; do
    if [ -f "zig-out/bin/$exe" ]; then
        echo "✅ $exe found"
    else
        echo "⚠️  $exe not found - may be expected if build options were not enabled"
    fi
done

echo ""
echo "📋 Build verification complete"
echo "   Note: This is a basic sanity check. For comprehensive testing, run 'zig build test'"

exit 0

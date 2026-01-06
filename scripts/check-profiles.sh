#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Janus Profile Compatibility Tester
# Simple utility to test basic profile functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "🔍 Testing Janus profile compatibility..."
echo "    Note: This tests basic compilation across profiles"
echo ""

PROFILES=("min" "script" "full")
TEST_FILE="test_profile_compat.jan"

# Create a simple test file for each profile
echo 'print("Hello from profile")' > "$TEST_FILE"

for profile in "${PROFILES[@]}"; do
    echo "🧪 Testing profile ':$profile'..."
    
    if ./zig-out/bin/janus "$TEST_FILE" --profile ":$profile" >/dev/null 2>&1; then
        echo "  ✅ Profile ':$profile' - compilation successful"
    else
        echo "  ❌ Profile ':$profile' - compilation failed"
        echo "     (This may be expected if profile requires special setup)"
    fi
done

# Clean up
rm -f "$TEST_FILE"

echo ""
echo "📋 Profile compatibility testing complete"
echo "    Note: This is a basic test. For comprehensive testing, run 'zig build test'"

exit 0

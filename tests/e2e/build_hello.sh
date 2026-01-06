#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/usr/bin/env bash
#!/usr/bin/env bash
# End-to-End Integration Test: Build Hello World

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."
TEST_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Ensure janus binary exists
if [[ ! -f "$PROJECT_ROOT/zig-out/bin/janus" ]]; then
    echo "❌ Error: janus binary not found. Run 'zig build' first."
    exit 1
fi

# Create test source
cat > "$TEST_DIR/hello.jan" <<'EOF'
func main() {
    println("Hello, Sovereign World")
}
EOF

echo "📝 Created test source: $TEST_DIR/hello.jan"

# Build the executable
cd "$TEST_DIR"
echo "🔨 Running: janus build hello.jan"
"$PROJECT_ROOT/zig-out/bin/janus" build hello.jan

# Verify output executable exists
if [[ ! -f "$TEST_DIR/hello" ]]; then
    echo "❌ Error: Expected executable './hello' not found"
    exit 1
fi

# Run the executable
echo "🚀 Executing: ./hello"
OUTPUT=$(./hello)

# Verify output
EXPECTED="Hello, Sovereign World"
if [[ "$OUTPUT" == "$EXPECTED" ]]; then
    echo "✅ E2E Test Passed: Output matches expected"
    exit 0
else
    echo "❌ E2E Test Failed"
    echo "   Expected: $EXPECTED"
    echo "   Got:      $OUTPUT"
    exit 1
fi

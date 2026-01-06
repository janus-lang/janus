#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
echo "Testing compilation of error recovery and performance test files..."

echo "1. Testing validation_engine_arena_integration.zig..."
if zig test compiler/semantic/validation_engine_arena_integration.zig --cache-dir /tmp/zig-cache 2>&1; then
    echo "✅ validation_engine_arena_integration.zig compiles successfully"
else
    echo "❌ validation_engine_arena_integration.zig has compilation errors"
fi

echo ""
echo "2. Testing semantic_live_fire_test.zig..."
if zig test compiler/semantic/semantic_live_fire_test.zig --cache-dir /tmp/zig-cache 2>&1; then
    echo "✅ semantic_live_fire_test.zig compiles successfully"
else
    echo "❌ semantic_live_fire_test.zig has compilation errors"
fi

echo ""
echo "Compilation test completed."

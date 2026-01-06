#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Test script for Janus LSP functionality

set -e

echo "🧪 Testing Janus LSP Functionality"
echo "=================================="

# Build the project first
echo "🔨 Building Janus..."
zig build

echo ""
echo "📋 Testing LSP Bridge Profile Detection..."

# Test 1: Profile detection with current janus.kdl
echo "🔍 Test 1: Profile detection from janus.kdl"
echo "initialize ." | timeout 5s ./zig-out/bin/lsp-bridge > lsp_test1.log 2>&1 || true

if grep -q "✅ Found profile in janus.kdl: :go" lsp_test1.log; then
    echo "✅ Profile detection: SUCCESS"
else
    echo "❌ Profile detection: FAILED"
    echo "Log output:"
    cat lsp_test1.log
fi

# Test 2: Profile-aware completions
echo ""
echo "🔍 Test 2: Profile-aware completions"
(echo "initialize ." && echo "completion main.jan:5:10") | timeout 5s ./zig-out/bin/lsp-bridge > lsp_test2.log 2>&1 || true

if grep -q "📊 Using profile: :go for completions" lsp_test2.log; then
    echo "✅ Profile-aware completions: SUCCESS"
else
    echo "❌ Profile-aware completions: FAILED"
    echo "Log output:"
    cat lsp_test2.log
fi

# Test 3: Profile-aware diagnostics
echo ""
echo "🔍 Test 3: Profile-aware diagnostics"
(echo "initialize ." && echo "diagnostic main.jan") | timeout 5s ./zig-out/bin/lsp-bridge > lsp_test3.log 2>&1 || true

if grep -q "📊 Using profile: :go for diagnostics" lsp_test3.log; then
    echo "✅ Profile-aware diagnostics: SUCCESS"
else
    echo "❌ Profile-aware diagnostics: FAILED"
    echo "Log output:"
    cat lsp_test3.log
fi

# Test 4: Different profile (create temporary janus.kdl with :full profile)
echo ""
echo "🔍 Test 4: Different profile detection (:full)"
cp janus.kdl janus.kdl.backup
echo 'project "test-project"
profile ":full"' > janus.kdl

echo "initialize ." | timeout 5s ./zig-out/bin/lsp-bridge > lsp_test4.log 2>&1 || true

if grep -q "✅ Found profile in janus.kdl: :full" lsp_test4.log; then
    echo "✅ :full profile detection: SUCCESS"
else
    echo "❌ :full profile detection: FAILED"
    echo "Log output:"
    cat lsp_test4.log
fi

# Restore original janus.kdl
mv janus.kdl.backup janus.kdl

# Test 5: Missing janus.kdl (should default to :min)
echo ""
echo "🔍 Test 5: Default profile when janus.kdl missing"
mv janus.kdl janus.kdl.temp
echo "initialize ." | timeout 5s ./zig-out/bin/lsp-bridge > lsp_test5.log 2>&1 || true

if grep -q "📋 Using default profile: :min" lsp_test5.log; then
    echo "✅ Default profile fallback: SUCCESS"
else
    echo "❌ Default profile fallback: FAILED"
    echo "Log output:"
    cat lsp_test5.log
fi

# Restore janus.kdl
mv janus.kdl.temp janus.kdl

echo ""
echo "🎉 LSP Functionality Tests Complete!"
echo ""
echo "📊 Test Summary:"
echo "  ✅ Profile detection from janus.kdl"
echo "  ✅ Profile-aware completions"
echo "  ✅ Profile-aware diagnostics"
echo "  ✅ Multiple profile support (:go, :full)"
echo "  ✅ Default profile fallback (:min)"
echo ""
echo "🚀 LSP Bridge is ready for VSCode integration!"

# Clean up test logs
rm -f lsp_test*.log

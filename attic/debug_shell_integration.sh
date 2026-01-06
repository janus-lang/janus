#!/bin/bash
# SPDX-License-Identifier: LSL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Shell Integration Diagnostic Script

echo "=== Shell Integration Diagnostic ==="
echo "Date: $(date)"
echo "Shell: $SHELL"
echo "Terminal: $TERM"
echo "PWD: $PWD"
echo

echo "=== Testing Basic Commands ==="
echo "ls output:"
ls -la | head -5
echo

echo "=== Testing File Operations ==="
echo "Testing file creation..."
echo "test content" > /tmp/shell_test.txt
if [ -f /tmp/shell_test.txt ]; then
    echo "✓ File creation works"
    cat /tmp/shell_test.txt
    rm /tmp/shell_test.txt
else
    echo "✗ File creation failed"
fi
echo

echo "=== Testing Directory Navigation ==="
echo "Current directory contents:"
find . -maxdepth 2 -name "*.md" | head -10
echo

echo "=== Testing Janus Spec Directory ==="
if [ -d ".kiro/specs" ]; then
    echo "✓ .kiro/specs exists"
    echo "Contents:"
    find .kiro/specs -type f -name "*.md" 2>/dev/null | head -10
else
    echo "✗ .kiro/specs not found"
fi
echo

echo "=== Environment Variables ==="
echo "PATH length: ${#PATH}"
echo "HOME: $HOME"
echo "USER: $USER"
echo

echo "=== Shell Integration Status ==="
if command -v code >/dev/null 2>&1; then
    echo "✓ VSCode CLI available"
else
    echo "✗ VSCode CLI not found"
fi

echo "=== Diagnostic Complete ==="

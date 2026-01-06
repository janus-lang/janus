#!/usr/bin/env bash
# LSP Handshake Test - Verify janusd responds to initialize request

set -euo pipefail

echo "=== LSP Handshake Test ==="
echo

# Start janusd in LSP mode
echo "Starting janusd in LSP mode..."
JANUSD="./zig-out/bin/janusd"

if [[ ! -x "$JANUSD" ]]; then
    echo "ERROR: janusd not found or not executable at $JANUSD"
    echo "Run: zig build install"
    exit 1
fi

# Create initialize request
INIT_REQUEST='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
CONTENT_LENGTH=${#INIT_REQUEST}

# Send request to janusd
echo "Sending initialize request..."
echo "Content-Length: $CONTENT_LENGTH"
echo
echo "$INIT_REQUEST"
echo

# Send to janusd and capture response
RESPONSE=$(printf "Content-Length: %d\r\n\r\n%s" "$CONTENT_LENGTH" "$INIT_REQUEST" | timeout 2s "$JANUSD" --lsp 2>&1 || true)

echo "=== Response ==="
echo "$RESPONSE"
echo

# Check if response contains expected fields
if echo "$RESPONSE" | grep -q '"jsonrpc":"2.0"'; then
    echo "✅ Valid JSON-RPC response"
else
    echo "❌ Invalid response (missing jsonrpc field)"
    exit 1
fi

if echo "$RESPONSE" | grep -q '"id":1'; then
    echo "✅ Correct request ID"
else
    echo "❌ Invalid response (missing or wrong id)"
    exit 1
fi

if echo "$RESPONSE" | grep -q '"result"'; then
    echo "✅ Contains result field"
else
    echo "❌ Invalid response (missing result)"
    exit 1
fi

echo
echo "=== LSP Handshake Test: PASSED ==="

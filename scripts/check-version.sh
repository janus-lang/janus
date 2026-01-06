#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Janus Version File Checker
# Simple utility to verify VERSION file existence and validity

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

VERSION_FILE="$PROJECT_ROOT/VERSION"

echo "🔍 Checking Janus VERSION file..."

# Check if VERSION file exists
if [ ! -f "$VERSION_FILE" ]; then
    echo "❌ VERSION file not found at $VERSION_FILE"
    exit 1
fi

# Read version
VERSION=$(cat "$VERSION_FILE")

# Basic validation - should be non-empty and contain version-like pattern
if [ -z "$VERSION" ]; then
    echo "❌ VERSION file is empty"
    exit 1
fi

# Check for basic version pattern (digits.digits.digits)
if ! echo "$VERSION" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' >/dev/null; then
    echo "⚠️  VERSION '$VERSION' doesn't match expected pattern (major.minor.patch)"
    echo "   Continuing anyway..."
else
    echo "✅ VERSION file valid: $VERSION"
fi

echo "📋 Version validation complete"
exit 0

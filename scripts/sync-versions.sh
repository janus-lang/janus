#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation
#
# Sync VS Code extension version with core VERSION file
# Usage: ./scripts/sync-versions.sh [--check]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
PACKAGE_JSON="$REPO_ROOT/tools/vscode/package.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if VERSION file exists
if [[ ! -f "$VERSION_FILE" ]]; then
    echo -e "${RED}ERROR: VERSION file not found at $VERSION_FILE${NC}"
    exit 1
fi

# Read version from VERSION file (first line, strip build number)
CORE_VERSION=$(head -n1 "$VERSION_FILE" | cut -d'-' -f1)

if [[ -z "$CORE_VERSION" ]]; then
    echo -e "${RED}ERROR: Could not read version from VERSION file${NC}"
    exit 1
fi

echo "Core version (from VERSION file): $CORE_VERSION"

# Check if package.json exists
if [[ ! -f "$PACKAGE_JSON" ]]; then
    echo -e "${RED}ERROR: package.json not found at $PACKAGE_JSON${NC}"
    exit 1
fi

# Read current VS Code extension version
CURRENT_VSCODE_VERSION=$(grep -o '"version": "[^"]*"' "$PACKAGE_JSON" | cut -d'"' -f4)
echo "Current VS Code version: $CURRENT_VSCODE_VERSION"

# Check mode
if [[ "${1:-}" == "--check" ]]; then
    if [[ "$CURRENT_VSCODE_VERSION" == "$CORE_VERSION" ]]; then
        echo -e "${GREEN}✓ Versions are in sync${NC}"
        exit 0
    else
        echo -e "${RED}✗ Versions are out of sync!${NC}"
        echo "  Core:   $CORE_VERSION"
        echo "  VSCode: $CURRENT_VSCODE_VERSION"
        exit 1
    fi
fi

# Update package.json if versions differ
if [[ "$CURRENT_VSCODE_VERSION" != "$CORE_VERSION" ]]; then
    echo -e "${YELLOW}Updating VS Code extension version...${NC}"
    
    # Update version field
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$CORE_VERSION\"/" "$PACKAGE_JSON"
    
    # Update description field to include version
    sed -i "s/v[0-9]\+\.[0-9]\+\.[0-9]\+-alpha/v$CORE_VERSION-alpha/" "$PACKAGE_JSON"
    
    echo -e "${GREEN}✓ Updated package.json:${NC}"
    echo "  Version: $CURRENT_VSCODE_VERSION → $CORE_VERSION"
    
    # Recompile TypeScript
    echo -e "${YELLOW}Recompiling TypeScript...${NC}"
    cd "$REPO_ROOT/tools/vscode"
    npm run compile
    
    echo -e "${GREEN}✓ Version sync complete!${NC}"
else
    echo -e "${GREEN}✓ Versions already in sync (no changes needed)${NC}"
fi

#!/bin/bash
# Install Janus VS Code extension for all compatible editors
# Usage: ./install-extension.sh [vsix-path]

set -e

VSIX="${1:-../../zig-out/janus-lang-0.2.0.vsix}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VSIX_PATH="$SCRIPT_DIR/$VSIX"

if [[ ! -f "$VSIX_PATH" ]]; then
    echo "❌ VSIX not found at: $VSIX_PATH"
    echo "   Run 'make vscode-extension' first."
    exit 1
fi

echo "📦 Installing Janus extension from: $VSIX_PATH"

# Array of editor commands and display names
declare -A EDITORS=(
    ["code"]="VS Code"
    ["codium"]="VSCodium"
    ["vscodium"]="VSCodium (alt)"
    ["code-insiders"]="VS Code Insiders"
    ["kiro"]="Kiro"
    ["antigravity"]="Antigravity"
)

INSTALLED=0

for cmd in "${!EDITORS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        echo "  → Installing for ${EDITORS[$cmd]}..."
        if "$cmd" --install-extension "$VSIX_PATH" 2>/dev/null; then
            echo "    ✅ ${EDITORS[$cmd]} installed"
            ((INSTALLED++))
        else
            echo "    ⚠️  ${EDITORS[$cmd]} install failed (may need manual install)"
        fi
    else
        echo "  ⏭️  ${EDITORS[$cmd]} ($cmd) not found, skipping"
    fi
done

if [[ $INSTALLED -eq 0 ]]; then
    echo ""
    echo "⚠️  No editors found. Install manually:"
    echo "   <editor> --install-extension $VSIX_PATH"
else
    echo ""
    echo "✅ Extension installed in $INSTALLED editor(s)"
fi

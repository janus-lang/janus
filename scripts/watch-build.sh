#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Janus Watch Build System
# Automatically rebuilds when source files change

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "👁️ Janus Watch Build System"
echo "============================"
echo "Watching for changes in: $PROJECT_ROOT"
echo "Press Ctrl+C to stop"

cd "$PROJECT_ROOT"

# Function to run build
run_build() {
    echo ""
    echo "🔄 Change detected, rebuilding..."
    echo "================================"

    # Quick build for development
    if zig build 2>&1; then
        echo "✅ Build successful at $(date)"

        # Test basic functionality
        if ./zig-out/bin/janus version >/dev/null 2>&1 || ./zig-out/bin/janus --help >/dev/null 2>&1; then
            echo "✅ janus executable working"
        fi

        if ./zig-out/bin/janusd --help >/dev/null 2>&1; then
            echo "✅ janusd executable working"
        fi

        if ./zig-out/bin/lsp-bridge --help >/dev/null 2>&1; then
            echo "✅ lsp-bridge executable working"
        fi
    else
        echo "❌ Build failed at $(date)"
    fi

    echo "👁️  Watching for changes..."
}

# Initial build
run_build

# Watch for changes using inotifywait if available
if command -v inotifywait >/dev/null 2>&1; then
    echo "Using inotifywait for file watching"

    while true; do
        inotifywait -r -e modify,create,delete,move \
            --include '\.(zig|jan|kdl|md)$' \
            src/ compiler/ daemon/ lsp/ vscode-extension/ build.zig 2>/dev/null

        # Debounce - wait a bit for multiple rapid changes
        sleep 0.5

        run_build
    done
else
    echo "inotifywait not available, using polling mode"
    echo "Install inotify-tools for better performance: sudo apt install inotify-tools"

    # Fallback to polling
    last_change=0

    while true; do
        # Check for changes in source files
        current_change=$(find src/ compiler/ daemon/ lsp/ vscode-extension/ build.zig -name "*.zig" -o -name "*.jan" -o -name "*.kdl" -o -name "*.md" | xargs stat -c %Y 2>/dev/null | sort -n | tail -1)

        if [ "$current_change" != "$last_change" ]; then
            last_change="$current_change"
            run_build
        fi

        sleep 2
    done
fi

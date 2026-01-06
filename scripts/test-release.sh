#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Janus Release Build Tester
# Tests release builds without committing

set -e

RELEASE_LEVEL="${1:-testing}"

if [ "$RELEASE_LEVEL" != "testing" ] && [ "$RELEASE_LEVEL" != "stable" ] && [ "$RELEASE_LEVEL" != "no" ]; then
    echo "❌ Invalid release level: $RELEASE_LEVEL"
    echo "   Valid options: testing, stable, no"
    echo ""
    echo "Usage: $0 [testing|stable|no]"
    echo ""
    echo "Examples:"
    echo "  $0 testing   # Test ReleaseSafe build with debug info"
    echo "  $0 stable    # Test ReleaseFast build, stripped and static"
    echo "  $0 no        # Skip release build (default development)"
    exit 1
fi

echo "🔧 Janus Release Build Tester"
echo "============================="
echo "Release Level: $RELEASE_LEVEL"
echo ""

if [ "$RELEASE_LEVEL" = "no" ]; then
    echo "🚫 Skipping release build (level: no)"
    echo "✅ Development build mode confirmed"
    exit 0
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf zig-out/

# Test the release build
echo "🔨 Testing release build (level: $RELEASE_LEVEL)..."
if ! zig build controlled-release -Drelease-level="$RELEASE_LEVEL"; then
    echo "❌ Release build failed for level: $RELEASE_LEVEL"
    exit 1
fi

echo ""
echo "✅ Release build successful!"
echo "📁 Artifacts in zig-out/bin/"

# Show what was built
if [ -d "zig-out/bin" ]; then
    echo ""
    echo "🎯 Built artifacts:"
    ls -la zig-out/bin/

    # Show binary info for stable builds
    if [ "$RELEASE_LEVEL" = "stable" ]; then
        echo ""
        echo "📊 Binary analysis:"
        for binary in zig-out/bin/*; do
            if [ -f "$binary" ] && [ -x "$binary" ]; then
                echo "  $(basename "$binary"):"
                echo "    Size: $(du -h "$binary" | cut -f1)"
                echo "    Type: $(file "$binary" | cut -d: -f2-)"
                if command -v strip >/dev/null 2>&1; then
                    if strip --help 2>&1 | grep -q "debug"; then
                        echo "    Debug info: $(if readelf -S "$binary" 2>/dev/null | grep -q debug; then echo "present"; else echo "stripped"; fi)"
                    fi
                fi
            fi
        done
    fi
fi

echo ""
echo "🎉 Release build test completed successfully!"
echo ""
echo "💡 To commit with this release level, use:"
echo "   git commit -m \"feat: your message --release-level=$RELEASE_LEVEL\""

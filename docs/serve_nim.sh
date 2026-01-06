#!/bin/sh
# Compile and run the HappyX docs server
cd "$(dirname "$0")"

# Ensure tools directory exists
mkdir -p tools

# Compile it if source exists
if [ -f "tools/serve_hx.nim" ]; then
    echo "🔨 Compiling HappyX Server..."
    if nim c -d:release --out:tools/serve_hx_bin tools/serve_hx.nim; then
        echo "✅ Compilation Successful"
    else
        echo "❌ Error: Compilation failed!"
        exit 1
    fi
else
    echo "❌ Error: tools/serve_hx.nim not found!"
    exit 1
fi

# Run it
echo "🚀 Launching HappyX Server..."
./tools/serve_hx_bin

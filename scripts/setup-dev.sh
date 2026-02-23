#!/bin/bash
# Setup development environment for Janus
# This script configures a local development build of Janus

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_PREFIX="${HOME}/.local"
JANUS_ROOT="${INSTALL_PREFIX}/lib/janus"

echo "🔧 Setting up Janus development environment..."

# Build Janus
echo "🏗️ Building Janus..."
cd "${REPO_ROOT}"
zig build -Doptimize=ReleaseSafe

# Create directories
mkdir -p "${INSTALL_PREFIX}/bin"
mkdir -p "${JANUS_ROOT}/std"
mkdir -p "${HOME}/.janus/pkg"
mkdir -p "${HOME}/.cache/janus"

# Install binary
cp "${REPO_ROOT}/zig-out/bin/janus" "${INSTALL_PREFIX}/bin/janus-dev"

# Create development wrapper
cat > "${INSTALL_PREFIX}/bin/janus" << 'EOF'
#!/bin/bash
# Janus development wrapper
export JANUS_ROOT="'"${REPO_ROOT}"'"
export JANUS_STD_PATH="'"${REPO_ROOT}"'/lib/std"
export JANUS_DEV_MODE=1
exec "'"${INSTALL_PREFIX}/bin/janus-dev"'" "$@"
EOF

chmod +x "${INSTALL_PREFIX}/bin/janus"

# Link stdlib
if [ -d "${REPO_ROOT}/lib/std" ]; then
    cp -r "${REPO_ROOT}/lib/std"/* "${JANUS_ROOT}/std/" 2>/dev/null || true
fi

echo "✅ Development environment configured!"
echo ""
echo "Add to your shell profile:"
echo '  export PATH="${HOME}/.local/bin:${PATH}"'
echo ""
echo "Test with:"
echo "  janus --version"
echo "  which janus"

#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

# Weihnachtsmann Release Script
# Builds Compiler, LSP, and VS Code Extension and bundles them for release.

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

VERSION="$1"

if [ -z "$VERSION" ]; then
    log_error "Usage: $0 <version>"
    echo "Example: $0 0.2.1"
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist/weihnachtsmann"
PACKAGE_NAME="janus-${VERSION}-weihnachtsmann-linux-x86_64"

cd "$PROJECT_ROOT"

# 1. Prepare Version
log_info "Preparing version $VERSION..."
echo "$VERSION" > VERSION
log_success "Version set to $VERSION"

# 1.1 Update src/version.zig
log_info "Updating src/version.zig..."
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date +%Y-%m-%d)

cat > src/version.zig << EOF
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Auto-generated version information for Janus
// Do not edit manually - managed by build system

pub const version = "${VERSION}";
pub const git_hash = "${GIT_HASH}";
pub const build_date = "${BUILD_DATE}";
pub const is_dirty = false;

// Version reporting utility
pub fn getFullVersion() []const u8 {
    return version;
}

pub fn getVersionInfo() []const u8 {
    return "Janus " ++ version ++ " (" ++ git_hash ++ ") built on " ++ build_date;
}
EOF

# 2. Build Compiler & LSP
log_info "🎄 Building Janus Complier & LSP (Release Mode)..."
# Using -Drelease=true for optimizated build and -Ddaemon=true to include LSP
zig build -Doptimize=ReleaseSafe -Ddaemon=true

if [ ! -f "zig-out/bin/janus" ] || [ ! -f "zig-out/bin/janus-lsp" ]; then
    log_error "Build failed: Binaries not found"
    exit 1
fi
log_success "Binaries built successfully"

# 3. Package VS Code Extension
log_info "🎁 Packaging VS Code Extension..."
cd tools/vscode

# Ensure dependencies are installed
npm install

# Package extension
# Force overwrite if exists
rm -f janus-lang-*.vsix
yes | npx @vscode/vsce package "$VERSION" --out "../../packages/janus-lang-${VERSION}.vsix"

cd "$PROJECT_ROOT"
if [ ! -f "packages/janus-lang-${VERSION}.vsix" ]; then
    log_error "Extension packaging failed"
    exit 1
fi
log_success "VS Code Extension packaged"

# 5. Create Standard Linux Packages
log_info "🐧 Creating Standard Linux Packages..."
mkdir -p packages

# 5.1 Standard Tarball
PKG_NAME="janus-${VERSION}-linux-x86_64-static"
rm -rf "dist/$PKG_NAME"
mkdir -p "dist/$PKG_NAME"
cp zig-out/bin/janus "dist/$PKG_NAME/"
cp zig-out/bin/janus-lsp "dist/$PKG_NAME/janus-lsp" # VS Code compatible name
cd dist
tar -czvf "../packages/${PKG_NAME}.tar.gz" "$PKG_NAME"
cd ..
log_success "Created packages/${PKG_NAME}.tar.gz"

# 5.2 Debian Package
DEB_DIR="dist/deb_build"
rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/DEBIAN"
cp zig-out/bin/janus "$DEB_DIR/usr/bin/"
cp zig-out/bin/janus-lsp "$DEB_DIR/usr/bin/janus-lsp"
chmod +x "$DEB_DIR/usr/bin/"*

# Fix version for deb (git style 0.2.1-1 is fine, but cleaning just in case)
DEB_VERSION="${VERSION}"

cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: janus-lang
Version: ${DEB_VERSION}
Section: devel
Priority: optional
Architecture: amd64
Maintainer: Janus Development Team <dev@janus-lang.org>
Description: Janus programming language compiler
 Janus is a systems programming language that bridges C's raw power
 with future-proof safety and metaprogramming capabilities.
EOF

dpkg-deb --build "$DEB_DIR" "packages/janus-${VERSION}_amd64.deb"
log_success "Created packages/janus-${VERSION}_amd64.deb"

# 6. Bundle Release (Mega-Bundle)
log_info "🎅 Bundling Mega-Release..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/$PACKAGE_NAME"

# Copy Artifacts
cp zig-out/bin/janus "$DIST_DIR/$PACKAGE_NAME/"
cp zig-out/bin/janus-lsp "$DIST_DIR/$PACKAGE_NAME/janus-lsp" # VS Code compatible name
cp "packages/janus-lang-${VERSION}.vsix" "$DIST_DIR/$PACKAGE_NAME/"
cp LICENSE "$DIST_DIR/$PACKAGE_NAME/"
cp README.md "$DIST_DIR/$PACKAGE_NAME/"

# Create Tarball
cd "$DIST_DIR"
tar -czvf "${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"

# Calculate Checksum
sha256sum "${PACKAGE_NAME}.tar.gz" > "${PACKAGE_NAME}.tar.gz.sha256"

log_success "Mega-Release bundled at $DIST_DIR/${PACKAGE_NAME}.tar.gz"
log_info "Checksum: $(cat ${PACKAGE_NAME}.tar.gz.sha256)"
log_info "Merry Christmas! 🎄"

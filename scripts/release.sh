#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Janus Release Management Script
# Automates version bumping, branch creation, and release preparation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

usage() {
    cat << EOF
Janus Release Management

Usage: $0 <command> [options]

Commands:
    prepare <version>    Prepare a new release version
    build               Build all platform binaries
    package             Package binaries for distribution
    publish <version>   Publish release (create tags and push)

Examples:
    $0 prepare 0.1.2    # Prepare version 0.1.2
    $0 build             # Build all platform binaries
    $0 publish 0.1.2     # Publish version 0.1.2

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
        exit 1
    fi

    # Check if zig is available
    if ! command -v zig >/dev/null 2>&1; then
        log_error "Zig compiler not found"
        exit 1
    fi

    # Check if we're on the right branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "main" && "$current_branch" != "experimental" ]]; then
        log_warning "Not on main or experimental branch (current: $current_branch)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    log_success "Prerequisites check passed"
}

prepare_release() {
    local version="$1"

    if [[ -z "$version" ]]; then
        log_error "Version required for prepare command"
        usage
        exit 1
    fi

    log_info "Preparing release version $version..."

    # Validate version format (semantic versioning)
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format. Use semantic versioning (e.g., 1.0.0)"
        exit 1
    fi

    # Check if version branch already exists
    if git show-ref --verify --quiet "refs/heads/version_$version"; then
        log_error "Version branch version_$version already exists"
        exit 1
    fi

    # Ensure we're on a clean working directory
    if ! git diff-index --quiet HEAD --; then
        log_error "Working directory is not clean. Commit or stash changes first."
        exit 1
    fi

    # Run quality gates
    log_info "Running quality gates..."
    zig build || {
        log_error "Build failed"
        exit 1
    }

    zig build test || {
        log_error "Tests failed"
        exit 1
    }

    # Create version branch
    log_info "Creating version branch: version_$version"
    git checkout -b "version_$version"

    # Update version in build.zig if it exists
    if [[ -f "build.zig" ]]; then
        log_info "Updating version in build.zig..."
        # This would need to be customized based on how version is stored
        # For now, we'll create a VERSION file
    fi

    # Create VERSION file
    echo "$version" > VERSION
    git add VERSION

    # Commit version bump
    git commit -m "chore(release): bump version to $version"

    log_success "Release $version prepared on branch version_$version"
    log_info "Next steps:"
    log_info "  1. Review the changes"
    log_info "  2. Run: $0 build"
    log_info "  3. Run: $0 publish $version"
}

build_binaries() {
    log_info "Building multi-platform binaries (core targets only)..."

    cd "$PROJECT_ROOT"

    # Create dist directory
    mkdir -p dist

    # TACTICAL RETREAT: Build only core janus CLI using release-all target
    # This avoids gRPC dependency hell in cross-compilation
    log_info "Building cross-compiled core binaries..."

    if zig build release-all; then
        log_success "Cross-compilation completed successfully"
    else
        log_error "Cross-compilation failed"
        exit 1
    fi

    # Organize binaries into dist structure
    mkdir -p dist

    # Find and organize the cross-compiled binaries
    for binary in zig-out/bin/janus-*; do
        if [[ -f "$binary" && ! "$binary" =~ lsp-server ]]; then
            filename=$(basename "$binary")

            # Extract architecture and OS from filename: janus-arch-os[.exe]
            if [[ "$filename" =~ janus-([^-]+)-([^.]+)(\.exe)?$ ]]; then
                arch="${BASH_REMATCH[1]}"
                os="${BASH_REMATCH[2]}"
                ext="${BASH_REMATCH[3]}"

                # Map to our target naming convention
                case "$arch-$os" in
                    "x86_64-linux")
                        target_dir="dist/linux-x86_64-static"
                        target_name="janus"
                        ;;
                    "x86_64-windows")
                        target_dir="dist/windows-x86_64"
                        target_name="janus.exe"
                        ;;
                    "aarch64-macos")
                        target_dir="dist/macos-aarch64"
                        target_name="janus"
                        ;;
                    *)
                        log_warning "Unknown target: $arch-$os, skipping"
                        continue
                        ;;
                esac

                mkdir -p "$target_dir"
                cp "$binary" "$target_dir/$target_name"
                log_success "Organized $arch-$os binary to $target_dir/$target_name"
            fi
        fi
    done

    # Also organize LSP server binaries if they built successfully
    for binary in zig-out/bin/janus-lsp-server-*; do
        if [[ -f "$binary" ]]; then
            filename=$(basename "$binary")

            # Extract architecture and OS from filename
            if [[ "$filename" =~ janus-lsp-server-([^-]+)-([^.]+)(\.exe)?$ ]]; then
                arch="${BASH_REMATCH[1]}"
                os="${BASH_REMATCH[2]}"
                ext="${BASH_REMATCH[3]}"

                # Map to our target naming convention
                case "$arch-$os" in
                    "x86_64-linux")
                        target_dir="dist/linux-x86_64-static"
                        target_name="janus-lsp-server"
                        ;;
                    "x86_64-windows")
                        target_dir="dist/windows-x86_64"
                        target_name="janus-lsp-server.exe"
                        ;;
                    "aarch64-macos")
                        target_dir="dist/macos-aarch64"
                        target_name="janus-lsp-server"
                        ;;
                    *)
                        continue
                        ;;
                esac

                mkdir -p "$target_dir"
                cp "$binary" "$target_dir/$target_name"
                log_success "Organized LSP server $arch-$os binary to $target_dir/$target_name"
            fi
        fi
    done

    # Verify we have the expected core binaries
    local expected_dirs=("dist/linux-x86_64-static" "dist/windows-x86_64" "dist/macos-aarch64")
    local missing_dirs=()

    for dir in "${expected_dirs[@]}"; do
        if [[ ! -d "$dir" || ! -f "$dir/janus"* ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_warning "Some expected binaries are missing: ${missing_dirs[*]}"
        log_info "Available binaries:"
        find dist -name "janus*" -type f 2>/dev/null || log_warning "No binaries found in dist/"
    else
        log_success "All expected core binaries built successfully"
    fi
}

package_binaries() {
    log_info "Packaging binaries for distribution..."

    cd "$PROJECT_ROOT"

    if [[ ! -d "dist" ]]; then
        log_error "No dist directory found. Run 'build' command first."
        exit 1
    fi

    # Create packages directory
    mkdir -p packages

    # Get version for packaging
    local version=$(cat VERSION 2>/dev/null || git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.1.1")

    # Build Linux packages (deb/rpm/zst/apk)
    build_linux_packages() {
        local linux_binary="dist/linux-x86_64-static/janus"
        local lsp_binary="dist/linux-x86_64-static/janus-lsp-server"

        if [[ ! -f "$linux_binary" ]]; then
            log_warning "No Linux binary found at $linux_binary, skipping Linux packages"
            return
        fi

        log_info "Building Linux packages from $linux_binary"

        # Debian package (.deb)
        log_info "Building Debian package..."
        local deb_dir="janus_${version}_amd64"
        mkdir -p "$deb_dir/usr/bin"
        mkdir -p "$deb_dir/DEBIAN"

        cp "$linux_binary" "$deb_dir/usr/bin/janus"
        chmod +x "$deb_dir/usr/bin/janus"

        if [[ -f "$lsp_binary" ]]; then
            cp "$lsp_binary" "$deb_dir/usr/bin/janus-lsp-server"
            chmod +x "$deb_dir/usr/bin/janus-lsp-server"
        fi

        cat > "$deb_dir/DEBIAN/control" << EOF
Package: janus-lang
Version: $version
Section: devel
Priority: optional
Architecture: amd64
Maintainer: Janus Development Team <dev@janus-lang.org>
Description: Janus programming language compiler
 Janus is a sy "$ls programming language that bridges C's raw power
 with future-proof safety and metaprogramming capabilities.
EOF

        if command -v dpkg-deb >/dev/null 2>&1; then
            dpkg-deb --build "$deb_dir"
            mv "${deb_dir}.deb" "packages/janus-${version}_amd64.deb"
            log_success "Debian package built: janus-${version}_amd64.deb"
        else
            log_warning "dpkg-deb not available, skipping .deb package"
        fi
        rm -rf "$deb_dir"

        # RPM package (.rpm)
        log_info "Building RPM package..."
        if command -v rpmbuild >/dev/null 2>&1; then
            mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

            cat > rpmbuild/SPECS/janus.spec << EOF
Name: janus-lang
Version: $version
Release: 1%{?dist}
Summary: Janus programming language compiler
License: LSL-1.0
URL: https://github.com/janus-lang/janus

%description
Janus is a systems programming language that bridges C's raw power
with future-proof safety and metaprogramming capabilities.

%install
mkdir -p %{buildroot}/usr/bin
cp $PWD/$linux_binary %{buildroot}/usr/bin/janus
EOF
            if [[ -f "$lsp_binary" ]]; then
                echo "cp $PWD/$lsp_binary %{buildroot}/usr/bin/janus-lsp-server" >> rpmbuild/SPECS/janus.spec
            fi

            cat >> rpmbuild/SPECS/janus.spec << EOF

%files
/usr/bin/janus
EOF
            if [[ -f "$lsp_binary" ]]; then
                echo "/usr/bin/janus-lsp-server" >> rpmbuild/SPECS/janus.spec
            fi

            if rpmbuild --define "_topdir $PWD/rpmbuild" -bb rpmbuild/SPECS/janus.spec 2>/dev/null; then
                find rpmbuild/RPMS -name "*.rpm" -exec cp {} packages/ \;
                log_success "RPM package built"
            else
                log_warning "RPM build failed"
            fi
            rm -rf rpmbuild
        else
            log_warning "rpmbuild not available, skipping .rpm package"
        fi

        # Arch Linux package (.pkg.tar.zst)
        log_info "Building Arch Linux package..."
        if command -v makepkg >/dev/null 2>&1; then
            mkdir -p arch-build
            cd arch-build

            cat > PKGBUILD << EOF
pkgname=janus-lang
pkgver=$version
pkgrel=1
pkgdesc="Janus programming language compiler"
arch=('x86_64')
url="https://github.com/janus-lang/janus"
license=('LSL-1.0')
source=()

package() {
    install -Dm755 "../$linux_binary" "\$pkgdir/usr/bin/janus"
EOF
            if [[ -f "../$lsp_binary" ]]; then
                echo "    install -Dm755 \"../$lsp_binary\" \"\$pkgdir/usr/bin/janus-lsp-server\"" >> PKGBUILD
            fi
            echo "}" >> PKGBUILD

            if makepkg -f --noconfirm 2>/dev/null; then
                cp *.pkg.tar.* ../packages/
                log_success "Arch package built"
            else
                log_warning "Arch package build failed"
            fi
            cd ..
            rm -rf arch-build
        else
            log_warning "makepkg not available, skipping .pkg.tar.zst package"
        fi

        # Alpine package (.apk)
        log_info "Building Alpine package..."
        if command -v abuild >/dev/null 2>&1; then
            mkdir -p alpine-build
            cd alpine-build

            cat > APKBUILD << EOF
pkgname=janus-lang
pkgver=$version
pkgrel=0
pkgdesc="Janus programming language compiler"
url="https://github.com/janus-lang/janus"
arch="x86_64"
license="LSL-1.0"
source=""

package() {
    install -Dm755 "../$linux_binary" "\$pkgdir/usr/bin/janus"
EOF
            if [[ -f "../$lsp_binary" ]]; then
                echo "    install -Dm755 \"../$lsp_binary\" \"\$pkgdir/usr/bin/janus-lsp-server\"" >> APKBUILD
            fi
            echo "}" >> APKBUILD

            if abuild -r 2>/dev/null; then
                find ~/packages -name "janus-lang-*.apk" -exec cp {} ../packages/ \; 2>/dev/null || true
                log_success "Alpine package built"
            else
                log_warning "Alpine package build failed"
            fi
            cd ..
            rm -rf alpine-build
        else
            log_warning "abuild not available, skipping .apk package"
        fi
    }

    # Build Linux packages
    build_linux_packages

    # Package platform binaries as archives
    for platform_dir in dist/*/; do
        if [[ -d "$platform_dir" ]]; then
            platform_name=$(basename "$platform_dir")

            log_info "Creating archive for $platform_name..."

            case "$platform_name" in
                *windows*)
                    cd dist && zip -r "../packages/janus-${version}-$platform_name.zip" "$platform_name"
                    cd ..
                    ;;
                *)
                    tar -czf "packages/janus-${version}-$platform_name.tar.gz" -C dist "$platform_name"
                    ;;
            esac

            log_success "Archived janus-${version}-$platform_name"
        fi
    done

    # Generate checksums
    cd packages
    if ls *.deb *.rpm *.pkg.tar.* *.apk *.tar.gz *.zip >/dev/null 2>&1; then
        sha256sum * > SHA256SUMS
        log_success "Checksums generated"
    fi
    cd ..

    log_success "All packages created in packages/ directory"
    log_info "Available packages:"
    ls -la packages/
}

publish_release() {
    local version="$1"

    if [[ -z "$version" ]]; then
        log_error "Version required for publish command"
        usage
        exit 1
    fi

    log_info "Publishing release version $ve"

    # Check if we're on the correct version branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "version_$version" ]]; then
        log_error "Not on version branch version_$version (current: $current_branch)"
        exit 1
    fi

    # Final quality check
    log_info "Final quality check..."
    zig build test || {
        log_error "Tests failed"
        exit 1
    }

    # Create and push tag
    log_info "Creating tag v$version..."
    git tag -a "v$version" -m "Release version $version"

    # Push branch and tag
    log_info "Pushing version branch and tag..."
    git push origin "version_$version"
    git push origin "v$version"

    log_success "Release $version published!"
    log_info "CI/CD pipeline will automatically create the release with binaries"
}

# Main script logic
case "${1:-}" in
    prepare)
        check_prerequisites
        prepare_release "$2"
        ;;
    build)
        check_prerequisites
        build_binaries
        ;;
    package)
        check_prerequisites
        package_binaries
        ;;
    publish)
        check_prerequisites
        publish_release "$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac

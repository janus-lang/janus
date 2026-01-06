#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

# Janus Version Management Script - Hybrid Versioning Scheme
# Handles version bumping with packager-friendly hybrid format
# Supports semver for releases, dev.<date>.r<rev>.g<short> for rolling

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$PROJECT_ROOT/VERSION"

show_help() {
    cat << EOF
Janus Version Management Script - Hybrid Versioning

Usage: $0 <command> [options]

Commands:
  bump [major|minor|patch|dev|hybrid]  Bump version with hybrid scheme
  set <version>                        Set specific version
  show                                 Show current version and components
  build                                Build with current version
  release                              Create release build

Hybrid Versioning Scheme:
  Stable:     <semver>                    (e.g., 0.1.8)
  Development: dev.<date>.r<rev>.g<short>  (e.g., dev.20251015.r42.g214a4a8)
  With Crypto: ...cid<hex>                (e.g., dev.20251015.r42.g214a4a8.cid1a2b3c4d)

Examples:
  $0 bump patch                        # 0.1.7 -> 0.1.8
  $0 bump dev                          # 0.1.8 -> dev.20251015.r0.g214a4a8
  $0 bump hybrid                       # dev.20251015.r0.g214a4a8 -> dev.20251015.r1.g214a4a9
  $0 set 1.0.0-beta.1                  # Set specific version
  $0 release                           # Create release build

Packager Compatibility:
  - Arch AUR: dev.<date>.r<rev>.g<short>-pkgrel
  - Nix: <date>.git<short> or rev
  - Debian: <semver> for releases
  - Guix: .cid<hex> for crypto verification
EOF
}

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "0.1.0-dev.$(date +%Y%m%d)"
    fi
}

set_version() {
    local new_version="$1"
    echo "$new_version" > "$VERSION_FILE"
    echo "📝 Version set to: $new_version"
}

detect_version_type() {
    local version="$1"

    if [[ "$version" =~ ^dev\.[0-9]{8}\.r[0-9]+\.g[0-9a-f]+$ ]]; then
        echo "dev"
    elif [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "stable"
    elif [[ "$version" =~ ^[0-9]{8}\.r[0-9]+\.g[0-9a-f]+$ ]]; then
        echo "snapshot"
    else
        echo "unknown"
    fi
}

generate_hybrid_version() {
    local base_version="$1"
    local bump_type="$2"

    # Remove any existing suffixes for clean bumping
    local clean_version=$(echo "$base_version" | sed 's/-.*$//' | sed 's/\.cid[0-9a-f]*$//')

    # Split version into components
    IFS='.' read -r major minor patch <<< "$clean_version"

    case "$bump_type" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            echo "$major.$minor.$patch"
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            echo "$major.$minor.$patch"
            ;;
        "patch")
            patch=$((patch + 1))
            echo "$major.$minor.$patch"
            ;;
        "dev")
            local date=$(date -u +%Y%m%d)
            local rev=$(git rev-list --count HEAD ^$(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~))
            local git=$(git rev-parse --short=7 HEAD)
            echo "dev.${date}.r${rev}.g${git}"
            ;;
        "hybrid")
            local current_type=$(detect_version_type "$base_version")
            local date=$(date -u +%Y%m%d)
            local rev=$(git rev-list --count HEAD ^$(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~))
            local git=$(git rev-parse --short=7 HEAD)

            case "$current_type" in
                "dev")
                    # Increment revision for dev builds
                    local current_rev=$(echo "$base_version" | sed -n 's/.*\.r\([0-9]\+\)\.g.*/\1/p')
                    local new_rev=$((current_rev + 1))
                    echo "dev.${date}.r${new_rev}.g${git}"
                    ;;
                "stable")
                    # Convert stable to dev
                    echo "dev.${date}.r0.g${git}"
                    ;;
                *)
                    echo "dev.${date}.r${rev}.g${git}"
                    ;;
            esac
            ;;
        *)
            echo "❌ Invalid bump type: $bump_type"
            echo "   Valid types: major, minor, patch, dev, hybrid"
            exit 1
            ;;
    esac
}

bump_version() {
    local bump_type="$1"
    local current_version=$(get_current_version)

    echo "📈 Bumping version: $current_version (type: $bump_type)"

    local new_version=$(generate_hybrid_version "$current_version" "$bump_type")
    set_version "$new_version"
}

trigger_build() {
    local build_type="$1"

    echo ""
    echo "🚀 Triggering automated build..."

    cd "$PROJECT_ROOT"

    case "$build_type" in
        "release")
            echo "🎯 Creating release build..."
            ./scripts/automated-build.sh
            ;;
        "dev"|*)
            echo "🔨 Creating development build..."
            ./scripts/automated-build.sh
            ;;
    esac
}

main() {
    cd "$PROJECT_ROOT"

    case "${1:-show}" in
        "bump")
            if [ -z "$2" ]; then
                echo "❌ Bump type required"
                show_help
                exit 1
            fi
            bump_version "$2"
            trigger_build "dev"
            ;;
        "set")
            if [ -z "$2" ]; then
                echo "❌ Version required"
                show_help
                exit 1
            fi
            set_version "$2"
            trigger_build "dev"
            ;;
        "show")
            local current_version=$(get_current_version)
            local version_type=$(detect_version_type "$current_version")

            echo "Current version: $current_version"
            echo "Version type: $version_type"

            case "$version_type" in
                "dev")
                    echo "Components:"
                    echo "  - Format: Development build"
                    echo "  - Date: $(echo "$current_version" | sed -n 's/dev\.\([0-9]\{8\}\)\.r.*/\1/p')"
                    echo "  - Revision: $(echo "$current_version" | sed -n 's/.*\.r\([0-9]\+\)\.g.*/\1/p')"
                    echo "  - Git: $(echo "$current_version" | sed -n 's/.*\.g\([0-9a-f]\+\).*/\1/p')"
                    ;;
                "stable")
                    echo "Components:"
                    echo "  - Format: Stable release"
                    echo "  - Semver: $current_version"
                    ;;
                "snapshot")
                    echo "Components:"
                    echo "  - Format: Point-in-time snapshot"
                    echo "  - Date: $(echo "$current_version" | sed -n 's/\([0-9]\{8\}\)\.r.*/\1/p')"
                    echo "  - Revision: $(echo "$current_version" | sed -n 's/.*\.r\([0-9]\+\)\.g.*/\1/p')"
                    echo "  - Git: $(echo "$current_version" | sed -n 's/.*\.g\([0-9a-f]\+\).*/\1/p')"
                    ;;
            esac
            ;;
        "build")
            trigger_build "dev"
            ;;
        "release")
            # For releases, ensure we have a clean version (no -dev suffix)
            current_version=$(get_current_version)
            if [[ "$current_version" == *"-dev."* ]]; then
                echo "🎯 Converting dev version to release version..."
                clean_version=$(echo "$current_version" | sed 's/-dev\..*$//')
                set_version "$clean_version"
            fi
            trigger_build "release"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo "❌ Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"

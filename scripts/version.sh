#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation
#
# Janus CalVer Version Management Script
# Format: YYYY.Q.PATCH (e.g., 2026.1.0)
# LTS: Q4 Even Years (4-year support)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

VERSION_FILE="VERSION"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_ROOT"

# Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Get current version
get_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "2026.1.0"
    fi
}

# Get Git short hash
get_git_hash() {
    git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown"
}

# Get branch name
get_branch() {
    git branch --show-current 2>/dev/null || echo "unknown"
}

# Check if repo is dirty
is_dirty() {
    ! git diff --quiet || ! git diff --staged --quiet
}

# Parse CalVer version (YYYY.Q.PATCH)
parse_version() {
    local version=$1
    local year=$(echo "$version" | cut -d'.' -f1)
    local quarter=$(echo "$version" | cut -d'.' -f2)
    local patch=$(echo "$version" | cut -d'.' -f3)
    
    echo "$year|$quarter|$patch"
}

# Check if version is LTS (Q4 Even Year)
is_lts_version() {
    local version=$1
    local parsed=$(parse_version "$version")
    
    IFS='|' read -r year quarter patch <<< "$parsed"
    
    if [ "$quarter" = "4" ] && [ $((year % 2)) -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Increment version
bump_version() {
    local bump_type=$1
    local current=$(get_version)
    local parsed=$(parse_version "$current")
    
    IFS='|' read -r year quarter patch <<< "$parsed"
    
    local new_version=""
    
    case "$bump_type" in
        quarter|q)
            quarter=$((quarter + 1))
            if [ $quarter -gt 4 ]; then
                year=$((year + 1))
                quarter=1
            fi
            patch=0
            new_version="${year}.${quarter}.${patch}"
            ;;
        patch|p)
            patch=$((patch + 1))
            new_version="${year}.${quarter}.${patch}"
            ;;
        year|y)
            year=$((year + 1))
            quarter=1
            patch=0
            new_version="${year}.${quarter}.${patch}"
            ;;
        *)
            print_status "$RED" "❌ Unknown bump type: $bump_type"
            echo "Valid types: quarter (q), patch (p), year (y)"
            exit 1
            ;;
    esac
    
    echo "$new_version"
}

# Validate CalVer format (YYYY.Q.PATCH)
validate_version() {
    local version=$1
    if echo "$version" | grep -qE '^[0-9]{4}\.[1-4]\.[0-9]+$'; then
        return 0
    else
        return 1
    fi
}

# Show current version
cmd_show() {
    local version=$(get_version)
    local branch=$(get_branch)
    local hash=$(get_git_hash)
    local dirty=$(is_dirty && echo "dirty" || echo "clean")
    local lts=$(is_lts_version "$version" && echo "LTS (4-year support)" || echo "Standard (6-month support)")
    
    print_status "$BLUE" "📦 Janus Version Information"
    echo ""
    echo "  Version: $version"
    echo "  Type:    $lts"
    echo "  Branch:  $branch"
    echo "  Commit:  $hash"
    echo "  Status:  $dirty"
    echo ""
    
    if validate_version "$version"; then
        print_status "$GREEN" "✅ CalVer format valid"
    else
        print_status "$RED" "❌ CalVer format invalid"
        exit 1
    fi
    
    # Show next LTS
    local parsed=$(parse_version "$version")
    IFS='|' read -r year quarter patch <<< "$parsed"
    
    local next_lts_year=$year
    if [ $((year % 2)) -ne 0 ]; then
        next_lts_year=$((year + 1))
    elif [ "$quarter" -eq 4 ]; then
        next_lts_year=$((year + 2))
    fi
    
    echo ""
    print_status "$YELLOW" "📅 Next LTS: ${next_lts_year}.4.0 (Citadel)"
}

# Bump version
cmd_bump() {
    local bump_type=$1
    local current=$(get_version)
    local new_version=$(bump_version "$bump_type")
    
    print_status "$BLUE" "📦 Version Bump: $bump_type"
    echo ""
    echo "  Current: $current"
    echo "  New:     $new_version"
    
    if is_lts_version "$new_version"; then
        print_status "$YELLOW" "🏰 LTS Release (4-year support)"
    fi
    
    echo ""
    
    if ! validate_version "$new_version"; then
        print_status "$RED" "❌ Generated version is invalid: $new_version"
        exit 1
    fi
    
    # Write new version
    echo "$new_version" > "$VERSION_FILE"
    print_status "$GREEN" "✅ Version updated to $new_version"
    
    # Suggest next steps
    echo ""
    print_status "$YELLOW" "💡 Next steps:"
    echo "  git add VERSION"
    echo "  git commit -m \"chore: bump version to $new_version\""
}

# Validate current version
cmd_validate() {
    local version=$(get_version)
    
    print_status "$BLUE" "🔍 Validating version: $version"
    echo ""
    
    if ! validate_version "$version"; then
        print_status "$RED" "❌ Invalid CalVer format"
        echo "Expected: YYYY.Q.PATCH (e.g., 2026.1.0)"
        exit 1
    fi
    
    print_status "$GREEN" "✅ CalVer format valid"
    
    if is_lts_version "$version"; then
        print_status "$GREEN" "✅ LTS version (Q4 Even Year)"
    fi
}

# Show help
cmd_help() {
    cat <<EOF
Janus CalVer Version Management

Format: YYYY.Q.PATCH (e.g., 2026.1.0)
LTS: Q4 Even Years (4-year support)

Usage:
  ./scripts/version.sh show              Show current version
  ./scripts/version.sh bump <type>      Bump version
  ./scripts/version.sh validate          Validate current version
  ./scripts/version.sh help              Show this help

Bump Types:
  quarter (q)    Increment quarter (2026.1.0 → 2026.2.0)
  patch (p)      Increment patch (2026.1.0 → 2026.1.1)
  year (y)       Increment year (2026.4.0 → 2027.1.0)

Examples:
  ./scripts/version.sh show
  ./scripts/version.sh bump quarter
  ./scripts/version.sh bump patch

LTS Releases:
  2026.4.0  Citadel Alpha   (LTS until 2030)
  2028.4.0  Citadel Beta    (LTS until 2032)
  2030.4.0  Citadel Gamma   (LTS until 2034)

EOF
}

# Main command dispatcher
main() {
    local cmd=${1:-show}
    
    case "$cmd" in
        show)
            cmd_show
            ;;
        bump)
            local bump_type=${2:-quarter}
            cmd_bump "$bump_type"
            ;;
        validate)
            cmd_validate
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            print_status "$RED" "❌ Unknown command: $cmd"
            echo "Run './scripts/version.sh help' for usage"
            exit 1
            ;;
    esac
}

main "$@"

#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Pre-commit hook to check license headers in staged files
# Usage: Install as .git/hooks/pre-commit or run manually

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# License mapping based on directory
declare -A LICENSE_MAP=(
    ["src/"]="LSL-1.0"
    ["compiler/"]="LSL-1.0"
    ["daemon/"]="LSL-1.0"
    ["lsp/"]="LSL-1.0"
    ["tools/"]="LSL-1.0"
    ["tests/"]="LSL-1.0"
    ["scripts/"]="LSL-1.0"
    ["packaging/"]="LSL-1.0"
    ["vscode-extension/"]="LSL-1.0"
    ["build.zig"]="LSL-1.0"
    ["std/"]="Apache-2.0"
    ["packages/"]="CC0-1.0"
    ["examples/"]="CC0-1.0"
)

# File extensions that require license headers
EXTENSIONS=("zig" "jan" "ts" "js" "py" "sh" "c" "h")

# Function to determine expected license for a file
get_expected_license() {
    local file="$1"

    # Check exact file matches first
    if [[ -n "${LICENSE_MAP[$file]:-}" ]]; then
        echo "${LICENSE_MAP[$file]}"
        return
    fi

    # Check directory prefixes
    for dir in "${!LICENSE_MAP[@]}"; do
        if [[ "$file" == "$dir"* ]]; then
            echo "${LICENSE_MAP[$dir]}"
            return
        fi
    done

    # Default to LSL-1.0 for unmatched files
    echo "LSL-1.0"
}

# Function to check if file needs license header
needs_license_header() {
    local file="$1"
    local ext="${file##*.}"

    # Skip if not a source file
    for valid_ext in "${EXTENSIONS[@]}"; do
        if [[ "$ext" == "$valid_ext" ]]; then
            return 0
        fi
    done

    # Skip generated files, vendor directories, etc.
    if [[ "$file" == *"/node_modules/"* ]] || \
       [[ "$file" == *"/zig-out/"* ]] || \
       [[ "$file" == *"/.git/"* ]] || \
       [[ "$file" == *"/.kiro/"* ]] || \
       [[ "$file" == *"/third_party/"* ]]; then
        return 1
    fi

    return 0
}

# Function to get comment style for file extension
get_comment_style() {
    local ext="$1"
    case "$ext" in
        "zig"|"jan"|"ts"|"js"|"c"|"h")
            echo "//"
            ;;
        "py"|"sh")
            echo "#"
            ;;
        "md")
            echo "<!--"
            ;;
        *)
            echo "//"
            ;;
    esac
}

# Function to check license header in file
check_license_header() {
    local file="$1"
    local expected_license="$2"
    local ext="${file##*.}"
    local comment_style
    comment_style=$(get_comment_style "$ext")

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Read first few lines of file
    local header
    header=$(head -n 10 "$file")

    # Check for SPDX license identifier
    if echo "$header" | grep -q "SPDX-License-Identifier: $expected_license"; then
        # Check for copyright line
        if echo "$header" | grep -q "Copyright (c) 2026 Self Sovereign Society Foundation"; then
            return 0
        else
            echo "Missing or incorrect copyright line in $file"
            return 1
        fi
    else
        echo "Missing or incorrect SPDX license identifier in $file"
        echo "Expected: $expected_license"
        return 1
    fi
}

# Function to show expected header for a file
show_expected_header() {
    local file="$1"
    local license="$2"
    local ext="${file##*.}"
    local comment_style
    comment_style=$(get_comment_style "$ext")

    echo "Expected header for $file:"
    echo ""

    if [[ "$ext" == "sh" ]]; then
        echo "#!/bin/bash"
    fi

    if [[ "$ext" == "md" ]]; then
        echo "<!--"
        echo "SPDX-License-Identifier: $license"
        echo "Copyright (c) 2026 Self Sovereign Society Foundation"
        echo "-->"
    else
        echo "$comment_style SPDX-License-Identifier: $license"
        echo "$comment_style Copyright (c) 2026 Self Sovereign Society Foundation"
    fi
    echo ""
}

# Main function
main() {
    local exit_code=0
    local files_checked=0
    local files_failed=0

    echo -e "${GREEN}🔍 Checking license headers in staged files...${NC}"

    # Get list of staged files
    local staged_files
    if command -v git >/dev/null 2>&1; then
        staged_files=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
    else
        echo -e "${YELLOW}⚠️  Git not available, checking all files${NC}"
        staged_files=$(find . -type f -name "*.zig" -o -name "*.jan" -o -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.sh" -o -name "*.c" -o -name "*.h" | grep -v -E "(node_modules|zig-out|\.git|\.kiro|third_party)" || true)
    fi

    if [[ -z "$staged_files" ]]; then
        echo -e "${GREEN}✅ No source files to check${NC}"
        return 0
    fi

    # Check each staged file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        if needs_license_header "$file"; then
            files_checked=$((files_checked + 1))
            expected_license=$(get_expected_license "$file")

            if ! check_license_header "$file" "$expected_license"; then
                files_failed=$((files_failed + 1))
                exit_code=1
                echo -e "${RED}❌ License header violation: $file${NC}"
                show_expected_header "$file" "$expected_license"
                echo -e "${YELLOW}📖 See docs/LICENSE-HEADERS.md for complete guide${NC}"
                echo ""
            fi
        fi
    done <<< "$staged_files"

    # Summary
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✅ All $files_checked files have correct license headers${NC}"
    else
        echo -e "${RED}❌ $files_failed of $files_checked files have license header violations${NC}"
        echo -e "${YELLOW}💡 Fix the headers above and try again${NC}"
        echo -e "${YELLOW}📖 Complete guide: docs/LICENSE-HEADERS.md${NC}"
    fi

    return $exit_code
}

# Install as git hook if requested
if [[ "${1:-}" == "--install" ]]; then
    if [[ ! -d ".git" ]]; then
        echo -e "${RED}❌ Not in a git repository${NC}"
        exit 1
    fi

    hook_file=".git/hooks/pre-commit"

    # Detect Git hosting platform
    local platform="unknown"
    if [[ -d ".github" ]]; then
        platform="GitHub"
    elif [[ -d ".forgejo" ]]; then
        platform="Forgejo"
    elif [[ -d ".gitea" ]]; then
        platform="Gitea"
    fi

    if [[ -f "$hook_file" ]]; then
        echo -e "${YELLOW}⚠️  Pre-commit hook already exists${NC}"
        echo "Current hook:"
        cat "$hook_file"
        echo ""
        read -p "Replace existing hook? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted"
            exit 1
        fi
    fi

    cat > "$hook_file" << 'EOF'
#!/bin/bash
# Auto-generated pre-commit hook for license header checking
# Compatible with GitHub, Forgejo, and Gitea

exec scripts/pre-commit-license-check.sh
EOF

    chmod +x "$hook_file"
    echo -e "${GREEN}✅ Pre-commit hook installed${NC}"
    echo "Hook will run automatically on git commit"
    echo "Platform detected: $platform"
    echo ""
    echo "CI/CD workflows available:"
    [[ -f ".github/workflows/license-check.yml" ]] && echo "  ✅ GitHub Actions: .github/workflows/license-check.yml"
    [[ -f ".forgejo/workflows/license-check.yml" ]] && echo "  ✅ Forgejo: .forgejo/workflows/license-check.yml"
    [[ -f ".gitea/workflows/license-check.yml" ]] && echo "  ✅ Gitea: .gitea/workflows/license-check.yml"
    exit 0
fi

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "License Header Pre-commit Check"
    echo ""
    echo "Usage:"
    echo "  $0                 Check staged files"
    echo "  $0 --install       Install as git pre-commit hook"
    echo "  $0 --help          Show this help"
    echo ""
    echo "This script checks that all source files have appropriate license headers"
    echo "based on their directory location. See docs/LICENSE-HEADERS.md for details."
    exit 0
fi

# Run the main check
main "$@"

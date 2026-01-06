#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Automated tool to add license headers to existing files
# Usage: ./scripts/add-license-headers.sh [--dry-run] [--force] [file_pattern...]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=false
FORCE=false

# License mapping (same as pre-commit hook)
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

# Function to check if file already has license header
has_license_header() {
    local file="$1"
    local expected_license="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Read first few lines of file
    local header
    header=$(head -n 10 "$file")

    # Check for SPDX license identifier and copyright
    if echo "$header" | grep -q "SPDX-License-Identifier: $expected_license" && \
       echo "$header" | grep -q "Copyright (c) 2026 Self Sovereign Society Foundation"; then
        return 0
    fi

    return 1
}

# Function to generate license header for a file
generate_header() {
    local file="$1"
    local license="$2"
    local ext="${file##*.}"

    case "$ext" in
        "zig"|"jan"|"ts"|"js"|"c"|"h")
            echo "// SPDX-License-Identifier: $license"
            echo "// Copyright (c) 2026 Self Sovereign Society Foundation"
            echo ""
            ;;
        "py")
            echo "# SPDX-License-Identifier: $license"
            echo "# Copyright (c) 2026 Self Sovereign Society Foundation"
            echo ""
            ;;
        "sh")
            # For shell scripts, preserve shebang if it exists
            if head -n 1 "$file" | grep -q "^#!"; then
                head -n 1 "$file"
                echo "# SPDX-License-Identifier: $license"
                echo "# Copyright (c) 2026 Self Sovereign Society Foundation"
                echo ""
                tail -n +2 "$file"
            else
                echo "# SPDX-License-Identifier: $license"
                echo "# Copyright (c) 2026 Self Sovereign Society Foundation"
                echo ""
                cat "$file"
            fi
            return
            ;;
        "md")
            echo "<!--"
            echo "SPDX-License-Identifier: $license"
            echo "Copyright (c) 2026 Self Sovereign Society Foundation"
            echo "-->"
            echo ""
            ;;
        *)
            echo "// SPDX-License-Identifier: $license"
            echo "// Copyright (c) 2026 Self Sovereign Society Foundation"
            echo ""
            ;;
    esac

    # Add original file content (except for shell scripts, handled above)
    if [[ "$ext" != "sh" ]]; then
        cat "$file"
    fi
}

# Function to add header to a file
add_header_to_file() {
    local file="$1"
    local license="$2"
    local temp_file
    temp_file=$(mktemp)

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DRY RUN]${NC} Would add $license header to: $file"
        return 0
    fi

    # Generate new file content with header
    generate_header "$file" "$license" > "$temp_file"

    # Replace original file
    if mv "$temp_file" "$file"; then
        echo -e "${GREEN}✅${NC} Added $license header to: $file"
        return 0
    else
        echo -e "${RED}❌${NC} Failed to add header to: $file"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to find files that need headers
find_files_needing_headers() {
    local patterns=("$@")
    local files=()

    if [[ ${#patterns[@]} -eq 0 ]]; then
        # Default: find all source files
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find . -type f \( -name "*.zig" -o -name "*.jan" -o -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.sh" -o -name "*.c" -o -name "*.h" \) -print0)
    else
        # Use provided patterns
        for pattern in "${patterns[@]}"; do
            while IFS= read -r -d '' file; do
                files+=("$file")
            done < <(find . -type f -name "$pattern" -print0)
        done
    fi

    # Filter and check each file
    local needs_header=()
    for file in "${files[@]}"; do
        # Remove leading ./
        file="${file#./}"

        if needs_license_header "$file"; then
            local expected_license
            expected_license=$(get_expected_license "$file")

            if ! has_license_header "$file" "$expected_license" || [[ "$FORCE" == "true" ]]; then
                needs_header+=("$file:$expected_license")
            fi
        fi
    done

    printf '%s\n' "${needs_header[@]}"
}

# Function to show summary
show_summary() {
    local total_files="$1"
    local processed_files="$2"
    local failed_files="$3"

    echo ""
    echo "📊 Summary:"
    echo "  Total files found: $total_files"
    echo "  Files processed: $processed_files"
    echo "  Files failed: $failed_files"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}💡 This was a dry run. Use --force to actually add headers.${NC}"
        echo -e "${YELLOW}📖 Review the changes above, then run without --dry-run${NC}"
    elif [[ "$processed_files" -gt 0 ]]; then
        echo ""
        echo -e "${GREEN}✅ License headers added successfully!${NC}"
        echo -e "${YELLOW}💡 Run git diff to review the changes${NC}"
        echo -e "${YELLOW}📖 Commit the changes when ready${NC}"
    fi
}

# Function to show help
show_help() {
    cat << EOF
Automated License Header Addition Tool

Usage:
  $0 [OPTIONS] [FILE_PATTERNS...]

Options:
  --dry-run     Show what would be done without making changes
  --force       Add headers even if files already have them (replace)
  --help        Show this help message

Examples:
  $0                          # Add headers to all source files
  $0 --dry-run               # Preview changes without applying
  $0 --force src/*.zig       # Force add headers to specific files
  $0 "*.jan"                 # Add headers to all .jan files

File Patterns:
  If no patterns are provided, all source files will be processed.
  Patterns are passed to 'find -name', so shell wildcards work.

License Assignment:
  - src/, compiler/, daemon/, lsp/, tools/     → LSL-1.0
  - std/                                       → Apache-2.0
  - packages/, examples/                       → CC0-1.0
  - Other directories                          → LSL-1.0 (default)

See docs/LICENSE-HEADERS.md for complete documentation.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Remaining arguments are file patterns
            break
            ;;
    esac
done

# Main execution
main() {
    echo -e "${GREEN}🔧 Automated License Header Addition${NC}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}🔍 DRY RUN MODE - No files will be modified${NC}"
    fi

    if [[ "$FORCE" == "true" ]]; then
        echo -e "${YELLOW}⚠️  FORCE MODE - Will replace existing headers${NC}"
    fi

    echo ""

    # Find files that need headers
    local files_needing_headers
    mapfile -t files_needing_headers < <(find_files_needing_headers "$@")

    if [[ ${#files_needing_headers[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ All source files already have correct license headers${NC}"
        return 0
    fi

    echo -e "${BLUE}📋 Found ${#files_needing_headers[@]} files needing license headers:${NC}"
    echo ""

    # Process each file
    local processed=0
    local failed=0

    for file_info in "${files_needing_headers[@]}"; do
        local file="${file_info%:*}"
        local license="${file_info#*:}"

        if add_header_to_file "$file" "$license"; then
            processed=$((processed + 1))
        else
            failed=$((failed + 1))
        fi
    done

    show_summary "${#files_needing_headers[@]}" "$processed" "$failed"

    if [[ "$failed" -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Change to repository root
cd "$REPO_ROOT"

# Run main function
main "$@"

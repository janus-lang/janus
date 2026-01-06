#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
# License header format validation tool
# Usage: ./scripts/validate-license-headers.sh [--fix] [--check-year] [file_pattern...]

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
FIX_MODE=false
CHECK_YEAR=false
CURRENT_YEAR=$(date +%Y)

# SPDX license database with validation patterns
declare -A SPDX_PATTERNS=(
    ["LSL-1.0"]="^EUPL-1\.2$"
    ["Apache-2.0"]="^Apache-2\.0$"
    ["CC0-1.0"]="^CC0-1\.0$"
    ["MIT"]="^MIT$"
    ["GPL-3.0-only"]="^GPL-3\.0-only$"
    ["BSD-2-Clause"]="^BSD-2-Clause$"
    ["LSL-1.0"]="^SSS-1\.0$"
    ["MPL-2.0"]="^MPL-2\.0$"
)

# Valid copyright patterns
COPYRIGHT_PATTERN="^Copyright \(c\) [0-9]{4}(-[0-9]{4})? [A-Za-z0-9 ]+$"

# Function to validate SPDX license format
validate_spdx_format() {
    local license="$1"

    # Check if license exists in our database
    if [[ -n "${SPDX_PATTERNS[$license]:-}" ]]; then
        local pattern="${SPDX_PATTERNS[$license]}"
        if [[ "$license" =~ $pattern ]]; then
            return 0
        fi
    fi

    return 1
}

# Function to validate copyright format
validate_copyright_format() {
    local copyright="$1"

    # Remove comment prefixes
    copyright=$(echo "$copyright" | sed 's/^[#\/\*]*[ ]*//')

    # Check basic format
    if [[ "$copyright" =~ ^Copyright\ \(c\)\ [0-9]{4}(-[0-9]{4})?\ .+$ ]]; then
        return 0
    fi

    return 1
}

# Function to extract year from copyright
extract_copyright_year() {
    local copyright="$1"
    echo "$copyright" | sed -n 's/.*Copyright (c) \([0-9]\{4\}\).*/\1/p'
}

# Function to validate header format in file
validate_file_header() {
    local file="$1"
    local issues=()
    local suggestions=()

    if [[ ! -f "$file" ]]; then
        echo "ERROR:File not found"
        return 1
    fi

    local ext="${file##*.}"
    local header
    header=$(head -n 10 "$file")

    # Determine expected comment style
    local comment_prefix
    case "$ext" in
        "zig"|"jan"|"ts"|"js"|"c"|"h")
            comment_prefix="//"
            ;;
        "py"|"sh")
            comment_prefix="#"
            ;;
        "md")
            comment_prefix="<!--"
            ;;
        *)
            comment_prefix="//"
            ;;
    esac

    # Extract SPDX line
    local spdx_line=""
    local spdx_license=""
    if echo "$header" | grep -q "SPDX-License-Identifier:"; then
        spdx_line=$(echo "$header" | grep "SPDX-License-Identifier:" | head -n 1)
        spdx_license=$(echo "$spdx_line" | sed 's/.*SPDX-License-Identifier: *\([^ ]*\).*/\1/')
    else
        issues+=("Missing SPDX-License-Identifier line")
    fi

    # Extract copyright line
    local copyright_line=""
    local copyright_text=""
    if echo "$header" | grep -q "Copyright"; then
        copyright_line=$(echo "$header" | grep "Copyright" | head -n 1)
        copyright_text=$(echo "$copyright_line" | sed 's/[^#\/]*\(Copyright.*\)/\1/')
    else
        issues+=("Missing Copyright line")
    fi

    # Validate SPDX format
    if [[ -n "$spdx_license" ]]; then
        if ! validate_spdx_format "$spdx_license"; then
            issues+=("Invalid SPDX license identifier format: $spdx_license")
            suggestions+=("Use a valid SPDX identifier from: ${!SPDX_PATTERNS[*]}")
        fi

        # Check SPDX line format
        local expected_spdx="$comment_prefix SPDX-License-Identifier: $spdx_license"
        if [[ "$ext" == "md" ]]; then
            expected_spdx="SPDX-License-Identifier: $spdx_license"
        fi

        if [[ "$spdx_line" != "$expected_spdx" ]]; then
            issues+=("SPDX line format incorrect")
            suggestions+=("Expected: $expected_spdx")
        fi
    fi

    # Validate copyright format
    if [[ -n "$copyright_text" ]]; then
        if ! validate_copyright_format "$copyright_text"; then
            issues+=("Copyright line format incorrect")
            suggestions+=("Expected format: Copyright (c) YYYY Name or Copyright (c) YYYY-YYYY Name")
        fi

        # Check copyright line format
        local expected_copyright="$comment_prefix Copyright (c) 2026 Self Sovereign Society Foundation"
        if [[ "$ext" == "md" ]]; then
            expected_copyright="Copyright (c) 2026 Self Sovereign Society Foundation"
        fi

        if [[ "$CHECK_YEAR" == "true" ]]; then
            local copyright_year
            copyright_year=$(extract_copyright_year "$copyright_text")
            if [[ -n "$copyright_year" && "$copyright_year" != "$CURRENT_YEAR" ]]; then
                issues+=("Copyright year may be outdated: $copyright_year (current: $CURRENT_YEAR)")
                suggestions+=("Consider updating to: Copyright (c) $CURRENT_YEAR Self Sovereign Society Foundation")
            fi
        fi
    fi

    # Check header positioning
    local line_num=1
    local found_spdx=false
    local found_copyright=false
    local shebang_line=""

    while IFS= read -r line; do
        if [[ $line_num -eq 1 && "$line" =~ ^#! ]]; then
            shebang_line="$line"
        elif [[ "$line" =~ SPDX-License-Identifier ]]; then
            found_spdx=true
            if [[ "$ext" == "sh" && -n "$shebang_line" && $line_num -ne 2 ]]; then
                issues+=("SPDX line should be on line 2 (after shebang)")
            elif [[ "$ext" != "sh" && $line_num -ne 1 ]]; then
                issues+=("SPDX line should be on line 1")
            fi
        elif [[ "$line" =~ Copyright ]]; then
            found_copyright=true
            break
        fi
        line_num=$((line_num + 1))
        [[ $line_num -gt 5 ]] && break
    done <<< "$header"

    # Return results
    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "OK"
    else
        echo "ISSUES:$(IFS=';'; echo "${issues[*]}"):$(IFS=';'; echo "${suggestions[*]}")"
    fi
}

# Function to fix header format in file
fix_file_header() {
    local file="$1"
    local temp_file
    temp_file=$(mktemp)

    local ext="${file##*.}"
    local comment_prefix
    case "$ext" in
        "zig"|"jan"|"ts"|"js"|"c"|"h")
            comment_prefix="//"
            ;;
        "py"|"sh")
            comment_prefix="#"
            ;;
        "md")
            comment_prefix=""
            ;;
        *)
            comment_prefix="//"
            ;;
    esac

    # Read original file
    local content
    content=$(cat "$file")

    # Extract existing license and copyright if present
    local existing_license=""
    local existing_copyright=""

    if echo "$content" | head -n 10 | grep -q "SPDX-License-Identifier:"; then
        existing_license=$(echo "$content" | head -n 10 | grep "SPDX-License-Identifier:" | head -n 1 | sed 's/.*SPDX-License-Identifier: *\([^ ]*\).*/\1/')
    fi

    # Remove existing license headers (first few lines that contain SPDX or Copyright)
    local cleaned_content=""
    local skip_lines=true
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Keep shebang line
        if [[ $line_num -eq 1 && "$line" =~ ^#! ]]; then
            cleaned_content="$line"$'\n'
            continue
        fi

        # Skip license header lines
        if [[ "$skip_lines" == "true" ]]; then
            if [[ "$line" =~ (SPDX-License-Identifier|Copyright) ]] || \
               [[ "$line" =~ ^[[:space:]]*$ ]] || \
               [[ "$line" =~ ^[#\/\*]*[[:space:]]*$ ]]; then
                continue
            else
                skip_lines=false
            fi
        fi

        cleaned_content="$cleaned_content$line"$'\n'
    done <<< "$content"

    # Generate new header
    local new_header=""

    # Add shebang if it was present
    if [[ "$content" =~ ^#! ]]; then
        new_header=$(echo "$content" | head -n 1)$'\n'
    fi

    # Add license header
    if [[ "$ext" == "md" ]]; then
        new_header="$new_header<!--"$'\n'
        new_header="${new_header}SPDX-License-Identifier: LUL-1.0"$'\n'
        new_header="${new_header}Copyright (c) $CURRENT_YEAR Self Sovereign Society Foundation"$'\n'
        new_header="$new_header-->"$'\n'
    else
        new_header="$new_header$comment_prefix SPDX-License-Identifier: LUL-1.0"$'\n'
        new_header="$new_header$comment_prefix Copyright (c) $CURRENT_YEAR Self Sovereign Society Foundation"$'\n'
    fi

    new_header="$new_header"$'\n'

    # Combine header with cleaned content
    echo -n "$new_header" > "$temp_file"
    echo -n "$cleaned_content" >> "$temp_file"

    # Replace original file
    if mv "$temp_file" "$file"; then
        echo -e "${GREEN}✅${NC} Fixed header format in: $file"
        return 0
    else
        echo -e "${RED}❌${NC} Failed to fix header in: $file"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to show help
show_help() {
    cat << EOF
License Header Format Validation Tool

Usage:
  $0 [OPTIONS] [FILE_PATTERNS...]

Options:
  --fix         Fix format issues automatically
  --check-year  Check if copyright year is current ($CURRENT_YEAR)
  --help        Show this help message

Examples:
  $0                          # Validate all source files
  $0 --fix                   # Fix format issues in all files
  $0 --check-year src/*.zig  # Check specific files with year validation
  $0 --fix --check-year      # Fix all issues including year updates

Validation Checks:
  - SPDX license identifier format and validity
  - Copyright notice format and positioning
  - Proper comment syntax for file type
  - Header positioning (after shebang for shell scripts)
  - Optional: Copyright year currency

Supported File Types:
  - .zig, .jan, .ts, .js, .c, .h  → // comments
  - .py, .sh                      → # comments
  - .md                           → <!-- --> comments

See docs/LICENSE-HEADERS.md for complete documentation.
EOF
}

# Parse command line arguments
file_patterns=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_MODE=true
            shift
            ;;
        --check-year)
            CHECK_YEAR=true
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
            file_patterns+=("$1")
            shift
            ;;
    esac
done

# Main execution
main() {
    cd "$REPO_ROOT"

    echo -e "${GREEN}🔍 License Header Format Validator${NC}"
    echo ""

    if [[ "$FIX_MODE" == "true" ]]; then
        echo -e "${YELLOW}🔧 FIX MODE - Will automatically correct format issues${NC}"
    fi

    if [[ "$CHECK_YEAR" == "true" ]]; then
        echo -e "${YELLOW}📅 YEAR CHECK - Will validate copyright year ($CURRENT_YEAR)${NC}"
    fi

    echo ""

    # Find files to validate
    local files=()
    if [[ ${#file_patterns[@]} -eq 0 ]]; then
        # Default: find all source files
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find . -type f \( -name "*.zig" -o -name "*.jan" -o -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.sh" -o -name "*.c" -o -name "*.h" -o -name "*.md" \) -print0)
    else
        # Use provided patterns
        for pattern in "${file_patterns[@]}"; do
            while IFS= read -r -d '' file; do
                files+=("$file")
            done < <(find . -type f -name "$pattern" -print0)
        done
    fi

    # Filter out excluded directories
    local filtered_files=()
    for file in "${files[@]}"; do
        file="${file#./}"
        if [[ "$file" != *"/node_modules/"* ]] && \
           [[ "$file" != *"/zig-out/"* ]] && \
           [[ "$file" != *"/.git/"* ]] && \
           [[ "$file" != *"/.kiro/"* ]] && \
           [[ "$file" != *"/third_party/"* ]]; then
            filtered_files+=("$file")
        fi
    done

    if [[ ${#filtered_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No files found to validate${NC}"
        return 0
    fi

    echo -e "${BLUE}📋 Validating ${#filtered_files[@]} files...${NC}"
    echo ""

    # Validate each file
    local total_files=0
    local valid_files=0
    local fixed_files=0
    local failed_files=0

    for file in "${filtered_files[@]}"; do
        total_files=$((total_files + 1))

        local result
        result=$(validate_file_header "$file")

        if [[ "$result" == "OK" ]]; then
            valid_files=$((valid_files + 1))
            echo -e "${GREEN}✅${NC} $file"
        else
            # Parse issues and suggestions
            IFS=':' read -r status issues suggestions <<< "$result"

            echo -e "${RED}❌${NC} $file"
            echo "   Issues: ${issues//;/, }"
            if [[ -n "$suggestions" ]]; then
                echo "   Suggestions: ${suggestions//;/, }"
            fi

            # Try to fix if in fix mode
            if [[ "$FIX_MODE" == "true" ]]; then
                if fix_file_header "$file"; then
                    fixed_files=$((fixed_files + 1))
                else
                    failed_files=$((failed_files + 1))
                fi
            fi

            echo ""
        fi
    done

    # Summary
    echo ""
    echo "📊 Summary:"
    echo "  Total files: $total_files"
    echo "  Valid files: $valid_files"

    if [[ "$FIX_MODE" == "true" ]]; then
        echo "  Fixed files: $fixed_files"
        echo "  Failed fixes: $failed_files"

        if [[ "$fixed_files" -gt 0 ]]; then
            echo ""
            echo -e "${GREEN}✅ Fixed $fixed_files files${NC}"
            echo -e "${YELLOW}💡 Run git diff to review the changes${NC}"
        fi
    else
        local issues_count=$((total_files - valid_files))
        echo "  Files with issues: $issues_count"

        if [[ "$issues_count" -gt 0 ]]; then
            echo ""
            echo -e "${YELLOW}💡 Run with --fix to automatically correct format issues${NC}"
        fi
    fi

    # Return appropriate exit code
    if [[ "$FIX_MODE" == "true" ]]; then
        [[ "$failed_files" -eq 0 ]]
    else
        [[ "$valid_files" -eq "$total_files" ]]
    fi
}

# Run main function
main "$@"

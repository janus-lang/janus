#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

# License compliance scanning and reporting tool
# Usage: ./scripts/license-compliance-scan.sh [--format json|markdown|text] [--output file]

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
OUTPUT_FORMAT="text"
OUTPUT_FILE=""

# License mapping (same as other tools)
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
    ["packages/"]="Apache-2.0"
    ["examples/"]="CC0-1.0"
    ["demos/"]="CC0-1.0"
)

# SPDX license database (subset of commonly used licenses)
declare -A SPDX_LICENSES=(
    ["LSL-1.0"]="Self Sovereign Society License 1.0"
    ["Apache-2.0"]="Apache License 2.0"
    ["CC0-1.0"]="Creative Commons Zero v1.0 Universal"
    ["MIT"]="MIT License"
    ["GPL-3.0-only"]="GNU General Public License v3.0 only"
    ["BSD-2-Clause"]="BSD 2-Clause \"Simplified\" License"
    ["MPL-2.0"]="Mozilla Public License 2.0"
)

# Function to validate SPDX license identifier
validate_spdx_license() {
    local license="$1"
    if [[ -n "${SPDX_LICENSES[$license]:-}" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to scan a single file
scan_file() {
    local file="$1"
    local result=""

    if [[ ! -f "$file" ]]; then
        echo "ERROR:File not found"
        return
    fi

    # Read first 20 lines to find license information
    local header
    header=$(head -n 20 "$file")

    # Extract SPDX license identifier
    local spdx_license=""
    if echo "$header" | grep -q "SPDX-License-Identifier:"; then
        spdx_license=$(echo "$header" | grep "SPDX-License-Identifier:" | head -n 1 | sed 's/.*SPDX-License-Identifier: *\([^ ]*\).*/\1/')
    fi

    # Extract copyright information
    local copyright=""
    if echo "$header" | grep -q "Copyright"; then
        copyright=$(echo "$header" | grep "Copyright" | head -n 1 | sed 's/[^#\/]*\(Copyright.*\)/\1/')
    fi

    # Determine expected license
    local expected_license=""
    for dir in "${!LICENSE_MAP[@]}"; do
        if [[ "$file" == "$dir"* ]]; then
            expected_license="${LICENSE_MAP[$dir]}"
            break
        fi
    done
    [[ -z "$expected_license" ]] && expected_license="LSL-1.0"

    # Validate findings
    local status="OK"
    local issues=()

    if [[ -z "$spdx_license" ]]; then
        status="MISSING_SPDX"
        issues+=("Missing SPDX license identifier")
    elif [[ "$spdx_license" != "$expected_license" ]]; then
        status="WRONG_LICENSE"
        issues+=("Expected $expected_license, found $spdx_license")
    elif ! validate_spdx_license "$spdx_license"; then
        status="INVALID_SPDX"
        issues+=("Invalid SPDX identifier: $spdx_license")
    fi

    if [[ -z "$copyright" ]]; then
        status="MISSING_COPYRIGHT"
        issues+=("Missing copyright notice")
    elif ! echo "$copyright" | grep -q "2025 Self Sovereign Society Foundation"; then
        status="WRONG_COPYRIGHT"
        issues+=("Incorrect copyright notice")
    fi

    # Return structured result
    echo "$status|$spdx_license|$copyright|$expected_license|$(IFS=';'; echo "${issues[*]}")"
}

# Function to generate text report
generate_text_report() {
    local scan_results=("$@")
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

    echo "# Janus License Compliance Report"
    echo ""
    echo "**Generated**: $timestamp"
    echo "**Repository**: $(git remote get-url origin 2>/dev/null || echo "Local repository")"
    echo "**Commit**: $(git rev-parse HEAD 2>/dev/null || echo "Unknown")"
    echo ""

    # Summary statistics
    local total_files=0
    local compliant_files=0
    local files_with_issues=0

    declare -A license_counts
    declare -A status_counts

    for result in "${scan_results[@]}"; do
        IFS='|' read -r file status spdx_license copyright expected_license issues <<< "$result"
        total_files=$((total_files + 1))

        if [[ "$status" == "OK" ]]; then
            compliant_files=$((compliant_files + 1))
        else
            files_with_issues=$((files_with_issues + 1))
        fi

        # Count licenses
        if [[ -n "$spdx_license" ]]; then
            license_counts["$spdx_license"]=$((${license_counts["$spdx_license"]:-0} + 1))
        fi

        # Count status types
        status_counts["$status"]=$((${status_counts["$status"]:-0} + 1))
    done

    echo "## Summary"
    echo ""
    echo "- **Total files scanned**: $total_files"
    echo "- **Compliant files**: $compliant_files"
    echo "- **Files with issues**: $files_with_issues"
    echo "- **Compliance rate**: $(( compliant_files * 100 / total_files ))%"
    echo ""

    # License distribution
    echo " License Distribution"
    echo ""
    for license in "${!license_counts[@]}"; do
        local count="${license_counts[$license]}"
        local description="${SPDX_LICENSES[$license]:-Unknown license}"
        echo "- **$license**: $count files ($description)"
    done
    echo ""

    # Issues by type
    if [[ "$files_with_issues" -gt 0 ]]; then
        echo "## Issues by Type"
        echo ""
        for status in "${!status_counts[@]}"; do
            if [[ "$status" != "OK" ]]; then
                local count="${status_counts[$status]}"
                echo "- **$status**: $count files"
            fi
        done
        echo ""

        echo "## Files with Issues"
        echo ""
        for result in "${scan_results[@]}"; do
            IFS='|' read -r file status spdx_license copyright expected_license issues <<< "$result"
            if [[ "$status" != "OK" ]]; then
                echo "### $file"
                echo ""
                echo "- **Status**: $status"
                echo "- **Expected License**: $expected_license"
                echo "- **Found License**: ${spdx_license:-None}"
                echo "- **Issues**: ${issues//;/, }"
                echo ""
            fi
        done
    fi

    echo "## License Requirements"
    echo ""
    echo "The Janus project uses a tiered licensing model:"
    echo ""
    echo "- **Compiler/Tooling (LSL-1.0)**: File-level reciprocity for core components"
    echo "- **Standard Library (Apache-2.0)**: Permissive licensing for maximum adoption"
    echo "- **Community Packages (CC0-1.0)**: Public domain for maximum reusability"
    echo ""
    echo "See [docs/LICENSE-HEADERS.md](docs/LICENSE-HEADERS.md) for complete documentation."
}

# Function to generate JSON report
generate_json_report() {
    local scan_results=("$@")
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    echo "{"
    echo "  \"report\": {"
    echo "    \"timestamp\": \"$timestamp\","
    echo "    \"repository\": \"$(git remote get-url origin 2>/dev/null || echo "Local repository")\","
    echo "    \"commit\": \"$(git rev-parse HEAD 2>/dev/null || echo "unknown")\","
    echo "    \"tool\": \"janus-license-compliance-scan\","
    echo "    \"version\": \"1.0.0\""
    echo "  },"

    # Summary
    local total_files=0
    local compliant_files=0

    for result in "${scan_results[@]}"; do
        IFS='|' read -r file status spdx_license copyright expected_license issues <<< "$result"
        total_files=$((total_files + 1))
        if [[ "$status" == "OK" ]]; then
            compliant_files=$((compliant_files + 1))
        fi
    done

    echo "  \"summary\": {"
    echo "    \"total_files\": $total_files,"
    echo "    \"compliant_files\": $compliant_files,"
    echo "    \"files_with_issues\": $((total_files - compliant_files)),"
    echo "    \"compliance_rate\": $(( compliant_files * 100 / total_files ))"
    echo "  },"

    # Files
    echo "  \"files\": ["
    local first=true
    for result in "${scan_results[@]}"; do
        IFS='|' read -r file status spdx_license copyright expected_license issues <<< "$result"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        echo -n "    {"
        echo -n "\"file\": \"$file\", "
        echo -n "\"status\": \"$status\", "
        echo -n "\"spdx_license\": \"${spdx_license:-null}\", "
        echo -n "\"expected_license\": \"$expected_license\", "
        echo -n "\"copyright\": \"${copyright:-null}\", "
        echo -n "\"issues\": [$(echo "$issues" | sed 's/;/", "/g' | sed 's/^/"/; s/$/"/')]"
        echo -n "}"
    done
    echo ""
    echo "  ]"
    echo "}"
}

# Function to scan repository
scan_repository() {
    local files=()

    # Find all source files
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find . -type f \( -name "*.zig" -o -name "*.jan" -o -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.sh" -o -name "*.c" -o -name "*.h" \) -print0)

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

    echo -e "${BLUE}🔍 Scanning ${#filtered_files[@]} source files...${NC}" >&2

    # Scan each file
    local results=()
    for file in "${filtered_files[@]}"; do
        local result
        result=$(scan_file "$file")
        results+=("$file|$result")
    done

    printf '%s\n' "${results[@]}"
}

# Function to show help
show_help() {
    cat << EOF
License Compliance Scanning Tool

Usage:
  $0 [OPTIONS]

Options:
  --format FORMAT    Output format: text, markdown, or json (default: text)
  --output FILE      Write output to file instead of stdout
  --help             Show this help message

Examples:
  $0                                    # Generate text report to stdout
  $0 --format json                     # Generate JSON report
  $0 --format markdown --output report.md  # Generate markdown report to file

The tool scans all source files in the repository and validates:
  - Presence of SPDX license identifiers
  - Correctness of license identifiers
  - Presence of copyright notices
  - Compliance with project license requirements

See docs/LICENSE-HEADERS.md for license requirements.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --format)
            OUTPUT_FORMAT="$2"
            if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "markdown" && "$OUTPUT_FORMAT" != "json" ]]; then
                echo -e "${RED}❌ Invalid format: $OUTPUT_FORMAT${NC}"
                echo "Valid formats: text, markdown, json"
                exit 1
            fi
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
main() {
    cd "$REPO_ROOT"

    echo -e "${GREEN}📊 License Compliance Scanner${NC}" >&2
    echo "" >&2

    # Scan repository
    local scan_results
    mapfile -t scan_results < <(scan_repository)

    # Generate report
    local report=""
    case "$OUTPUT_FORMAT" in
        "json")
            report=$(generate_json_report "${scan_results[@]}")
            ;;
        "text"|"markdown")
            report=$(generate_text_report "${scan_results[@]}")
            ;;
    esac

    # Output report
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$report" > "$OUTPUT_FILE"
        echo -e "${GREEN}✅ Report written to: $OUTPUT_FILE${NC}" >&2
    else
        echo "$report"
    fi

    # Check if there are any compliance issues
    local has_issues=false
    for result in "${scan_results[@]}"; do
        IFS='|' read -r file status _ _ _ _ <<< "$result"
        if [[ "$status" != "OK" ]]; then
            has_issues=true
            break
        fi
    done

    if [[ "$has_issues" == "true" ]]; then
        echo -e "${YELLOW}⚠️  Compliance issues found. See report for details.${NC}" >&2
        return 1
    else
        echo -e "${GREEN}✅ All files are compliant with license requirements.${NC}" >&2
        return 0
    fi
}

# Run main function
main "$@"

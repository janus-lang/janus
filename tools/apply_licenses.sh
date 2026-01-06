#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Markus Maiwald
# Stewardship: Self Sovereign Society Foundation

# License Header Application Script
# Enforces LSL-1.0 for Core and LUL-1.0 for Peripherals
# Updates LSL-1.0 -> Correct License
# Updates Foundation -> Stichting

set -e

fix_header() {
    local file="$1"
    local license="$2"
    
    # Skip if file doesn't exist
    [ ! -f "$file" ] && return

    # Check for LSL-1.0 and replace
    if grep -q "SPDX-License-Identifier: LUL-1.0" "$file"; then
        sed -i "s/SPDX-License-Identifier: LUL-1.0/SPDX-License-Identifier: $license/g" "$file"
        echo "UPDATED SSS->$license: $file"
    fi

    # Check for old Foundation copyright and replace
    if grep -q "Self Sovereign Society Foundation" "$file"; then
        sed -i "s/Self Sovereign Society Foundation/Self Sovereign Society Foundation/g" "$file"
        echo "UPDATED Foundation->Stichting: $file"
    fi

    # If header is missing completely, add it
    if ! head -n 5 "$file" | grep -q "SPDX-License-Identifier"; then
        local tmp=$(mktemp)
        echo "// SPDX-License-Identifier: $license" > "$tmp"
        echo "// Copyright (c) 2026 Self Sovereign Society Foundation" >> "$tmp"
        echo "" >> "$tmp"
        cat "$file" >> "$tmp"
        mv "$tmp" "$file"
        echo "ADDED Header: $file"
    fi
}

echo "=== Applying Headers ==="

# Layer 1: Sovereign Core (LSL-1.0)
# Compiler, Std, Runtime, Grafts
echo "Targeting Core (LSL-1.0)..."
find compiler std runtime grafts -type f \( -name "*.zig" -o -name "*.jan" \) 2>/dev/null | while read f; do
    fix_header "$f" "LSL-1.0"
done

# Layer 2: Unbound (LUL-1.0)
# Tests, Examples, Packages
echo "Targeting Unbound (LUL-1.0)..."
find tests examples packages -type f \( -name "*.zig" -o -name "*.jan" \) 2>/dev/null | while read f; do
    fix_header "$f" "LUL-1.0"
done

echo "=== License Application Complete ==="

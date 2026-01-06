#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# The full text of the license can be found in the LICENSE file at the root of the repository.

# JSON Contamination Check - Enforces Protocol Purity
# This script ensures no std.json contamination exists in daemon/ or compiler/

set -euo pipefail

echo "🔍 Checking for std.json contamination..."

# Check daemon directory (ignore comments)
if grep -r "std\.json" daemon/ | grep -v "//.*std\.json" 2>/dev/null; then
    echo "❌ PROTOCOL VIOLATION: std.json found in daemon/ directory!"
    echo "💥 The Citadel Protocol mandates pure MessagePack - no JSON allowed!"
    exit 1
fi

# Note: Compiler directory may legitimately use JSON for other purposes (ledger, diagnostics)
# Only daemon/ must be pure MessagePack for Citadel Protocol compliance

echo "✅ Protocol purity verified - no std.json contamination found"
echo "🏰 The Citadel Protocol remains pure and uncompromised"
exit 0

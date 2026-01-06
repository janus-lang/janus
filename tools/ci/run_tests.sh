#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail

export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$PWD/.zig-global-cache}"
echo "Using ZIG_GLOBAL_CACHE_DIR=$ZIG_GLOBAL_CACHE_DIR"

zig version || (echo "Zig not found in PATH" >&2; exit 127)

echo "Running full test suite with golden + sanitizers..."
zig build test -Dgolden=true -Dsanitizers=true

echo "✅ Tests completed."

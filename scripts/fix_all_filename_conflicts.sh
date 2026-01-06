#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Batch rename all filename conflicts according to Unique Filename Doctrine

set -euo pipefail

echo "🔧 Fixing all filename conflicts in batch..."

# Remaining conflicts to fix
mv compiler/libjanus/dispatch.zig compiler/libjanus/libjanus_dispatch.zig
mv compiler/libjanus/query/impl/dispatch.zig compiler/libjanus/query/impl/query_dispatch.zig

mv compiler/libjanus/tests/dispatch_table_compression_test.zig compiler/libjanus/tests/libjanus_dispatch_compression_test.zig
mv compiler/libjanus/dispatch_table_compression_test.zig compiler/libjanus/dispatch_compression_test.zig

mv compiler/libjanus/integration_test.zig compiler/libjanus/libjanus_integration_test.zig
mv tests/golden/framework/integration_test.zig tests/golden/framework/golden_integration_test.zig

mv compiler/libjanus/tests/ir_test.zig compiler/libjanus/tests/libjanus_ir_test.zig
mv tests/libjanus/ir_test.zig tests/libjanus/ir_integration_test.zig

mv .kiro/internal-docs/minimal_tokenizer_test.zig .kiro/internal-docs/internal_minimal_tokenizer_test.zig
mv tests/unit/minimal_tokenizer_test.zig tests/unit/unit_minimal_tokenizer_test.zig

mv compiler/libjanus/tests/parser_test.zig compiler/libjanus/tests/libjanus_parser_test.zig
mv tests/libjanus/parser_test.zig tests/libjanus/parser_integration_test.zig

mv compiler/libjanus/tests/semantic_test.zig compiler/libjanus/tests/libjanus_semantic_test.zig
mv tests/libjanus/semantic_test.zig tests/libjanus/semantic_integration_test.zig

mv compiler/simple_end_to_end_test.zig compiler/legacy_simple_end_to_end_test.zig
mv tests/unit/simple_end_to_end_test.zig tests/unit/unit_simple_end_to_end_test.zig

mv compiler/libjanus/simple_integration_test.zig compiler/libjanus/libjanus_simple_integration_test.zig
mv tests/integration/simple_integration_test.zig tests/integration/integration_simple_test.zig

mv tests/golden/astdb/test_cid_simple.zig tests/golden/astdb/golden_cid_simple_test.zig
mv tests/unit/test_cid_simple.zig tests/unit/unit_cid_simple_test.zig

mv .kiro/internal-docs/test_parser_basic.zig .kiro/internal-docs/internal_parser_basic_test.zig
mv tests/unit/test_parser_basic.zig tests/unit/unit_parser_basic_test.zig

mv compiler/libjanus/tests/tokenizer_test.zig compiler/libjanus/tests/libjanus_tokenizer_test.zig
mv tests/libjanus/tokenizer_test.zig tests/libjanus/tokenizer_integration_test.zig

echo "✅ All filename conflicts resolved!"
echo "🎯 Unique Filename Doctrine now enforced across codebase"

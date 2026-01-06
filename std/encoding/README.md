<!--
SPDX-License-Identifier: LSL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# std.encoding: The Scribe (formerly std.data)

**Philosophy:** Universal translation and encoding/decoding of structured data formats.

**Key Modules:**
*   `json`: SIMD-accelerated JSON parsing (simdjson integration)
*   `csv`: Multithreaded CSV reader/writer
*   `markdown`: CommonMark-compliant Markdown parser
*   `html`: HTML5 streaming tokenizer/parser
*   `arrow`: Columnar memory format (Apache Arrow)

**Performance Targets:**

**Performance Targets:**
*   JSON: 4+ GB/s throughput
*   CSV: Multi-core parallel processing
*   Arrow: Zero-copy data transfer to Python/Pandas

**Current Status:**
*   ✅ JSON: SIMD-accelerated parser with capability gating
*   ⏳ Arrow: Planned
*   ⏳ CSV: Planned

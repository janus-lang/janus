<!--
SPDX-License-Identifier: LSL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Changelog

All notable changes to the Janus programming language and compiler will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version scheme: `YYYY.MM.patch` (Mars Calendar).

## [2026.1.10] - 2026-01-25

### Added

#### Complete Operator Support in QTJIR Compiler
- **Logical Operators**: `and`, `or` with proper short-circuit evaluation using alloca/store/load pattern
- **Modulo Operator**: `%` (remainder) for integer arithmetic
- **Bitwise Operators**: Full support for `^` (XOR), `<<` (left shift), `>>` (right shift), `~` (NOT)
- **LLVM Bindings**: Added `buildSRem`, `buildXor`, `buildShl`, `buildAShr`, `buildNot`

#### Numeric Literal Prefixes
- **Hexadecimal**: `0xFF`, `0x1A2B` (case insensitive)
- **Binary**: `0b1010`, `0b11111111`
- **Octal**: `0o755`, `0o777`
- Both tokenizers updated (janus_tokenizer and ASTDB lexer) for consistency

#### Comprehensive E2E Test Suite
- `modulo_e2e_test.zig`: 8 tests covering basic modulo, zero remainder, expressions, loops, digit extraction
- `bitwise_e2e_test.zig`: 8 tests covering AND, OR, XOR, shifts, bit flags, mask patterns
- `numeric_literals_e2e_test.zig`: 8 tests covering hex, binary, octal literals and mixed expressions
- Total: 24 new E2E tests, bringing suite to 16 passing test modules

### Fixed

#### Parser Bug: Boolean `not` Operator
- Fixed missing `.not_` token in `parseExpression` unary operator check
- Fixed `parsePrimary` calling itself instead of `parseExpression` for operands
- Boolean `not` now correctly works with variables, literals, and compound expressions

### Changed
- QTJIR `emitUnaryOp` helper added for single-operand operations (bitwise NOT)
- Short-circuit logical operators use stack allocation instead of PHI nodes for robustness

## [0.2.5] - 2026-01-09

### Added
- **Constitutional Stack**: Tier 0-6 specification hierarchy.
- **SPEC-015**: Ownership & Affinity specification (The Semantic Lock).
- **Normative Standards**: RFC 2119 language and paragraph indexing across all specs.
- **Legacy Archive**: Cleanup of outdated documentation.

### Changed
- **Ratification**: SPEC-001, SPEC-002, SPEC-004, SPEC-005 updated to Normative status.
- **Docs Structure**: Synchronized `specs/` directory with the new hierarchy.

## [0.2.0-alpha] - 2025-12-15
 
### Added

- **Turing Completeness**: Full control flow support (if/else, while loop)
- **Sovereign Numerics**: f64 precision and VectorF64 dynamic handles
- **Deterministic Safety**: Resource management via `defer`
- **File I/O & String Handles**: Comprehensive `std.io` and `std.string` capabilities with heap management
- **Architecture**: Zero-copy tokenization & JIT/AOT Parity (Interpreter matches Compiler semantics)


- **Advanced Dispatch Strategy Selection (Task 19)**: Intelligent strategy selection with performance profiling
  - Automatic strategy selection based on call frequency, complexity, and cache locality
  - Performance profiling with execution time, cache miss rates, and branch misprediction tracking
  - AI-auditable decision tracking with detailed rationale and risk assessment
  - Robust fallback mechanisms with automatic strategy recovery (PerfectHash → SwitchTable → Static → InlineCache)
  - Integration with LLVM dispatch codegen for production-ready performance optimization
  - Comprehensive effectiveness scoring and adaptive threshold adjustment for continuous learning

#### Semantic Validation Engine - Production Ready Performance
- **Validation engine: 15.25ms/10k nodes; 90% dedup; O(1) cleanup**
- Complete semantic analysis pipeline with symbol resolution, type inference, and validation
- Feature flag system with `--validate=optimized` (default in CI) and `--validate=baseline` fallback
- Performance contracts enforced in CI: validation_ms ≤ 25ms, error_dedup_ratio ≥ 0.85, cache_hit_rate ≥ 0.95
- Automatic fallback mechanism with timeout protection (100ms default)
- Arena-based memory management with zero-leak guarantees and O(1) cleanup
- BLAKE3-based canonical type hashing eliminates O(N²) brute-force searches
- Sophisticated error deduplication with stable tuple hashing
- Real-time performance monitoring via `janus trace dispatch --timing`
- CI validation benchmarks with performance regression detection
- Comprehensive API documentation and usage examples

#### Integration Protocol Implementation
- Feature flags: `--validate=optimized|baseline|auto` with environment variable support
- Performance metrics exposure: validation_ms, error_dedup_ratio, cache_hit_rate
- CI enforcement: `validation-bench` job with hard performance gates
- Metrics integration: JSON output for tooling, Prometheus-compatible endpoints
- Fallback safety: Automatic degradation on performance contract violations
- Documentation: Complete operational guides and troubleshooting procedures

### Changed

#### Semantic Engine Consolidation
- Merged three separate semantic specs (semantic-core, semantic-resolution, semantic-validation-engine) into unified semantic-engine
- Removed 17 outdated semantic component files and proof artifacts
- Cleaned build system of obsolete test targets and references
- Streamlined semantic directory to production-ready components only

### Performance

#### Semantic Analysis Optimization
- **O(1) type operations** via canonical hashing (was O(N²) brute-force)
- **O(log n) symbol resolution** with string interning and hash tables
- **Sub-second analysis** for 100K+ line codebases
- **<10ms LSP queries** for hover, go-to-definition, diagnostics
- **<100ms incremental updates** for typical edit-compile cycles
- **Arena allocation** with scoped lifetime management and bulk deallocation

### Fixed

#### Build System and Repository Cleanup
- Removed broken test definitions and obsolete file references
- Fixed module import conflicts in build.zig
- Eliminated duplicate validation engine implementations
- Cleaned up proof files, benchmarks, and development artifacts

### Documentation

#### Comprehensive Semantic Engine Documentation
- `docs/semantic-engine/README.md`: Complete user guide with architecture overview
- `docs/semantic-engine/api-reference.md`: Detailed API documentation with examples
- `docs/validation.md`: Technical deep-dive with complexity proofs and cache invariants
- `docs/cli/trace.md`: Performance monitoring and metrics documentation
- `examples/semantic-engine/`: Janus example programs showcasing semantic features
- `demos/semantic-analysis/`: Interactive demonstration of semantic engine capabilities

## [Previous Releases]

### [0.1.0] - Foundation
- Initial Janus language specification
- Basic compiler infrastructure
- ASTDB query-powered architecture
- LSP server implementation
- Core type system and symbol management

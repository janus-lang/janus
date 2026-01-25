<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Compiler - AI Agent Context

This file provides essential context for AI agents working on the Janus compiler.

## Project Structure

```
janus-lang/
├── compiler/
│   ├── libjanus/           # Core library (parser, tokenizer, semantic)
│   │   ├── janus_parser.zig
│   │   └── janus_tokenizer.zig  # PRIMARY TOKENIZER
│   ├── astdb/              # ASTDB columnar database
│   │   ├── lexer.zig       # SECONDARY LEXER (for ASTDB)
│   │   └── core.zig
│   ├── qtjir/              # Quantum-Tensor Janus IR
│   │   ├── lower.zig       # AST → IR lowering
│   │   ├── graph.zig       # IR graph/OpCode definitions
│   │   ├── llvm_emitter.zig
│   │   └── llvm_bindings.zig
│   └── semantic/           # Semantic analysis
├── tests/
│   └── integration/        # E2E tests (source → executable)
├── runtime/
│   └── janus_rt.zig        # Runtime library (print_int, etc.)
├── docs/
│   └── architecture/       # Architecture documentation
├── specs/                  # Language specifications
└── build.zig               # Build configuration
```

## Key Architectural Decisions

### Dual Lexer Architecture
**See**: `docs/architecture/LEXER-ARCHITECTURE.md`

The compiler has TWO lexers:
1. **janus_tokenizer** (`compiler/libjanus/janus_tokenizer.zig`) - Used by janus_parser for compilation
2. **RegionLexer** (`compiler/astdb/lexer.zig`) - Used by ASTDB for semantic analysis

**Important**: When adding new token support, update BOTH lexers for consistency.

### Compilation Pipeline
```
Source → janus_tokenizer → janus_parser → AST → QTJIR (lower.zig) → LLVM IR → Executable
```

### Module Dependencies (build.zig)
- `janus_parser` imports `janus_tokenizer`
- `qtjir` imports `janus_parser`, `astdb_core`
- All E2E tests import `janus_parser`, `qtjir`, `astdb_core`

## Common Tasks

### Adding a New Operator
1. Add token to `janus_tokenizer.zig` (TokenType enum + scanToken)
2. Add token to `astdb/lexer.zig` for consistency
3. Add OpCode to `qtjir/graph.zig`
4. Add lowering case in `qtjir/lower.zig`
5. Add LLVM binding in `qtjir/llvm_bindings.zig` if needed
6. Add emission in `qtjir/llvm_emitter.zig`
7. Create E2E test in `tests/integration/`
8. Update CHANGELOG.md

### Adding a New Keyword
1. Add to TokenType enum in `janus_tokenizer.zig`
2. Add to keywords map in `getKeywordType()`
3. Add to `astdb/lexer.zig` for consistency
4. Add parser support in `janus_parser.zig`

### Running Tests
```bash
zig build test                    # All tests
zig build test-<name>-e2e         # Specific E2E test
zig build test-qtjir              # QTJIR unit tests
```

## Version Scheme

**Mars Calendar**: `YYYY.MM.patch` (e.g., `2026.1.10`)

## Branch Strategy

- `unstable` - Development branch
- `testing` - Integration testing
- `stable` - Production releases

All tests must pass before merging to stable.

## E2E Test Pattern

E2E tests compile Janus source to executable and verify output:
```zig
fn compileAndRun(allocator, source, test_name) ![]u8 {
    // 1. Parse source
    // 2. Lower to QTJIR
    // 3. Emit LLVM IR
    // 4. Compile with llc
    // 5. Link with runtime
    // 6. Execute and capture stdout
}
```

## Current Test Modules (16 passing)

- hello_world, for_loop, if_else, while_loop
- function_call, continue, match, struct
- string, type_annotation, array, unary
- logical, modulo, bitwise, numeric_literals

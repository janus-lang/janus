<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Lexer Architecture

**Status**: Active (Dual-Lexer)
**Target**: Single ASTDB-based lexer for stable beta release
**Last Updated**: 2026-01-25

## Overview

The Janus compiler maintains two separate lexers that serve different architectural purposes. This document explains why they exist, their differences, and the planned unification strategy.

## The Two Lexers

### 1. janus_tokenizer (Traditional Parser Path)

**Location**: `compiler/libjanus/janus_tokenizer.zig`

**Used By**:
- `janus_parser.zig` (recursive descent parser)
- All E2E compilation tests
- LLVM codegen pipeline

**Pipeline**:
```
Source → Tokenizer → Parser → AST → QTJIR → LLVM IR → Executable
```

| Aspect | Description |
|--------|-------------|
| Token Storage | `Token` struct with raw `lexeme: []const u8` slices |
| Memory Model | Tokens own source slices directly |
| Trivia Handling | Not captured (whitespace/comments discarded) |
| Incremental Support | No |
| Profile Support | `:min`, `:go`, `:sovereign` keywords |

**Token Structure**:
```zig
pub const Token = struct {
    type: TokenType,        // Direct enum (126 variants)
    lexeme: []const u8,     // Raw source slice
    span: SourceSpan,       // Start/end position
};
```

### 2. RegionLexer (ASTDB Path)

**Location**: `compiler/astdb/lexer.zig`

**Used By**:
- `region.zig` (ASTDB region-based parsing)
- `semantic_analyzer.zig` (type checking)
- LSP server (incremental updates)

**Pipeline**:
```
Source → RegionLexer → ASTDB Snapshot → Columnar Queries → Semantic Analysis
```

| Aspect | Description |
|--------|-------------|
| Token Storage | `Token` struct with `str: ?StrId` (interned string ID) |
| Memory Model | String interning via `StrInterner` (deduplication) |
| Trivia Handling | Separate `Trivia` array with `trivia_lo`/`trivia_hi` indices |
| Incremental Support | Yes (region boundaries: `start_pos`, `end_pos`) |
| Designed For | Columnar database queries, incremental parsing |

**Token Structure**:
```zig
pub const Token = struct {
    kind: TokenKind,        // Enum with 220+ variants
    str: ?StrId,            // Interned string (null for punctuation)
    span: SourceSpan,       // Byte offsets + line/column
    trivia_lo: u32,         // Index into trivia array
    trivia_hi: u32,         // Exclusive end of trivia
};
```

## Architectural Comparison

| Aspect | janus_tokenizer | RegionLexer |
|--------|-----------------|-------------|
| **Origin** | Traditional compiler front-end | ASTDB columnar database |
| **Memory Model** | Token owns lexeme slices | String interning (deduplication) |
| **Trivia** | Discarded | Preserved separately |
| **Incremental** | No | Yes (region boundaries) |
| **Use Case** | AST generation, compilation | Semantic queries, LSP |
| **Optimization** | Speed | Memory efficiency |

## Why Two Lexers?

### Historical Reasons
1. **janus_tokenizer** was built first for the traditional compilation pipeline
2. **RegionLexer** was added later for ASTDB's incremental parsing requirements
3. Different consumers evolved with different data model expectations

### Technical Reasons
1. **Different Storage Models**: Raw slices vs. interned strings
2. **Different Consumers**: Parser expects sequential stream; ASTDB expects columnar data
3. **Different Optimization Goals**: Speed vs. memory efficiency + incrementality

## Current State (2026.1.x)

Both lexers support the same token types:
- All operators (arithmetic, logical, bitwise, comparison)
- All keywords (`:min`, `:go`, `:sovereign` profiles)
- Numeric literals: decimal, hex (`0xFF`), binary (`0b1010`), octal (`0o777`)
- String literals, identifiers, punctuation

This consistency is actively maintained - any new token support must be added to both lexers.

## Unification Strategy (Future)

**Target**: Stable beta release should use single ASTDB-based lexer

### Phase 1: Adapter Layer
Create a thin adapter that converts RegionLexer output to janus_tokenizer format:
```
Source → RegionLexer → Adapter → Parser (unchanged)
```

### Phase 2: Parser Migration
Modify parser to consume ASTDB tokens directly:
```
Source → RegionLexer → ASTDB Snapshot → Parser → AST
```

### Phase 3: Deprecation
Remove janus_tokenizer once all consumers migrate to ASTDB path.

### Benefits of Unification
- Single source of truth for tokenization
- Automatic incremental parsing for all paths
- Memory-efficient string interning everywhere
- Trivia preservation for formatting tools

### Challenges
- Parser expects raw lexemes, ASTDB uses interned IDs
- Performance regression risk during transition
- Test coverage must be maintained

## Files Reference

| File | Purpose |
|------|---------|
| `compiler/libjanus/janus_tokenizer.zig` | Traditional tokenizer |
| `compiler/astdb/lexer.zig` | ASTDB region-based lexer |
| `compiler/astdb/core.zig` | ASTDB token/trivia definitions |
| `compiler/libjanus/janus_parser.zig` | Uses janus_tokenizer |
| `compiler/semantic_analyzer.zig` | Uses RegionLexer |

## Maintenance Guidelines

When adding new token support:
1. Update both lexers for consistency
2. Test with E2E tests (uses janus_tokenizer path)
3. Test with semantic analysis (uses RegionLexer path)
4. Document any divergence in this file

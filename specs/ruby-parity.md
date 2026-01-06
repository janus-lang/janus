<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Ruby to Janus Migration Guide

## Overview

This guide helps Ruby developers migrate to Janus, leveraging familiar block syntax and implicit returns.

## Quick Comparison

| Ruby | Janus :script | Janus :sovereign |
|------|---------------|-------------|
| `def add(a, b); a + b; end` | `fn add(a, b) = a + b` | `fn add(a: i64, b: i64) -> i64 { return a + b; }` |
| `[1, 2, 3].map { \|x\| x * 2 }` | `[1, 2, 3].map { \|x\| x * 2 }` | Same with explicit types |
| `hash = {key: "value"}` | `let hash = %{key: "value"}` | `let hash: HashMap[Str, Str]` |

## Block Syntax Parity

Ruby's powerful block syntax is preserved in Janus with explicit cost revelation.

## Migration Path

**Status:** Coming Soon - Full Ruby migration guide under development

See [Memory Safety Comparison](./SPEC-memory-safety-rust-cpp-comparison.md) for safety differences.

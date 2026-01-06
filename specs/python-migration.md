<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Python to Janus Migration Guide

## Overview

This guide helps Python developers migrate to Janus, leveraging familiar syntax while gaining systems language benefits.

## Quick Comparison

| Python | Janus :script | Janus :core |
|--------|---------------|------------|
| `def func(x): return x * 2` | `fn func(x) = x * 2` | `fn func(x: i64) -> i64 { return x * 2; }` |
| `x = [1, 2, 3]` | `let x = [1, 2, 3]` | `let x: [i64] = [1, 2, 3]` |
| `d = {"key": 42}` | `let d = %{key: 42}` | `let d = HashMap.init()` |

## Migration Path

**Status:** Coming Soon - Full migration guide under development

See [Memory Safety Comparison](./SPEC-memory-safety-rust-cpp-comparison.md) for safety approach differences.

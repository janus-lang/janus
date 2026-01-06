<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Go to Janus :service Migration Guide

## Overview

Go-familiar patterns with memory safety and honest error handling.

## Comparison

| Go | Janus :service |
|----|-----------|
| `func add(a, b int) int` | `fn add(a: i64, b: i64) -> i64` |
| `if err != nil` | `or { return err }` sugar |
| `defer cleanup()` | `defer cleanup()` |
| `go func() {}()` | Actor spawn with supervision |

## Status

**Coming Soon** - Full Go migration guide under development

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Oracle Proof Pack Demo

This example demonstrates Janus's perfect incremental compilation with measurable, verifiable results.

## What This Proves

1. **No-Work Rebuilds**: Unchanged code compiles in 0ms
2. **Interface vs Implementation**: Only interface changes trigger dependent rebuilds
3. **Minimal Invalidation**: Changes affect only what they must

## Running the Proof

```bash
# Initial build
janus build hello.jan

# No-work rebuild (should be 0ms)
janus build hello.jan --explain

# Verify with Oracle introspection
janus oracle introspect build-invariance --json
```

## Test Scenarios

### 1. Comment-Only Change
Edit `hello.jan` to add/modify comments only.
**Expected**: 0ms rebuild, 100% cache hit rate

### 2. Implementation-Only Change
Modify the implementation of `internal_helper()` in `lib.jan`.
**Expected**: Only `lib.jan` rebuilds, `hello.jan` uses cached artifacts

### 3. Interface Change
Modify the signature of `format_greeting()` in `lib.jan`.
**Expected**: Both `lib.jan` and `hello.jan` rebuild (minimal dependency set)

## Acceptance Criteria

- [ ] No-work rebuild shows all stages 0ms or "skipped"
- [ ] Interface change rebuilds dependents only
- [ ] Implementation change rebuilds single unit only
- [ ] ≥90% cache hit rate on repeated builds
- [ ] Cryptographic integrity verification passes

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus CI Firewall: Targets and Invariants

The CI firewall enforces correctness and integrity across the codebase while
keeping the local developer loop fast.

## Targets

- `test`: Full suite, including unit, integration, and (optionally) golden IR tests.
- `test-parser`: Focused, high-speed parser validation using a unified, data-driven test factory.
- `grpc-smoke`: Live-fire gRPC smoke test to verify the end-to-end binary pipeline.

## Parser Validation (Unified Factory)

The parser suite validates:

- Expression shapes: precedence, chaining, complex parentheses, unary nests.
- Statement forms: empty program, multi-function units, functions with bodies/calls/returns.
- Span integrity: token spans map precisely to source slices (literals) and containers (blocks/programs).
- CID stability: snapshot content CIDs are stable and non-zero for selected nodes.

Design principles:

- One system, one source of truth. All parser tests share a data-driven harness.
- Structural assertions first; avoid brittle string equality tied to interner storage unless necessary.
- Minimal/no stderr logs to keep CI signal clear.

## Recommended Flags

- `-Doptimize=ReleaseSafe`: cleaner logs, good default for CI.
- `-Dgolden=true`: enable golden IR tests when verifying IR changes.
- `-j<N>`: use parallel jobs locally.

## Notes

- The parser test target is configured to run in `ReleaseSafe` by default to ensure clean CI logs.
- Golden tests are gated to keep default cycles fast.

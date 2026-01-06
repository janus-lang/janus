<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





<!--
---
title: Hinge Transparency Log
description: Local append-only Merkle log, statements, and proofs
author: Self Sovereign Society Foundation
date: 2025-09-24
license: |
  
  // Copyright (c) 2026 Self Sovereign Society Foundation
  // The full text of the license can be found in the LICENSE file at the root of the repository.
version: 0.1
---
-->

# Hinge Transparency Log

The transparency log provides an append-only record of published packages. Each line is a statement (JSON), and the log’s Merkle root commits to all lines.

## Location

- File: `~/.hinge/transparency.log`

## Statement Format

Each publish appends a single JSON object on one line, for example:

```
{"hash":"d035e6…2234","keyid":"a1b2c3d4e5f6a7b8","ts":1727145600}
```

- `hash`: BLAKE3 Merkle root of the package payload (contents of `package/hash.b3`).
- `keyid`: 16-hex prefix of `blake3(public_key)`, where `public_key` is the signer’s public key bytes.
- `ts`: Unix timestamp (seconds).

## Commands

```
# Append a statement for a package (uses package/package/hash.b3)
hinge publish <path/to/pkg.jpk> <path/to/public.key>

# Print local Merkle root
hinge log-sync

# Verify inclusion of a statement
#  - Pass a package path (reads its hash) or a raw JSON line
hinge log-verify <path/to/pkg.jpk>
hinge log-verify '{"hash":"…","keyid":"…","ts":…}'

# Create a checkpoint (anchor) and verify it
hinge checkpoint [--from file:///path/to/snapshot]
hinge checkpoint-verify ~/.hinge/checkpoint.json builders/trust.pub

# Verify a package against the pinned checkpoint and export proof JSON for CI
hinge verify --export-proof out/proofs/pkg.json dist/pkg.jpk
```

## Merkle Proofs

The log can produce and verify Merkle proofs for inclusion. The proof is a JSON-like struct:

```
{
  "index": 42,
  "total": 123,
  "siblings": [
    "<32-byte BLAKE3 hash as hex>",
    "…"
  ]
}
```

Verification recomputes the Merkle root from the leaf (the exact line bytes) and the `siblings` list. The CLI prints:

```
🌲 Included at index 42/123; proof_len=7; root <hex>; verify=OK
```

## Notes

- The local log is append-only by convention; tampering changes the root.
- Remote sync and signed tree heads will be added next; the local root already enables CI attestation and reproducibility checks.

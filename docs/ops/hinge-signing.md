<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





<!--
---
title: Hinge Signing & Verification
description: How to seal and verify .jpk packages with trust policies
author: Self Sovereign Society Foundation
date: 2025-09-24
license: |
  
  // Copyright (c) 2026 Self Sovereign Society Foundation
  // The full text of the license can be found in the LICENSE file at the root of the repository.
version: 0.1
---
-->

# Hinge Signing & Verification (Phase C)

This guide shows how to sign (.seal) and verify Janus packages (.jpk) and how to use consensus (N‑of‑M) trust.

## Concepts

- `hash.b3`: BLAKE3 Merkle root of the package payload.
- `signatures/`: Directory inside `package/` that contains signatures and public keys.
  - Files: `<keyid>.sig` and `<keyid>.pub` where `keyid` is the first 16 hex chars of `blake3(pub)`.
- Modes:
  - `strict`: all discovered signatures must verify.
  - `consensus`: at least `N` of `M` discovered signatures must verify.

## Seal (Sign)

```
# Sign and write artifacts into the package
hinge seal <package.jpk> <private_key> <output_dir> --into-package

# Example
hinge seal demo_output/janus-demo-1.0.0.jpk private.key sealed_out --into-package
```

Auto‑seal during pack:

```
hinge pack <src> <name> <version> --format jpk --sign --key private.key
```

This writes signature and public key into `package/signatures/<keyid>.{sig,pub}`.

## Verify

```
hinge verify <package.jpk> [--mode strict|consensus] [--threshold N/M]

# Example (2 of 3 signatures must be valid)
hinge verify demo_output/janus-demo-1.0.0.jpk --mode consensus --threshold 2/3
```

Verification reads `package/hash.b3` and checks signatures from `package/signatures/`.

## Key Management

### Test keys (current stub)

The current integration uses a Dilithium3‑test backend so you can try the flow without external deps.

- Private key: any random bytes (e.g., 48 bytes) work for testing.

```
# Generate a 48‑byte test private key
dd if=/dev/urandom bs=48 count=1 of=private.key

# Seal a package using the test key
hinge seal demo_output/janus-demo-1.0.0.jpk private.key sealed_out --into-package

# Verify
hinge verify demo_output/janus-demo-1.0.0.jpk --mode strict
```

The public key is derived automatically during sealing and written to
`package/signatures/<keyid>.pub`.

### Keyring & Trust (Identity is Content)

Janus uses sovereign, content‑addressed identity. A key’s identity (KeyID) is the first 16 hex chars of `blake3(public_key_bytes)`. A key is trusted when explicitly added to the local keyring:

```
# Add a trusted key to the local keyring
hinge trust add ./builders/alfa.pub   # prints the KeyID, e.g. a1b2c3d4e5f6a7b8

# Strict policy: requires at least one valid signature from a trusted KeyID
hinge verify pkg.jpk --mode strict

# Consensus policy: requires N trusted signatures
hinge verify pkg.jpk --mode consensus --threshold 2/3
```

Keyring store: `~/.hinge/keyring/<keyid>.pub`.

### Real Dilithium3 (upcoming)

The build supports a `-Dcrypto-backend` option to select a real backend once the
vendor code is present (e.g., PQClean). See notes inside `tools/hinge/build.zig`
and `tools/hinge/crypto_dilithium_pqclean.zig`. By default, the build uses
the safe test backend.

## Implementation status

- Algorithm: Dilithium3‑test (BLAKE3‑based stub) for integration and flow; will be replaced by real Dilithium3.
- Policy: `strict` and `consensus N/M` supported via CLI flags.
- Layout: `package/signatures/<keyid>.sig` and `<keyid>.pub`.

## Notes

- Keys are user‑supplied files. For testing, any byte string can serve as a private key with this stub.
- Real Dilithium3 and trust key management will follow in Phase C completion.

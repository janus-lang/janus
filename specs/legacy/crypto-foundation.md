<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC: Janus Cryptographic Foundations
**Version:** 0.1.0
**Status:** Draft → Public Review
**Author:** Self Sovereign Society Foundation
**Date:** 2025-10-15
**License:** LSL-1.0
**Epic:** M7 — Security Foundations
**Dependencies:** std/io, std/string, Allocator Sovereignty, Capability System
**Profiles:** :service → :sovereign (cryptographic ops gated in :core)

---

## 0. Purpose

Provide a **post-quantum-ready, capability-secure cryptographic foundation** for the Janus Standard Library.
All primitives must be deterministic, capability-gated, and allocator-sovereign.
No ambient randomness, global state, or hidden allocations are permitted.

The goal is to allow developers to **build secure systems with visible cost** — cryptography as an *honest mechanism*, not an opaque API.

---

## 1. Scope

This specification covers the *core cryptographic submodules* of Janus:

```

std/
├─ enc/       → Encoding and serialization primitives
├─ hash/      → Hash functions (BLAKE3, SipHash, SHA-2/3)
├─ cipher/    → Symmetric encryption (ChaCha20-Poly1305, AES-GCM)
├─ kem/       → Key Encapsulation (Kyber768, Kyber1024, Classic McEliece)
├─ sign/      → Digital signatures (Ed25519, Dilithium, SPHINCS+)
├─ rand/      → Randomness sources and deterministic generators
└─ kdf/       → Key derivation (HKDF, PBKDF2, BLAKE3-derive)

````

All modules share common traits:

- Capability-based entropy and key usage
- Explicit allocator threading
- Zero-copy data flow
- Determinism under `--deterministic`
- Portable reference implementations with optional hardware acceleration

---

## 2. Design Doctrines

| Doctrine | Enforcement |
|-----------|-------------|
| **Reveal the cost** | All APIs expose buffer sizes, allocations, and entropy sources. |
| **Capability Security** | Keys, RNG, and crypto contexts require explicit capability tokens. |
| **Allocator Sovereignty** | No implicit heap use; all buffers come from caller allocators. |
| **Determinism** | All non-deterministic operations fail under `--deterministic` unless policy grants. |
| **Zero Ambient Authority** | No global RNG, no singleton crypto context. |
| **Error Transparency** | All failure modes are surfaced via `!CryptoError`. |

---

## 3. Core Capability Model

| Capability | Purpose | Default Profile |
|-------------|----------|-----------------|
| `CapRng` | Access to entropy or PRNG seed | :service |
| `CapCryptoKeyUse` | Permission to use stored keys | :sovereign |
| `CapCryptoKdf` | Permission to derive keys | :service |
| `CapCryptoPq` | Permission to use PQ algorithms (Kyber/Dilithium) | :sovereign |
| `CapCryptoHardware` | Access to hardware acceleration (AES-NI, SHA-NI, TPM) | :sovereign |

Capabilities are granted via context injection (`with ctx do … end`) and are visible in the function signatures.

---

## 4. Module Overview

### 4.1 std/enc — Encoding

Human-safe serialization primitives.

```janus
func enc.base64.encode(input: []u8, alloc: Alloc) -> string!CryptoError
func enc.base64.decode(input: string, alloc: Alloc) -> []u8!CryptoError
func enc.hex.encode(input: []u8) -> string
func enc.hex.decode(input: string, alloc: Alloc) -> []u8!CryptoError
````

Deterministic, no capabilities required.

---

### 4.2 std/hash — Hash Functions

Cryptographic and non-cryptographic hash functions.

```janus
func hash.blake3(data: []u8) -> [32]u8
func hash.siphash(data: []u8, key: [16]u8) -> u64
func hash.sha3_256(data: []u8) -> [32]u8
```

* Pure functions (no alloc by default).
* `!CryptoError` only for allocation or parameter errors.
* Designed for deterministic verification (used by nip/nexus).

---

### 4.3 std/cipher — Symmetric Ciphers

```janus
func cipher.chacha20poly1305.encrypt(
    plaintext: []u8,
    nonce: [12]u8,
    key: [32]u8,
    ad: []u8,
    alloc: Alloc
) -> []u8!CryptoError

func cipher.chacha20poly1305.decrypt(
    ciphertext: []u8,
    nonce: [12]u8,
    key: [32]u8,
    ad: []u8,
    alloc: Alloc
) -> []u8!CryptoError
```

Capability: `CapCryptoKeyUse`.

Errors:

* E3201_INVALID_KEY_LEN
* E3203_AUTH_FAIL
* E3205_ALLOC_FAIL

---

### 4.4 std/kem — Key Encapsulation (Post-Quantum)

**Kyber768 Reference Implementation**

```janus
func kem.kyber768.keypair(rng: CapRng, alloc: Alloc) -> (PublicKey, SecretKey)!CryptoError
func kem.kyber768.encaps(pk: PublicKey, rng: CapRng, alloc: Alloc) -> (Ciphertext, SharedKey)!CryptoError
func kem.kyber768.decaps(ct: Ciphertext, sk: SecretKey, alloc: Alloc) -> SharedKey!CryptoError
```

Characteristics:

* IND-CCA2 secure
* PQC NIST level 3
* Pure Zig/Janus implementation preferred (PQClean fallback)
* Compatible with `std.sign.dilithium` for hybrid schemes

Errors (E33xx):

* E3301_KEYGEN_FAIL
* E3303_ENCAP_FAIL
* E3305_DECAP_FAIL
* E3307_INVALID_CT

Capability: `CapRng`, `CapCryptoPq`.

---

### 4.5 std/sign — Digital Signatures

```janus
func sign.ed25519.keypair(rng: CapRng, alloc: Alloc) -> (PublicKey, SecretKey)!CryptoError
func sign.ed25519.sign(msg: []u8, sk: SecretKey) -> Signature!CryptoError
func sign.ed25519.verify(msg: []u8, sig: Signature, pk: PublicKey) -> bool

func sign.dilithium.sign(msg: []u8, sk: SecretKey, alloc: Alloc) -> Signature!CryptoError
func sign.dilithium.verify(msg: []u8, sig: Signature, pk: PublicKey) -> bool
```

Capability: `CapCryptoKeyUse`, `CapCryptoPq` (for PQ variants).
Deterministic signing modes required for reproducible builds.

---

### 4.6 std/rand — Randomness

* Deterministic PRNG (`xoshiro256**`) for reproducible builds.
* Hardware entropy source (RDRAND, /dev/random) behind `CapRng`.
* `rng.seed()` visible; never implicit.

```janus
func rand.fill(buf: []u8, cap: CapRng) -> void!CryptoError
func rand.deterministic(seed: [32]u8) -> Rng
```

---

### 4.7 std/kdf — Key Derivation

```janus
func kdf.hkdf(ikm: []u8, salt: []u8, info: []u8, length: usize) -> []u8!CryptoError
func kdf.blake3.derive(key: []u8, context: string, length: usize) -> []u8!CryptoError
```

Capability: `CapCryptoKdf`.
All deterministic given identical inputs.

---

## 5. Determinism Policy

| Mode              | Allowed RNG                 | PQ Crypto                    | Notes                   |
| ----------------- | --------------------------- | ---------------------------- | ----------------------- |
| `--deterministic` | deterministic PRNG only     | disabled (E3407_PQ_DISABLED) | ensures reproducibility |
| `--secure`        | hardware RNG allowed        | enabled                      | for runtime deployments |
| `--fips`          | FIPS-compliant sources only | hybrid (PQ + classical)      | enterprise policy       |

Attempting to use disallowed entropy raises `E3401_RNG_UNAVAILABLE`.

---

## 6. Error Model

**Error Codes (E32xx–E34xx)**

| Code                  | Description                                 |
| --------------------- | ------------------------------------------- |
| E3201_INVALID_KEY_LEN | Key size mismatch                           |
| E3203_AUTH_FAIL       | Authentication tag mismatch                 |
| E3301_KEYGEN_FAIL     | Keypair generation failed                   |
| E3305_DECAP_FAIL      | Decapsulation failure                       |
| E3401_RNG_UNAVAILABLE | RNG capability missing or denied            |
| E3405_ALLOC_FAIL      | Allocator error                             |
| E3407_PQ_DISABLED     | PQ crypto disabled under deterministic mode |

---

## 7. Security Policies

* **Memory Cleansing:** All secret buffers are zeroized before free.
* **Constant-time:** All operations on secret data must avoid branches or timing leaks.
* **No Key Reuse:** KEM decaps and sign operations check key freshness.
* **Audit Trail:** Each capability use logged under `ctx.log.crypto` when enabled.
* **Test Vectors:** Verified against NIST KATs for each algorithm.

---

## 8. Integration Points

| System                   | Use Case                                        |
| ------------------------ | ----------------------------------------------- |
| **Citadel Architecture** | Secure daemon RPC handshake (Kyber + Dilithium) |
| **NexusOS / nip**        | Package signature & repository verification     |
| **Capsules**             | Signed, attestable container manifests          |
| **Libertaria**           | Token ledger signing & on-chain identity proofs |
| **AI Agents**            | Secure model provenance and dispatch integrity  |

---

## 9. Testing & Verification

* ✅ Unit tests: vector conformance for all algorithms
* ✅ Fuzz tests for decoders and RNG interfaces
* ✅ Determinism tests under `--deterministic`
* ✅ Benchmark tests for throughput and latency
* ✅ Memory safety validated by ASan/UBSan builds
* ✅ Optional formal verification (vale/spec-proofs later)

---

## 10. Future Work

1. **Hybrid KEMs:** Kyber + X25519 composite exchange.
2. **Hardware acceleration:** Integrate with AES-NI / SHA-NI via `CapCryptoHardware`.
3. **Secure enclave integration:** TPM, SGX, TrustZone capability bindings.
4. **FIPS 140-3 mode:** Policy enforcement for enterprise builds.
5. **PQ Transition toolkit:** Hybrid key exchange demo for Citadel RPC.

---

## 11. Success Criteria

✅ Pure Janus implementation of `kyber768` passes NIST vectors.
✅ All crypto functions capability-gated, deterministic under policy.
✅ Zero ambient entropy or hidden allocations.
✅ Cross-profile compatibility: :service (classical) → :sovereign (PQ-enabled).
✅ 100 % test coverage with deterministic test suite.

---

**THE CRYPTO FOUNDATION IS THE WALL AROUND THE CITADEL.**
**VISIBLE, AUDITABLE, POST-QUANTUM, AND HONEST.**

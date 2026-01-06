<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Registry Sovereignty Protocol (RSP‑1) — Foundation

Status: prototype-hardened (0.1.x)

This document summarizes the first hardened implementation of RSP‑1 integrated into janusd and the UTCP lease registry.

Core properties
- Multi‑secret BLAKE3 MAC (active + previous epochs): signatures are verified against all known epochs to allow zero‑downtime key rotation.
- MAC input: group, name, ttl_ns, heartbeat_counter (prevents replay across heartbeats).
- Rotation: new epoch becomes active, previous remains accepted for a grace window.
- Replication discipline: mutations replicate only after local validation succeeds.

Implementation
- Crypto: std/rsp1_crypto.zig (Apache‑2.0)
  - EpochKey { key: `[32]u8`, id: u64 }
  - LeaseVerifier with MAX_KEYS=3, sign/verify
  - Uses std.crypto.hash.Blake3 keyed hashing
- Registry integration: std/utcp_registry.zig (Apache‑2.0)
  - Stores ttl_ns, deadline_ns, heartbeat_count, signature
  - registerLease signs with heartbeat_count=0
  - heartbeat verifies current MAC, then increments counter and re‑signs
  - rotateKey installs a new epoch key and demotes previous
- Cluster replication: std/rsp1_cluster.zig (Apache‑2.0)
  - Minimal in‑memory log with majority quorum
  - Registry attaches an optional Replicator adapter; replication happens after validation

Security & quotas
- Namespace quotas: setNamespaceQuota(max) limits entries per group and is enforced before replication.
- Admin endpoints gate rotation and quotas behind registry.admin:*.

References
- **[Registry Protocol Overview](./README.md)** - Complete registry system documentation
- **[BLAKE3 Integration](../src/)** - Cryptographic content addressing implementation

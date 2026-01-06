<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Registry API (janusd)

All endpoints are served by janusd (HTTP mode). Capability tokens follow the form `namespace.verb:<resource>` and are required where noted.

Client endpoints
- POST /registry/lease.register
  - Body: {"group":"<g>","name":"<n>","ttl_seconds":<u64>}
  - Caps: registry.lease.register:<g>
  - Success: {"ok":true}
- POST /registry/lease.heartbeat
  - Body: {"group":"<g>","name":"<n>","ttl_seconds":<u64>}
  - Caps: registry.lease.heartbeat:<g>
  - Success: {"ok":true}, 409 on invalid signature
- GET /registry/state
  - Returns UTCP registry JSON document (namespaced groups + lease metadata)
- GET /registry/tokens
  - Documents the token model for client apps

Admin endpoints (require registry.admin:*)
- GET /registry/quota
  - Returns {"max_entries_per_group": N}
- POST /registry/quota.set
  - Body: {"max_entries_per_group": <non-negative integer>}
  - Success: {"ok":true}
- POST /registry/rotate
  - Body: {"key_hex":"<64 hex>"}
  - Success: {"ok":true}

Notes
- Replication occurs only after local validation (quota, signature checks).
- Quotas are enforced per group and purge expired entries opportunistically.
- The UTCP manual (/utcp) includes these tools with x‑janus‑capabilities for discovery.

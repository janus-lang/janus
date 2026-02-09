# RFC-023: GrainStore (stdlib) v0.1 — Minimal LSM KV for :cluster

**Version:** 1.0.0-MINIMAL  
**Status:** APPROVED (LOCKED SCOPE)  
**Date:** 2026-02-09  
**Author:** Janus + Markus  
**Depends On:** RFC-021 (:cluster), RFC-022 (LSM Tree)  

## Summary

**GrainStore** is the **stdlib embedded KV store** for `:cluster` Grains. It provides **minimal LSM** persistence with **TTL** and **WAL batching** — enough for ~90% of simple actor use cases.

**Out of scope:** compression, snapshots, column families, transactions. These move to **StoreDB** (plugin).

---

## Goals

- **Actor-Friendly:** persistent Grain state with low overhead
- **High Throughput:** WAL batching for bursty workloads
- **Automatic Cleanup:** TTL expiry for ephemeral data
- **Zero deps:** no zstd/snappy

## Non-Goals

- Feature parity with RocksDB
- SQL or document layers
- Replication or sharding

---

## Minimal Feature Set (LOCKED)

✅ MemTable / WAL / SSTable / Compaction  
✅ Bloom filters  
✅ **TTL expiry** (per key)  
✅ **WAL batching** (group fsync)  
✅ Single column family  
✅ Simple iterators

---

## API Sketch

```zig
var store = GrainStore.open(allocator, "grain_user42.db", .{
    .ttl_default_ms = 3600_000,
    .wal_batch_ms = 10,
});

defer store.close();

try store.put("session.token", "xyz", .{ .ttl_ms = 300_000 });
try store.put("hp", "100", .{});

const hp = store.get("hp") orelse "0";
```

---

## TTL Semantics

- TTL stored in key metadata
- Expired keys filtered on read
- Compaction purges expired keys
- Optional `ttl_default_ms`

---

## WAL Batching

- `wal_batch_ms` controls group commit
- Multiple writes → single fsync
- Guarantees: durability within batch window

---

## Use Cases

**WhatsApp/Chat:** sessions, OTPs, presence flags  
**Games:** cooldowns, buffs, NPC state  
**Supply Chain:** telemetry windows, ephemeral alerts  
**Rovers:** transient sensor anomalies

---

## StoreDB (Plugin) — Deferred

All advanced features move to **StoreDB** plugin:
- Column families
- Compression (zstd/snappy)
- Snapshots
- Transactions
- Advanced compaction heuristics

---

## Implementation Plan

**Phase 1:** Core LSM (DONE)  
**Phase 2:** TTL metadata + purge  
**Phase 3:** WAL batching  
**Phase 4:** Iterators

---

**LOCKED SCOPE**

GrainStore v0.1 = minimal LSM + TTL + WAL batching.  
Everything else deferred to StoreDB plugin.

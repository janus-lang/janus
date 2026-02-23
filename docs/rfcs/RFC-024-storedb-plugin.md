# RFC-024: StoreDB Plugin — RocksDB-Class KV Engine

**Version:** 0.1.0-DRAFT  
**Status:** PROPOSAL  
**Date:** 2026-02-09  
**Author:** Janus + Markus  
**Depends On:** RFC-023 (GrainStore stdlib)  

## Summary

**StoreDB** is a **plugin (not core stdlib)** providing RocksDB‑class features for advanced workloads. It builds on GrainStore architecture but adds compression, column families, snapshots, and advanced compaction. It is distributed as an SDK/plugin crate and loaded on demand.

**Reason:** Keep core minimal, deterministic, and dependency‑free; move heavy features to optional plugin.

## Goals
- Feature parity with RocksDB
- Modular plugin distribution
- Advanced heuristics (adaptive compaction)
- Optional compression (zstd/snappy)

## Non-Goals
- Replace GrainStore in stdlib
- Ship in default Janus runtime

## Features (v1)
- Column Families
- Snapshots
- Compression (zstd/snappy)
- TTL + Tombstone tuning
- Block cache + LRU
- Manifest versioning + recovery

## Distribution Model
```
use storedb // plugin crate

const db = StoreDB.open("path", .{ .compression = .zstd });
```

## Timeline
- v0.1 (3–4 weeks): core parity + compression
- v0.2: tuning + metrics
- v1.0: production hardened

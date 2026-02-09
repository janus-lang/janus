# GrainStore (stdlib)

**Status:** v0.1 LOCKED  
**Profile:** :cluster  
**Purpose:** Minimal embedded LSM KV store for Grains  

## Features (v0.1)
✅ MemTable + WAL + SSTable + Compaction  
✅ Bloom Filter  
✅ **TTL per key**  
✅ **WAL batching (group fsync)**  
✅ Single column family  

## API

```zig
var store = GrainStore.open(allocator, "grain_user42.db", .{
    .ttl_default_ms = 3600_000, // 1h
    .wal_batch_ms = 10,         // 10ms
});

defer store.close();

try store.put("session", "token", null); // uses default TTL
try store.put("hp", "100", .{ .ttl_ms = 0 });

const hp = store.get("hp") orelse "0";
```

## TTL Semantics
- TTL stored in key metadata
- Expired keys filtered on read
- Compaction purges expired keys

## WAL Batching
- `wal_batch_ms` groups writes
- Single fsync per batch window

## Out of Scope (StoreDB plugin)
- Compression
- Snapshots
- Column families
- Transactions

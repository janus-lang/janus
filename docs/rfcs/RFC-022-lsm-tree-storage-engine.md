# RFC-022: LSM-Tree Storage Engine for Janus

**Version:** 1.0.0-DRAFT  
**Status:** PROPOSAL  
**Date:** 2026-02-09  
**Author:** Janus (synthesized from GPT-5.2-Codex blueprint)  
**Supersedes:** None  
**Depends On:** :sovereign profile (raw pointers, comptime)  

## Summary

This RFC specifies an **embedded LSM-tree key-value store** in Zig for Janus `:cluster` Grains persistence. Provides RocksDB-like performance with Janus-native safety (explicit allocators, error unions, comptime optimizations).

**Goals:**
- **Grain Persistence:** Durable actor state across restarts
- **High Performance:** 100k writes/sec, <100µs reads
- **Zig-Native:** No C bindings, comptime-tuned structures
- **Production Ready:** WAL durability, compaction, bloom filters

**Non-Goals:**
- Distributed replication (L2 federation)
- SQL layer (future :compute profile)
- WAL replication (future RFC)

## Design

### LSM Components

1. **MemTable:** Skip list (arena-backed)
2. **WAL:** Append-only with CRC32
3. **SSTable:** Immutable [Data][Index][Footer] with bloom filter
4. **Manifest:** Metadata for levels
5. **Compactor:** Level-based background merging

### Write Path
```
Write → WAL (batch fsync) → MemTable → Flush L0 SSTable → Compaction
```

### Read Path
```
MemTable → Immutable MemTables → Bloom Filter → SSTable Binary Search → Block Scan
```

### File Formats

**WAL Entry:** `[len: u32][key_len: u32][key][value_len: u32][value][crc32: u32]`

**SSTable:**
```
[Data Blocks (prefix-compressed K/V)] [Index Block (sparse key→offset)] [Footer (magic/index_offset/bloom_offset)]
```

## Zig Implementation

### 1. MemTable (Skip List + Arena)

```zig
const MemTable = struct {
    skiplist: SkipList([]const u8, []const u8),
    arena: std.heap.ArenaAllocator,
    size_bytes: usize,
    
    pub fn put(self: *MemTable, key: []const u8, value: []const u8) !void {
        try self.skiplist.insert(try self.arena.allocator().dupe(u8, key), 
                                 try self.arena.allocator().dupe(u8, value));
        self.size_bytes += key.len + value.len;
    }
};
```

### 2. WAL

```zig
const WALEntry = packed struct {
    len: u32,
    key_len: u32,
    value_len: u32,
    crc32: u32,
};

const WAL = struct {
    file: std.fs.File,
    
    pub fn append(self: *WAL, key: []const u8, value: []const u8) !void {
        const entry = WALEntry{
            .len = @intCast(key.len + value.len + 8),
            .key_len = @intCast(key.len),
            .value_len = @intCast(value.len),
            .crc32 = std.hash.Crc32.hash(key ++ value),
        };
        try self.file.writer().writeStruct(entry);
        try self.file.writer().writeAll(key);
        try self.file.writer().writeAll(value);
        try self.file.sync(); // Durability
    }
};
```

### 3. SSTable + Bloom Filter

```zig
const BloomFilter = struct {
    bits: []u8,
    num_hashes: comptime_int = 7,
    
    pub fn add(self: *BloomFilter, key: []const u8) void {
        inline for (0..self.num_hashes) |i| {
            const hash = std.hash.Wyhash.hash(i, key);
            const idx = hash % (self.bits.len * 8);
            self.bits[idx / 8] |= 1 << @intCast(idx % 8);
        }
    }
};

const SSTable = struct {
    file: std.fs.File,
    bloom: BloomFilter,
    
    pub fn get(self: *SSTable, key: []const u8) !?[]const u8 {
        if (!self.bloom.mightContain(key)) return null;
        // Binary search index + block scan
    }
};
```

### 4. Compaction

```zig
const Compactor = struct {
    pub fn compact(db: *DB, level: usize) !void {
        const files = db.manifest.levelFiles(level);
        const candidates = db.manifest.overlappingFiles(level + 1, files);
        var merger = try MultiWayMerge.init(db.allocator, files ++ candidates);
        defer merger.deinit();
        
        var builder = try SSTableBuilder.init(db.allocator);
        while (try merger.next()) |entry| {
            try builder.add(entry.key, entry.value);
        }
        try builder.finish();
        try db.manifest.replace(level + 1, builder.sstables);
    }
};
```

## Integration with Janus

**Grain Storage:**
```
grain UserGrain do
    init(id) do
        self.db = LSMTree([]const u8, State).open(id)
    end
    
    handle_call({:balance, user_id}, from, state) !Reply do
        try self.db.put(user_id, state.balance)
        let balance = self.db.get(user_id) orelse 0
        {:reply, balance, state}
    end
end
```

**Comptime Specialization:**
```zig
pub fn LSMTree(comptime K: type, comptime V: type) type {
    return struct {
        // Specialized serializers
        comptime {
            // Generate optimal code for K/V types
        }
    };
}
```

## Testing Strategy

**BDD-TDD (Forgie Rigor):**
```
Scenario: LSM write durability
  Given LSM DB with WAL
  When write key/value + crash
  Then WAL replay restores MemTable
```

**Property Tests:**
- Write/read consistency
- Compaction idempotency
- Bloom false positive rate <1%

## Benchmarks vs RocksDB/Fjall

| Metric | Target | RocksDB | Fjall |
|--------|--------|---------|-------|
| Writes/sec | 100k | 120k | 95k |
| Read µs | <100 | 80 | 120 |
| Compaction CPU | <10% | 8% | 12% |

## Rollout Plan

1. **Phase 1:** LSM + MemTable/WAL (Week 1)
2. **Phase 2:** SSTable + Bloom (Week 2)
3. **Phase 3:** Compaction + Benchmarks (Week 3)
4. **Phase 4:** Grain integration + tests (Week 4)

**Status:** READY FOR IMPLEMENTATION

**Next:** Spawn gpt-5.2-codex for Phase 1 code?

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Dispatch Advanced Stub Strategies Spec (Task 2)

**Status:** Draft — Ready for Implementation
**Filename:** `docs/specs/dispatch-advanced-stubs.md`

---

## Purpose

**Task 2: Advanced Stub Strategies** builds upon the foundation of Task 1 to implement highrmance dispatch optimization techniques. The goal is to provide O(1) dispatch for large overload sets and hot-path optimization for frequently called dispatch sites.

This task transforms dispatch from "efficient" to "zero-cost abstraction" for production workloads.

---

## Scope & Objectives

### **Objective 1: Perfect Hash Generation**

**Goal:** Implement O(1) dispatch table lookup for large overload sets (>10 candidates).

**Requirements:**
- Generate minimal perfect hash functions at compile time
- Fallback to switch table if perfect hash is impossible
- Hash collision detection and resolution
- Memory-efficient hash table layout

**Success Criteria:**
- O(1) lookup time regardless of candidate count
- Hash table size ≤ 1.5× candidate count
- Generation time ≤ 100ms for 1000 candidates
- Zero false positives in hash collision detection

---

### **Objective 2: Inline Cache Implementation**

**Goal:** Optimize hot dispatch paths with adaptive caching.

**Requirements:**
- Last-seen type caching with configurable cache size
- Adaptive behavior based on call site patterns
- Graceful degradation to full dispatch on cache miss
- Profile-guided cache size selection

**Success Criteria:**
- Cache hit: ≤ 3 cycles overhead
- Cache miss: ≤ 10% additional overhead vs switch table
- Memory footprint: ≤ 32 bytes per cache entry
- Adaptive sizing based on call frequency

---

### **Objective 3: Strategy Selection Heuristics**

**Goal:** Automatic strategy selection based on dispatch characteristics.

**Requirements:**
- Compile-time analysis of overload set characteristics
- Runtime profiling integration for adaptive selection
- Cost model for strategy comparison
- Override mechanism via attributes

**Selection Algorithm:**
```
if candidates ≤ 3:
    strategy = switch_table
elif candidates ≤ 50 and perfect_hash_possible:
    strategy = perfect_hash
elif hot_path_detected:
    strategy = inline_cache
else:
    strategy = switch_table
```

---

## Implementation Details

### **Perfect Hash Generation**

**Algorithm:** CHD (Compress, Hash, and Displace) algorithm
- Minimal perfect hash with excellent space efficiency
- Handles up to 10,000 candidates efficiently
- Deterministic generation for reproducible builds

**Data Structure:**
```zig
const PerfectHashTable = struct {
    // CHD algorithm components
    buckets: []HashBucket,
    displacement: []u32,
    hash_seed: u64,

    // Metadata
    candidate_count: u32,
    table_size: u32,
    generation_time_ns: u64,

    pub fn lookup(self: *const PerfectHashTable, type_id: TypeId) ?*const DispatchEntry;
    pub fn generate(candidates: []CandidateIR, allocator: Allocator) !PerfectHashTable;
};

const HashBucket = struct {
    entries: []?*DispatchEntry,
    displacement_index: u32,
};
```

**Generation Process:**
1. **Analysis Phase**: Analyze type ID distribution and collision patterns
2. **Hash Selection**: Choose optimal hash function and seed
3. **Bucket Assignment**: Assign candidates to buckets with minimal collisions
4. **Displacement Calculation**: Compute displacement values for collision resolution
5. **Validation**: Verify perfect hash properties and performance characteristics

---

### **Inline Cache Implementation**

**Cache Structure:**
```zig
const InlineCache = struct {
    // Cache entries (configurable size: 1, 2, 4, 8)
    entries: []CacheEntry,
    cache_size: u8,

    // Statistics for adaptive behavior
    hits: u64,
    misses: u64,
    evictions: u64,

    pub fn lookup(self: *InlineCache, type_id: TypeId) ?*const DispatchEntry;
    pub fn insert(self: *InlineCache, type_id: TypeId, entry: *const DispatchEntry) void;
    pub fn shouldResize(self: *const InlineCache) bool;
};

const CacheEntry = struct {
    type_id: TypeId,
    entry: *const DispatchEntry,
    access_count: u32,
    last_access: u64, // Timestamp for LRU
};
```

**Cache Policies:**
- **Insertion**: LRU (Least Recently Used) eviction
- **Sizing**: Start with size 1, grow to 2/4/8 based on miss rate
- **Invalidation**: Clear on dispatch table updates

**Generated Code Pattern:**
```llvm
define ptr @process_inline_cache_stub(ptr %arg) {
entry:
  %type_id = load i32, ptr %arg

  ; Check cache entry 0
  %cache_type_0 = load i32, ptr @cache_entry_0_type
  %cache_match_0 = icmp eq i32 %type_id, %cache_type_0
  br i1 %cache_match_0, label %cache_hit_0, label %check_cache_1

cache_hit_0:
  %cached_func_0 = load ptr, ptr @cache_entry_0_func
  %result_0 = call ptr %cached_func_0(ptr %arg)
  ret ptr %result_0

check_cache_1:
  ; ... additional cache entries

cache_miss:
  ; Fall back to full dispatch table
  %result_full = call ptr @process_full_dispatch_stub(ptr %arg)
  ; Update cache with result
  call void @update_inline_cache(i32 %type_id, ptr %result_full)
  ret ptr %result_full
}
```

---

### **Strategy Selection Integration**

**Compile-Time Analysis:**
```zig
const StrategyAnalyzer = struct {
    pub fn selectOptimalStrategy(
        candidates: []CandidateIR,
        call_frequency: ?u64,
        attribute_override: ?StubStrategy,
    ) StubStrategy {
        // Override takes precedence
        if (attribute_override) |override| {
            return override;
        }

        // Analyze characteristics
        const candidate_count = candidates.len;
        const type_diversity = analyzeTypeDiversity(candidates);
        const hash_feasible = isPerfectHashFeasible(candidates);

        // Apply selection heuristics
        if (candidate_count <= 3) {
            return .switch_table; // Simple cases
        }

        if (candidate_count <= 50 and hash_feasible) {
            return .perfect_hash; // Medium sets with good hash properties
        }

        if (call_frequency != null and call_frequency.? > HOT_PATH_THRESHOLD) {
            return .inline_cache; // Hot paths benefit from caching
        }

        return .switch_table; // Safe default
    }
};
```

**Runtime Profiling Integration:**
```zig
const ProfileGuidedOptimization = struct {
    call_counts: std.HashMap([]const u8, u64),
    cache_performance: std.HashMap([]const u8, CacheStats),

    pub fn shouldUpgradeStrategy(
        self: *ProfileGuidedOptimization,
        family_name: []const u8,
        current_strategy: StubStrategy,
    ) ?StubStrategy {
        const stats = self.cache_performance.get(family_name) orelse return null;

        switch (current_strategy) {
            .switch_table => {
                if (stats.call_frequency > HOT_PATH_THRESHOLD) {
                    return .inline_cache;
                }
            },
            .inline_cache => {
                if (stats.cache_miss_rate > 0.3) { // 30% miss rate
                    return .perfect_hash;
                }
            },
            .perfect_hash => {
                // Already optimal for large sets
                return null;
            },
        }

        return null;
    }
};
```

---

## Performance Targets

### **Perfect Hash Performance**

| Metric | Target | Maximum |
|--------|--------|---------|
| Lookup Time | O(1) | 5 cycles |
| Memory Overhead | 1.2× candidates | 1.5× candidates |
| Generation Time | <10ms per 100 candidates | 100ms per 1000 candidates |
| Hash Quality | Zero collisions | N/A |

### **Inline Cache Performance**

| Metric | Target | Maximum |
|--------|--------|---------|
| Cache Hit Latency | 2 cycles | 3 cycles |
| Cache Miss Penalty | 5% | 10% |
| Memory per Entry | 24 bytes | 32 bytes |
| Cache Effectiveness | 80% hit rate | 70% minimum |

### **Strategy Selection Accuracy**

| Metric | Target | Maximum |
|--------|--------|---------|
| Optimal Selection Rate | 90% | 85% minimum |
| Performance Regression | 0% | 5% maximum |
| Adaptation Time | <1000 calls | 10000 calls |

---

## Implementation Plan

### **Phase 1: Perfect Hash Foundation**
1. Implement CHD algorithm for hash generation
2. Add perfect hash table data structure
3. Integrate with existing LLVM codegen
4. Comprehensive testing with various candidate sets

### **Phase 2: Inline Cache System**
1. Design cache entry structure and policies
2. Implement LRU eviction and adaptive sizing
3. Generate optimized LLVM IR for cache checks
4. Profile-guided optimization integration

### **Phase 3: Strategy Selection**
1. Implement compile-time analysis heuristics
2. Add runtime profiling infrastructure
3. Create adaptive strategy upgrade system
4. Comprehensive benchmarking and validation

### **Phase 4: Integration & Optimization**
1. Integrate with existing dispatch table manager
2. Add comprehensive test coverage
3. Performance validation and tuning
4. Documentation and examples

---

## Testing Strategy

### **Unit Tests**
- Perfect hash generation with various input sets
- Inline cache behavior under different access patterns
- Strategy selection accuracy with known workloads
- Memory management and leak detection

### **Integration Tests**
- End-to-end dispatch with all three strategies
- Strategy switching and adaptation
- Performance regression detection
- Cross-platform compatibility

### **Performance Tests**
- Microbenchmarks for each strategy
- Large-scale dispatch workloads
- Memory usage profiling
- Cache behavior analysis

### **Stress Tests**
- Large overload sets (1000+ candidates)
- High-frequency dispatch calls
- Memory pressure scenarios
- Concurrent access patterns

---

## Success Criteria

### **Functional Requirements**
- ✅ Perfect hash generation succeeds for 95% of real-world overload sets
- ✅ Inline cache achieves >80% hit rate on typical workloads
- ✅ Strategy selection chooses optimal strategy in >90% of cases
- ✅ All existing tests continue to pass

### **Performance Requirements**
- ✅ Perfect hash: O(1) lookup in ≤5 cycles
- ✅ Inline cache: ≤3 cycles for cache hits
- ✅ Strategy overhead: ≤5% vs optimal manual selection
- ✅ Memory efficiency: ≤1.5× candidate count for all strategies

### **Quality Requirements**
- ✅ Zero memory leaks in all strategies
- ✅ Deterministic code generation for reproducible builds
- ✅ Comprehensive error handling and diagnostics
- ✅ Complete documentation and examples

---

## Deliverables

### **Core Implementation**
- `perfect_hash_generator.zig` - CHD algorithm implementation
- `inline_cache_manager.zig` - Cache system and policies
- `strategy_selector.zig` - Heuristics and profiling integration
- Enhanced `llvm_dispatch_codegen.zig` - Support for all strategies

### **Testing & Validation**
- Comprehensive test suite for all strategies
- Performance benchmark suite
- Strategy selection validation tests
- Memory usage and leak detection tests

### **Documentation**
- Implementation guide for advanced strategies
- Performance tuning recommendations
- Strategy selection guidelines
- Migration guide from Task 1

---

## Risk Mitigation

### **Perfect Hash Generation Failure**
- **Risk**: Some overload sets may not be suitable for perfect hashing
- **Mitigation**: Automatic fallback to switch table with clear diagnostics

### **Inline Cache Thrashing**
- **Risk**: Poor cache performance on highly polymorphic call sites
- **Mitigation**: Adaptive cache sizing and automatic strategy downgrade

### **Strategy Selection Overhead**
- **Risk**: Analysis and profiling may impact compilation performance
- **Mitigation**: Lazy evaluation and caching of analysis results

### **Memory Fragmentation**
- **Risk**: Multiple strategies may increase memory usage
- **Mitigation**: Shared arena allocation and careful memory layout

---

⚔️ **Task 2 transforms dispatch from "efficient" to "zero-cost abstraction" through intelligent optimization strategies.**

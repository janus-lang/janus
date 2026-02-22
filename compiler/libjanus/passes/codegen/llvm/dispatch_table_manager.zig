// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

// IR and codegen imports
const DispatchIR = @import("ir_dispatch.zig").DispatchIR;
const DynamicStubIR = @import("ir_dispatch.zig").DynamicStubIR;
const StubStrategy = @import("ir_dispatch.zig").StubStrategy;

/// Memory management for dispatch tables following the Arena Sovereignty Law
pub const DispatchTableManager = struct {
    // The sovereign arena for this package's dispatch tables
    arena: std.heap.ArenaAllocator,
    base_allocator: Allocator,

    // Active dispatch tables
    tables: std.StringHashMap(DispatchTable),

    // Serialization cache
    cache_dir: ?[]const u8,

    // Statistics
    stats: ManagerStats,

    const ManagerStats = struct {
        tables_created: u32 = 0,
        tables_cached: u32 = 0,
        total_memory_bytes: u64 = 0,
        cache_hits: u32 = 0,
        cache_misses: u32 = 0,

        pub fn reset(self: *ManagerStats) void {
            self.* = ManagerStats{};
        }
    };

    pub fn init(base_allocator: Allocator, cache_dir: ?[]const u8) DispatchTableManager {
        return DispatchTableManager{
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .base_allocator = base_allocator,
            .tables = std.StringHashMap(DispatchTable).init(base_allocator),
            .cache_dir = cache_dir,
            .stats = ManagerStats{},
        };
    }

    pub fn deinit(self: *DispatchTableManager) void {
        // Clear all tables first
        var iterator = self.tables.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.tables.deinit();

        // Dispose of the arena (The Arena Sovereignty Law)
        self.arena.deinit();

        std.debug.print("🏛️ Dispatch arena destroyed (sovereignty ended)\\n", .{});
    }

    /// Create or retrieve a dispatch table for a family
    pub fn getOrCreateTable(
        self: *DispatchTableManager,
        family_name: []const u8,
        dynamic_ir: DynamicStubIR,
    ) !*DispatchTable {
        // Check if table already exists
        if (self.tables.getPtr(family_name)) |existing_table| {
            std.debug.print("📋 Reusing existing dispatch table for {s}\\n", .{family_name});
            return existing_table;
        }

        // Try to load from cache first
        if (try self.loadFromCache(family_name)) |cached_table| {
            try self.tables.put(family_name, cached_table);
            self.stats.cache_hits += 1;
            std.debug.print("💾 Loaded dispatch table from cache: {s}\\n", .{family_name});
            return self.tables.getPtr(family_name).?;
        }

        // Create new table
        const table = try self.createTable(family_name, dynamic_ir);
        try self.tables.put(family_name, table);

        // Cache the new table
        try self.saveToCache(family_name, &table);

        self.stats.tables_created += 1;
        self.stats.cache_misses += 1;

        std.debug.print("🆕 Created new dispatch table: {s} ({} entries)\\n", .{ family_name, table.entries.len });

        return self.tables.getPtr(family_name).?;
    }

    /// Create a new dispatch table
    fn createTable(
        self: *DispatchTableManager,
        family_name: []const u8,
        dynamic_ir: DynamicStubIR,
    ) !DispatchTable {
        const arena_allocator = self.arena.allocator();

        // Allocate family name in arena
        const owned_name = try arena_allocator.dupe(u8, family_name);

        // Create dispatch entries
        const entries = try arena_allocator.alloc(DispatchEntry, dynamic_ir.candidates.len);

        for (dynamic_ir.candidates, 0..) |candidate, i| {
            entries[i] = DispatchEntry{
                .type_id = candidate.type_check_ir.target_type,
                .function_name = try arena_allocator.dupe(u8, candidate.function_ref.name),
                .mangled_name = try arena_allocator.dupe(u8, candidate.function_ref.mangled_name),
                .match_score = candidate.match_score,
                .conversion_cost = self.calculateConversionCost(candidate.conversion_path),
            };
        }

        // Sort entries by match score for optimal lookup
        std.sort.insertion(DispatchEntry, entries, {}, DispatchEntry.lessThan);

        const table_size = @sizeOf(DispatchTable) + entries.len * @sizeOf(DispatchEntry);
        self.stats.total_memory_bytes += table_size;

        return DispatchTable{
            .family_name = owned_name,
            .entries = entries,
            .strategy = dynamic_ir.strategy,
            .hash_table = null, // Will be populated if using perfect hash
            .cache_friendly_layout = true,
        };
    }

    /// Load dispatch table from cache
    fn loadFromCache(self: *DispatchTableManager, family_name: []const u8) !?DispatchTable {
        if (self.cache_dir == null) return null;

        const cache_path = try std.fmt.allocPrint(
            self.base_allocator,
            "{s}/{s}.dispatch",
            .{ self.cache_dir.?, family_name },
        );
        defer self.base_allocator.free(cache_path);

        // Check if cache file exists
        const file = std.fs.cwd().openFile(cache_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        defer file.close();

        // Read and deserialize
        const file_size = try file.getEndPos();
        const buffer = try self.base_allocator.alloc(u8, file_size);
        defer self.base_allocator.free(buffer);

        _ = try file.readAll(buffer);

        return try self.deserializeTable(buffer);
    }

    /// Save dispatch table to cache
    fn saveToCache(self: *DispatchTableManager, family_name: []const u8, table: *const DispatchTable) !void {
        if (self.cache_dir == null) return;

        const cache_path = try std.fmt.allocPrint(
            self.base_allocator,
            "{s}/{s}.dispatch",
            .{ self.cache_dir.?, family_name },
        );
        defer self.base_allocator.free(cache_path);

        // Ensure cache directory exists
        std.fs.cwd().makePath(self.cache_dir.?) catch {};

        // Serialize and write
        const serialized = try self.serializeTable(table);
        defer self.base_allocator.free(serialized);

        const file = try std.fs.cwd().createFile(cache_path, .{});
        defer file.close();

        try file.writeAll(serialized);

        self.stats.tables_cached += 1;
        std.debug.print("💾 Cached dispatch table: {s} ({} bytes)\\n", .{ family_name, serialized.len });
    }

    /// Serialize dispatch table to CBOR format
    fn serializeTable(self: *DispatchTableManager, table: *const DispatchTable) ![]u8 {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit();

        // Simple binary format (would use CBOR in production)
        // Format: [name_len][name][entry_count][entries...]

        // Write family name
        try buffer.writer().writeInt(u32, @intCast(table.family_name.len), .little);
        try buffer.appendSlice(table.family_name);

        // Write strategy
        try buffer.writer().writeInt(u8, @intFromEnum(table.strategy), .little);

        // Write entry count
        try buffer.writer().writeInt(u32, @intCast(table.entries.len), .little);

        // Write entries
        for (table.entries) |entry| {
            // Type ID
            try buffer.writer().writeInt(u64, entry.type_id.id, .little);

            // Function name
            try buffer.writer().writeInt(u32, @intCast(entry.function_name.len), .little);
            try buffer.appendSlice(entry.function_name);

            // Mangled name
            try buffer.writer().writeInt(u32, @intCast(entry.mangled_name.len), .little);
            try buffer.appendSlice(entry.mangled_name);

            // Scores
            try buffer.writer().writeInt(u32, entry.match_score, .little);
            try buffer.writer().writeInt(u32, entry.conversion_cost, .little);
        }

        return try buffer.toOwnedSlice();
    }

    /// Deserialize dispatch table from CBOR format
    fn deserializeTable(self: *DispatchTableManager, data: []const u8) !DispatchTable {
        var stream = std.io.fixedBufferStream(data);
        const reader = stream.reader();
        const arena_allocator = self.arena.allocator();

        // Read family name
        const name_len = try reader.readInt(u32, .little);
        const family_name = try arena_allocator.alloc(u8, name_len);
        _ = try reader.readAll(family_name);

        // Read strategy
        const strategy_byte = try reader.readInt(u8, .little);
        const strategy = @as(StubStrategy, @enumFromInt(strategy_byte));

        // Read entry count
        const entry_count = try reader.readInt(u32, .little);
        const entries = try arena_allocator.alloc(DispatchEntry, entry_count);

        // Read entries
        for (entries) |*entry| {
            // Type ID
            const TypeId = @import("type_registry.zig").TypeId;
            const type_id_raw = try reader.readInt(u64, .little);
            entry.type_id = TypeId{ .id = @intCast(type_id_raw) };

            // Function name
            const func_name_len = try reader.readInt(u32, .little);
            const func_name = try arena_allocator.alloc(u8, func_name_len);
            _ = try reader.readAll(func_name);
            entry.function_name = func_name;

            // Mangled name
            const mangled_name_len = try reader.readInt(u32, .little);
            const mangled_name = try arena_allocator.alloc(u8, mangled_name_len);
            _ = try reader.readAll(mangled_name);
            entry.mangled_name = mangled_name;

            // Scores
            entry.match_score = try reader.readInt(u32, .little);
            entry.conversion_cost = try reader.readInt(u32, .little);
        }

        return DispatchTable{
            .family_name = family_name,
            .entries = entries,
            .strategy = strategy,
            .hash_table = null,
            .cache_friendly_layout = true,
        };
    }

    /// Calculate conversion cost for ranking
    fn calculateConversionCost(self: *DispatchTableManager, conversions: []const @import("ir_dispatch.zig").ConversionStep) u32 {
        _ = self;
        var total_cost: u32 = 0;

        for (conversions) |conversion| {
            total_cost += conversion.cost;
        }

        return total_cost;
    }

    /// Get manager statistics
    pub fn getStats(self: *const DispatchTableManager) ManagerStats {
        return self.stats;
    }

    /// Clear all tables (for testing)
    pub fn clearTables(self: *DispatchTableManager) void {
        var iterator = self.tables.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.tables.clearAndFree();

        // Reset arena
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.base_allocator);

        self.stats.reset();

        std.debug.print("🧹 All dispatch tables cleared\\n", .{});
    }
};

/// Dispatch table structure (cache-friendly layout)
pub const DispatchTable = struct {
    family_name: []const u8,
    entries: []DispatchEntry,
    strategy: StubStrategy,
    hash_table: ?PerfectHashTable,
    cache_friendly_layout: bool,

    pub fn deinit(self: *DispatchTable) void {
        // Memory is managed by arena, no explicit cleanup needed
        _ = self;
    }

    /// Find entry by type ID
    pub fn findEntry(self: *const DispatchTable, type_id: @import("type_registry.zig").TypeId) ?*const DispatchEntry {
        if (self.hash_table) |hash_table| {
            return hash_table.lookup(type_id);
        }

        // Linear search for switch table strategy
        for (self.entries) |*entry| {
            if (entry.type_id.equals(type_id)) {
                return entry;
            }
        }

        return null;
    }

    /// Get the best matching entry for a type
    pub fn getBestMatch(self: *const DispatchTable, type_id: @import("type_registry.zig").TypeId) ?*const DispatchEntry {
        var best_entry: ?*const DispatchEntry = null;
        var best_score: u32 = std.math.maxInt(u32);

        for (self.entries) |*entry| {
            if (entry.type_id.equals(type_id) and entry.match_score < best_score) {
                best_entry = entry;
                best_score = entry.match_score;
            }
        }

        return best_entry;
    }
};

/// Individual dispatch table entry
pub const DispatchEntry = struct {
    type_id: @import("type_registry.zig").TypeId,
    function_name: []const u8,
    mangled_name: []const u8,
    match_score: u32,
    conversion_cost: u32,

    pub fn lessThan(context: void, a: DispatchEntry, b: DispatchEntry) bool {
        _ = context;
        return a.match_score < b.match_score;
    }
};

/// Perfect hash table for O(1) dispatch
pub const PerfectHashTable = struct {
    table: []?*DispatchEntry,
    size: usize,
    hash_function: HashFunction,

    const HashFunction = enum {
        simple_string_hash,
        fnv1a_hash,
        murmur3_hash,
    };

    pub fn lookup(self: *const PerfectHashTable, type_id: @import("type_registry.zig").TypeId) ?*const DispatchEntry {
        // Simplified lookup - would use proper type-based hashing in production
        const hash = type_id.id % self.size;
        var index = hash;

        // Linear probing
        while (self.table[index]) |entry| {
            if (entry.type_id.equals(type_id)) {
                return entry;
            }
            index = (index + 1) % self.size;
        }

        return null;
    }
};

// Tests
test "DispatchTableManager lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = DispatchTableManager.init(allocator, null);
    defer manager.deinit();

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u32, 0), stats.tables_created);
    try std.testing.expectEqual(@as(u64, 0), stats.total_memory_bytes);

    std.debug.print("✅ DispatchTableManager lifecycle test passed\\n", .{});
}

test "Dispatch table creation and lookup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = DispatchTableManager.init(allocator, null);
    defer manager.deinit();

    // Create mock dynamic IR
    const TypeId = @import("type_registry.zig").TypeId;
    const FunctionRef = @import("ir_dispatch.zig").FunctionRef;
    const FunctionSignature = @import("ir_dispatch.zig").FunctionSignature;
    const CandidateIR = @import("ir_dispatch.zig").CandidateIR;
    const TypeCheckIR = @import("ir_dispatch.zig").TypeCheckIR;
    const SourceSpan = @import("ir_dispatch.zig").SourceSpan;

    const candidates = [_]CandidateIR{
        CandidateIR{
            .function_ref = FunctionRef{
                .name = "process_int",
                .mangled_name = "_Z11process_inti",
                .signature = FunctionSignature{
                    .parameters = @constCast(&[_]TypeId{TypeId.I32}),
                    .return_type = TypeId.STRING,
                    .is_variadic = false,
                },
            },
            .conversion_path = &[_]@import("ir_dispatch.zig").ConversionStep{},
            .match_score = 10,
            .type_check_ir = TypeCheckIR{
                .check_kind = .exact_match,
                .target_type = TypeId.I32,
                .parameter_index = 0,
            },
        },
    };

    const dynamic_ir = DynamicStubIR{
        .family_name = "process",
        .candidates = @constCast(&candidates),
        .strategy = .switch_table,
        .cost_estimate = 15,
        .source_location = SourceSpan{
            .file = "test.jan",
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 10,
        },
    };

    const table = try manager.getOrCreateTable("process", dynamic_ir);
    try std.testing.expect(table.entries.len == 1);
    try std.testing.expectEqualStrings("process", table.family_name);

    // Test lookup
    const entry = table.findEntry(TypeId.I32);
    try std.testing.expect(entry != null);
    try std.testing.expectEqualStrings("process_int", entry.?.function_name);

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.tables_created);

    std.debug.print("✅ Dispatch table creation and lookup test passed\\n", .{});
}

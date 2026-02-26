const std = @import("std");
const lsm = @import("../../runtime/lsm");

test "LSM Phase 2 — SSTable + Bloom" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memtable = try lsm.MemTable.init(allocator, 1024);
    defer memtable.deinit();

    try memtable.put("key1", "value1");
    try memtable.put("key2", "value2");

    // Flush to SSTable
    var sstable = try lsm.SSTable.fromMemTable(memtable, allocator, "test.sstable");
    defer sstable.deinit();

    // Test bloom filter
    try std.testing.expect(sstable.bloom.mightContain("key1"));
    try std.testing.expect(!sstable.bloom.mightContain("missing"));

    // Test get
    const val1 = try sstable.get("key1");
    try std.testing.expectEqualStrings("value1", val1.?);

    const val2 = try sstable.get("key2");
    try std.testing.expectEqualStrings("value2", val2.?);

    const missing = try sstable.get("missing");
    try std.testing.expect(missing == null);
}

const std = @import("std");
const lsm = @import("../../runtime/lsm");

test "LSM Phase 1 — MemTable + WAL" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // WAL durability
    var wal = try lsm.WAL.init(allocator, "test.wal");
    defer wal.deinit();

    try wal.append("key1", "value1");
    try wal.append("key2", "value2");

    // Crash simulation
    wal.deinit();

    // Recovery
    var memtable = try lsm.WAL.recover(allocator, "test.wal");
    defer memtable.deinit();

    const val1 = memtable.get("key1");
    try std.testing.expectEqualStrings("value1", val1.?);

    const val2 = memtable.get("key2");
    try std.testing.expectEqualStrings("value2", val2.?);
}

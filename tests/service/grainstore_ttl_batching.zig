const std = @import("std");
const GrainStore = @import("../../runtime/lsm/lsm.zig").GrainStore;

test "GrainStore TTL + WAL batching" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try GrainStore.open(allocator, "grain_test.db", .{
        .ttl_default_ms = 100,
        .wal_batch_ms = 10,
    });
    defer store.close();

    try store.put("session", "token", null); // uses default TTL
    const val = store.get("session");
    try std.testing.expectEqualStrings("token", val.?);

    // Wait past TTL
    std.time.sleep(150 * std.time.ns_per_ms);
    const expired = store.get("session");
    try std.testing.expect(expired == null);
}

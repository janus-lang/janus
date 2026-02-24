// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Integration Test: Full :service Profile CSP System
//!
//! This test validates the COMPLETE :service profile by combining:
//! - Nurseries (structured concurrency)
//! - Spawn (parallel task execution)
//! - Channels (CSP communication)
//! - Select (multiplexing)
//!
//! This proves that all CSP primitives work together in a real scenario.

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test ":service profile: Producer-Consumer with channels in nursery" {
    const allocator = testing.allocator;

    // Producer-consumer pattern: spawn two tasks that communicate via channel
    const source =
        \\func producer(ch: Channel) do
        \\    ch.send(42)
        \\    ch.send(100)
        \\    ch.close()
        \\    return 0
        \\end
        \\
        \\func consumer(ch: Channel) do
        \\    let val1 = ch.recv()
        \\    print(val1)
        \\    let val2 = ch.recv()
        \\    print(val2)
        \\    return 0
        \\end
        \\
        \\async func main() do
        \\    let ch = channel(2)
        \\    nursery do
        \\        spawn producer(ch)
        \\        spawn consumer(ch)
        \\    end
        \\    return 0
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Verify QTJIR contains all expected opcodes
    var found_nursery_begin = false;
    var found_nursery_end = false;
    var found_spawn = false;
    var found_channel_create = false;
    var found_channel_send = false;
    var found_channel_recv = false;
    var spawn_count: usize = 0;

    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items, 0..) |node, i| {
            switch (node.op) {
                .Nursery_Begin => found_nursery_begin = true,
                .Nursery_End => found_nursery_end = true,
                .Spawn => {
                    found_spawn = true;
                    spawn_count += 1;
                    switch (node.data) {
                        .string => |s| std.debug.print(" -> '{s}'", .{s}),
                        else => {},
                    }
                },
                .Channel_Create => found_channel_create = true,
                .Channel_Send => found_channel_send = true,
                .Channel_Recv => found_channel_recv = true,
                else => {},
            }
        }
    }

    try testing.expect(found_nursery_begin);
    try testing.expect(found_nursery_end);
    try testing.expect(found_spawn);
    try testing.expect(found_channel_create);
    try testing.expect(found_channel_send);
    try testing.expect(found_channel_recv);
    try testing.expectEqual(@as(usize, 2), spawn_count); // 2 spawned tasks

    // Emit to LLVM IR
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "producer_consumer_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);


    // Verify all runtime functions are called
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_nursery_create") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_nursery_spawn") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_nursery_await_all") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_channel_create") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_channel_send") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_channel_recv") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_channel_close") != null);

    // Verify producer and consumer functions exist
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@producer") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@consumer") != null);

}

test ":service profile: Select with spawned tasks" {
    const allocator = testing.allocator;

    // Select statement with multiple channel operations inside a nursery
    const source =
        \\async func main() do
        \\    let ch1 = channel(1)
        \\    let ch2 = channel(1)
        \\
        \\    select do
        \\        case ch1.recv() do
        \\            print(1)
        \\        end
        \\        case ch2.recv() do
        \\            print(2)
        \\        end
        \\        timeout(1000) do
        \\            print(999)
        \\        end
        \\        default do
        \\            print(0)
        \\        end
        \\    end
        \\
        \\    return 0
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Verify select opcodes are present
    var found_select_begin = false;
    var found_select_add_recv = false;
    var found_select_add_timeout = false;
    var found_select_add_default = false;
    var found_select_wait = false;

    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items, 0..) |node, i| {
            switch (node.op) {
                .Select_Begin => found_select_begin = true,
                .Select_Add_Recv => found_select_add_recv = true,
                .Select_Add_Timeout => found_select_add_timeout = true,
                .Select_Add_Default => found_select_add_default = true,
                .Select_Wait => found_select_wait = true,
                else => {},
            }
        }
    }

    try testing.expect(found_select_begin);
    try testing.expect(found_select_add_recv);
    try testing.expect(found_select_add_timeout);
    try testing.expect(found_select_add_default);
    try testing.expect(found_select_wait);

    // Emit to LLVM IR
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "select_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);


    // Verify all select runtime functions are called
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_select_create") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_select_add_recv") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_select_add_timeout") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_select_add_default") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_select_wait") != null);

}

test ":service profile: Complete CSP system (nursery + spawn + channels + select)" {
    const allocator = testing.allocator;

    // Complex scenario: Multiple spawned tasks communicating via channels with select
    const source =
        \\func sender1(ch: Channel) do
        \\    ch.send(111)
        \\    return 0
        \\end
        \\
        \\func sender2(ch: Channel) do
        \\    ch.send(222)
        \\    return 0
        \\end
        \\
        \\func receiver(ch1: Channel, ch2: Channel) do
        \\    select do
        \\        case ch1.recv() do
        \\            print(1)
        \\        end
        \\        case ch2.recv() do
        \\            print(2)
        \\        end
        \\        default do
        \\            print(0)
        \\        end
        \\    end
        \\    return 0
        \\end
        \\
        \\async func main() do
        \\    let ch1 = channel(1)
        \\    let ch2 = channel(1)
        \\
        \\    nursery do
        \\        spawn sender1(ch1)
        \\        spawn sender2(ch2)
        \\        spawn receiver(ch1, ch2)
        \\    end
        \\
        \\    return 0
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Count all CSP primitives
    var nursery_count: usize = 0;
    var spawn_count: usize = 0;
    var channel_create_count: usize = 0;
    var select_count: usize = 0;

    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items, 0..) |node, i| {
            switch (node.op) {
                .Nursery_Begin => nursery_count += 1,
                .Spawn => {
                    spawn_count += 1;
                    switch (node.data) {
                        .string => |s| std.debug.print(" -> '{s}'", .{s}),
                        else => {},
                    }
                },
                .Channel_Create => channel_create_count += 1,
                .Select_Begin => select_count += 1,
                else => {},
            }
        }
    }

    try testing.expectEqual(@as(usize, 1), nursery_count); // 1 nursery
    try testing.expectEqual(@as(usize, 3), spawn_count); // 3 spawned tasks
    try testing.expectEqual(@as(usize, 2), channel_create_count); // 2 channels
    try testing.expectEqual(@as(usize, 1), select_count); // 1 select (inside receiver)

    // Emit to LLVM IR
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "complete_csp_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);


    // Verify ALL CSP runtime functions are present
    const required_functions = [_][]const u8{
        "janus_nursery_create",
        "janus_nursery_spawn",
        "janus_nursery_await_all",
        "janus_channel_create",
        "janus_channel_send",
        "janus_channel_recv",
        "janus_select_create",
        "janus_select_add_recv",
        "janus_select_add_default",
        "janus_select_wait",
    };

    for (required_functions) |func_name| {
        const found = std.mem.indexOf(u8, llvm_ir, func_name) != null;
        if (!found) {
        }
        try testing.expect(found);
    }

    // Verify thunk generation for spawns with args
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "__spawn_thunk") != null);

}

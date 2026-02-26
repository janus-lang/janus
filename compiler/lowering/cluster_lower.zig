// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! :cluster Lowering — Actor/Grain Desugaring to Core IR

const std = @import("std");
const astdb = @import("../libjanus/astdb/granite_snapshot.zig");
const actors = @import("../../runtime/actors/actor_runtime.zig");

// Stub handle used for lowering debug output
fn ensureActorRuntimeStub() void {}

pub fn lowerClusterDecl(snapshot: *astdb.Snapshot, node_id: astdb.NodeId) !void {
    const node = snapshot.nodes.get()[@intFromEnum(node_id)];
    switch (node.kind) {
        .actor_decl => {
            // Lower actor_decl to actor_runtime.spawn (stub)
            const actor_name = snapshot.getNodeString(node.first_child());
            std.debug.print("Lowering actor {s} (stub)\n", .{actor_name});
            ensureActorRuntimeStub();
        },
        .grain_decl => {
            // Lower to GrainActor.init + persist
        },
        .receive_stmt => {
            // Lower to actors.receive().match(patterns)
        },
        else => {},
    }
}

test "Cluster lowering" {
    // Test lowering actor_decl → spawn call
}

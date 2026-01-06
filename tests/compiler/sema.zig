// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const libjanus = @import("../../../compiler/libjanus/api.zig");
const astdb = @import("../../../compiler/astdb/core.zig");
const Diag = @import("../../../compiler/libjanus/diag.zig");

test "sema: runSema pipeline" {
    const gpa = std.testing.allocator;
    var ctx = Diag.DiagContext.init(gpa);
    defer ctx.deinit();

    var db = astdb.AstDb.init(gpa);
    defer db.deinit();

    try libjanus.runSema(gpa, &db, &ctx);
}

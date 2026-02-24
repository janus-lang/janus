// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Lowering-level tests for trait/impl semantic registration + static dispatch (SPEC-025 Phase B)
// Validates: metadata collection, namespaced graph emission, completeness checks

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;

test "TRAIT-L01: trait registration with 2 method sigs" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\trait Serializable {
        \\    func serialize(self) -> string
        \\    func deserialize(data: string) -> bool do
        \\        return true
        \\    end
        \\}
        \\func main() -> i32 do
        \\    return 0
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var meta = try lower.collectTraitImplMetadata(&snapshot.core_snapshot, allocator, unit_id);
    defer meta.deinit();

    // Trait registered
    const trait_def = meta.traits.get("Serializable") orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(@as(usize, 2), trait_def.methods.items.len);

    // First method: serialize (bodyless signature, no default)
    try testing.expectEqualStrings("serialize", trait_def.methods.items[0].name);
    try testing.expect(!trait_def.methods.items[0].has_default);

    // Second method: deserialize (has default body)
    try testing.expectEqualStrings("deserialize", trait_def.methods.items[1].name);
    try testing.expect(trait_def.methods.items[1].has_default);
}

test "TRAIT-L02: complete trait impl emits namespaced graph" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\trait Printable {
        \\    func to_string(self) -> string
        \\}
        \\impl Printable for Point {
        \\    func to_string(self) -> string do
        \\        return "point"
        \\    end
        \\}
        \\func main() -> i32 do
        \\    return 0
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Should have at least 2 graphs: main + Point_Printable_to_string
    try testing.expect(ir_graphs.items.len >= 2);

    // Find the qualified-name graph
    var found = false;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Point_Printable_to_string")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "TRAIT-L03: standalone impl emits Type_method graph" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\impl Point {
        \\    func distance(self) -> f64 do
        \\        return 0
        \\    end
        \\}
        \\func main() -> i32 do
        \\    return 0
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Find Point_distance graph (no trait prefix)
    var found = false;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Point_distance")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "TRAIT-L04: missing required method -> MissingTraitImpl" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\trait Printable {
        \\    func to_string(self) -> string
        \\    func format(self) -> string
        \\}
        \\impl Printable for Point {
        \\    func to_string(self) -> string do
        \\        return "point"
        \\    end
        \\}
        \\func main() -> i32 do
        \\    return 0
        \\end
    ;
    // "format" is required (no default) but not provided in impl

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit_id: astdb.UnitId = @enumFromInt(0);

    const result = lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    try testing.expectError(error.MissingTraitImpl, result);
}

test "TRAIT-L05: duplicate impl Trait for Type -> DuplicateTraitImpl" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\trait Printable {
        \\    func to_string(self) -> string
        \\}
        \\impl Printable for Point {
        \\    func to_string(self) -> string do
        \\        return "point"
        \\    end
        \\}
        \\impl Printable for Point {
        \\    func to_string(self) -> string do
        \\        return "point2"
        \\    end
        \\}
        \\func main() -> i32 do
        \\    return 0
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit_id: astdb.UnitId = @enumFromInt(0);

    const result = lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    try testing.expectError(error.DuplicateTraitImpl, result);
}

test "TRAIT-L06: trait with default impl + override" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\trait Printable {
        \\    func to_string(self) -> string
        \\    func debug(self) -> string do
        \\        return "default"
        \\    end
        \\}
        \\impl Printable for Point {
        \\    func to_string(self) -> string do
        \\        return "point"
        \\    end
        \\    func debug(self) -> string do
        \\        return "point_debug"
        \\    end
        \\}
        \\func main() -> i32 do
        \\    return 0
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Both methods should be emitted: required + override of default
    var found_to_string = false;
    var found_debug = false;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Point_Printable_to_string")) found_to_string = true;
        if (std.mem.eql(u8, g.function_name, "Point_Printable_debug")) found_debug = true;
    }
    try testing.expect(found_to_string);
    try testing.expect(found_debug);
}

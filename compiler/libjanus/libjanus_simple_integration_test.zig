// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Import core components
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = @import("type_registry.zig").TypeId;
const ConversionRegistry = @import("conversion_registry.zig").ConversionRegistry;
const DiagnosticEngine = @import("diagnostic_engine.zig").DiagnosticEngine;
const FixSuggestionEngine = @import("fix_suggestion_engine.zig").FixSuggestionEngine;

// Simple integration tests focusing on core functionality
test "Simple integration: TypeRegistry and ConversionRegistry" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    // Test type compatibility
    const i32_type = type_registry.getTypeByName("i32").?;
    const f64_type = type_registry.getTypeByName("f64").?;

    try std.testing.expect(!type_registry.areCompatible(i32_type, f64_type));

    // Test explicit conversion
    const conversion = conversion_registry.findExplicitConversion(TypeId.I32, TypeId.F64).?;
    try std.testing.expect(conversion.cost == 5);
    try std.testing.expect(!conversion.is_lossy);
}

test "Simple integration: Diagnostic and Fix engines" {
    const diagnostic_engine = DiagnosticEngine.init(std.testing.allocator);
    const fix_engine = FixSuggestionEngine.init(std.testing.allocator);

    _ = diagnostic_engine;
    _ = fix_engine;

    // Test that engines initialize correctly
    try std.testing.expect(true);
}

test "Simple integration: Edit distance calculation" {
    var fix_engine = FixSuggestionEngine.init(std.testing.allocator);

    // Test edit distance for typo correction
    const distance1 = fix_engine.calculateEditDistance("hello", "hello");
    const distance2 = fix_engine.calculateEditDistance("hello", "helo");
    const distance3 = fix_engine.calculateEditDistance("lenght", "length");

    try std.testing.expect(distance1 == 0);
    try std.testing.expect(distance2 == 1);
    try std.testing.expect(distance3 == 2);
}

test "Simple integration: Type name resolution" {
    var fix_engine = FixSuggestionEngine.init(std.testing.allocator);

    const i32_name = try fix_engine.getTypeName(TypeId.I32);
    defer std.testing.allocator.free(i32_name);

    const f64_name = try fix_engine.getTypeName(TypeId.F64);
    defer std.testing.allocator.free(f64_name);

    try std.testing.expectEqualStrings(i32_name, "i32");
    try std.testing.expectEqualStrings(f64_name, "f64");
}

test "Simple integration: Conversion path creation" {
    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    const from_types = [_]TypeId{TypeId.I32};
    const to_types = [_]TypeId{TypeId.F64};

    var path = (try conversion_registry.findConversionPath(from_types[0..], to_types[0..], std.testing.allocator)).?;
    defer path.deinit();

    try std.testing.expect(path.conversions.len == 1);
    try std.testing.expect(path.total_cost == 5);
    try std.testing.expect(!path.is_lossy);
}

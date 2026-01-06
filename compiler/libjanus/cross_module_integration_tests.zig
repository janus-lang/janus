// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;
const ModuleDispatcher = @import("module_dispatch.zig").ModuleDispatcher;
const ModuleInfo = @import("module_dispatch.zig").ModuleInfo;

test "Cross-module dispatch integration" {
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var module_dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer module_dispatcher.deinit();

    // Register basic types
    const int_type = try type_registry.registerType("int", .primitive, &.{});
    _ = try type_registry.registerType("string", .primitive, &.{});

    // Register modules
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const math_module = try module_dispatcher.registerModule("math", "/lib/math", version, &.{});
    const app_module = try module_dispatcher.registerModule("app", "/src/app", version, &.{});

    // Create a test implementation
    const impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "add",
            .module = "math",
            .id = 1,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{ int_type, int_type }),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(impl.param_type_ids);

    // Export from math module
    const implementations = [_]*const SignatureAnalyzer.Implementation{&impl};
    try module_dispatcher.exportSignature(math_module, "add", &implementations, .public, null);

    // Import into app module
    try module_dispatcher.importSignature(app_module, math_module, "add", null, .unqualified, .merge);

    // Test cross-module dispatch
    const args = [_]TypeId{ int_type, int_type };
    const result = try module_dispatcher.resolveCrossModuleDispatch(app_module, "add", &args, null);

    try testing.expect(result != null);
    try testing.expectEqualStrings("math", result.?.function_id.module);
    try testing.expectEqualStrings("add", result.?.function_id.name);
}

test "Qualified call disambiguation" {
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var module_dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer module_dispatcher.deinit();

    // Register basic types
    const string_type = try type_registry.registerType("string", .primitive, &.{});

    // Register modules
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const json_module = try module_dispatcher.registerModule("json", "/lib/json", version, &.{});
    const xml_module = try module_dispatcher.registerModule("xml", "/lib/xml", version, &.{});

    // Create implementations for both modules
    const json_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "parse",
            .module = "json",
            .id = 1,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{string_type}),
        .return_type_id = string_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(json_impl.param_type_ids);

    const xml_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "parse",
            .module = "xml",
            .id = 2,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{string_type}),
        .return_type_id = string_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(xml_impl.param_type_ids);

    // Export from both modules
    const json_impls = [_]*const SignatureAnalyzer.Implementation{&json_impl};
    const xml_impls = [_]*const SignatureAnalyzer.Implementation{&xml_impl};

    try module_dispatcher.exportSignature(json_module, "parse", &json_impls, .public, null);
    try module_dispatcher.exportSignature(xml_module, "parse", &xml_impls, .public, null);

    // Test qualified calls
    const json_qualified = try module_dispatcher.createQualifiedCall("json", "parse", false);
    const xml_qualified = try module_dispatcher.createQualifiedCall("xml", "parse", false);

    const args = [_]TypeId{string_type};

    // Test JSON qualified call
    const json_result = try module_dispatcher.resolveCrossModuleDispatch(0, "parse", &args, json_qualified);
    try testing.expect(json_result != null);
    try testing.expectEqualStrings("json", json_result.?.function_id.module);

    // Test XML qualified call
    const xml_result = try module_dispatcher.resolveCrossModuleDispatch(0, "parse", &args, xml_qualified);
    try testing.expect(xml_result != null);
    try testing.expectEqualStrings("xml", xml_result.?.function_id.module);
}
test "Module loading and dispatch table updates" {
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allr, &type_registry);

    var module_dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer module_dispatcher.deinit();

    // Register basic types
    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Register modules
    const version_1_0 = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const version_1_1 = ModuleInfo.Version{ .major = 1, .minor = 1, .patch = 0 };

    const core_module = try module_dispatcher.registerModule("core", "/lib/core", version_1_0, &.{});
    const plugin_module = try module_dispatcher.registerModule("plugin", "/plugins/plugin", version_1_0, &.{});

    // Create initial implementation
    const core_process = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "process",
            .module = "core",
            .id = 1,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 50,
    };
    defer allocator.free(core_process.param_type_ids);

    const core_impls = [_]*const SignatureAnalyzer.Implementation{&core_process};
    try module_dispatcher.exportSignature(core_module, "process", &core_impls, .public, null);

    // Import into plugin
    try module_dispatcher.importSignature(plugin_module, core_module, "process", null, .unqualified, .merge);

    // Load core module
    try module_dispatcher.loadModule(core_module);

    // Test initial dispatch
    const args = [_]TypeId{int_type};
    const initial_result = try module_dispatcher.resolveCrossModuleDispatch(plugin_module, "process", &args, null);
    try testing.expect(initial_result != null);
    try testing.expectEqualStrings("core", initial_result.?.function_id.module);

    // Simulate module update - register new version with additional implementation
    const core_v2_module = try module_dispatcher.registerModule("core_v2", "/lib/core", version_1_1, &.{});

    const enhanced_process = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "process",
            .module = "core_v2",
            .id = 2,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100, // Higher specificity
    };
    defer allocator.free(enhanced_process.param_type_ids);

    const enhanced_impls = [_]*const SignatureAnalyzer.Implementation{&enhanced_process};
    try module_dispatcher.exportSignature(core_v2_module, "process", &enhanced_impls, .public, null);

    // Import the new version
    try module_dispatcher.importSignature(plugin_module, core_v2_module, "process", null, .unqualified, .merge);

    // Load the new module
    try module_dispatcher.loadModule(core_v2_module);

    // Test that dispatch now selects the more specific implementation
    const updated_result = try module_dispatcher.resolveCrossModuleDispatch(plugin_module, "process", &args, null);
    try testing.expect(updated_result != null);
    try testing.expectEqualStrings("core_v2", updated_result.?.function_id.module);
    try testing.expectEqual(@as(u32, 2), updated_result.?.function_id.id);
}

test "Hot reloading with dispatch consistency" {
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var module_dispatcher = ModuleDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer module_dispatcher.deinit();

    // Register basic types
    const string_type = try type_registry.registerType("string", .primitive, &.{});

    // Register a module
    const version = ModuleInfo.Version{ .major = 1, .minor = 0, .patch = 0 };
    const dynamic_module = try module_dispatcher.registerModule("dynamic", "/lib/dynamic", version, &.{});

    // Create initial implementation
    const initial_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "transform",
            .module = "dynamic",
            .id = 1,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{string_type}),
        .return_type_id = string_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(initial_impl.param_type_ids);

    const initial_export = ExportedSignature{
        .signature_name = "transform",
        .module_id = dynamic_module,
        .implementations = &[_]*const SignatureAnalyzer.Implementation{&initial_impl},
        .visibility = .public,
        .export_name = null,
    };

    // Export and load initial version
    try module_dispatcher.exportSignature(dynamic_module, "transform", &[_]*const SignatureAnalyzer.Implementation{&initial_impl}, .public, null);
    try module_dispatcher.loadModule(dynamic_module);

    // Test initial dispatch
    const args = [_]TypeId{string_type};
    const initial_result = try module_dispatcher.resolveCrossModuleDispatch(dynamic_module, "transform", &args, null);
    try testing.expect(initial_result != null);
    try testing.expectEqual(@as(u32, 1), initial_result.?.function_id.id);

    // Create updated implementation for hot reload
    const updated_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "transform",
            .module = "dynamic",
            .id = 2,
        },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{string_type}),
        .return_type_id = string_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 150, // Higher specificity
    };
    defer allocator.free(updated_impl.param_type_ids);

    const updated_export = ExportedSignature{
        .signature_name = "transform",
        .module_id = dynamic_module,
        .implementations = &[_]*const SignatureAnalyzer.Implementation{&updated_impl},
        .visibility = .public,
        .export_name = null,
    };

    // Hot reload with updated implementation
    try module_dispatcher.hotReloadModule(dynamic_module, &[_]ExportedSignature{updated_export});

    // Test that dispatch now uses the updated implementation
    const updated_result = try module_dispatcher.resolveCrossModuleDispatch(dynamic_module, "transform", &args, null);
    try testing.expect(updated_result != null);
    try testing.expectEqual(@as(u32, 2), updated_result.?.function_id.id);
    try testing.expectEqual(@as(u32, 150), updated_result.?.specificity_rank);

    // Check dispatch consistency
    var consistency_report = try module_dispatcher.checkDispatchConsistency();
    defer consistency_report.deinit();

    // Should be consistent after hot reload
    try testing.expect(!consistency_report.hasInconsistencies());
}

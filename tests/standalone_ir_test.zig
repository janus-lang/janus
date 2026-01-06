// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Copy the minimal IR structures here for testing
const ValueType = enum {
    Void,
    String,
    Function,
};

const Value = struct {
    id: u32,
    type: ValueType,
    name: []const u8,
};

const InstructionKind = enum {
    FunctionDef,
    StringConst,
    Call,
    Return,
};

const Instruction = struct {
    kind: InstructionKind,
    result: ?Value,
    operands: []Value,
    metadata: []const u8,
};

const Module = struct {
    instructions: std.ArrayList(Instruction),
    values: std.ArrayList(Value),
    metadata_strings: std.ArrayList([]const u8),
    next_value_id: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Module {
        return Module{
            .instructions = std.ArrayList(Instruction){},
            .values = std.ArrayList(Value){},
            .metadata_strings = std.ArrayList([]const u8){},
            .next_value_id = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Module) void {
        for (self.instructions.items) |instruction| {
            self.allocator.free(instruction.operands);
        }
        for (self.metadata_strings.items) |metadata| {
            self.allocator.free(metadata);
        }
        self.instructions.deinit();
        self.values.deinit();
        self.metadata_strings.deinit();
    }

    pub fn createValue(self: *Module, value_type: ValueType, name: []const u8) !Value {
        const value = Value{
            .id = self.next_value_id,
            .type = value_type,
            .name = name,
        };
        self.next_value_id += 1;
        try self.values.append(value);
        return value;
    }

    pub fn addInstruction(self: *Module, kind: InstructionKind, result: ?Value, operands: []const Value, metadata: []const u8) !void {
        const owned_operands = try self.allocator.dupe(Value, operands);

        // Always copy metadata to ensure we own it
        const owned_metadata = try self.allocator.dupe(u8, metadata);
        try self.metadata_strings.append(owned_metadata);

        const instruction = Instruction{
            .kind = kind,
            .result = result,
            .operands = owned_operands,
            .metadata = owned_metadata,
        };

        try self.instructions.append(instruction);
    }
};

test "ir: basic module functionality" {
    const allocator = testing.allocator;

    var module = Module.init(allocator);
    defer module.deinit();

    // Test value creation
    const value = try module.createValue(.String, "test");
    try testing.expect(value.id == 0);
    try testing.expect(value.type == .String);

    // Test instruction creation
    try module.addInstruction(.StringConst, value, &[_]Value{}, "test metadata");
    try testing.expect(module.instructions.items.len == 1);

    const instruction = module.instructions.items[0];
    try testing.expect(instruction.kind == .StringConst);
    try testing.expect(instruction.result != null);
    try testing.expect(instruction.result.?.id == value.id);
}

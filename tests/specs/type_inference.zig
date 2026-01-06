// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const libjanus = @import("libjanus");
const semantic = @import("semantic");

const astdb = libjanus.astdb;
const TypeSystem = semantic.TypeSystem;
const SymbolTable = semantic.SymbolTable;
const TypeInference = semantic.TypeInference;

// Helper to setup test environment
const TestEnv = struct {
    allocator: std.mem.Allocator,
    astdb: *astdb.ASTDBSystem,
    symbol_table: *SymbolTable,
    type_system: *TypeSystem,
    inference: *TypeInference,
    unit_id: astdb.UnitId,

    fn init(allocator: std.mem.Allocator, source: []const u8) !TestEnv {
        // 1. Initialize ASTDB on heap
        const db = try allocator.create(astdb.ASTDBSystem);
        db.* = try astdb.ASTDBSystem.init(allocator, false);
        
        // 2. Parse source into ASTDB
        var parser = libjanus.parser.Parser.init(allocator);
        defer parser.deinit();
        
        var snapshot = try parser.parseIntoAstDB(db, "test.jan", source);
        defer snapshot.deinit();
        
        const unit_id = db.getUnitByPath("test.jan").?.id;

        // 3. Initialize Semantic components
        const sym_tbl = try SymbolTable.init(allocator);
        
        const type_sys = try allocator.create(TypeSystem);
        type_sys.* = try TypeSystem.init(allocator);
        
        // 4. Initialize TypeInference
        const inference = try TypeInference.init(allocator, type_sys, sym_tbl, db, unit_id);

        return TestEnv{
            .allocator = allocator,
            .astdb = db,
            .symbol_table = sym_tbl,
            .type_system = type_sys,
            .inference = inference,
            .unit_id = unit_id,
        };
    }

    fn deinit(self: *TestEnv) void {
        self.inference.deinit();
        self.type_system.deinit();
        self.allocator.destroy(self.type_system);
        self.symbol_table.deinit();
        self.astdb.deinit();
        self.allocator.destroy(self.astdb);
    }
};

test "infer let binding type from integer literal" {
    const allocator = std.testing.allocator;
    const source = "let x = 42";
    
    var env = try TestEnv.init(allocator, source);
    defer env.deinit();

    // Find the let statement node
    // In "let x = 42", the root is likely a script/module containing the let stmt
    // We need to traverse to find the let stmt
    // const unit = env.astdb.getUnit(env.unit_id);
    // Assuming first child of root is the let stmt
    // const root = unit.nodes[0]; // Root node
    // TODO: Navigate to let stmt. For now, let's assume we can just run inference on the whole unit/root
    
    // Run inference on the root node
    try env.inference.generateConstraints(@as(astdb.NodeId, @enumFromInt(0)));
    try env.inference.solveConstraints();
    try env.inference.assignResolvedTypes();

    // Verify 'x' has type i32
    // We need to find the node ID for 'x' or check the symbol table
    // For now, let's check if we can retrieve the type of the variable declaration node
    // ...
}

test "infer let binding type from float literal" {
    const allocator = std.testing.allocator;
    const source = "let x = 3.14";
    var env = try TestEnv.init(allocator, source);
    defer env.deinit();
    
    try env.inference.generateConstraints(@as(astdb.NodeId, @enumFromInt(0)));
    try env.inference.solveConstraints();
    // Verify type is f64
}

test "infer let binding type from boolean literal" {
    const allocator = std.testing.allocator;
    const source = "let x = true";
    var env = try TestEnv.init(allocator, source);
    defer env.deinit();
    
    try env.inference.generateConstraints(@as(astdb.NodeId, @enumFromInt(0)));
    try env.inference.solveConstraints();
    // Verify type is bool
}

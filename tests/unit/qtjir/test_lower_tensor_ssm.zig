// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration tests for Tensor and SSM operation lowering
// Doctrine: Arrange-Act-Assert with explicit validation of tenancy and OpCodes

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");

const lower = qtjir.lower;
const graph = qtjir.graph;

// ============================================================================
// Tensor Operation Tests - NPU_Tensor Tenancy
// ============================================================================

test "Lower: tensor.matmul creates Tensor_Matmul with NPU tenancy" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    let a = tensor.matmul([1, 2], [3, 4])
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "tensor_matmul.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find Tensor_Matmul node
    var found_matmul = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Tensor_Matmul) {
            found_matmul = true;

            // Validate tenancy
            try testing.expectEqual(graph.Tenancy.NPU_Tensor, node.tenancy);

            // Validate input count (2 matrices)
            try testing.expectEqual(@as(usize, 2), node.inputs.items.len);

            break;
        }
    }

    try testing.expect(found_matmul);
}

test "Lower: tensor.relu creates Tensor_Relu with NPU tenancy" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    let x = tensor.relu([1, -2, 3])
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "tensor_relu.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find Tensor_Relu node
    var found_relu = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Tensor_Relu) {
            found_relu = true;

            // Validate tenancy
            try testing.expectEqual(graph.Tenancy.NPU_Tensor, node.tenancy);

            // Validate input count (1 tensor)
            try testing.expectEqual(@as(usize, 1), node.inputs.items.len);

            break;
        }
    }

    try testing.expect(found_relu);
}

test "Lower: tensor.softmax creates Tensor_Softmax with NPU tenancy" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    let probs = tensor.softmax([1, 2, 3])
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "tensor_softmax.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find Tensor_Softmax node
    var found_softmax = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Tensor_Softmax) {
            found_softmax = true;

            // Validate tenancy
            try testing.expectEqual(graph.Tenancy.NPU_Tensor, node.tenancy);

            // Validate input count (1 tensor)
            try testing.expectEqual(@as(usize, 1), node.inputs.items.len);

            break;
        }
    }

    try testing.expect(found_softmax);
}

// ============================================================================
// Quantum Operation Tests - QPU_Quantum Tenancy
// ============================================================================

test "Lower: quantum.hadamard creates Quantum_Gate with QPU tenancy" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    quantum.hadamard(0)
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "quantum_hadamard.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find Quantum_Gate node
    var found_hadamard = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Quantum_Gate) {
            found_hadamard = true;

            // Validate tenancy
            try testing.expectEqual(graph.Tenancy.QPU_Quantum, node.tenancy);

            // Validate quantum metadata
            const metadata = node.quantum_metadata orelse {
                try testing.expect(false); // Should have metadata
                return;
            };

            try testing.expectEqual(graph.GateType.Hadamard, metadata.gate_type);
            try testing.expectEqual(@as(usize, 1), metadata.qubits.len);
            try testing.expectEqual(@as(usize, 0), metadata.qubits[0]);

            break;
        }
    }

    try testing.expect(found_hadamard);
}

test "Lower: quantum.cnot creates Quantum_Gate with 2 qubits" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    quantum.cnot(0, 1)
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "quantum_cnot.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find Quantum_Gate node
    var found_cnot = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Quantum_Gate) {
            const metadata = node.quantum_metadata orelse continue;

            if (metadata.gate_type == .CNOT) {
                found_cnot = true;

                // Validate tenancy
                try testing.expectEqual(graph.Tenancy.QPU_Quantum, node.tenancy);

                // Validate qubit count (control + target)
                try testing.expectEqual(@as(usize, 2), metadata.qubits.len);
                try testing.expectEqual(@as(usize, 0), metadata.qubits[0]); // control
                try testing.expectEqual(@as(usize, 1), metadata.qubits[1]); // target

                break;
            }
        }
    }

    try testing.expect(found_cnot);
}

test "Lower: quantum.measure creates Quantum_Measure node" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    let result = quantum.measure(0)
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "quantum_measure.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find Quantum_Measure node
    var found_measure = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Quantum_Measure) {
            found_measure = true;

            // Validate tenancy
            try testing.expectEqual(graph.Tenancy.QPU_Quantum, node.tenancy);

            // Validate quantum metadata
            const metadata = node.quantum_metadata orelse {
                try testing.expect(false);
                return;
            };

            try testing.expectEqual(@as(usize, 1), metadata.qubits.len);
            try testing.expectEqual(@as(usize, 0), metadata.qubits[0]);

            break;
        }
    }

    try testing.expect(found_measure);
}

// ============================================================================
// SSM Operation Tests - NPU_Tensor Tenancy (Mamba-3 Inspired)
// ============================================================================

test "Lower: ssm.scan creates SSM_Scan with NPU tenancy" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    let state = ssm.scan([1], [2], [3])
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "ssm_scan.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find SSM_Scan node
    var found_scan = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .SSM_Scan) {
            found_scan = true;

            // Validate tenancy (SSM operations use NPU_Tensor)
            try testing.expectEqual(graph.Tenancy.NPU_Tensor, node.tenancy);

            // Validate input count (A, B, C matrices)
            try testing.expectEqual(@as(usize, 3), node.inputs.items.len);

            break;
        }
    }

    try testing.expect(found_scan);
}

test "Lower: ssm.selective_scan creates SSM_SelectiveScan with 4 inputs" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    let state = ssm.selective_scan([1], [2], [3], [4])
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "ssm_selective_scan.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find SSM_SelectiveScan node
    var found_selective_scan = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .SSM_SelectiveScan) {
            found_selective_scan = true;

            // Validate tenancy
            try testing.expectEqual(graph.Tenancy.NPU_Tensor, node.tenancy);

            // Validate input count (A, B, C, delta)
            try testing.expectEqual(@as(usize, 4), node.inputs.items.len);

            break;
        }
    }

    try testing.expect(found_selective_scan);
}

// ============================================================================
// Cross-Tenancy Validation Tests
// ============================================================================

test "Lower: Mixed tensor and quantum operations maintain correct tenancy" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    let x = tensor.relu([1, 2])
        \\    quantum.hadamard(0)
        \\    let y = tensor.softmax([3, 4])
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "mixed_tenancy.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Validate that each operation has correct tenancy
    var tensor_count: usize = 0;
    var quantum_count: usize = 0;

    for (ir_graph.nodes.items) |node| {
        switch (node.op) {
            .Tensor_Relu, .Tensor_Softmax => {
                try testing.expectEqual(graph.Tenancy.NPU_Tensor, node.tenancy);
                tensor_count += 1;
            },
            .Quantum_Gate => {
                try testing.expectEqual(graph.Tenancy.QPU_Quantum, node.tenancy);
                quantum_count += 1;
            },
            else => {},
        }
    }

    // Verify we found the expected operations
    try testing.expectEqual(@as(usize, 2), tensor_count);
    try testing.expectEqual(@as(usize, 1), quantum_count);
}

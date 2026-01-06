<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Type Inference Guide for Janus

## What is Type Inference?

Type inference is the compiler's ability to **automatically deduce the types** of expressions without requiring explicit type annotations. Instead of writing:

```janus
let x: i32 = 42;
```

You can write:

```janus
let x = 42;  // Compiler infers x is i32
```

The compiler analyzes the code and figures out that `42` is an integer literal, therefore `x` must be of type `i32`.

## Why Type Inference Matters

1. **Less Boilerplate**: Write cleaner code without repetitive type annotations
2. **Maintain Type Safety**: Still get compile-time type checking
3. **Better Refactoring**: Change types in one place, inference propagates automatically
4. **Improved Readability**: Focus on logic, not type bureaucracy

## How Type Inference Works in Janus

Janus uses **constraint-based type inference** with **unification**. This is a three-phase process:

### Phase 1: Constraint Generation

The compiler walks through your code and generates **type constraints** - relationships between types that must hold true.

```janus
let x = 42;
let y = x + 10;
```

Constraints generated:
1. `x` has type of literal `42` → `i32`
2. `x + 10` requires both operands to be numeric
3. Result of `x + 10` must be assignable to `y`
4. Therefore `y` must be `i32`

### Phase 2: Constraint Solving (Unification)

The compiler solves these constraints using **unification** - finding a consistent assignment of types that satisfies all constraints.

Think of it like solving a system of equations:
- If `x = 42`, then `x` is `i32`
- If `y = x + 10`, and `x` is `i32`, then `y` is `i32`

### Phase 3: Type Assignment

Once all constraints are solved, the compiler assigns the inferred types back to the AST nodes.

## Types of Constraints in Janus

### 1. Equality Constraints

Two types must be exactly the same:

```janus
let x = 42;
let y = x;  // type(y) == type(x)
```

### 2. Subtype Constraints

One type must be a subtype of another:

```janus
fn process(value: Number) { ... }
process(42);  // i32 <: Number
```

### 3. Function Call Constraints

Function arguments must match parameter types:

```janus
fn add(a: i32, b: i32) -> i32 { a + b }
let result = add(10, 20);  // result is i32
```

### 4. Operator Constraints

Operators impose constraints on their operands:

```janus
let x = 10 + 20;  // Both operands must be numeric, result is numeric
let b = x > 5;    // Comparison returns bool
```

## Inference Variables

When the compiler doesn't immediately know a type, it creates an **inference variable** (like `?T0`, `?T1`):

```janus
let x = getValue();  // x has type ?T0 initially
```

As the compiler gathers more information:

```janus
let x = getValue();  // ?T0
let y: i32 = x;      // ?T0 must equal i32
// Now ?T0 is resolved to i32
```

## Advanced Inference Scenarios

### Bidirectional Type Flow

Types can flow both **forward** and **backward**:

```janus
// Forward: from expression to variable
let x = 42;  // 42 → i32 → x

// Backward: from context to expression
let y: f64 = getValue();  // f64 → getValue() must return f64
```

### Generic Function Inference

```janus
fn identity<T>(value: T) -> T { value }

let x = identity(42);  // T is inferred as i32
```

The compiler:
1. Sees `identity(42)` call
2. Creates inference variable `?T0` for generic `T`
3. Unifies `?T0` with `i32` (type of `42`)
4. Substitutes `T = i32` in return type
5. Result: `x` is `i32`

### Array and Collection Inference

```janus
let numbers = [1, 2, 3, 4, 5];  // Inferred as [i32; 5]
```

Process:
1. Each element `1, 2, 3, 4, 5` is `i32`
2. All elements must have same type
3. Array has 5 elements
4. Result: `[i32; 5]`

### Struct Field Inference

```janus
struct Point {
    x: i32,
    y: i32,
}

let p = Point { x: 10, y: 20 };  // p is Point
let x_val = p.x;                  // x_val is i32
```

## Expanding Type Inference in Janus

Here's how to add new inference capabilities:

### 1. Add New Constraint Types

In `type_inference.zig`, extend `TypeConstraint`:

```zig
pub const TypeConstraint = union(enum) {
    equality: struct { left: TypeId, right: TypeId },
    subtype: struct { sub: TypeId, super: TypeId },
    function_call: FunctionCallConstraint,
    array_access: ArrayAccessConstraint,
    field_access: FieldAccessConstraint,
    numeric: TypeId,
    comparable: TypeId,
    iterable: IterableConstraint,
    
    // NEW: Add your constraint type here
    pattern_match: PatternMatchConstraint,
};
```

### 2. Generate Constraints for New Constructs

Add inference methods for new language features:

```zig
fn inferPatternMatch(self: *TypeInference, node_id: NodeId) !void {
    const scrutinee = accessors.getMatchScrutinee(self.astdb, self.unit_id, node_id);
    const patterns = accessors.getMatchPatterns(self.astdb, self.unit_id, node_id);
    
    // Generate constraints for pattern matching
    const scrutinee_type = self.getNodeType(scrutinee);
    
    for (patterns) |pattern| {
        const pattern_type = try self.createInferenceVar();
        try self.addConstraint(.{
            .pattern_match = .{
                .scrutinee = scrutinee_type,
                .pattern = pattern_type,
            }
        });
    }
}
```

### 3. Implement Constraint Solving

Add solver for your new constraint:

```zig
fn solvePatternMatch(self: *TypeInference, constraint: PatternMatchConstraint) !bool {
    const scrutinee_info = self.type_system.getTypeInfo(constraint.scrutinee);
    const pattern_info = self.type_system.getTypeInfo(constraint.pattern);
    
    // Check if pattern can match scrutinee type
    if (!self.type_system.isPatternCompatible(scrutinee_info, pattern_info)) {
        return error.IncompatiblePattern;
    }
    
    // Unify types if needed
    try self.unifyTypes(constraint.scrutinee, constraint.pattern);
    return true;
}
```

### 4. Update Constraint Solver Loop

In `solveConstraints()`, add handling for new constraint:

```zig
pub fn solveConstraints(self: *TypeInference) !void {
    var changed = true;
    while (changed) {
        changed = false;
        for (self.constraints.items) |constraint| {
            const solved = switch (constraint) {
                .equality => |eq| try self.solveEquality(eq),
                .subtype => |sub| try self.solveSubtype(sub),
                .function_call => |call| try self.solveFunctionCall(call),
                // ... other constraints ...
                .pattern_match => |pm| try self.solvePatternMatch(pm),
            };
            if (solved) changed = true;
        }
    }
}
```

## Common Inference Patterns to Implement

### 1. Literal Type Inference

```zig
fn inferLiteralInt(self: *TypeInference, node_id: NodeId) !void {
    try self.setNodeType(node_id, self.type_system.getPrimitiveType(.i32));
}

fn inferLiteralFloat(self: *TypeInference, node_id: NodeId) !void {
    try self.setNodeType(node_id, self.type_system.getPrimitiveType(.f64));
}
```

### 2. Binary Operation Inference

```zig
fn inferBinaryOp(self: *TypeInference, node_id: NodeId) !void {
    const left = accessors.getBinaryOpLeft(self.astdb, self.unit_id, node_id);
    const right = accessors.getBinaryOpRight(self.astdb, self.unit_id, node_id);
    
    try self.generateConstraints(left);
    try self.generateConstraints(right);
    
    const left_type = self.getNodeType(left);
    const right_type = self.getNodeType(right);
    
    // Both operands must be numeric
    try self.addConstraint(.{ .numeric = left_type });
    try self.addConstraint(.{ .numeric = right_type });
    
    // Result type is promoted type of operands
    const result_type = try self.promoteArithmeticTypes(left_type, right_type);
    try self.setNodeType(node_id, result_type);
}
```

### 3. Function Call Inference

```zig
fn inferFunctionCall(self: *TypeInference, node_id: NodeId) !void {
    const func_expr = accessors.getFunctionCallExpression(self.astdb, self.unit_id, node_id);
    const args = accessors.getFunctionCallArguments(self.astdb, self.unit_id, node_id);
    
    try self.generateConstraints(func_expr);
    const func_type = self.getNodeType(func_expr);
    
    var arg_types = ArrayList(TypeId).init(self.allocator);
    defer arg_types.deinit();
    
    for (args) |arg| {
        try self.generateConstraints(arg);
        try arg_types.append(self.getNodeType(arg));
    }
    
    const result_type = try self.createInferenceVar();
    const owned_args = try self.allocator.dupe(TypeId, arg_types.items);
    
    try self.addConstraint(.{
        .function_call = .{
            .func = func_type,
            .args = owned_args,
            .result = result_type,
        }
    });
    
    try self.setNodeType(node_id, result_type);
}
```

## Testing Type Inference

Always add tests for new inference capabilities:

```zig
test "infer generic function call" {
    const allocator = std.testing.allocator;
    const source = 
        \\fn identity<T>(x: T) -> T { x }
        \\let result = identity(42);
    ;
    
    var env = try TestEnv.init(allocator, source);
    defer env.deinit();
    
    try env.inference.generateConstraints(@enumFromInt(0));
    try env.inference.solveConstraints();
    try env.inference.assignResolvedTypes();
    
    // Verify result is i32
    const result_type = env.inference.getNodeType(result_node_id);
    try std.testing.expect(result_type.eql(env.type_system.getPrimitiveType(.i32)));
}
```

## Debugging Type Inference

### Enable Debug Output

```zig
pub fn generateConstraints(self: *TypeInference, node_id: NodeId) !void {
    if (builtin.mode == .Debug) {
        std.debug.print("Generating constraints for node {}\n", .{node_id});
    }
    // ... constraint generation ...
}
```

### Print Constraint Graph

```zig
pub fn debugPrintConstraints(self: *TypeInference) void {
    std.debug.print("\n=== Type Constraints ===\n", .{});
    for (self.constraints.items, 0..) |constraint, i| {
        std.debug.print("  [{}] {}\n", .{i, constraint});
    }
    std.debug.print("========================\n\n", .{});
}
```

### Track Inference Variables

```zig
pub fn debugPrintInferenceVars(self: *TypeInference) void {
    std.debug.print("\n=== Inference Variables ===\n", .{});
    var it = self.inference_vars.iterator();
    while (it.next()) |entry| {
        std.debug.print("  ?T{} = {}\n", .{
            @intFromEnum(entry.key_ptr.*),
            entry.value_ptr.*,
        });
    }
    std.debug.print("===========================\n\n", .{});
}
```

## Best Practices

1. **Start Simple**: Begin with basic literal inference, then add operators, then function calls
2. **Test Incrementally**: Add tests for each new inference capability
3. **Handle Errors Gracefully**: Provide clear error messages when inference fails
4. **Avoid Infinite Loops**: Ensure constraint solving terminates (use iteration limit)
5. **Document Constraints**: Comment why each constraint is necessary
6. **Profile Performance**: Type inference should be fast - O(n) for most cases

## Next Steps for Janus Type Inference

1. **Implement Generic Type Inference**: Support for parametric polymorphism
2. **Add Trait Constraints**: Infer types based on trait bounds
3. **Implement Let Polymorphism**: Allow local type variables
4. **Add Recursive Type Inference**: Handle recursive data structures
5. **Implement Effect Inference**: Infer effect types (async, throws, etc.)
6. **Add Refinement Types**: Infer value-dependent types

## Resources

- **Algorithm W**: Classic Hindley-Milner type inference algorithm
- **Bidirectional Type Checking**: Modern approach combining inference and checking
- **Constraint-Based Type Inference**: More flexible than Algorithm W
- **Local Type Inference**: Pierce & Turner's practical approach

## Summary

Type inference in Janus:
1. **Generates constraints** from code structure
2. **Solves constraints** via unification
3. **Assigns types** back to AST nodes

To expand it:
1. Add new constraint types
2. Implement constraint generation for new constructs
3. Add constraint solving logic
4. Test thoroughly

The current implementation provides a solid foundation - you can now build upon it to support more advanced type inference scenarios as Janus evolves!

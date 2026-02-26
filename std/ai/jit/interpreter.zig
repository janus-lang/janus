// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR Interpreter - Minimal execution backend for :script profile
// Purpose: Execute QTJIR graphs directly for immediate usability
// Doctrine: Mechanism over Policy - simple interpreter, native codegen layered later

const std = @import("std");
const compat_fs = @import("compat_fs");
const janus_context = @import("janus_context");

// =============================================================================
// Public Types
// =============================================================================

pub const InterpreterError = error{
    InvalidGraph,
    UnknownBuiltin,
    InvalidArgument,
    ExecutionFailed,
    OutOfMemory,
    CapabilityDenied,
};

pub const InterpreterResult = struct {
    exit_code: i32,
    stdout_buffer: ?[]const u8,

    pub fn success() InterpreterResult {
        return .{ .exit_code = 0, .stdout_buffer = null };
    }

    pub fn withExitCode(code: i32) InterpreterResult {
        return .{ .exit_code = code, .stdout_buffer = null };
    }
};

// =============================================================================
// Interpreter
// =============================================================================

/// A minimal QTJIR graph interpreter for the :script profile
/// Handles: Call (println/print), Return, Constant
/// Defers complex control flow to future native codegen implementations
/// Runtime value representation
pub const RuntimeValue = union(enum) {
    integer: i64,
    float: f64,
    boolean: bool,
    string: []const u8, // Borrowed from graph data usually
    struct_val: *StructValue, // Pointer to heap-allocated struct
    array_val: *ArrayValue, // Pointer to heap-allocated array

    pub fn toInt(self: RuntimeValue) i64 {
        return switch (self) {
            .integer => |i| i,
            .float => |f| @intFromFloat(f),
            .boolean => |b| if (b) 1 else 0,
            .string => std.fmt.parseInt(i64, self.string, 10) catch 0,
            .struct_val, .array_val => 0, // Composite types don't convert to int
        };
    }

    pub fn toString(self: RuntimeValue, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .string => |s| s, // Already a string
            .integer => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}),
            .boolean => |b| if (b) "true" else "false",
            .struct_val => "<struct>",
            .array_val => "<array>",
        };
    }

    /// PROBATIO: Convert to boolean for assert intrinsic
    pub fn toBool(self: RuntimeValue) bool {
        return switch (self) {
            .boolean => |b| b,
            .integer => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.len > 0,
            .struct_val, .array_val => true, // Non-null composite = true
        };
    }
};

/// Heap-allocated struct value (field name -> value)
pub const StructValue = struct {
    fields: std.StringHashMap(RuntimeValue),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StructValue {
        return .{
            .fields = std.StringHashMap(RuntimeValue).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StructValue) void {
        self.fields.deinit();
    }
};

/// Heap-allocated array value (indexed elements)
pub const ArrayValue = struct {
    elements: std.ArrayListUnmanaged(RuntimeValue),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ArrayValue {
        return .{
            .elements = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ArrayValue) void {
        self.elements.deinit(self.allocator);
    }
};

/// Stack frame for function call tracking
/// Saves caller state to enable recursion and proper returns
pub const StackFrame = struct {
    return_pc: usize, // Where to resume in caller
    return_graph_name: []const u8, // Caller's graph name
    return_register: u32, // Where to store result in caller
    saved_results: std.AutoHashMap(u32, RuntimeValue), // Caller's results snapshot
    saved_memory: std.AutoHashMap(u32, RuntimeValue), // Caller's memory snapshot

    pub fn deinit(self: *StackFrame) void {
        self.saved_results.deinit();
        self.saved_memory.deinit();
    }
};

/// A minimal QTJIR graph interpreter for the :script profile
/// Handles: Call (println/print + user functions), Return, Constant, Variables, Arithmetic
/// Supports recursion via call stack with configurable depth limit
pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    verbose: bool,

    // State management
    results: std.AutoHashMap(u32, RuntimeValue), // Node ID -> Result
    memory: std.AutoHashMap(u32, RuntimeValue), // Alloca ID -> Value

    // Function call support
    function_table: std.StringHashMap(*const anyopaque), // Function name -> Graph pointer
    call_stack: std.ArrayListUnmanaged(StackFrame), // Call stack for recursion
    max_call_depth: usize, // Stack overflow protection
    current_graph_name: []const u8, // Currently executing function

    // Capability system (optional for backward compatibility)
    context: ?*const janus_context.Context,

    pub fn init(allocator: std.mem.Allocator) Interpreter {
        return .{
            .allocator = allocator,
            .verbose = false,
            .results = std.AutoHashMap(u32, RuntimeValue).init(allocator),
            .memory = std.AutoHashMap(u32, RuntimeValue).init(allocator),
            .function_table = std.StringHashMap(*const anyopaque).init(allocator),
            .call_stack = .{},
            .max_call_depth = 1000,
            .current_graph_name = "main",
            .context = null,
        };
    }

    pub fn deinit(self: *Interpreter) void {
        self.results.deinit();
        self.memory.deinit();
        self.function_table.deinit();
        // Clean up any remaining stack frames
        for (self.call_stack.items) |*frame| {
            frame.deinit();
        }
        self.call_stack.deinit(self.allocator);
    }

    pub fn setVerbose(self: *Interpreter, v: bool) void {
        self.verbose = v;
    }

    /// Set execution context (for capability enforcement)
    pub fn setContext(self: *Interpreter, ctx: *const janus_context.Context) void {
        self.context = ctx;
    }

    /// Register a function graph for later dispatch
    /// Call this for each function in the compilation unit before calling run()
    pub fn registerFunction(self: *Interpreter, comptime GraphType: type, name: []const u8, graph: *const GraphType) !void {
        try self.function_table.put(name, @ptrCast(graph));
        if (self.verbose) {
            std.debug.print("[INTERPRETER] Registered function: {s}\n", .{name});
        }
    }

    /// Run the interpreter starting from the specified entry point (typically "main")
    pub fn run(self: *Interpreter, comptime GraphType: type, entry_point: []const u8) InterpreterResult {
        const graph_ptr = self.function_table.get(entry_point) orelse {
            if (self.verbose) std.debug.print("[INTERPRETER] Entry point '{s}' not found\n", .{entry_point});
            return InterpreterResult.withExitCode(-1);
        };
        const graph: *const GraphType = @ptrCast(@alignCast(graph_ptr));
        self.current_graph_name = entry_point;
        return self.interpretGraph(GraphType, graph);
    }

    /// Interpret a QTJIR graph and execute its operations (legacy API)
    /// Returns the exit code from the main function (or 0 if void return)
    pub fn interpret(self: *Interpreter, comptime GraphType: type, graph: *const GraphType) InterpreterResult {
        return self.interpretGraph(GraphType, graph);
    }

    /// Internal graph interpretation with call stack support
    fn interpretGraph(self: *Interpreter, comptime GraphType: type, graph: *const GraphType) InterpreterResult {

        // Clear results for new execution scope, but preserve memory
        // (memory contains arguments passed by caller)
        self.results.clearRetainingCapacity();
        // NOTE: Do NOT clear memory here - it contains function arguments

        if (graph.nodes.items.len == 0) {
            return InterpreterResult.withExitCode(0);
        }

        if (self.verbose) {
            std.debug.print("[INTERPRETER] Executing function: {s}\n", .{graph.function_name});
        }

        // Build label map for jumps
        var label_map = std.AutoHashMap(u32, usize).init(self.allocator);
        defer label_map.deinit();

        for (graph.nodes.items, 0..) |node, idx| {
            const id = if (@hasField(@TypeOf(node), "id")) node.id else @as(u32, @intCast(idx));
            // Check op type dynamism - assuming generic graph has Label op
            // We use @tagName to check if op is Label to avoid compilation error if enum doesn't have it
            // properties of the node.
            // Actually, for generic interpret, we assume the Enum has these fields.
            // If the user passes a graph without these fields, it will fail at compile time.
            if (node.op == .Label) {
                label_map.put(id, idx) catch return InterpreterResult.withExitCode(-1);
            }
        }

        const exit_code: i32 = 0;
        var pc: usize = 0;

        while (pc < graph.nodes.items.len) {
            const node = graph.nodes.items[pc];
            // Safe index increment by default, control flow ops will override
            var next_pc = pc + 1;

            const id = if (@hasField(@TypeOf(node), "id")) node.id else @as(u32, @intCast(pc));

            switch (node.op) {
                .Constant => {
                    const val: RuntimeValue = switch (node.data) {
                        .integer => |i| .{ .integer = i },
                        .float => |f| .{ .float = f },
                        .boolean => |b| .{ .boolean = b },
                        .string => |s| .{ .string = s },
                    };
                    self.results.put(id, val) catch return InterpreterResult.withExitCode(-1);
                },
                .Alloca => {
                    self.memory.put(id, .{ .integer = 0 }) catch return InterpreterResult.withExitCode(-1);
                },
                .Store => {
                    if (node.inputs.items.len >= 2) {
                        const ptr_id = node.inputs.items[0];
                        const val_id = node.inputs.items[1];
                        if (self.results.get(val_id)) |val| {
                            self.memory.put(ptr_id, val) catch return InterpreterResult.withExitCode(-1);
                        }
                    }
                },
                .Load => {
                    if (node.inputs.items.len >= 1) {
                        const ptr_id = node.inputs.items[0];
                        // First try memory (for Alloca pointers)
                        if (self.memory.get(ptr_id)) |val| {
                            self.results.put(id, val) catch return InterpreterResult.withExitCode(-1);
                        }
                        // If ptr_id refers to an Index node, fetch from results instead
                        // (Index handler already put the element value there)
                        else if (self.results.get(ptr_id)) |val| {
                            self.results.put(id, val) catch return InterpreterResult.withExitCode(-1);
                        }
                    }
                },

                .Argument => {
                    // Argument nodes read their value from memory slots set by caller
                    // The node's data.integer contains the argument index
                    const arg_index: u32 = switch (node.data) {
                        .integer => |i| @intCast(i),
                        else => 0,
                    };
                    if (self.memory.get(arg_index)) |val| {
                        self.results.put(id, val) catch return InterpreterResult.withExitCode(-1);
                        if (self.verbose) std.debug.print("[INTERPRETER] Argument {} = {}\n", .{ arg_index, val.toInt() });
                    } else {
                        // Default to 0 if no argument was passed
                        self.results.put(id, .{ .integer = 0 }) catch return InterpreterResult.withExitCode(-1);
                    }
                },
                .Add, .Sub, .Mul, .Div, .Equal, .NotEqual, .Less, .LessEqual, .Greater, .GreaterEqual => {
                    if (node.inputs.items.len >= 2) {
                        const lhs = self.results.get(node.inputs.items[0]) orelse {
                            pc = next_pc;
                            continue;
                        };
                        const rhs = self.results.get(node.inputs.items[1]) orelse {
                            pc = next_pc;
                            continue;
                        };
                        var res: RuntimeValue = undefined;

                        switch (node.op) {
                            .Add => res = .{ .integer = lhs.toInt() + rhs.toInt() },
                            .Sub => res = .{ .integer = lhs.toInt() - rhs.toInt() },
                            .Mul => res = .{ .integer = lhs.toInt() * rhs.toInt() },
                            .Div => {
                                if (rhs.toInt() == 0) return InterpreterResult.withExitCode(-2);
                                res = .{ .integer = @divTrunc(lhs.toInt(), rhs.toInt()) };
                            },
                            .Equal => res = .{ .boolean = lhs.toInt() == rhs.toInt() },
                            .NotEqual => res = .{ .boolean = lhs.toInt() != rhs.toInt() },
                            .Less => res = .{ .boolean = lhs.toInt() < rhs.toInt() },
                            .LessEqual => res = .{ .boolean = lhs.toInt() <= rhs.toInt() },
                            .Greater => res = .{ .boolean = lhs.toInt() > rhs.toInt() },
                            .GreaterEqual => res = .{ .boolean = lhs.toInt() >= rhs.toInt() },
                            else => unreachable,
                        }
                        self.results.put(id, res) catch return InterpreterResult.withExitCode(-1);
                    }
                },
                .Array_Construct => {
                    // Create array from input values
                    const arr = self.allocator.create(ArrayValue) catch return InterpreterResult.withExitCode(-1);
                    arr.* = ArrayValue.init(self.allocator);

                    for (node.inputs.items) |input_id| {
                        if (self.results.get(input_id)) |val| {
                            arr.elements.append(arr.allocator, val) catch {};
                        }
                    }
                    self.results.put(id, .{ .array_val = arr }) catch return InterpreterResult.withExitCode(-1);
                },
                .Index => {
                    // Array access: arr[idx]
                    if (node.inputs.items.len >= 2) {
                        const arr_id = node.inputs.items[0];
                        const idx_id = node.inputs.items[1];

                        const arr_val = self.results.get(arr_id) orelse {
                            pc = next_pc;
                            continue;
                        };
                        const idx_val = self.results.get(idx_id) orelse {
                            pc = next_pc;
                            continue;
                        };

                        switch (arr_val) {
                            .array_val => |arr| {
                                const idx: usize = @intCast(idx_val.toInt());
                                if (idx < arr.elements.items.len) {
                                    self.results.put(id, arr.elements.items[idx]) catch {};
                                }
                            },
                            else => {},
                        }
                    }
                },
                .Index_Store => {
                    // Array element store: arr[idx] = val
                    if (node.inputs.items.len >= 3) {
                        const arr_id = node.inputs.items[0];
                        const idx_id = node.inputs.items[1];
                        const val_id = node.inputs.items[2];

                        if (self.results.get(arr_id)) |arr_val| {
                            switch (arr_val) {
                                .array_val => |arr| {
                                    const idx: usize = @intCast((self.results.get(idx_id) orelse RuntimeValue{ .integer = 0 }).toInt());
                                    const val = self.results.get(val_id) orelse RuntimeValue{ .integer = 0 };
                                    if (idx < arr.elements.items.len) {
                                        arr.elements.items[idx] = val;
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                },
                .Struct_Construct => {
                    // Create struct - field names in node.data.string (comma-separated)
                    // Values in inputs
                    const struct_val = self.allocator.create(StructValue) catch return InterpreterResult.withExitCode(-1);
                    struct_val.* = StructValue.init(self.allocator);

                    // Parse field names from comma-separated string
                    const field_names_str = switch (node.data) {
                        .string => |s| s,
                        else => "",
                    };

                    var field_iter = std.mem.splitScalar(u8, field_names_str, ',');
                    var field_idx: usize = 0;
                    while (field_iter.next()) |field_name| {
                        if (field_idx < node.inputs.items.len) {
                            const input_id = node.inputs.items[field_idx];
                            if (self.results.get(input_id)) |val| {
                                // Dupe field name for HashMap key
                                const key = self.allocator.dupe(u8, field_name) catch "";
                                struct_val.fields.put(key, val) catch {};
                            }
                        }
                        field_idx += 1;
                    }
                    self.results.put(id, .{ .struct_val = struct_val }) catch {};
                },

                .Field_Access => {
                    // Field read: s.field
                    if (node.inputs.items.len >= 1) {
                        const struct_id = node.inputs.items[0];
                        const field_name = switch (node.data) {
                            .string => |s| s,
                            else => "",
                        };

                        if (self.results.get(struct_id)) |s_val| {
                            switch (s_val) {
                                .struct_val => |s| {
                                    if (s.fields.get(field_name)) |val| {
                                        self.results.put(id, val) catch {};
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                },
                .Field_Store => {
                    // Field write: s.field = val
                    if (node.inputs.items.len >= 2) {
                        const struct_id = node.inputs.items[0];
                        const val_id = node.inputs.items[1];
                        const field_name = switch (node.data) {
                            .string => |s| s,
                            else => "",
                        };

                        if (self.results.get(struct_id)) |s_val| {
                            switch (s_val) {
                                .struct_val => |s| {
                                    if (self.results.get(val_id)) |val| {
                                        s.fields.put(field_name, val) catch {};
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                },
                .Call => {
                    const callee_name = switch (node.data) {
                        .string => |s| s,
                        else => "",
                    };
                    if (callee_name.len == 0) {
                        pc = next_pc;
                        continue;
                    }

                    // Check if it's a builtin first
                    if (self.isBuiltin(callee_name)) {
                        self.executeBuiltinCall(callee_name, &node.inputs, graph, id) catch |err| {
                            if (self.verbose) std.debug.print("[INTERPRETER] Builtin call failed: {s} - {}\n", .{ callee_name, err });
                            if (err == error.AssertionFailed) {
                                return InterpreterResult.withExitCode(1);
                            }
                        };
                        pc = next_pc;
                        continue;
                    }

                    // User function call - look up in function table
                    const callee_ptr = self.function_table.get(callee_name) orelse {
                        if (self.verbose) std.debug.print("[INTERPRETER] Function not found: {s}\n", .{callee_name});
                        pc = next_pc;
                        continue;
                    };

                    // Stack overflow protection
                    if (self.call_stack.items.len >= self.max_call_depth) {
                        if (self.verbose) std.debug.print("[INTERPRETER] Stack overflow at depth {}\n", .{self.call_stack.items.len});
                        return InterpreterResult.withExitCode(-10);
                    }

                    const callee_graph: *const GraphType = @ptrCast(@alignCast(callee_ptr));

                    // Push stack frame - save current state
                    var saved_results = std.AutoHashMap(u32, RuntimeValue).init(self.allocator);
                    var iter = self.results.iterator();
                    while (iter.next()) |entry| {
                        saved_results.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
                    }

                    var saved_memory = std.AutoHashMap(u32, RuntimeValue).init(self.allocator);
                    var mem_iter = self.memory.iterator();
                    while (mem_iter.next()) |entry| {
                        saved_memory.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
                    }

                    self.call_stack.append(self.allocator, .{
                        .return_pc = next_pc,
                        .return_graph_name = self.current_graph_name,
                        .return_register = id,
                        .saved_results = saved_results,
                        .saved_memory = saved_memory,
                    }) catch return InterpreterResult.withExitCode(-1);

                    // Pass arguments: copy input values to callee's parameter slots (0, 1, 2...)
                    // The callee's Argument nodes will read from these positions
                    for (node.inputs.items, 0..) |arg_id, arg_idx| {
                        if (self.results.get(arg_id)) |arg_val| {
                            // Store in memory slot for the argument index
                            self.memory.put(@intCast(arg_idx), arg_val) catch {};
                        }
                    }

                    // Clear results for callee's fresh scope
                    self.results.clearRetainingCapacity();

                    // Switch to callee graph
                    self.current_graph_name = callee_name;

                    // Recursively interpret the callee
                    const callee_result = self.interpretGraph(GraphType, callee_graph);

                    // On return, the result is in callee_result.exit_code (for i32 returns)
                    // Pop frame and restore state
                    if (self.call_stack.items.len > 0) {
                        const frame = self.call_stack.pop().?;

                        // Restore caller's state
                        self.results.deinit();
                        self.results = frame.saved_results;
                        self.memory.deinit();
                        self.memory = frame.saved_memory;
                        self.current_graph_name = frame.return_graph_name;

                        // Store return value in caller's result map
                        self.results.put(frame.return_register, .{ .integer = callee_result.exit_code }) catch {};
                    }

                    pc = next_pc;
                    continue;
                },
                .Return => {
                    var return_value: i64 = 0;
                    if (node.inputs.items.len > 0) {
                        const ret_val_id = node.inputs.items[0];
                        if (self.results.get(ret_val_id)) |val| {
                            return_value = val.toInt();
                            if (self.verbose) std.debug.print("[INTERPRETER] Return: results[{}] = {}\n", .{ ret_val_id, return_value });
                        } else if (ret_val_id < graph.nodes.items.len) {
                            const ret_node = graph.nodes.items[ret_val_id];
                            if (ret_node.op == .Constant) {
                                switch (ret_node.data) {
                                    .integer => |i| return_value = i,
                                    else => {},
                                }
                                if (self.verbose) std.debug.print("[INTERPRETER] Return: const {} = {}\n", .{ ret_val_id, return_value });
                            } else {
                                if (self.verbose) std.debug.print("[INTERPRETER] Return: node {} not found, op={s}\n", .{ ret_val_id, @tagName(ret_node.op) });
                            }
                        } else {
                            if (self.verbose) std.debug.print("[INTERPRETER] Return: ret_val_id {} out of bounds\n", .{ret_val_id});
                        }
                    }
                    // Return with the value - caller will handle frame restoration
                    return InterpreterResult.withExitCode(@intCast(return_value));
                },

                .Label => {
                    // No-op, just a marker
                },
                .Jump => {
                    // Unconditional jump
                    if (node.inputs.items.len >= 1) {
                        const target_id = node.inputs.items[0];
                        if (label_map.get(target_id)) |target_pc| {
                            next_pc = target_pc;
                        } else {
                            // Runtime error: Jump target not found
                            if (self.verbose) std.debug.print("Jump target {d} not found\n", .{target_id});
                            return InterpreterResult.withExitCode(-3);
                        }
                    }
                },
                .Branch => {
                    // Conditional jump
                    // inputs: [cond, true_target, false_target]
                    if (node.inputs.items.len >= 3) {
                        const cond_id = node.inputs.items[0];
                        const true_target = node.inputs.items[1];
                        const false_target = node.inputs.items[2];

                        const cond_val = self.results.get(cond_id) orelse {
                            // Error: Condition not found
                            return InterpreterResult.withExitCode(-4);
                        };

                        // Check boolean truthiness (or integer 0/1)
                        const is_true = switch (cond_val) {
                            .boolean => |b| b,
                            .integer => |i| i != 0,
                            else => false,
                        };

                        const target_id = if (is_true) true_target else false_target;

                        if (label_map.get(target_id)) |target_pc| {
                            next_pc = target_pc;
                        } else {
                            // Runtime error: Branch target not found
                            if (self.verbose) std.debug.print("Branch target {d} not found\n", .{target_id});
                            return InterpreterResult.withExitCode(-3);
                        }
                    }
                },
                else => {
                    // Skip non-executable nodes
                },
            }

            // Advance PC
            pc = next_pc;
        }

        if (self.verbose) {
            std.debug.print("[INTERPRETER] Function complete, exit code: {d}\n", .{exit_code});
        }

        return InterpreterResult.withExitCode(exit_code);
    }

    /// Check if a function name is a known builtin
    fn isBuiltin(self: *Interpreter, name: []const u8) bool {
        _ = self;
        return std.mem.eql(u8, name, "janus_println") or
            std.mem.eql(u8, name, "janus_print") or
            std.mem.eql(u8, name, "println") or
            std.mem.eql(u8, name, "print") or
            std.mem.eql(u8, name, "janus_read_file") or
            std.mem.eql(u8, name, "janus_write_file") or
            std.mem.eql(u8, name, "janus_cast_i32_to_i64") or
            std.mem.eql(u8, name, "janus_string_create") or
            std.mem.eql(u8, name, "janus_string_handle_len") or
            std.mem.eql(u8, name, "janus_string_eq") or
            std.mem.eql(u8, name, "janus_string_print") or
            std.mem.eql(u8, name, "janus_string_concat") or
            std.mem.eql(u8, name, "janus_string_free") or
            std.mem.eql(u8, name, "assert"); // PROBATIO: Assertion intrinsic
    }

    /// Execute a builtin runtime call
    fn executeBuiltinCall(
        self: *Interpreter,
        callee_name: []const u8,
        inputs: anytype,
        graph: anytype,
        call_node_id: u32,
    ) !void {
        if (self.verbose) std.debug.print("DEBUG: executeBuiltinCall {s}\n", .{callee_name});

        // janus_println / janus_print - output to stdout (capability-controlled)
        if (std.mem.eql(u8, callee_name, "janus_println") or
            std.mem.eql(u8, callee_name, "janus_print"))
        {
            // Check stdout capability if context is set
            if (self.context) |ctx| {
                if (!ctx.canWriteStdout()) {
                    const stderr = compat_fs.stderr();
                    stderr.writeAll("ERROR: Capability denied: stdout_write (SYNTACTIC HONESTY)\n") catch {};
                    return error.CapabilityDenied;
                }
            }

            const add_newline = std.mem.eql(u8, callee_name, "janus_println");
            const stdout = compat_fs.stdout();

            // Get the first argument
            if (inputs.items.len > 0) {
                const arg_id = inputs.items[0];

                // Try to get from computed results first
                if (self.results.get(arg_id)) |val| {
                    const formatted = try val.toString(self.allocator);
                    // If allocated, we should free it, but for interpret lifetime it's tricky.
                    // For short strings/integers, toString allocates. We should free it.
                    defer if (val != .string) self.allocator.free(formatted);

                    stdout.writeAll(formatted) catch {};
                    if (add_newline) {
                        stdout.writeAll("\n") catch {};
                    }
                } else if (arg_id < graph.nodes.items.len) {
                    // Fallback to constant data access
                    const arg_node = graph.nodes.items[arg_id];
                    if (arg_node.op == .Constant) {
                        switch (arg_node.data) {
                            .string => |s| {
                                stdout.writeAll(s) catch {};
                                if (add_newline) stdout.writeAll("\n") catch {};
                            },
                            .integer => |i| {
                                var buf: [32]u8 = undefined;
                                const formatted = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "";
                                stdout.writeAll(formatted) catch {};
                                if (add_newline) stdout.writeAll("\n") catch {};
                            },
                            else => {},
                        }
                    }
                }
            }
            return;
        }

        // janus_panic
        if (std.mem.eql(u8, callee_name, "janus_panic")) {
            const stderr = compat_fs.stderr();
            if (inputs.items.len > 0) {
                // Simplified panic for now
                stderr.writeAll("PANIC\n") catch {};
            }
            return;
        }

        // PROBATIO: Assert intrinsic
        if (std.mem.eql(u8, callee_name, "assert")) {
            if (inputs.items.len > 0) {
                const arg_id = inputs.items[0];
                if (self.results.get(arg_id)) |val| {
                    const condition = val.toBool();
                    if (!condition) {
                        std.debug.print("Assertion failed\n", .{});
                        return error.AssertionFailed;
                    }
                }
            }
            return;
        }

        // janus_read_file(path: string) -> string (capability-controlled)
        if (std.mem.eql(u8, callee_name, "janus_read_file")) {
            // Check fs_read capability
            if (self.context) |ctx| {
                if (!ctx.canReadFs()) {
                    const stderr = compat_fs.stderr();
                    stderr.writeAll("ERROR: Capability denied: fs_read (SYNTACTIC HONESTY)\n") catch {};
                    return error.CapabilityDenied;
                }
            }

            // Get path argument
            if (inputs.items.len > 0) {
                const path_id = inputs.items[0];
                const path_val = self.results.get(path_id) orelse {
                    self.results.put(call_node_id, .{ .string = "" }) catch {};
                    return;
                };

                const path = switch (path_val) {
                    .string => |s| s,
                    else => {
                        self.results.put(call_node_id, .{ .string = "" }) catch {};
                        return;
                    },
                };

                // Check path is allowed
                if (self.context) |ctx| {
                    if (!ctx.isPathAllowed(path)) {
                        const stderr = compat_fs.stderr();
                        stderr.writeAll("ERROR: Path not allowed for filesystem operations\n") catch {};
                        return error.CapabilityDenied;
                    }
                }

                // Read file
                const contents = compat_fs.readFileAlloc(
                    self.allocator,
                    path,
                    10 * 1024 * 1024, // 10MB max
                ) catch |err| {
                    if (self.verbose) std.debug.print("File read error: {}\n", .{err});
                    self.results.put(call_node_id, .{ .string = "" }) catch {};
                    return;
                };

                // Store result (contents will be leaked until interpreter cleanup)
                self.results.put(call_node_id, .{ .string = contents }) catch {};
            } else {
                self.results.put(call_node_id, .{ .string = "" }) catch {};
            }
            return;
        }

        // janus_write_file(path: string, content: string) (capability-controlled)
        if (std.mem.eql(u8, callee_name, "janus_write_file")) {
            // Check fs_write capability
            if (self.context) |ctx| {
                if (!ctx.canWriteFs()) {
                    const stderr = compat_fs.stderr();
                    stderr.writeAll("ERROR: Capability denied: fs_write (SYNTACTIC HONESTY)\n") catch {};
                    return error.CapabilityDenied;
                }
            }

            // Get arguments
            if (inputs.items.len >= 2) {
                const path_id = inputs.items[0];
                const content_id = inputs.items[1];

                const path_val = self.results.get(path_id) orelse return;
                const content_val = self.results.get(content_id) orelse return;

                const path = switch (path_val) {
                    .string => |s| s,
                    else => return,
                };

                const content = switch (content_val) {
                    .string => |s| s,
                    else => "",
                };

                // Check path is allowed
                if (self.context) |ctx| {
                    if (!ctx.isPathAllowed(path)) {
                        const stderr = compat_fs.stderr();
                        stderr.writeAll("ERROR: Path not allowed for filesystem operations\n") catch {};
                        return error.CapabilityDenied;
                    }
                }

                // Write file
                const file = compat_fs.createFile(path, .{}) catch |err| {
                    if (self.verbose) std.debug.print("File write error: {}\n", .{err});
                    return;
                };
                defer file.close();

                file.writeAll(content) catch {};
            }
            return;
        }

        // String Operations
        if (std.mem.eql(u8, callee_name, "janus_string_create")) {
            // janus_string_create(ptr, len, alloc) -> string
            if (inputs.items.len >= 2) {
                const ptr_id = inputs.items[0];
                const len_id = inputs.items[1];

                const str_val = self.results.get(ptr_id) orelse RuntimeValue{ .string = "" };
                const len_val = self.results.get(len_id) orelse RuntimeValue{ .integer = 0 };

                const full_str = switch (str_val) {
                    .string => |s| s,
                    else => "",
                };

                const len = @as(usize, @intCast(len_val.toInt()));
                const final_len = if (len > full_str.len) full_str.len else len;

                // Return substring
                self.results.put(call_node_id, .{ .string = full_str[0..final_len] }) catch {};
            } else {
                // Return empty string on error context
                self.results.put(call_node_id, .{ .string = "" }) catch {};
            }
            return;
        }

        if (std.mem.eql(u8, callee_name, "janus_string_concat")) {
            // janus_string_concat(s1, s2, alloc) -> string
            if (inputs.items.len >= 2) {
                const s1_id = inputs.items[0];
                const s2_id = inputs.items[1];
                const s1_val = self.results.get(s1_id) orelse RuntimeValue{ .string = "" };
                const s2_val = self.results.get(s2_id) orelse RuntimeValue{ .string = "" };

                const s1 = switch (s1_val) {
                    .string => |s| s,
                    else => "",
                };
                const s2 = switch (s2_val) {
                    .string => |s| s,
                    else => "",
                };

                const concat = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ s1, s2 });
                // Leak intentionally for interpreter lifespan or track?
                // Interpreter doesn't track allocations well yet.
                self.results.put(call_node_id, .{ .string = concat }) catch {};
            }
            return;
        }

        if (std.mem.eql(u8, callee_name, "janus_string_handle_len")) {
            // janus_string_handle_len(handle) -> i64
            if (inputs.items.len >= 1) {
                const handle_id = inputs.items[0];
                const handle_val = self.results.get(handle_id) orelse RuntimeValue{ .string = "" };
                const s = switch (handle_val) {
                    .string => |s| s,
                    else => "",
                };
                self.results.put(call_node_id, .{ .integer = @intCast(s.len) }) catch {};
            }
            return;
        }

        if (std.mem.eql(u8, callee_name, "janus_string_print")) {
            // janus_string_print(handle) -> void
            if (inputs.items.len >= 1) {
                const handle_id = inputs.items[0];
                const handle_val = self.results.get(handle_id) orelse RuntimeValue{ .string = "" };
                const s = switch (handle_val) {
                    .string => |s| s,
                    else => "(null)",
                };
                compat_fs.stdout().writeAll(s) catch {};
            }
            return;
        }

        if (std.mem.eql(u8, callee_name, "janus_string_free")) {
            // No-op for interpreter
            return;
        }

        if (std.mem.eql(u8, callee_name, "janus_cast_i32_to_i64")) {
            if (inputs.items.len >= 1) {
                const arg_id = inputs.items[0];
                const val = self.results.get(arg_id) orelse RuntimeValue{ .integer = 0 };
                // Pass through integer
                self.results.put(call_node_id, val) catch {};
            }
            return;
        }

        if (self.verbose) {
            std.debug.print("[INTERPRETER] Unknown builtin: {s}\n", .{callee_name});
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Interpreter: basic initialization" {
    const allocator = std.testing.allocator;
    var interp = Interpreter.init(allocator);
    interp.setVerbose(true);
    try std.testing.expect(interp.verbose);
}

test "Interpreter: empty graph returns 0" {
    const allocator = std.testing.allocator;
    var interp = Interpreter.init(allocator);

    // Create a mock graph type
    const MockGraph = struct {
        nodes: struct {
            items: []const MockNode,
        },
        function_name: []const u8 = "test",

        const MockNode = struct {
            op: enum { Call, Return, Constant, Add, Sub, Mul, Div, Alloca, Store, Load, Jump, Branch, Label, Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual, Other },
            data: union(enum) { integer: i64, string: []const u8, float: f64, boolean: bool },
            inputs: struct {
                items: []const u32,
            },
        };
    };

    const empty_graph = MockGraph{
        .nodes = .{ .items = &.{} },
    };

    const result = interp.interpret(MockGraph, &empty_graph);
    try std.testing.expectEqual(@as(i32, 0), result.exit_code);
    interp.deinit();
}

test "Interpreter: arithmetic operations" {
    const allocator = std.testing.allocator;
    var interp = Interpreter.init(allocator);
    defer interp.deinit();

    // Mock graph for: return 10 + 32
    const MockGraph = struct {
        nodes: struct {
            items: []const MockNode,
        },
        function_name: []const u8 = "test_arithmetic",

        const MockNode = struct {
            op: enum { Call, Return, Constant, Add, Sub, Mul, Div, Alloca, Store, Load, Jump, Branch, Label, Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual, Other },
            data: union(enum) { integer: i64, string: []const u8, float: f64, boolean: bool },
            inputs: struct {
                items: []const u32,
            },
        };
    };

    const nodes = [_]MockGraph.MockNode{
        // 0: Const 10
        .{ .op = .Constant, .data = .{ .integer = 10 }, .inputs = .{ .items = &.{} } },
        // 1: Const 32
        .{ .op = .Constant, .data = .{ .integer = 32 }, .inputs = .{ .items = &.{} } },
        // 2: Add(0, 1) -> 42
        .{ .op = .Add, .data = .{ .integer = 0 }, .inputs = .{ .items = &.{ 0, 1 } } },
        // 3: Return(2)
        .{ .op = .Return, .data = .{ .integer = 0 }, .inputs = .{ .items = &.{2} } },
    };

    const graph = MockGraph{
        .nodes = .{ .items = &nodes },
    };

    const result = interp.interpret(MockGraph, &graph);
    try std.testing.expectEqual(@as(i32, 42), result.exit_code);
}

test "Interpreter: variables (alloca/store/load)" {
    const allocator = std.testing.allocator;
    var interp = Interpreter.init(allocator);
    defer interp.deinit();

    // Mock graph for:
    // let a = 5;
    // let b = 7;
    // return a * b;
    const MockGraph = struct {
        nodes: struct {
            items: []const MockNode,
        },
        function_name: []const u8 = "test_vars",

        const MockNode = struct {
            op: enum { Call, Return, Constant, Add, Sub, Mul, Div, Alloca, Store, Load, Jump, Branch, Label, Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual, Other },
            data: union(enum) { integer: i64, string: []const u8, float: f64, boolean: bool },
            inputs: struct {
                items: []const u32,
            },
        };
    };

    const nodes = [_]MockGraph.MockNode{
        // 0: Const 5
        .{ .op = .Constant, .data = .{ .integer = 5 }, .inputs = .{ .items = &.{} } },
        // 1: Const 7
        .{ .op = .Constant, .data = .{ .integer = 7 }, .inputs = .{ .items = &.{} } },
        // 2: Alloca "a"
        .{ .op = .Alloca, .data = .{ .string = "a" }, .inputs = .{ .items = &.{} } },
        // 3: Store(ptr=2, val=0) -> a = 5
        .{ .op = .Store, .data = .{ .integer = 0 }, .inputs = .{ .items = &.{ 2, 0 } } },
        // 4: Alloca "b"
        .{ .op = .Alloca, .data = .{ .string = "b" }, .inputs = .{ .items = &.{} } },
        // 5: Store(ptr=4, val=1) -> b = 7
        .{ .op = .Store, .data = .{ .integer = 0 }, .inputs = .{ .items = &.{ 4, 1 } } },
        // 6: Load(ptr=2) -> 5
        .{ .op = .Load, .data = .{ .integer = 0 }, .inputs = .{ .items = &.{2} } },
        // 7: Load(ptr=4) -> 7
        .{ .op = .Load, .data = .{ .integer = 0 }, .inputs = .{ .items = &.{4} } },
        // 8: Mul(6, 7) -> 35
        .{ .op = .Mul, .data = .{ .integer = 0 }, .inputs = .{ .items = &.{ 6, 7 } } },
        // 9: Return(8)
        .{ .op = .Return, .data = .{ .integer = 0 }, .inputs = .{ .items = &.{8} } },
    };

    const graph = MockGraph{
        .nodes = .{ .items = &nodes },
    };

    const result = interp.interpret(MockGraph, &graph);
    try std.testing.expectEqual(@as(i32, 35), result.exit_code);
}

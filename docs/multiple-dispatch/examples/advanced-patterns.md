<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Advanced Multiple Dispatch Patterns

This document covers sophisticated patterns and techniques for using multiple dispatch effectively in complex scenarios.

## Table of Contents

- [Cross-Module Function Families](#cross-module-function-families)
- [Performance-Critical Dispatch](#performance-critical-dispatch)
- [Dynamic Dispatch Patterns](#dynamic-dispatch-patterns)
- [Generic Programming with Dispatch](#generic-programming-with-dispatch)
- [State Machine Dispatch](#state-machine-dispatch)
- [Visitor Pattern Alternative](#visitor-pattern-alternative)

## Cross-Module Function Families

### Extensible Serialization System

```janus
// Core serialization module
module Core.Serialization

// Base serialization for primitives
func serialize(value: i32) -> string do
  return "{value}"
end

func serialize(value: f64) -> string do
  return "{value}"
end

func serialize(value: string) -> string do
  return "\"{value}\""
end

func serialize(value: bool) -> string do
  return if value then "true" else "false"
end

// Export for extension
export serialize
```

```janus
// Collections extension module
module Collections.Serialization

import Core.Serialization.serialize

// Extend serialization for collections
func serialize(arr: []any) -> string do
  let parts = []
  for item in arr do
    parts.append(serialize(item))  // Dispatch to appropriate serializer
  end
  return "[{parts.join(", ")}]"
end

func serialize(map: table) -> string do
  let parts = []
  for key, value in map do
    let key_str = serialize(key)
    let value_str = serialize(value)
    parts.append("{key_str}: {value_str}")
  end
  return "{{parts.join(", ")}}"
end

// Export extended functionality
export serialize
```

```janus
// Custom types extension
module CustomTypes.Serialization

import Collections.Serialization.serialize  // Imports both Collections and Core

// Custom business types
type User = table {
  id: i32,
  name: string,
  email: string,
  active: bool
}

type Order = table {
  id: i32,
  user_id: i32,
  items: []string,
  total: f64
}

// Extend serialization for custom types
func serialize(user: User) -> string do
  return serialize({
    id: user.id,
    name: user.name,
    email: user.email,
    active: user.active
  })
end

func serialize(order: Order) -> string do
  return serialize({
    id: order.id,
    user_id: order.user_id,
    items: order.items,
    total: order.total
  })
end

// Export complete serialization system
export serialize
```

```janus
// Application using the complete system
module Application

import CustomTypes.Serialization.serialize

func main() do
  let user = User{
    id: 1,
    name: "John Doe",
    email: "john@example.com",
    active: true
  }

  let order = Order{
    id: 100,
    user_id: 1,
    items: ["laptop", "mouse", "keyboard"],
    total: 1299.99
  }

  // All dispatch to appropriate implementations
  println(serialize(42))           // Core: "42"
  println(serialize([1, 2, 3]))    // Collections: "[1, 2, 3]"
  println(serialize(user))         // CustomTypes: complex JSON
  println(serialize(order))        // CustomTypes: complex JSON
end
```

### Plugin Architecture with Dispatch

```janus
// Core plugin system
module Core.Plugins

type Plugin = table {
  name: string,
  version: string
}

type DataProcessor = table extends Plugin {
  supported_formats: []string
}

type Renderer = table extends Plugin {
  output_formats: []string
}

// Base plugin operations
func initialize(plugin: Plugin) -> bool do
  println("Initializing plugin: {plugin.name} v{plugin.version}")
  return true
end

func cleanup(plugin: Plugin) do
  println("Cleaning up plugin: {plugin.name}")
end

// Export plugin interface
export Plugin, DataProcessor, Renderer
export initialize, cleanup
```

```janus
// Data processing plugins
module Plugins.DataProcessing

import Core.Plugins.{DataProcessor, initialize, cleanup}

type JsonProcessor = table extends DataProcessor {
  pretty_print: bool
}

type XmlProcessor = table extends DataProcessor {
  validate_schema: bool
}

// Specific initialization for data processors
func initialize(processor: DataProcessor) -> bool do
  if not initialize(processor as Plugin) then
    return false
  end

  println("Supported formats: {processor.supported_formats}")
  return true
end

func initialize(json: JsonProcessor) -> bool do
  if not initialize(json as DataProcessor) then
    return false
  end

  println("Pretty print enabled: {json.pretty_print}")
  return true
end

func initialize(xml: XmlProcessor) -> bool do
  if not initialize(xml as DataProcessor) then
    return false
  end

  println("Schema validation: {xml.validate_schema}")
  return true
end

// Processing functions
func process(processor: JsonProcessor, data: string) -> string do
  // JSON-specific processing
  return if processor.pretty_print then format_json(data) else data
end

func process(processor: XmlProcessor, data: string) -> string do
  // XML-specific processing
  if processor.validate_schema then
    validate_xml_schema(data)
  end
  return normalize_xml(data)
end

export JsonProcessor, XmlProcessor
export process
```

## Performance-Critical Dispatch

### Hot Path Optimization

```janus
// High-performance numeric processing
module NumericProcessing

// Hot path: compile-time dispatch for known types
func process_batch(data: []i32) -> i64 do
  let sum: i64 = 0
  for value in data do
    sum += process(value)  // Static dispatch - zero overhead
  end
  return sum
end

func process_batch(data: []f64) -> f64 do
  let sum: f64 = 0.0
  for value in data do
    sum += process(value)  // Static dispatch - zero overhead
  end
  return sum
end

// Optimized implementations for specific types
func process(value: i32) -> i64 do
  // Highly optimized integer processing
  return (value * value + value) as i64
end

func process(value: i64) -> i64 do
  // Optimized long integer processing
  return value * value + value
end

func process(value: f32) -> f64 do
  // Optimized float processing
  let d = value as f64
  return d * d + d
end

func process(value: f64) -> f64 do
  // Optimized double processing
  return value * value + value
end

// Cold path: explicit dynamic dispatch for unknown types
func process_dynamic(value: any) -> f64 {.dispatch: dynamic.} do
  return process(value) as f64  // Runtime dispatch - visible cost
end

// Fallback for unsupported types
func process(value: any) -> f64 do
  return 0.0  // Safe fallback
end

// Performance monitoring
func benchmark_dispatch() do
  let data_i32 = [1, 2, 3, 4, 5] * 10000
  let data_f64 = [1.0, 2.0, 3.0, 4.0, 5.0] * 10000

  // Hot path - static dispatch
  let start = now()
  let result_i32 = process_batch(data_i32)
  let static_time = now() - start

  let start2 = now()
  let result_f64 = process_batch(data_f64)
  let static_time2 = now() - start2

  // Cold path - dynamic dispatch
  let start3 = now()
  let dynamic_result = 0.0
  for value in data_i32 do
    dynamic_result += process_dynamic(value)
  end
  let dynamic_time = now() - start3

  println("Static i32 dispatch: {static_time}ms")
  println("Static f64 dispatch: {static_time2}ms")
  println("Dynamic dispatch: {dynamic_time}ms")
  println("Overhead: {(dynamic_time - static_time) / static_time * 100}%")
end
```

### Cache-Friendly Dispatch Tables

```janus
// Optimized dispatch for frequently called functions
module OptimizedDispatch

// Mark functions for dispatch table optimization
{.optimize: cache_friendly.}
func transform(data: []i32) -> []i32 do
  let result = []
  for value in data do
    result.append(transform(value))  // Optimized dispatch
  end
  return result
end

{.optimize: cache_friendly.}
func transform(value: i32) -> i32 do
  return value * 2
end

{.optimize: cache_friendly.}
func transform(value: f64) -> f64 do
  return value * 2.0
end

{.optimize: cache_friendly.}
func transform(value: string) -> string do
  return value ++ value
end

// Batch processing with optimized dispatch
func process_mixed_batch(items: []any) do
  // Group by type for better cache locality
  let int_items = []
  let float_items = []
  let string_items = []

  for item in items do
    match typeof(item) {
      i32 => int_items.append(item as i32)
      f64 => float_items.append(item as f64)
      string => string_items.append(item as string)
    }
  end

  // Process in type-homogeneous batches
  for item in int_items do
    transform(item)  // Static dispatch, cache-friendly
  end

  for item in float_items do
    transform(item)  // Static dispatch, cache-friendly
  end

  for item in string_items do
    transform(item)  // Static dispatch, cache-friendly
  end
end
```

## Dynamic Dispatch Patterns

### Runtime Type Resolution

```janus
// Dynamic dispatch with explicit cost tracking
module DynamicProcessing

// Explicit dynamic dispatch annotation
func handle_request(request: any) -> Response {.dispatch: dynamic.} do
  // Runtime type resolution - cost is visible
  return Response{ status: 200, body: "Default handler" }
end

func handle_request(req: HttpRequest) -> Response do
  return Response{
    status: 200,
    body: "HTTP: {req.method} {req.path}"
  }
end

func handle_request(req: WebSocketRequest) -> Response do
  return Response{
    status: 101,
    body: "WebSocket: {req.protocol}"
  }
end

func handle_request(req: GraphQLRequest) -> Response do
  return Response{
    status: 200,
    body: "GraphQL: {req.query}"
  }
end

// Request router with performance monitoring
func route_request(request: any) -> Response do
  let start_time = now()

  let response = handle_request(request)  // Dynamic dispatch

  let end_time = now()
  let dispatch_time = end_time - start_time

  // Log performance metrics
  if dispatch_time > 1000 do  // 1ms threshold
    println("⚠️ Slow dispatch: {dispatch_time}μs for {typeof(request)}")
  end

  return response
end

// Type-specific optimization hints
func optimize_for_type(request_type: string) do
  match request_type {
    "HttpRequest" => {
      // Pre-warm HTTP dispatch table
      let dummy = HttpRequest{ method: "GET", path: "/" }
      handle_request(dummy)
    }
    "WebSocketRequest" => {
      // Pre-warm WebSocket dispatch table
      let dummy = WebSocketRequest{ protocol: "ws" }
      handle_request(dummy)
    }
  }
end
```

### Conditional Dispatch

```janus
// Dispatch based on runtime conditions
module ConditionalDispatch

type ProcessingMode = enum {
  Development,
  Production,
  Testing
}

// Mode-aware processing
func process_data(data: string, mode: ProcessingMode) -> string do
  match mode {
    ProcessingMode.Development => process_dev(data)
    ProcessingMode.Production => process_prod(data)
    ProcessingMode.Testing => process_test(data)
  }
end

func process_dev(data: string) -> string do
  // Development: verbose logging, validation
  println("DEV: Processing {data.len} bytes")
  validate_data(data)
  return transform_with_debug(data)
end

func process_prod(data: string) -> string do
  // Production: optimized, minimal logging
  return transform_optimized(data)
end

func process_test(data: string) -> string do
  // Testing: deterministic, traceable
  return transform_deterministic(data)
end

// Feature flag dispatch
func process_with_features(data: string, features: FeatureFlags) -> string do
  if features.new_algorithm then
    return process_v2(data)
  else
    return process_v1(data)
  end
end

func process_v1(data: string) -> string do
  // Legacy algorithm
  return data.reverse()
end

func process_v2(data: string) -> string do
  // New algorithm
  return data.transform_advanced()
end
```

## Generic Programming with Dispatch

### Type-Parameterized Functions

```janus
// Generic functions with dispatch
module GenericDispatch

// Generic container operations
func map<T, U>(container: []T, transform: (T) -> U) -> []U do
  let result = []
  for item in container do
    result.append(transform(item))
  end
  return result
end

func map<T, U>(container: Optional<T>, transform: (T) -> U) -> Optional<U> do
  match container {
    Optional.Some(value) => Optional.Some(transform(value))
    Optional.None => Optional.None
  }
end

func map<T, U, E>(container: Result<T, E>, transform: (T) -> U) -> Result<U, E> do
  match container {
    Result.Ok(value) => Result.Ok(transform(value))
    Result.Err(error) => Result.Err(error)
  }
end

// Generic reduction
func reduce<T, U>(container: []T, initial: U, combine: (U, T) -> U) -> U do
  let accumulator = initial
  for item in container do
    accumulator = combine(accumulator, item)
  end
  return accumulator
end

func reduce<T>(container: []T, combine: (T, T) -> T) -> Optional<T> do
  if container.is_empty() then
    return Optional.None
  end

  let accumulator = container[0]
  for i in 1..container.len do
    accumulator = combine(accumulator, container[i])
  end
  return Optional.Some(accumulator)
end

// Usage with type inference
func main() do
  let numbers = [1, 2, 3, 4, 5]
  let strings = ["a", "b", "c"]

  // map dispatches based on container type
  let doubled = map(numbers, |x| x * 2)        // []i32 -> []i32
  let lengths = map(strings, |s| s.len)        // []string -> []usize

  // reduce dispatches based on presence of initial value
  let sum = reduce(numbers, 0, |acc, x| acc + x)     // With initial
  let max = reduce(numbers, |a, b| if a > b then a else b)  // Without initial

  println("Doubled: {doubled}")
  println("Lengths: {lengths}")
  println("Sum: {sum}")
  println("Max: {max}")
end
```

### Trait-Based Dispatch

```janus
// Trait-based generic programming
module TraitDispatch

trait Serializable {
  func serialize(self) -> string
}

trait Comparable {
  func compare(self, other: Self) -> i32
}

// Generic functions using traits
func to_json<T: Serializable>(items: []T) -> string do
  let parts = []
  for item in items do
    parts.append(item.serialize())  // Trait method dispatch
  end
  return "[{parts.join(", ")}]"
end

func sort<T: Comparable>(items: []T) -> []T do
  // Simplified bubble sort using trait method
  let result = items.clone()
  for i in 0..result.len do
    for j in 0..(result.len - i - 1) do
      if result[j].compare(result[j + 1]) > 0 then
        let temp = result[j]
        result[j] = result[j + 1]
        result[j + 1] = temp
      end
    end
  end
  return result
end

// Implement traits for custom types
type Person = table {
  name: string,
  age: i32
}

impl Serializable for Person {
  func serialize(self) -> string do
    return "{{\"name\": \"{self.name}\", \"age\": {self.age}}}"
  end
}

impl Comparable for Person {
  func compare(self, other: Person) -> i32 do
    return self.age - other.age  // Compare by age
  end
}

// Usage
func main() do
  let people = [
    Person{ name: "Alice", age: 30 },
    Person{ name: "Bob", age: 25 },
    Person{ name: "Charlie", age: 35 }
  ]

  let json = to_json(people)      // Uses Serializable trait
  let sorted = sort(people)       // Uses Comparable trait

  println("JSON: {json}")
  println("Sorted by age: {to_json(sorted)}")
end
```

## State Machine Dispatch

### Protocol State Machine

```janus
// State machine using dispatch
module ProtocolStateMachine

type ConnectionState = sum {
  Disconnected,
  Connecting,
  Connected,
  Authenticated,
  Error(string)
}

type Connection = table {
  state: ConnectionState,
  socket: Socket,
  credentials: ?Credentials
}

// State-specific message handling
func handle_message(conn: Connection, msg: ConnectMessage) -> Connection do
  match conn.state {
    ConnectionState.Disconnected => {
      // Valid transition
      return Connection{
        state: ConnectionState.Connecting,
        socket: conn.socket,
        credentials: conn.credentials
      }
    }
    _ => {
      // Invalid transition
      return Connection{
        state: ConnectionState.Error("Invalid connect in state {conn.state}"),
        socket: conn.socket,
        credentials: conn.credentials
      }
    }
  }
end

func handle_message(conn: Connection, msg: AuthMessage) -> Connection do
  match conn.state {
    ConnectionState.Connected => {
      if validate_credentials(msg.credentials) then
        return Connection{
          state: ConnectionState.Authenticated,
          socket: conn.socket,
          credentials: Some(msg.credentials)
        }
      else
        return Connection{
          state: ConnectionState.Error("Authentication failed"),
          socket: conn.socket,
          credentials: conn.credentials
        }
      end
    }
    _ => {
      return Connection{
        state: ConnectionState.Error("Invalid auth in state {conn.state}"),
        socket: conn.socket,
        credentials: conn.credentials
      }
    }
  }
end

func handle_message(conn: Connection, msg: DataMessage) -> Connection do
  match conn.state {
    ConnectionState.Authenticated => {
      // Process data message
      process_data(msg.data)
      return conn  // State unchanged
    }
    _ => {
      return Connection{
        state: ConnectionState.Error("Data message requires authentication"),
        socket: conn.socket,
        credentials: conn.credentials
      }
    }
  }
end

// Generic message processor
func process_message(conn: Connection, msg: any) -> Connection do
  // Dispatch based on message type and current state
  return handle_message(conn, msg)
end
```

## Visitor Pattern Alternative

### AST Processing with Dispatch

```janus
// AST processing using multiple dispatch instead of visitor pattern
module ASTProcessing

type ASTNode = sum {
  Literal(LiteralNode),
  Binary(BinaryNode),
  Unary(UnaryNode),
  Variable(VariableNode),
  Function(FunctionNode)
}

type LiteralNode = table {
  value: any
}

type BinaryNode = table {
  operator: string,
  left: ASTNode,
  right: ASTNode
}

type UnaryNode = table {
  operator: string,
  operand: ASTNode
}

type VariableNode = table {
  name: string
}

type FunctionNode = table {
  name: string,
  arguments: []ASTNode
}

// Evaluation dispatch
func evaluate(node: LiteralNode, context: EvalContext) -> any do
  return node.value
end

func evaluate(node: BinaryNode, context: EvalContext) -> any do
  let left_val = evaluate(node.left, context)
  let right_val = evaluate(node.right, context)

  match node.operator {
    "+" => left_val + right_val
    "-" => left_val - right_val
    "*" => left_val * right_val
    "/" => left_val / right_val
    _ => error("Unknown binary operator: {node.operator}")
  }
end

func evaluate(node: UnaryNode, context: EvalContext) -> any do
  let operand_val = evaluate(node.operand, context)

  match node.operator {
    "-" => -operand_val
    "!" => !operand_val
    _ => error("Unknown unary operator: {node.operator}")
  }
end

func evaluate(node: VariableNode, context: EvalContext) -> any do
  return context.get_variable(node.name)
end

func evaluate(node: FunctionNode, context: EvalContext) -> any do
  let args = []
  for arg in node.arguments do
    args.append(evaluate(arg, context))
  end
  return context.call_function(node.name, args)
end

// Pretty printing dispatch
func pretty_print(node: LiteralNode, indent: i32) -> string do
  return "{node.value}"
end

func pretty_print(node: BinaryNode, indent: i32) -> string do
  let left_str = pretty_print(node.left, indent + 2)
  let right_str = pretty_print(node.right, indent + 2)
  return "({left_str} {node.operator} {right_str})"
end

func pretty_print(node: UnaryNode, indent: i32) -> string do
  let operand_str = pretty_print(node.operand, indent + 2)
  return "({node.operator}{operand_str})"
end

func pretty_print(node: VariableNode, indent: i32) -> string do
  return node.name
end

func pretty_print(node: FunctionNode, indent: i32) -> string do
  let args = []
  for arg in node.arguments do
    args.append(pretty_print(arg, indent + 2))
  end
  return "{node.name}({args.join(", ")})"
end

// Type checking dispatch
func type_check(node: LiteralNode, context: TypeContext) -> Type do
  return typeof(node.value)
end

func type_check(node: BinaryNode, context: TypeContext) -> Type do
  let left_type = type_check(node.left, context)
  let right_type = type_check(node.right, context)

  return infer_binary_type(node.operator, left_type, right_type)
end

func type_check(node: UnaryNode, context: TypeContext) -> Type do
  let operand_type = type_check(node.operand, context)
  return infer_unary_type(node.operator, operand_type)
end

func type_check(node: VariableNode, context: TypeContext) -> Type do
  return context.get_variable_type(node.name)
end

func type_check(node: FunctionNode, context: TypeContext) -> Type do
  let arg_types = []
  for arg in node.arguments do
    arg_types.append(type_check(arg, context))
  end
  return context.get_function_return_type(node.name, arg_types)
end

// Usage
func main() do
  // Build AST: (x + 5) * 2
  let ast = BinaryNode{
    operator: "*",
    left: BinaryNode{
      operator: "+",
      left: VariableNode{ name: "x" },
      right: LiteralNode{ value: 5 }
    },
    right: LiteralNode{ value: 2 }
  }

  let eval_context = EvalContext{ variables: { x: 10 } }
  let type_context = TypeContext{ variables: { x: i32 } }

  // Multiple dispatch automatically selects correct implementation
  let result = evaluate(ast, eval_context)        // 30
  let pretty = pretty_print(ast, 0)               // "((x + 5) * 2)"
  let ast_type = type_check(ast, type_context)    // i32

  println("Result: {result}")
  println("Pretty: {pretty}")
  println("Type: {ast_type}")
end
```

## Key Advanced Patterns

1. **Cross-Module Extension**: Function families can span multiple modules for extensible systems
2. **Performance Optimization**: Use static dispatch for hot paths, dynamic for flexibility
3. **Generic Dispatch**: Combine generics with dispatch for powerful abstractions
4. **State Machine Dispatch**: Use dispatch for clean state machine implementations
5. **AST Processing**: Replace visitor pattern with multiple dispatch for cleaner code
6. **Trait-Based Dispatch**: Combine traits with dispatch for flexible generic programming

These advanced patterns demonstrate how multiple dispatch can replace traditional design patterns while providing better performance and cleaner code structure.

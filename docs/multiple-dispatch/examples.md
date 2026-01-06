<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Multiple Dispatch Examples

This document provides comprehensive examples of using the Janus Multiple Dispatch System in various scenarios and use cases.

## Table of Contents

- [Basic Function Families](#basic-function-families)
- [Type Hierarchy Dispatch](#type-hierarchy-dispatch)
- [Mathematical Operations](#mathematical-operations)
- [Serialization System](#serialization-system)
- [Event Handling](#event-handling)
- [Cross-Module Dispatch](#cross-module-dispatch)
- [Runtime Dispatch](#runtime-dispatch)
- [Performance Optimization](#performance-optimization)
- [Error Handling](#error-handling)
- [Advanced Patterns](#advanced-patterns)

## Basic Function Families

### Simple Type-Based Dispatch

```janus
// Basic function family with different parameter types
func format(value: i32) -> string do
  return "{value}"
end

func format(value: f64) -> string do
  return "{value:.2}"
end

func format(value: bool) -> string do
  return if value then "true" else "false"
end

func format(value: string) -> string do
  return "\"{value}\""
end

// Usage
let examples = [
  format(42),        // → "42"
  format(3.14159),   // → "3.14"
  format(true),      // → "true"
  format("hello"),   // → "\"hello\""
]
```

### Arity-Based Dispatch

```janus
// Different number of parameters
func combine(a: string) -> string do
  return a
end

func combine(a: string, b: string) -> string do
  return a ++ " " ++ b
end

func combine(a: string, b: string, c: string) -> string do
  return a ++ " " ++ b ++ " " ++ c
end

func combine(parts: []string) -> string do
  return parts.join(" ")
end

// Usage
let result1 = combine("hello")                    // → "hello"
let result2 = combine("hello", "world")           // → "hello world"
let result3 = combine("hello", "beautiful", "world") // → "hello beautiful world"
let result4 = combine(["one", "two", "three"])    // → "one two three"
```

## Type Hierarchy Dispatch

### Shape Drawing System

```janus
// Base type
type Shape = table {
  x: f64,
  y: f64,
  color: Color
}

// Derived types
type Circle = table extends Shape {
  radius: f64
}

type Rectangle = table extends Shape {
  width: f64,
  height: f64
}

type Triangle = table extends Shape {
  vertices: [3]Point
}

// Function family with specificity
func draw(shape: Shape) -> string do
  return "Drawing generic shape at ({shape.x}, {shape.y})"
end

func draw(circle: Circle) -> string do
  return "Drawing circle: center=({circle.x}, {circle.y}), radius={circle.radius}"
end

func draw(rect: Rectangle) -> string do
  return "Drawing rectangle: origin=({rect.x}, {rect.y}), size={rect.width}x{rect.height}"
end

func draw(triangle: Triangle) -> string do
  let points = triangle.vertices.map(|p| "({p.x}, {p.y})").join(", ")
  return "Drawing triangle: vertices=[{points}]"
end

// Usage - most specific implementation is chosen
let shapes: []Shape = [
  Circle{ x: 0, y: 0, color: .red, radius: 5.0 },
  Rectangle{ x: 10, y: 10, color: .blue, width: 20, height: 15 },
  Triangle{ x: 5, y: 5, color: .green, vertices: [...] }
]

for shape in shapes do
  let description = draw(shape)  // Dispatches to most specific implementation
  print(description)
end
```

## Mathematical Operations

### Comprehensive Math Library

```janus
// Scalar operations
func add(a: i32, b: i32) -> i32 do
  return a + b
end

func add(a: f64, b: f64) -> f64 do
  return a + b
end

func add(a: i32, b: f64) -> f64 do
  return @as(f64, a) + b
end

func add(a: f64, b: i32) -> f64 do
  return a + @as(f64, b)
end

// Complex number operations
type Complex = table {
  real: f64,
  imag: f64
}

func add(a: Complex, b: Complex) -> Complex do
  return Complex{
    real: a.real + b.real,
    imag: a.imag + b.imag
  }
end

func add(a: Complex, b: f64) -> Complex do
  return Complex{
    real: a.real + b,
    imag: a.imag
  }
end

// Vector operations
type Vector2 = table {
  x: f64,
  y: f64
}

type Vector3 = table {
  x: f64,
  y: f64,
  z: f64
}

func add(a: Vector2, b: Vector2) -> Vector2 do
  return Vector2{ x: a.x + b.x, y: a.y + b.y }
end

func add(a: Vector3, b: Vector3) -> Vector3 do
  return Vector3{ x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }
end

// Usage examples
let int_sum = add(5, 3)                    // → 8 (i32)
let float_sum = add(2.5, 1.7)              // → 4.2 (f64)
let mixed_sum = add(5, 2.5)                // → 7.5 (f64)

let c1 = Complex{ real: 1.0, imag: 2.0 }
let c2 = Complex{ real: 3.0, imag: 4.0 }
let complex_sum = add(c1, c2)              // → Complex{ real: 4.0, imag: 6.0 }

let v1 = Vector2{ x: 1.0, y: 2.0 }
let v2 = Vector2{ x: 3.0, y: 4.0 }
let vector_sum = add(v1, v2)               // → Vector2{ x: 4.0, y: 6.0 }
```

## Serialization System

### JSON Serialization with Type-Specific Handling

```janus
// Generic fallback for unknown types
func to_json(value: any) -> string {.dispatch: dynamic.} do
  return "\"<unsupported type: {typeof(value)}>\""
end

// Primitive type serialization
func to_json(value: i32) -> string do
  return "{value}"
end

func to_json(value: f64) -> string do
  return "{value}"
end

func to_json(value: bool) -> string do
  return if value then "true" else "false"
end

func to_json(value: string) -> string do
  // Escape special characters
  let escaped = value
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")
    .replace("\n", "\\n")
    .replace("\r", "\\r")
    .replace("\t", "\\t")
  return "\"{escaped}\""
end

// Array serialization
func to_json(array: []any) -> string do
  let elements = array.map(|item| to_json(item)).join(", ")
  return "[{elements}]"
end

// Object serialization
func to_json(obj: table) -> string do
  let pairs = obj.entries()
    .map(|(key, value)| "{to_json(key)}: {to_json(value)}")
    .join(", ")
  return "{{{pairs}}}"
end

// Custom type serialization
type Person = table {
  name: string,
  age: i32,
  email: ?string
}

func to_json(person: Person) -> string do
  let name_json = to_json(person.name)
  let age_json = to_json(person.age)
  let email_json = to_json(person.email)
  return "{{\"name\": {name_json}, \"age\": {age_json}, \"email\": {email_json}}}"
end

// Usage
let person = Person{
  name: "Alice Johnson",
  age: 30,
  email: some("alice@example.com")
}

let json_output = to_json(person)
// → {"name": "Alice Johnson", "age": 30, "email": "alice@example.com"}
```

## Event Handling

### GUI Event System

```janus
// Base event type
type Event = table {
  timestamp: i64,
  target: ?ElementId
}

// Input events
type MouseEvent = table extends Event {
  x: i32,
  y: i32,
  button: MouseButton,
  modifiers: KeyModifiers
}

type KeyboardEvent = table extends Event {
  key: Key,
  modifiers: KeyModifiers,
  repeat: bool
}

// Generic event handler
func handle_event(event: Event) -> EventResult do
  log.debug("Handling generic event at {event.timestamp}")
  return .continue
end

// Specific event handlers
func handle_event(mouse: MouseEvent) -> EventResult do
  log.info("Mouse {mouse.button} at ({mouse.x}, {mouse.y})")

  return switch mouse.button do
    case .left => handle_left_click(mouse)
    case .right => handle_right_click(mouse)
    case .middle => handle_middle_click(mouse)
  end
end

func handle_event(keyboard: KeyboardEvent) -> EventResult do
  let key_name = keyboard.key.name()
  let modifiers = format_modifiers(keyboard.modifiers)

  log.info("Key pressed: {modifiers}{key_name}")

  if keyboard.modifiers.ctrl and keyboard.key == .c then
    return handle_copy()
  elseif keyboard.modifiers.ctrl and keyboard.key == .v then
    return handle_paste()
  else
    return handle_regular_key(keyboard)
  end
end

// Event processing loop
func process_events(events: []Event) -> void do
  for event in events do
    let result = handle_event(event)  // Dispatches to most specific handler

    if result == .stop then
      break
    end
  end
end
```

## Cross-Module Dispatch

### Math Library Module

**math_core.janus:**
```janus
// Core mathematical operations
export func add(a: i32, b: i32) -> i32 do
  return a + b
end

export func add(a: f64, b: f64) -> f64 do
  return a + b
end

export func multiply(a: i32, b: i32) -> i32 do
  return a * b
end

export func multiply(a: f64, b: f64) -> f64 do
  return a * b
end
```

**vector_math.janus:**
```janus
// Import core math operations
import math_core.{add, multiply}

// Vector types
export type Vector2 = table {
  x: f64,
  y: f64
}

// Extend the add family with vector operations
export func add(a: Vector2, b: Vector2) -> Vector2 do
  return Vector2{
    x: add(a.x, b.x),  // Uses math_core.add(f64, f64)
    y: add(a.y, b.y)
  }
end

// Scalar multiplication
export func multiply(scalar: f64, vector: Vector2) -> Vector2 do
  return Vector2{
    x: multiply(scalar, vector.x),  // Uses math_core.multiply(f64, f64)
    y: multiply(scalar, vector.y)
  }
end
```

**application.janus:**
```janus
// Import all math modules
import math_core.{add, multiply}
import vector_math.{Vector2, add as vec_add, multiply as vec_multiply}

// Application code using cross-module dispatch
func main() -> void do
  // Scalar operations - dispatches to math_core
  let sum = add(5, 3)                    // → math_core.add(i32, i32)
  let product = multiply(2.5, 4.0)       // → math_core.multiply(f64, f64)

  // Vector operations - dispatches to vector_math
  let v1 = Vector2{ x: 1.0, y: 2.0 }
  let v2 = Vector2{ x: 3.0, y: 4.0 }
  let v_sum = add(v1, v2)                // → vector_math.add(Vector2, Vector2)
  let v_scaled = multiply(2.0, v1)       // → vector_math.multiply(f64, Vector2)
end
```

## Runtime Dispatch

### Plugin System

```janus
// Plugin interface
type Plugin = table {
  name: string,
  version: string,
  process: (data: any) -> any
}

// Generic plugin processor with runtime dispatch
func process_with_plugin(plugin: Plugin, data: any) -> any {.dispatch: dynamic.} do
  return plugin.process(data)
end

// Specific plugin implementations
type ImagePlugin = table extends Plugin {
  supported_formats: []string
}

type AudioPlugin = table extends Plugin {
  sample_rate: i32,
  channels: i32
}

// Runtime dispatch based on plugin type
func process_with_plugin(plugin: ImagePlugin, data: ImageData) -> ProcessedImage do
  log.info("Processing image with {plugin.name}")
  return process_image(data, plugin)
end

func process_with_plugin(plugin: AudioPlugin, data: AudioData) -> ProcessedAudio do
  log.info("Processing audio with {plugin.name} at {plugin.sample_rate}Hz")
  return process_audio(data, plugin)
end

// Usage with runtime dispatch
let manager = PluginManager{
  plugins: [],
  active_plugins: table[string, Plugin]{}
}

// Register plugins at runtime
manager.active_plugins["image_processor"] = ImagePlugin{
  name: "Advanced Image Processor",
  version: "1.2.0",
  supported_formats: ["jpg", "png", "gif"],
  process: |data| process_image_data(data)
}

// Process data with runtime dispatch
let image_result = process_data(&manager, "image_processor", image_data)
```

## Performance Optimization

### Hot Path Optimization

```janus
// Performance-critical function with multiple implementations
func calculate_distance(p1: Point2D, p2: Point2D) -> f64 do
  let dx = p1.x - p2.x
  let dy = p1.y - p2.y
  return @sqrt(dx * dx + dy * dy)
end

// Optimized version for integer coordinates
func calculate_distance(p1: IntPoint2D, p2: IntPoint2D) -> f64 do
  let dx = @as(f64, p1.x - p2.x)
  let dy = @as(f64, p1.y - p2.y)
  return @sqrt(dx * dx + dy * dy)
end

// Squared distance when comparison is all that's needed
func calculate_distance_squared(p1: Point2D, p2: Point2D) -> f64 do
  let dx = p1.x - p2.x
  let dy = p1.y - p2.y
  return dx * dx + dy * dy  // Avoids expensive sqrt
end

// Usage in performance-critical code
func find_nearest_point(target: Point2D, candidates: []Point2D) -> ?Point2D do
  if candidates.len == 0 then
    return null
  end

  var nearest = candidates[0]
  var min_distance_sq = calculate_distance_squared(target, nearest)

  for candidate in candidates[1..] do
    let distance_sq = calculate_distance_squared(target, candidate)
    if distance_sq < min_distance_sq then
      min_distance_sq = distance_sq
      nearest = candidate
    end
  end

  return nearest
end
```

## Error Handling

### Graceful Error Handling with Dispatch

```janus
// Error types
type ParseError = union {
  invalid_syntax: string,
  unexpected_token: Token,
  missing_delimiter: char,
  type_mismatch: TypeMismatchInfo
}

// Generic error handling
func handle_parse_error(error: ParseError) -> string do
  return switch error do
    case .invalid_syntax(msg) => "Syntax error: {msg}"
    case .unexpected_token(token) => "Unexpected token: {token.value} at line {token.line}"
    case .missing_delimiter(delim) => "Missing delimiter: '{delim}'"
    case .type_mismatch(info) => "Type mismatch: expected {info.expected}, got {info.actual}"
  end
end

// Specific error handling for different contexts
func handle_parse_error(error: ParseError, context: JsonParseContext) -> string do
  let base_message = handle_parse_error(error)
  return "JSON parsing error at path '{context.path}': {base_message}"
end

func handle_parse_error(error: ParseError, context: XmlParseContext) -> string do
  let base_message = handle_parse_error(error)
  return "XML parsing error in element '{context.element}': {base_message}"
end

// Usage in parser
func parse_document(content: string, context: ParseContext) -> ParseResult(Document) do
  let result = try_parse(content)

  return switch result do
    case .success(doc) => .success(doc)
    case .error(err) => {
      let error_message = handle_parse_error(err, context)
      log.error(error_message)
      return .error(err)
    }
  end
end
```

## Advanced Patterns

### Builder Pattern with Dispatch

```janus
// Builder for different configuration types
type ConfigBuilder = table {
  values: table[string, any]
}

// Generic build method
func build(builder: ConfigBuilder, config_type: type) -> any do
  panic("Unsupported configuration type: {config_type}")
end

// Specific builders
func build(builder: ConfigBuilder, config_type: DatabaseConfig.type) -> DatabaseConfig do
  return DatabaseConfig{
    host: builder.values["host"] as string ?? "localhost",
    port: builder.values["port"] as i32 ?? 5432,
    database: builder.values["database"] as string ?? "default",
    username: builder.values["username"] as string ?? "user",
    password: builder.values["password"] as string ?? "",
    ssl_enabled: builder.values["ssl_enabled"] as bool ?? false
  }
end

func build(builder: ConfigBuilder, config_type: ServerConfig.type) -> ServerConfig do
  return ServerConfig{
    bind_address: builder.values["bind_address"] as string ?? "0.0.0.0",
    port: builder.values["port"] as i32 ?? 8080,
    max_connections: builder.values["max_connections"] as i32 ?? 1000,
    timeout_seconds: builder.values["timeout_seconds"] as i32 ?? 30,
    enable_logging: builder.values["enable_logging"] as bool ?? true
  }
end

// Usage
let builder = ConfigBuilder{ values: table[string, any]{} }
builder.values["host"] = "db.example.com"
builder.values["port"] = 5432
builder.values["database"] = "production"

let db_config = build(builder, DatabaseConfig)  // Dispatches to DatabaseConfig builder
```

### Visitor Pattern with Dispatch

```janus
// AST node types
type AstNode = union {
  literal: LiteralNode,
  binary_op: BinaryOpNode,
  function_call: FunctionCallNode,
  variable: VariableNode
}

type LiteralNode = table {
  value: any,
  type: Type
}

type BinaryOpNode = table {
  left: *AstNode,
  right: *AstNode,
  operator: BinaryOperator
}

// Generic visitor interface
func visit(visitor: any, node: AstNode) -> any {.dispatch: dynamic.} do
  return switch node do
    case .literal(lit) => visit(visitor, lit)
    case .binary_op(bin) => visit(visitor, bin)
    case .function_call(call) => visit(visitor, call)
    case .variable(var) => visit(visitor, var)
  end
end

// Pretty printer visitor
type PrettyPrinter = table {
  indent_level: i32,
  output: StringBuilder
}

func visit(printer: *PrettyPrinter, node: LiteralNode) -> void do
  printer.output.append("{node.value}")
end

func visit(printer: *PrettyPrinter, node: BinaryOpNode) -> void do
  printer.output.append("(")
  visit(printer, node.left.*)
  printer.output.append(" {node.operator} ")
  visit(printer, node.right.*)
  printer.output.append(")")
end

// Usage
let ast = AstNode.binary_op(BinaryOpNode{
  left: &AstNode.variable(VariableNode{ name: "x" }),
  right: &AstNode.literal(LiteralNode{ value: 42, type: .i32 }),
  operator: .add
})

// Pretty print
var printer = PrettyPrinter{ indent_level: 0, output: StringBuilder.init() }
visit(&printer, ast)
let pretty_output = printer.output.to_string()  // → "(x + 42)"
```

---

*These examples demonstrate the power and flexibility of the Janus Multiple Dispatch System. For more information, see the [main documentation](README.md) and [API reference](api-reference.md).*

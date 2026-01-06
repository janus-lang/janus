<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Basic Multiple Dispatch Examples

This document provides fundamental examples of multiple dispatch in Janus, demonstrating core concepts and common patterns.

## Table of Contents

- [Simple Function Families](#simple-function-families)
- [Type-Based Dispatch](#type-based-dispatch)
- [Inheritance Hierarchies](#inheritance-hierarchies)
- [Fallback Implementations](#fallback-implementations)
- [Error Handling](#error-handling)

## Simple Function Families

### Basic Arithmetic Operations

```janus
// Define arithmetic operations for different types
module BasicMath

// Integer arithmetic
func add(a: i32, b: i32) -> i32 do
  return a + b
end

func add(a: i64, b: i64) -> i64 do
  return a + b
end

// Floating-point arithmetic
func add(a: f32, b: f32) -> f32 do
  return a + b
end

func add(a: f64, b: f64) -> f64 do
  return a + b
end

// String concatenation
func add(a: string, b: string) -> string do
  return a ++ b
end

// Usage examples
func main() do
  // Each call resolves to the appropriate implementation
  let int_result = add(5, 3)           // Calls add(i32, i32) -> 8
  let long_result = add(5_i64, 3_i64)  // Calls add(i64, i64) -> 8
  let float_result = add(2.5_f32, 1.7_f32) // Calls add(f32, f32) -> 4.2
  let double_result = add(2.5, 1.7)    // Calls add(f64, f64) -> 4.2
  let string_result = add("Hello", " World") // Calls add(string, string) -> "Hello World"

  println("Integer: {int_result}")
  println("Long: {long_result}")
  println("Float: {float_result}")
  println("Double: {double_result}")
  println("String: {string_result}")
end
```

### Multiple Parameter Dispatch

```janus
// Function family with different arities
module Calculator

// Single parameter - absolute value
func abs(x: i32) -> i32 do
  return if x < 0 then -x else x
end

func abs(x: f64) -> f64 do
  return if x < 0.0 then -x else x
end

// Two parameters - maximum
func max(a: i32, b: i32) -> i32 do
  return if a > b then a else b
end

func max(a: f64, b: f64) -> f64 do
  return if a > b then a else b
end

// Three parameters - clamp
func clamp(value: i32, min: i32, max: i32) -> i32 do
  return if value < min then min else if value > max then max else value
end

func clamp(value: f64, min: f64, max: f64) -> f64 do
  return if value < min then min else if value > max then max else value
end

// Usage
func main() do
  println("abs(-5): {abs(-5)}")           // 5
  println("abs(-3.14): {abs(-3.14)}")     // 3.14
  println("max(10, 20): {max(10, 20)}")   // 20
  println("max(1.5, 2.7): {max(1.5, 2.7)}")  // 2.7
  println("clamp(15, 0, 10): {clamp(15, 0, 10)}")  // 10
  println("clamp(5.5, 0.0, 10.0): {clamp(5.5, 0.0, 10.0)}")  // 5.5
end
```

## Type-Based Dispatch

### Container Operations

```janus
// Operations on different container types
module Containers

// Array operations
func size(arr: []any) -> usize do
  return arr.len
end

func get(arr: []any, index: usize) -> any do
  return arr[index]
end

// String operations
func size(s: string) -> usize do
  return s.len
end

func get(s: string, index: usize) -> u8 do
  return s[index]
end

// Map operations
func size(map: table) -> usize do
  return map.count()
end

func get(map: table, key: string) -> any do
  return map[key]
end

// Usage examples
func main() do
  let numbers = [1, 2, 3, 4, 5]
  let text = "Hello"
  let data = { name: "John", age: 30 }

  // Dispatch based on container type
  println("Array size: {size(numbers)}")    // Calls size([]any)
  println("String size: {size(text)}")       // Calls size(string)
  println("Map size: {size(data)}")          // Calls size(table)

  println("Array[1]: {get(numbers, 1)}")    // Calls get([]any, usize)
  println("String[1]: {get(text, 1)}")       // Calls get(string, usize)
  println("Map['name']: {get(data, 'name')}")  // Calls get(table, string)
end
```

### Type-Specific Formatting

```janus
// Formatting different types for display
module Formatting

// Primitive type formatting
func format(value: i32) -> string do
  return "{value}"
end

func format(value: f64) -> string do
  return "{value:.2f}"
end

func format(value: bool) -> string do
  return if value then "true" else "false"
end

func format(value: string) -> string do
  return "\"{value}\""
end

// Collection formatting
func format(arr: []any) -> string do
  let parts = []
  for item in arr do
    parts.append(format(item))  // Recursive dispatch
  end
  return "[{parts.join(", ")}]"
end

func format(map: table) -> string do
  let parts = []
  for key, value in map do
    parts.append("{format(key)}: {format(value)}")
  end
  return "{{parts.join(", ")}}"
end

// Usage
func main() do
  println(format(42))           // "42"
  println(format(3.14159))      // "3.14"
  println(format(true))         // "true"
  println(format("hello"))      // "\"hello\""
  println(format([1, 2, 3]))    // "[1, 2, 3]"
  println(format({ x: 10, y: 20 }))  // "{\"x\": 10, \"y\": 20}"
end
```

## Inheritance Hierarchies

### Shape Hierarchy

```janus
// Classic shape hierarchy example
module Shapes

// Base shape type
type Shape = table {
  x: f64,
  y: f64
}

// Specific shape types
type Circle = table extends Shape {
  radius: f64
}

type Rectangle = table extends Shape {
  width: f64,
  height: f64
}

type Triangle = table extends Shape {
  base: f64,
  height: f64
}

// Generic shape operations (least specific)
func area(s: Shape) -> f64 do
  // Default implementation - should be overridden
  return 0.0
end

func perimeter(s: Shape) -> f64 do
  // Default implementation
  return 0.0
end

func describe(s: Shape) -> string do
  return "Shape at ({s.x}, {s.y})"
end

// Circle-specific implementations (more specific)
func area(c: Circle) -> f64 do
  return 3.14159 * c.radius * c.radius
end

func perimeter(c: Circle) -> f64 do
  return 2.0 * 3.14159 * c.radius
end

func describe(c: Circle) -> string do
  return "Circle at ({c.x}, {c.y}) with radius {c.radius}"
end

// Rectangle-specific implementations
func area(r: Rectangle) -> f64 do
  return r.width * r.height
end

func perimeter(r: Rectangle) -> f64 do
  return 2.0 * (r.width + r.height)
end

func describe(r: Rectangle) -> string do
  return "Rectangle at ({r.x}, {r.y}) with dimensions {r.width}x{r.height}"
end

// Triangle-specific implementations
func area(t: Triangle) -> f64 do
  return 0.5 * t.base * t.height
end

func perimeter(t: Triangle) -> f64 do
  // Simplified - assumes right triangle
  let hypotenuse = sqrt(t.base * t.base + t.height * t.height)
  return t.base + t.height + hypotenuse
end

func describe(t: Triangle) -> string do
  return "Triangle at ({t.x}, {t.y}) with base {t.base} and height {t.height}"
end

// Usage with polymorphism
func process_shape(shape: Shape) do
  // Dispatch resolves to most specific implementation
  println("Description: {describe(shape)}")
  println("Area: {area(shape)}")
  println("Perimeter: {perimeter(shape)}")
  println("---")
end

func main() do
  let circle = Circle{ x: 0.0, y: 0.0, radius: 5.0 }
  let rectangle = Rectangle{ x: 10.0, y: 10.0, width: 4.0, height: 6.0 }
  let triangle = Triangle{ x: 20.0, y: 20.0, base: 3.0, height: 4.0 }

  // Each call dispatches to the most specific implementation
  process_shape(circle)     // Calls Circle implementations
  process_shape(rectangle)  // Calls Rectangle implementations
  process_shape(triangle)   // Calls Triangle implementations
end
```

## Fallback Implementations

### Serialization with Fallbacks

```janus
// Serialization system with explicit fallbacks
module Serialization

// Specific implementations for common types
func serialize(value: i32) -> string do
  return "{value}"
end

func serialize(value: f64) -> string do
  return "{value}"
end

func serialize(value: bool) -> string do
  return if value then "true" else "false"
end

func serialize(value: string) -> string do
  return "\"{value}\""
end

// Collection serialization
func serialize(arr: []any) -> string do
  let parts = []
  for item in arr do
    parts.append(serialize(item))  // Recursive dispatch
  end
  return "[{parts.join(", ")}]"
end

func serialize(map: table) -> string do
  let parts = []
  for key, value in map do
    parts.append("{serialize(key)}: {serialize(value)}")
  end
  return "{{parts.join(", ")}}"
end

// Explicit fallback for unknown types
func serialize(value: any) -> string do
  // This is the fallback - must be lexically visible
  return "<unknown type: {typeof(value)}>"
end

// Usage
func main() do
  // These use specific implementations
  println(serialize(42))           // "42"
  println(serialize(3.14))         // "3.14"
  println(serialize(true))         // "true"
  println(serialize("hello"))      // "\"hello\""

  // These use collection implementations
  println(serialize([1, 2, 3]))    // "[1, 2, 3]"
  println(serialize({ x: 10 }))    // "{\"x\": 10}"

  // This uses the fallback
  let custom_object = CustomType{}
  println(serialize(custom_object)) // "<unknown type: CustomType>"
end
```

## Error Handling

### Result Types with Dispatch

```janus
// Error handling with multiple dispatch
module ErrorHandling

type Result(T, E) = sum {
  Ok(T),
  Err(E)
}

type ParseError = sum {
  InvalidFormat,
  OutOfRange,
  EmptyInput
}

// Parsing functions that return Results
func parse(input: string) -> Result(i32, ParseError) do
  if input.is_empty() then
    return Result.Err(ParseError.EmptyInput)
  end

  // Simplified parsing logic
  if input.all_digits() then
    let value = input.to_i32()
    if value >= -2147483648 and value <= 2147483647 then
      return Result.Ok(value)
    else
      return Result.Err(ParseError.OutOfRange)
    end
  else
    return Result.Err(ParseError.InvalidFormat)
  end
end

func parse(input: string) -> Result(f64, ParseError) do
  if input.is_empty() then
    return Result.Err(ParseError.EmptyInput)
  end

  // Simplified parsing logic
  if input.is_valid_float() then
    return Result.Ok(input.to_f64())
  else
    return Result.Err(ParseError.InvalidFormat)
  end
end

// Error handling functions
func handle_error(err: ParseError) -> string do
  match err {
    ParseError.InvalidFormat => "Invalid format provided"
    ParseError.OutOfRange => "Value is out of range"
    ParseError.EmptyInput => "Input cannot be empty"
  }
end

func handle_result(result: Result(i32, ParseError)) -> string do
  match result {
    Result.Ok(value) => "Parsed integer: {value}"
    Result.Err(error) => "Error: {handle_error(error)}"
  }
end

func handle_result(result: Result(f64, ParseError)) -> string do
  match result {
    Result.Ok(value) => "Parsed float: {value}"
    Result.Err(error) => "Error: {handle_error(error)}"
  }
end

// Usage
func main() do
  // Integer parsing
  let int_result1 = parse("42")      // Result.Ok(42)
  let int_result2 = parse("invalid") // Result.Err(InvalidFormat)

  println(handle_result(int_result1)) // "Parsed integer: 42"
  println(handle_result(int_result2)) // "Error: Invalid format provided"

  // Float parsing
  let float_result1 = parse("3.14")    // Result.Ok(3.14)
  let float_result2 = parse("")        // Result.Err(EmptyInput)

  println(handle_result(float_result1)) // "Parsed float: 3.14"
  println(handle_result(float_result2)) // "Error: Input cannot be empty"
end
```

## Key Takeaways

1. **Function Families**: Multiple functions with the same name form a family
2. **Type-Based Resolution**: Dispatch selects the most specific matching implementation
3. **Inheritance Awareness**: Subtype relationships are considered during resolution
4. **Explicit Fallbacks**: Use `any` type for catch-all implementations
5. **Compile-Time Resolution**: When types are known, dispatch is resolved at compile time
6. **Error Handling**: Multiple dispatch works naturally with Result and Optional types

These examples demonstrate the fundamental patterns you'll use when working with Janus multiple dispatch. The system provides both power and predictability by making dispatch rules explicit and following clear specificity hierarchies.

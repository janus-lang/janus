<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Multiple Dispatch System - Complete Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Basic Concepts](#basic-concepts)
3. [Usage Patterns](#usage-patterns)
4. [Best Practices](#best-practices)
5. [Common Pitfalls](#common-pitfalls)
6. [Performance Guidelines](#performance-guidelines)
7. [Advanced Features](#advanced-features)
8. [Debugging and Introspection](#debugging-and-introspection)
9. [Cross-Module Dispatch](#cross-module-dispatch)
10. [Examples and Tutorials](#examples-and-tutorials)

## Introduction

The Janus Multiple Dispatch System enables functions to dispatch on all argument types, not just the first. This powerful mechanism allows you to write clean, extensible code for complex type interactions while maintaining Janus's principles of **Syntactic Honesty** and **Revealed Complexity**.

### Key Benefits

- **Clean Code**: Write `collide(sphere, box)` instead of `sphere.collideWith(box)`
- **Extensibility**: Add new type combinations without modifying existing code
- **Performance**: Zero-overhead static dispatch when types are known at compile time
- **Safety**: All ambiguities caught at compile time with clear error messages

### Design Principles

- **Mechanism over Policy**: Provides tools, not decisions
- **Syntactic Honesty**: What you see is what you get - no hidden costs
- **Revealed Complexity**: Hard parts are visible, easy parts are easy

## Basic Concepts

### Function Families

Functions with the same name and arity form a **function family**:

```janus
// These form a function family for "add" with arity 2
func add(x: int, y: int) -> int { x + y }
func add(x: float, y: float) -> float { x + y }
func add(x: string, y: string) -> string { x ++ y }
```

### Dispatch Resolution

When you call a function, the system selects the most specific implementation:

```janus
let result1 = add(5, 10)        // Calls add(int, int)
let result2 = add(3.14, 2.71)   // Calls add(float, float)
let result3 = add("Hello", " World")  // Calls add(string, string)
```

### Specificity Rules

More specific types are preferred over less specific ones:

```janus
type Number = int | float
type SpecificInt = int

func process(x: Number) -> string { "generic number" }
func process(x: SpecificInt) -> string { "specific int" }

let result = process(42)  // Calls process(SpecificInt) - more specific
```

## Usage Patterns

### 1. Mathematical Operations

```janus
// Vector operations with multiple dispatch
func add(a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
func add(a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
func add(a: Matrix2, b: Matrix2) -> Matrix2 { /* matrix addition */ }

// Usage is clean and intuitive
let v2_result = add(vec2_a, vec2_b)
let v3_result = add(vec3_a, vec3_b)
let mat_result = add(matrix_a, matrix_b)
```

### 2. Collision Detection

```janus
// Collision detection between different shape types
func collide(a: Sphere, b: Sphere) -> CollisionInfo { /* sphere-sphere */ }
func collide(a: Sphere, b: Box) -> CollisionInfo { /* sphere-box */ }
func collide(a: Box, b: Sphere) -> CollisionInfo { /* box-sphere */ }
func collide(a: Box, b: Box) -> CollisionInfo { /* box-box */ }

// Symmetric dispatch - order doesn't matter for the API
let collision1 = collide(sphere, box)
let collision2 = collide(box, sphere)  // Different implementation, same API
```

### 3. Serialization

```janus
// Type-specific serialization
func serialize(value: int, writer: Writer) { writer.writeInt(value) }
func serialize(value: string, writer: Writer) { writer.writeString(value) }
func serialize(value: Array[T], writer: Writer) {
    writer.writeLength(value.length)
    for item in value {
        serialize(item, writer)  // Recursive dispatch
    }
}
```

### 4. Visitor Pattern Replacement

```janus
// Instead of traditional visitor pattern
type ASTNode = Expression | Statement | Declaration

func analyze(node: Expression, context: AnalysisContext) -> AnalysisResult {
    // Expression-specific analysis
}

func analyze(node: Statement, context: AnalysisContext) -> AnalysisResult {
    // Statement-specific analysis
}

func analyze(node: Declaration, context: AnalysisContext) -> AnalysisResult {
    // Declaration-specific analysis
}

// Clean usage without visitor boilerplate
for node in ast_nodes {
    let result = analyze(node, context)
}
```

## Best Practices

### 1. Design for Specificity

**Good**: Create clear type hierarchies

```janus
type Shape = Circle | Rectangle | Triangle
type Circle = { radius: float }
type Rectangle = { width: float, height: float }

func area(shape: Shape) -> float {
    // Generic fallback - should rarely be called
    panic("Unknown shape type")
}

func area(circle: Circle) -> float {
    PI * circle.radius * circle.radius
}

func area(rect: Rectangle) -> float {
    rect.width * rect.height
}
```

**Bad**: Flat type hierarchies that cause ambiguity

```janus
// These will be ambiguous for mixed calls
func process(a: TypeA, b: TypeB) -> Result { /* ... */ }
func process(a: TypeB, b: TypeA) -> Result { /* ... */ }

// Calling process(typeA, typeB) vs process(typeB, typeA) is clear,
// but process(union_value, union_value) might be ambiguous
```

### 2. Use Explicit Fallbacks

```janus
// Provide explicit fallbacks for extensibility
func convert(from: any, to: Type) -> any {
    // Generic conversion fallback
    error("No conversion available from {} to {}", typeof(from), to)
}

func convert(from: int, to: Type.String) -> string {
    toString(from)
}

func convert(from: string, to: Type.Int) -> int {
    parseInt(from)
}
```

### 3. Leverage Cross-Module Extension

```janus
// In graphics module
func render(shape: Shape, renderer: Renderer) -> void {
    // Default rendering
}

// In advanced_graphics module - extends the signature
import graphics.{render}

func render(shape: ComplexShape, renderer: AdvancedRenderer) -> void {
    // Advanced rendering for new types
}
```

### 4. Design for Performance

```janus
// Prefer sealed types for static dispatch
type sealed Color = Red | Green | Blue

func blend(a: Color, b: Color) -> Color {
    // Static dispatch - zero overhead
}

// Use open types only when extensibility is needed
type open Drawable = Shape | Text | Image

func draw(item: Drawable, canvas: Canvas) -> void {
    // Runtime dispatch - small overhead
}
```

## Common Pitfalls

### 1. Ambiguous Dispatch

**Problem**: Multiple implementations with same specificity

```janus
type A = { value: int }
type B = { value: int }

func process(a: A, b: B) -> string { "A-B" }
func process(a: B, b: A) -> string { "B-A" }

// This will be ambiguous if we have A|B union types
let mixed: A | B = getUnknownType()
let result = process(mixed, mixed)  // ERROR: Ambiguous dispatch
```

**Solution**: Add more specific implementations or use explicit types

```janus
// Add specific implementations for ambiguous cases
func process(a: A, b: A) -> string { "A-A" }
func process(a: B, b: B) -> string { "B-B" }

// Or use explicit type annotations
let result = process(mixed as A, mixed as B)
```

### 2. Forgetting Symmetric Cases

**Problem**: Only implementing one direction

```janus
func combine(a: TypeA, b: TypeB) -> Result { /* ... */ }
// Missing: func combine(a: TypeB, b: TypeA) -> Result

let result = combine(typeB, typeA)  // ERROR: No matching implementation
```

**Solution**: Implement all necessary combinations

```janus
func combine(a: TypeA, b: TypeB) -> Result { combineAB(a, b) }
func combine(a: TypeB, b: TypeA) -> Result { combineAB(b, a) }  // Delegate to avoid duplication
```

### 3. Over-Specific Implementations

**Problem**: Too many specific cases

```janus
// Too specific - hard to maintain
func format(value: int, precision: 0) -> string { /* ... */ }
func format(value: int, precision: 1) -> string { /* ... */ }
func format(value: int, precision: 2) -> string { /* ... */ }
// ... many more cases
```

**Solution**: Use generic implementations with parameters

```janus
func format(value: int, precision: int) -> string {
    // Single implementation handles all cases
}
```

### 4. Hidden Performance Costs

**Problem**: Unaware of dispatch overhead

```janus
// This looks innocent but might be expensive if types are not sealed
func processMany(items: Array[Drawable]) -> void {
    for item in items {
        process(item)  // Runtime dispatch on every iteration
    }
}
```

**Solution**: Use performance annotations and profiling

```janus
func processMany(items: Array[Drawable]) -> void {
    // Use dispatch profiling to identify hot paths
    @profile_dispatch
    for item in items {
        process(item)
    }
}
```

## Performance Guidelines

### 1. Static vs Dynamic Dispatch

**Static Dispatch (Zero Overhead)**:
- All argument types known at compile time
- Types are sealed
- Single implementation matches

```janus
type sealed Color = Red | Green | Blue

func blend(a: Color, b: Color) -> Color {
    // Static dispatch - compiled to direct function calls
}

let result = blend(Red, Blue)  // Zero overhead
```

**Dynamic Dispatch (Small Overhead)**:
- Argument types not fully known at compile time
- Open types or union types
- Multiple implementations possible

```janus
type open Drawable = Shape | Text | Image

func render(item: Drawable) -> void {
    // Runtime dispatch - small lookup overhead
}
```

### 2. Optimization Strategies

**Use Sealed Types When Possible**:
```janus
// Prefer this
type sealed Operation = Add | Subtract | Multiply | Divide

// Over this (unless extensibility is needed)
type open Operation = Add | Subtract | Multiply | Divide
```

**Profile Hot Paths**:
```janus
// Identify expensive dispatch sites
@profile_dispatch
func hotFunction(items: Array[ProcessableItem]) -> void {
    for item in items {
        process(item)  // This will be profiled
    }
}
```

**Use Compression for Large Signatures**:
```janus
// Large signature groups automatically use compression
// No code changes needed - handled by the system
func render(shape: Shape, material: Material, lighting: Lighting) -> void {
    // System automatically compresses dispatch tables for large signatures
}
```

### 3. Performance Monitoring

**Dispatch Overhead Measurement**:
```janus
import std.profiling.{measureDispatch}

func benchmarkDispatch() -> void {
    let stats = measureDispatch {
        for i in 0..10000 {
            process(getRandomItem())
        }
    }

    println("Average dispatch time: {} ns", stats.averageDispatchTime)
    println("Static dispatch ratio: {:.1}%", stats.staticDispatchRatio * 100)
}
```

**Memory Usage Analysis**:
```janus
import std.profiling.{analyzeDispatchMemory}

func analyzeMemoryUsage() -> void {
    let analysis = analyzeDispatchMemory("process")

    println("Dispatch table size: {} bytes", analysis.tableSize)
    println("Compression ratio: {:.1}%", analysis.compressionRatio * 100)
    println("Cache efficiency: {:.1}%", analysis.cacheEfficiency * 100)
}
```

## Advanced Features

### 1. Effect-Aware Dispatch

```janus
// Dispatch can consider effects
func process(data: Data) -> Result {.pure} {
    // Pure implementation
}

func process(data: Data) -> Result {.io} {
    // I/O implementation - different signature due to effects
}
```

### 2. Generic Dispatch

```janus
// Generic functions participate in dispatch after monomorphization
func convert[T, U](from: T, to: Type[U]) -> U {
    // Generic conversion
}

func convert(from: int, to: Type[string]) -> string {
    // Specific implementation for int -> string
}

let result = convert(42, Type[string])  // Uses specific implementation
```

### 3. Constraint-Based Dispatch

```janus
// Dispatch based on type constraints
func sort[T: Comparable](items: Array[T]) -> Array[T] {
    // Generic sort for comparable types
}

func sort(items: Array[int]) -> Array[int] {
    // Optimized sort for integers
}
```

## Debugging and Introspection

### 1. Dispatch Resolution Queries

```janus
import std.dispatch.{queryDispatch}

func debugDispatch() -> void {
    // Query which implementation would be chosen
    let resolution = queryDispatch("process", [Type[int], Type[string]])

    match resolution {
        case .unique(impl) => println("Would call: {}", impl.signature)
        case .ambiguous(impls) => {
            println("Ambiguous between:")
            for impl in impls {
                println("  - {}", impl.signature)
            }
        }
        case .noMatch => println("No matching implementation")
    }
}
```

### 2. Dispatch Tracing

```janus
import std.dispatch.{traceDispatch}

func traceExample() -> void {
    traceDispatch(true)  // Enable dispatch tracing

    process(someValue)   // This will log dispatch decisions

    traceDispatch(false) // Disable tracing
}
```

### 3. Signature Inspection

```janus
import std.dispatch.{inspectSignature}

func inspectExample() -> void {
    let signature = inspectSignature("process")

    println("Signature: {}", signature.name)
    println("Implementations: {}", signature.implementations.length)

    for impl in signature.implementations {
        println("  {} at {}:{}", impl.signature, impl.location.file, impl.location.line)
    }
}
```

## Cross-Module Dispatch

### 1. Exporting Signatures

```janus
// math_module.jan
export func add(x: int, y: int) -> int { x + y }
export func add(x: float, y: float) -> float { x + y }
```

### 2. Extending Signatures

```janus
// string_module.jan
import math.{add}  // Import existing signature

// Extend with string implementation
func add(x: string, y: string) -> string { x ++ y }
```

### 3. Conflict Resolution

```janus
// When multiple modules define the same signature
import module1.{process}
import module2.{process}  // Potential conflict

// Use qualified calls to disambiguate
let result1 = module1::process(data)
let result2 = module2::process(data)

// Or resolve conflicts explicitly
resolve_conflict("process", prefer: module1)
```

### 4. Module-Specific Implementations

```janus
// graphics_module.jan
func render(shape: Shape, renderer: Renderer) -> void {
    // Basic rendering
}

// advanced_graphics_module.jan
import graphics.{render}

// Add advanced rendering without modifying original module
func render(shape: ComplexShape, renderer: AdvancedRenderer) -> void {
    // Advanced rendering
}
```

## Examples and Tutorials

### Tutorial 1: Building a Calculator

```janus
// Step 1: Define basic operations
func calculate(op: Add, a: float, b: float) -> float { a + b }
func calculate(op: Subtract, a: float, b: float) -> float { a - b }
func calculate(op: Multiply, a: float, b: float) -> float { a * b }
func calculate(op: Divide, a: float, b: float) -> float { a / b }

// Step 2: Add integer optimizations
func calculate(op: Add, a: int, b: int) -> int { a + b }
func calculate(op: Subtract, a: int, b: int) -> int { a - b }
func calculate(op: Multiply, a: int, b: int) -> int { a * b }
func calculate(op: Divide, a: int, b: int) -> int { a / b }

// Step 3: Add string operations
func calculate(op: Add, a: string, b: string) -> string { a ++ b }

// Usage
let result1 = calculate(Add, 5, 3)        // int version: 8
let result2 = calculate(Add, 5.0, 3.0)    // float version: 8.0
let result3 = calculate(Add, "Hello", " World")  // string version: "Hello World"
```

### Tutorial 2: Shape Processing System

```janus
// Step 1: Define shape types
type Circle = { radius: float }
type Rectangle = { width: float, height: float }
type Triangle = { base: float, height: float }

// Step 2: Implement area calculations
func area(circle: Circle) -> float {
    PI * circle.radius * circle.radius
}

func area(rect: Rectangle) -> float {
    rect.width * rect.height
}

func area(triangle: Triangle) -> float {
    0.5 * triangle.base * triangle.height
}

// Step 3: Implement perimeter calculations
func perimeter(circle: Circle) -> float {
    2.0 * PI * circle.radius
}

func perimeter(rect: Rectangle) -> float {
    2.0 * (rect.width + rect.height)
}

func perimeter(triangle: Triangle) -> float {
    // Assuming equilateral for simplicity
    3.0 * triangle.base
}

// Step 4: Add collision detection
func collides(a: Circle, b: Circle) -> bool {
    let distance = sqrt((a.center.x - b.center.x)^2 + (a.center.y - b.center.y)^2)
    distance <= (a.radius + b.radius)
}

func collides(a: Rectangle, b: Rectangle) -> bool {
    // AABB collision detection
    !(a.right < b.left || b.right < a.left || a.bottom < b.top || b.bottom < a.top)
}

func collides(a: Circle, b: Rectangle) -> bool {
    // Circle-rectangle collision
    // Implementation details...
}

func collides(a: Rectangle, b: Circle) -> bool {
    collides(b, a)  // Symmetric - delegate to circle-rectangle
}

// Usage
let shapes = [
    Circle{radius: 5.0},
    Rectangle{width: 10.0, height: 8.0},
    Triangle{base: 6.0, height: 4.0}
]

for shape in shapes {
    println("Area: {}", area(shape))      // Dispatches to correct implementation
    println("Perimeter: {}", perimeter(shape))
}

// Collision detection
if collides(shapes[0], shapes[1]) {
    println("Circle and rectangle collide!")
}
```

### Tutorial 3: Extensible Serialization System

```janus
// Step 1: Define serialization interface
type Writer = {
    writeInt: (int) -> void,
    writeFloat: (float) -> void,
    writeString: (string) -> void,
    writeBytes: (Array[byte]) -> void
}

// Step 2: Implement basic serialization
func serialize(value: int, writer: Writer) -> void {
    writer.writeInt(value)
}

func serialize(value: float, writer: Writer) -> void {
    writer.writeFloat(value)
}

func serialize(value: string, writer: Writer) -> void {
    writer.writeString(value)
}

// Step 3: Add collection serialization
func serialize[T](array: Array[T], writer: Writer) -> void {
    writer.writeInt(array.length)
    for item in array {
        serialize(item, writer)  // Recursive dispatch
    }
}

func serialize[K, V](map: Map[K, V], writer: Writer) -> void {
    writer.writeInt(map.size)
    for (key, value) in map {
        serialize(key, writer)
        serialize(value, writer)
    }
}

// Step 4: Add custom type serialization
type Person = { name: string, age: int, email: string }

func serialize(person: Person, writer: Writer) -> void {
    serialize(person.name, writer)
    serialize(person.age, writer)
    serialize(person.email, writer)
}

// Step 5: Add format-specific serialization
type JsonWriter = Writer & { /* JSON-specific methods */ }
type BinaryWriter = Writer & { /* Binary-specific methods */ }

func serialize(value: Person, writer: JsonWriter) -> void {
    // JSON-specific person serialization
    writer.writeString("{")
    writer.writeString("\"name\":\"" ++ value.name ++ "\",")
    writer.writeString("\"age\":" ++ toString(value.age) ++ ",")
    writer.writeString("\"email\":\"" ++ value.email ++ "\"")
    writer.writeString("}")
}

// Usage
let person = Person{name: "Alice", age: 30, email: "alice@example.com"}
let data = [1, 2, 3, 4, 5]

let jsonWriter = createJsonWriter()
let binaryWriter = createBinaryWriter()

serialize(person, jsonWriter)    // Uses JSON-specific implementation
serialize(person, binaryWriter)  // Uses generic implementation
serialize(data, jsonWriter)      // Uses Array[int] implementation
```

## Conclusion

The Janus Multiple Dispatch System provides a powerful, efficient, and safe way to write polymorphic code. By following the patterns and guidelines in this guide, you can:

- Write clean, extensible code that's easy to understand and maintain
- Achieve excellent performance through static dispatch optimization
- Avoid common pitfalls and ambiguity issues
- Build complex systems that scale well across modules
- Debug and profile dispatch behavior effectively

Remember the core principles:
- **Design for specificity** - create clear type hierarchies
- **Use explicit fallbacks** - provide generic implementations
- **Profile performance** - understand dispatch costs
- **Leverage cross-module extension** - build extensible systems

The dispatch system is designed to grow with your codebase, providing both the flexibility you need for complex domains and the performance you need for production systems.

<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Migration Guide to Janus Multiplepatch

This guide helps developers migrate from other dispatch systems to the Janus Multiple Dispatch System.

## Table of Contents

- [From C++ Function Overloading](#from-c-function-overloading)
- [From Java Method Overloading](#from-java-method-overloading)
- [From Python Single Dispatch](#from-python-single-dispatch)
- [From Julia Multiple Dispatch](#from-julia-multiple-dispatch)
- [From Rust Traits](#from-rust-traits)
- [From Dynamic Languages](#from-dynamic-languages)
- [Common Migration Patterns](#common-migration-patterns)
- [Performance Considerations](#performance-considerations)

## From C++ Function Overloading

### C++ Pattern
```cpp
// C++ function overloading
class MathUtils {
public:
    static int add(int a, int b) {
        return a + b;
    }

    static double add(double a, double b) {
        return a + b;
    }

    static std::string add(const std::string& a, const std::string& b) {
        return a + b;
    }
};

// Usage
auto result1 = MathUtils::add(5, 3);        // int version
auto result2 = MathUtils::add(2.5, 1.7);    // double version
auto result3 = MathUtils::add("Hello", " World");  // string version
```

### Janus Equivalent
```janus
// Janus function family
func add(a: i32, b: i32) -> i32 do
  return a + b
end

func add(a: f64, b: f64) -> f64 do
  return a + b
end

func add(a: string, b: string) -> string do
  return a ++ b
end

// Usage - same syntax, but more powerful resolution
let result1 = add(5, 3)        // → add(i32, i32)
let result2 = add(2.5, 1.7)    // → add(f64, f64)
let result3 = add("Hello", " World")  // → add(string, string)
```

### Key Differences

1. **No class scope required**: Functions can be defined at module level
2. **Cross-module extension**: Function families can span multiple modules
3. **More sophisticated resolution**: Handles type hierarchies and conversions
4. **Runtime dispatch available**: Can dispatch on dynamic types when needed

### Migration Steps

1. **Extract functions from classes:**
```cpp
// C++ - class-based
class Processor {
    static Result process(const IntData& data);
    static Result process(const FloatData& data);
};
```

```janus
// Janus - module-based
func process(data: IntData) -> Result do
  // Implementation
end

func process(data: FloatData) -> Result do
  // Implementation
end
```

2. **Handle template specializations:**
```cpp
// C++ template specialization
template<typename T>
T multiply(T a, T b) { return a * b; }

template<>
Matrix multiply<Matrix>(Matrix a, Matrix b) {
    return a.matmul(b);
}
```

```janus
// Janus - explicit implementations
func multiply(a: i32, b: i32) -> i32 do return a * b end
func multiply(a: f64, b: f64) -> f64 do return a * b end
func multiply(a: Matrix, b: Matrix) -> Matrix do return a.matmul(b) end
```

## From Java Method Overloading

### Java Pattern
```java
// Java method overloading
public class StringUtils {
    public static String format(int value) {
        return String.valueOf(value);
    }

    public static String format(double value) {
        return String.format("%.2f", value);
    }

    public static String format(boolean value) {
        return value ? "true" : "false";
    }

    public static String format(Object value) {
        return value.toString();
    }
}

// Usage
String result1 = StringUtils.format(42);
String result2 = StringUtils.format(3.14159);
String result3 = StringUtils.format(true);
```

### Janus Equivalent
```janus
// Janus function family
func format(value: i32) -> string do
  return "{value}"
end

func format(value: f64) -> string do
  return "{value:.2}"
end

func format(value: bool) -> string do
  return if value then "true" else "false"
end

// Fallback for any type
func format(value: any) -> string {.dispatch: dynamic.} do
  return "{value}"  // Uses built-in string conversion
end

// Usage
let result1 = format(42)
let result2 = format(3.14159)
let result3 = format(true)
```

### Key Differences

1. **No inheritance required**: Java's Object hierarchy not needed
2. **Explicit fallback**: Must explicitly define `any` parameter for catch-all
3. **Better type safety**: No implicit boxing/unboxing
4. **Cross-module support**: Can extend function families across modules

### Migration Steps

1. **Convert static methods to functions:**
```java
// Java
public class Utils {
    public static void process(String data) { ... }
    public static void process(Integer data) { ... }
}
```

```janus
// Janus
func process(data: string) -> void do ... end
func process(data: i32) -> void do ... end
```

2. **Handle inheritance-based dispatch:**
```java
// Java - relies on inheritance
public void handle(Animal animal) { ... }
public void handle(Dog dog) { ... }  // More specific
```

```janus
// Janus - explicit type hierarchy
type Animal = table { name: string }
type Dog = table extends Animal { breed: string }

func handle(animal: Animal) -> void do ... end
func handle(dog: Dog) -> void do ... end  // More specific
```

## From Python Single Dispatch

### Python Pattern
```python
from functools import singledispatch

@singledispatch
def process(data):
    raise NotImplementedError(f"Cannot process {type(data)}")

@process.register
def _(data: int):
    return f"Processing integer: {data}"

@process.register
def _(data: str):
    return f"Processing string: {data}"

@process.register
def _(data: list):
    return f"Processing list with {len(data)} items"

# Usage
result1 = process(42)
result2 = process("hello")
result3 = process([1, 2, 3])
```

### Janus Equivalent
```janus
// Janus multiple dispatch (not limited to single argument)
func process(data: i32) -> string do
  return "Processing integer: {data}"
end

func process(data: string) -> string do
  return "Processing string: {data}"
end

func process(data: []any) -> string do
  return "Processing list with {data.len} items"
end

// Fallback for unhandled types
func process(data: any) -> string {.dispatch: dynamic.} do
  return "Cannot process {typeof(data)}"
end

// Usage - same as Python, but supports multiple arguments
let result1 = process(42)
let result2 = process("hello")
let result3 = process([1, 2, 3])

// Multiple dispatch - not possible in Python's singledispatch
func combine(a: i32, b: string) -> string do
  return "{a}: {b}"
end

func combine(a: string, b: i32) -> string do
  return "{a} ({b})"
end
```

### Key Differences

1. **True multiple dispatch**: Can dispatch on all arguments, not just the first
2. **Compile-time resolution**: Static dispatch when types are known
3. **No decorators needed**: Function families are implicit
4. **Better performance**: No runtime registration overhead

### Migration Steps

1. **Convert single dispatch to function families:**
```python
# Python
@singledispatch
def serialize(obj):
    return str(obj)

@serialize.register
def _(obj: dict):
    return json.dumps(obj)
```

```janus
// Janus
func serialize(obj: any) -> string {.dispatch: dynamic.} do
  return "{obj}"
end

func serialize(obj: table) -> string do
  return to_json(obj)  // Assuming to_json is available
end
```

2. **Extend to multiple dispatch:**
```python
# Python - limited to single argument
@singledispatch
def convert(value, target_type):
    # Can only dispatch on 'value', not 'target_type'
    pass
```

```janus
// Janus - can dispatch on both arguments
func convert(value: i32, target_type: string.type) -> string do
  return "{value}"
end

func convert(value: string, target_type: i32.type) -> i32 do
  return parse_int(value)
end
```

## From Julia Multiple Dispatch

### Julia Pattern
```julia
# Julia multiple dispatch
function add(x::Int64, y::Int64)
    return x + y
end

function add(x::Float64, y::Float64)
    return x + y
end

function add(x::String, y::String)
    return x * y  # String concatenation in Julia
end

# Multiple dispatch on different argument combinations
function process(data::Vector{Int64}, method::Symbol)
    if method == :sum
        return sum(data)
    elseif method == :mean
        return sum(data) / length(data)
    end
end

function process(data::Vector{Float64}, method::Symbol)
    # Similar but for floats
end

# Usage
result1 = add(5, 3)
result2 = add(2.5, 1.7)
result3 = add("Hello", " World")
```

### Janus Equivalent
```janus
// Janus multiple dispatch - very similar to Julia
func add(x: i64, y: i64) -> i64 do
  return x + y
end

func add(x: f64, y: f64) -> f64 do
  return x + y
end

func add(x: string, y: string) -> string do
  return x ++ y  // String concatenation in Janus
end

// Multiple dispatch on different argument combinations
type ProcessMethod = enum { sum, mean }

func process(data: []i64, method: ProcessMethod) -> f64 do
  return switch method do
    case .sum => @as(f64, data.sum())
    case .mean => @as(f64, data.sum()) / @as(f64, data.len)
  end
end

func process(data: []f64, method: ProcessMethod) -> f64 do
  return switch method do
    case .sum => data.sum()
    case .mean => data.sum() / @as(f64, data.len)
  end
end

// Usage - identical to Julia
let result1 = add(5, 3)
let result2 = add(2.5, 1.7)
let result3 = add("Hello", " World")
```

### Key Differences

1. **Static typing**: Janus requires explicit type annotations
2. **Compile-time optimization**: Better static dispatch optimization
3. **Module system**: Different approach to organizing function families
4. **Performance predictability**: More explicit about dispatch costs

### Migration Steps

1. **Add explicit type annotations:**
```julia
# Julia - types can be inferred
function process(data, threshold)
    # Implementation
end
```

```janus
// Janus - explicit types required
func process(data: []f64, threshold: f64) -> []f64 do
  // Implementation
end
```

2. **Handle parametric types:**
```julia
# Julia parametric types
function process(data::Vector{T}) where T <: Number
    # Generic implementation
end
```

```janus
// Janus - explicit implementations for each type
func process(data: []i32) -> ProcessResult do
  // Implementation for i32
end

func process(data: []f64) -> ProcessResult do
  // Implementation for f64
end

// Or use comptime for generics
func process(comptime T: type, data: []T) -> ProcessResult do
  // Generic implementation
end
```

## From Rust Traits

### Rust Pattern
```rust
// Rust trait-based dispatch
trait Display {
    fn display(&self) -> String;
}

impl Display for i32 {
    fn display(&self) -> String {
        self.to_string()
    }
}

impl Display for f64 {
    fn display(&self) -> String {
        format!("{:.2}", self)
    }
}

impl Display for String {
    fn display(&self) -> String {
        format!("\"{}\"", self)
    }
}

// Generic function using trait
fn show<T: Display>(value: T) -> String {
    value.display()
}

// Usage
let result1 = show(42);
let result2 = show(3.14159);
let result3 = show("hello".to_string());
```

### Janus Equivalent
```janus
// Janus function family approach
func display(value: i32) -> string do
  return "{value}"
end

func display(value: f64) -> string do
  return "{value:.2}"
end

func display(value: string) -> string do
  return "\"{value}\""
end

// Generic function using dispatch
func show(value: any) -> string {.dispatch: dynamic.} do
  return display(value)  // Dispatches to appropriate implementation
end

// Or with specific types for better performance
func show(value: i32) -> string do return display(value) end
func show(value: f64) -> string do return display(value) end
func show(value: string) -> string do return display(value) end

// Usage - same as Rust
let result1 = show(42)
let result2 = show(3.14159)
let result3 = show("hello")
```

### Key Differences

1. **No explicit trait definitions**: Function families are implicit
2. **Multiple dispatch**: Can dispatch on multiple arguments
3. **Simpler syntax**: No need for trait bounds or impl blocks
4. **Runtime dispatch available**: Can handle truly dynamic types

### Migration Steps

1. **Convert traits to function families:**
```rust
// Rust trait
trait Serialize {
    fn serialize(&self) -> String;
}

impl Serialize for User {
    fn serialize(&self) -> String {
        // Implementation
    }
}
```

```janus
// Janus function family
func serialize(user: User) -> string do
  // Implementation
end

func serialize(product: Product) -> string do
  // Implementation
end
```

2. **Handle generic constraints:**
```rust
// Rust generic with trait bounds
fn process<T: Clone + Debug>(data: Vec<T>) -> Vec<T> {
    // Implementation
}
```

```janus
// Janus - explicit implementations or comptime generics
func process(data: []User) -> []User do
  // Implementation for User
end

func process(data: []Product) -> []Product do
  // Implementation for Product
end

// Or comptime generic
func process(comptime T: type, data: []T) -> []T do
  // Generic implementation
end
```

## From Dynamic Languages

### JavaScript/Python Pattern
```javascript
// JavaScript - runtime type checking
function format(value) {
    if (typeof value === 'number') {
        return value.toString();
    } else if (typeof value === 'string') {
        return `"${value}"`;
    } else if (typeof value === 'boolean') {
        return value ? 'true' : 'false';
    } else if (Array.isArray(value)) {
        return `[${value.map(format).join(', ')}]`;
    } else {
        return JSON.stringify(value);
    }
}

// Usage
const result1 = format(42);
const result2 = format("hello");
const result3 = format([1, 2, 3]);
```

### Janus Equivalent
```janus
// Janus - compile-time dispatch when possible
func format(value: i32) -> string do
  return "{value}"
end

func format(value: string) -> string do
  return "\"{value}\""
end

func format(value: bool) -> string do
  return if value then "true" else "false"
end

func format(value: []any) -> string do
  let formatted = value.map(|v| format(v)).join(", ")
  return "[{formatted}]"
end

// Fallback for dynamic types
func format(value: any) -> string {.dispatch: dynamic.} do
  return to_json(value)  // Built-in JSON conversion
end

// Usage - same as JavaScript, but with better performance
let result1 = format(42)        // Static dispatch
let result2 = format("hello")   // Static dispatch
let result3 = format([1, 2, 3]) // Static dispatch

// Dynamic dispatch when type is unknown
func format_dynamic(value: any) -> string do
  return format(value)  // Runtime dispatch
end
```

### Key Differences

1. **Compile-time optimization**: Static dispatch when types are known
2. **Type safety**: Catches type errors at compile time
3. **Better performance**: No runtime type checking overhead for static cases
4. **Explicit dynamic dispatch**: Must explicitly opt into runtime dispatch

### Migration Steps

1. **Replace runtime type checking with function families:**
```javascript
// JavaScript - runtime checking
function process(data) {
    if (data instanceof User) {
        // Handle user
    } else if (data instanceof Product) {
        // Handle product
    } else {
        throw new Error("Unknown type");
    }
}
```

```janus
// Janus - compile-time dispatch
func process(data: User) -> Result do
  // Handle user
end

func process(data: Product) -> Result do
  // Handle product
end

// Explicit fallback
func process(data: any) -> Result {.dispatch: dynamic.} do
  panic("Unknown type: {typeof(data)}")
end
```

2. **Handle duck typing:**
```python
# Python - duck typing
def draw(shape):
    shape.draw()  # Assumes shape has draw method
```

```janus
// Janus - explicit interface or function family
type Drawable = trait {
  draw() -> void
}

func draw(shape: Drawable) -> void do
  shape.draw()
end

// Or function family approach
func draw(circle: Circle) -> void do
  // Circle-specific drawing
end

func draw(rectangle: Rectangle) -> void do
  // Rectangle-specific drawing
end
```

## Common Migration Patterns

### Pattern 1: Visitor Pattern Replacement

**Before (Traditional Visitor):**
```java
// Java visitor pattern
interface Visitor {
    void visit(IntNode node);
    void visit(StringNode node);
    void visit(ListNode node);
}

class PrintVisitor implements Visitor {
    public void visit(IntNode node) { ... }
    public void visit(StringNode node) { ... }
    public void visit(ListNode node) { ... }
}
```

**After (Janus Dispatch):**
```janus
// Janus function family
func print_node(node: IntNode) -> void do
  // Print integer node
end

func print_node(node: StringNode) -> void do
  // Print string node
end

func print_node(node: ListNode) -> void do
  // Print list node
end

// Usage is much simpler
func print_ast(nodes: []AstNode) -> void do
  for node in nodes do
    print_node(node)  // Dispatches automatically
  end
end
```

### Pattern 2: Factory Pattern Simplification

**Before (Factory Pattern):**
```java
// Java factory pattern
class ProcessorFactory {
    public static Processor create(DataType type) {
        switch (type) {
            case INT: return new IntProcessor();
            case STRING: return new StringProcessor();
            case FLOAT: return new FloatProcessor();
            default: throw new IllegalArgumentException();
        }
    }
}
```

**After (Janus Dispatch):**
```janus
// Janus direct dispatch
func process(data: IntData) -> Result do
  // Process integer data
end

func process(data: StringData) -> Result do
  // Process string data
end

func process(data: FloatData) -> Result do
  // Process float data
end

// No factory needed - dispatch handles it
```

### Pattern 3: Strategy Pattern Replacement

**Before (Strategy Pattern):**
```java
// Java strategy pattern
interface SortStrategy {
    void sort(int[] array);
}

class QuickSort implements SortStrategy {
    public void sort(int[] array) { ... }
}

class MergeSort implements SortStrategy {
    public void sort(int[] array) { ... }
}

class Sorter {
    private SortStrategy strategy;

    public void setStrategy(SortStrategy strategy) {
        this.strategy = strategy;
    }

    public void sort(int[] array) {
        strategy.sort(array);
    }
}
```

**After (Janus Dispatch):**
```janus
// Janus function family with strategy parameter
type SortStrategy = enum { quick, merge, heap }

func sort(array: []i32, strategy: SortStrategy) -> void do
  return switch strategy do
    case .quick => quick_sort(array)
    case .merge => merge_sort(array)
    case .heap => heap_sort(array)
  end
end

// Or separate implementations
func sort(array: []i32, strategy: QuickSortStrategy) -> void do
  // Quick sort implementation
end

func sort(array: []i32, strategy: MergeSortStrategy) -> void do
  // Merge sort implementation
end
```

## Performance Considerations

### Static vs Dynamic Dispatch

**Static Dispatch (Preferred):**
```janus
// Types known at compile time - zero overhead
func process_data(data: KnownType) -> Result do
  // Implementation
end

let result = process_data(known_data)  // Direct function call
```

**Dynamic Dispatch (When Necessary):**
```janus
// Types not known at compile time - small overhead
func process_data(data: any) -> Result {.dispatch: dynamic.} do
  // Implementation
end

let result = process_data(unknown_data)  // Table lookup + indirect call
```

### Migration Performance Tips

1. **Prefer static dispatch:**
   - Use specific types when possible
   - Avoid `any` parameters unless necessary
   - Let the compiler optimize

2. **Profile after migration:**
   - Measure dispatch overhead
   - Identify hot paths
   - Optimize critical sections

3. **Use batch processing:**
   - Process multiple items together
   - Reduce dispatch overhead
   - Improve cache locality

---

*For more detailed information about specific features, see the [main documentation](README.md), [API reference](api-reference.md), and [examples](examples.md).*

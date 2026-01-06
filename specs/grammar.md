<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Grammar Specification v0.1.1-dev

**Version:** 0.1.1-dev (CANONICAL)
**Status:** CANONICAL - Single Source of Truth
**Last Updated:** 2025-09-30
**Authority:** Language Architecture Team

---

## Design Philosophy

The Janus programming language embodies the principle of **Fluent Syntax, Honest Semantics**. The grammar is the human interface to the type system and runtime beneath. It must be a pleasure to read and write while always telling the truth about the underlying operations.

Janus code should feel like composing ideas or sending messages, not just issuing machine instructions. This fluency must **never** come at the cost of honesty.

---

## Profile System

Janus ships with **profiles** — enforcement modes that share the same parser/semantics core but gate surface area and features:

* **`:core`** — the **Teaching Subset** (6 value types, 18 keywords). For bootstrapping, teaching, and safe scripting.
* **`:cluster`** — **Actor-based profile** with Janus syntax and Distributed Logic.
* **`:sovereign`** — the **complete Janus**: effects & capabilities, systems programming.
* **`:compute`** — **Native Compute**: tensors, graph IR, acceleration (orthogonal to resilience concerns).

> One brain, many faces: all modes run on `libjanus`; the daemon/LSP and CLI just toggle a profile flag.

---

## Core Keywords (All Profiles)

### Declarations & Control Flow
```
func, let, var,
if, else, for, while,
match, when,
return, break, continue,
enum
```

### Block Delimiters
```
do, end, {, }
```

### Capability & Effects
```
cap, with, using
```

### Profile-Specific Keywords
* **:cluster**: `actor`, `spawn`
* **:sovereign**: `comptime`, `yield`

---

## `:core` Profile Grammar (v2.0.0)

The teaching subset with minimal complexity.

### Types (6 total)
```
i32, f64, bool, string, void, never
```

### Core Grammar Rules

#### 1. Declarations
```janus
let name: string = "Janus"  // Explicit type
let version := 1.0          // Inferred f64
var counter := 0            // Mutable integer
```

#### 2. Functions
```janus
func get_version -> string {
    return "Janus v0.1.0"
}

func add(a: i32, b: i32) -> i32 {
    return a + b
}
```

#### 3. Control Flow
```janus
if user.is_admin() do
    log.info "Admin access granted"
else
    log.warn "Access denied"
end

for item in items do
    process item
end

while condition do
    work()
end
```

#### 4. Pattern Matching
```janus
match value do
    0 => "zero"
    x when x < 0 => "negative"
    _ => "positive"
end
```

#### 5. Algebraic Data Types (Tagged Unions)
```janus
// Define enums with Ruby elegance
enum NetworkState {
    Disconnected,
    Connecting(u8),
    Connected { ip: String, port: u16 },
    Error(String),
}

// Pattern matching with Python's clarity
match state {
    .Disconnected => print("Not connected"),
    .Connecting(attempt) => print("Attempt: " + attempt),
    .Connected { ip, port } => print("Connected to: " + ip + ":" + port),
    .Error(msg) => print("Error: " + msg),
}

// Generic enums
enum Option<T> {
    Some(T),
    None,
}

enum Result<T, E> {
    Ok(T),
    Err(E),
}

// Nested patterns
match response {
    .Ok(.Some(data)) => process_data(data),
    .Ok(.None) => use_default(),
    .Err(error) => handle_error(error),
}

// Query desugared representation for transparency
// $ janus query desugar NetworkState
// Reveals: tag enum + union + memory layout
```

---

## Syntax Laws (Honesty Guards)

These rules ensure the syntax honestly reflects underlying operations:

1. **Property vs Call**
   - `obj.field` = **field access only** (cheap)
   - `obj.method()` = **function call** (potentially expensive)
   - Bare `obj.method` (no args, no block) is a **function value**, not a call

2. **Blocks vs Table literals**
   - `{ |…| … }` = **block** (single-line)
   - `do |…| … end` = **block** (multi-line)
   - `{ … }` **without** leading `|` is **always a Table literal**

3. **Optional parentheses**
   - Parentheses are optional **only** when you pass args or a trailing block
   - Zero-arg calls **must** use `()`: `user.deactivate()`

4. **Operators are minimal & not overloadable**
   - Arithmetic/comparison/boolean are fixed (`+ - * / % == != < <= > >= and or not`)
   - No ad-hoc operator overloading

---

## Lexical Grammar (PEG/EBNF)

### Tokens
```peg
WS          <- [ \t\r\n]+
COMMENT     <- '//' [^\n]* / '/*' (!'*/' .)* '*/'
IDENT       <- [_A-Za-z][_A-Za-z0-9]*
INT         <- '0' | [1-9][0-9]*
FLOAT       <- [0-9]+ '.' [0-9]+ ( [eE] [+\-]? [0-9]+ )?
STRING      <- '"' ( '\\"' | '\\n' | '\\t' | !'"' . )* '"'

KEYWORDS    <- 'let'/'var'/'func'/'if'/'else'/'for'/'while'/'match'
             / 'when'/'do'/'end'/'return'/'break'/'continue'
             / 'and'/'or'/'not'/'true'/'false'/'enum'

KW_COMPUTE      <- 'tensor'/'stream'/'event'/'on'

# Contextual keywords (:compute)
#   • KW_COMPUTE tokens MUST be emitted so parsers can branch without guessing.
#   • Outside :compute they fall back to IDENT; the frontend rejects them with
#     profile-aware diagnostics that point to docs/specs/profile-compute.md.
```

### Expressions
```peg
expr        <- or_expr
or_expr     <- and_expr ( 'or' and_expr )*
and_expr    <- eq_expr ( 'and' eq_expr )*
eq_expr     <- rel_expr ( ('==' | '!=') rel_expr )*
rel_expr    <- add_expr ( ('<' | '<=' | '>' | '>=') add_expr )*
add_expr    <- mul_expr ( ('+' | '-') mul_expr )*
mul_expr    <- unary_expr ( ('*' | '/' | '%') unary_expr )*
unary_expr  <- ('not' | '-') unary_expr / primary
primary     <- IDENT / INT / FLOAT / STRING / '(' expr ')'

## :compute Profile Grammar Extensions (Contextual)

```peg
# Extend the base grammar with the following productions ONLY when :compute is active.
# Existing rules (e.g., simple_type, postfix, toplevel_decl) retain their
# original semantics; they simply gain the listed alternatives.

tensor_type        <- 'tensor' '<' scalar_type ',' tensor_dims '>'
tensor_dims        <- tensor_dim ('x' tensor_dim)*
tensor_dim         <- INT / IDENT                  # compile-time ints or named consts

memspace_qualifier <- 'on' memspace
memspace           <- 'sram' / 'dram' / 'vram' / 'host'
qualified_type     <- simple_type [ memspace_qualifier ]

device_hint        <- 'on' 'device' '(' IDENT ')'
stream_decl        <- 'stream' IDENT device_hint NL
event_decl         <- 'event' IDENT NL

# Grammar adjustments applied with the above productions:
#   • simple_type gains a leading `tensor_type` alternative.
#   • Types may carry an optional `memspace_qualifier`.
#   • postfix (expression suffix) accepts `device_hint`.
#   • toplevel_decl accepts `stream_decl` and `event_decl`.

Notes:
- The above forms must only be accepted when :compute is enabled.
- Outside :compute, usage must produce deterministic, profile-aware diagnostics.
```

Example (:compute only)
```janus
stream s on device(compute)
event ready
let weights: tensor<f16, 512 x 512> on sram
let out := forward(inputs) on device(compute)
record ready, s
await ready
```

### Declarations
```peg
toplevel_decl <- func_decl / const_decl / var_decl / enum_decl

func_decl   <- 'func' IDENT param_list? ret_type? block
const_decl  <- 'let' IDENT ( ':' type )? '=' expr
var_decl    <- 'var' IDENT ( ':' type )? '=' expr
enum_decl   <- 'enum' IDENT generic_params? '{' enum_variants '}'

param_list  <- '(' param (',' param)* ')'
param       <- IDENT ':' type
ret_type    <- '->' type
generic_params <- '<' IDENT (',' IDENT)* '>'

enum_variants <- enum_variant (',' enum_variant)* ','?
enum_variant <- IDENT variant_payload?
variant_payload <- '(' type_list ')' / '{' struct_fields '}'
type_list   <- type (',' type)*
struct_fields <- struct_field (',' struct_field)* ','?
struct_field <- IDENT ':' type
```

### Statements
```peg
stmt        <- simple_stmt / block_stmt
simple_stmt <- assign / return / expr
block_stmt  <- if_stmt / for_stmt / while_stmt / match_stmt

if_stmt     <- 'if' expr block ( 'else' block )?
for_stmt    <- 'for' IDENT 'in' expr block
while_stmt  <- 'while' expr block
match_stmt  <- 'match' expr '{' match_arms '}'

match_arms  <- match_arm (',' match_arm)* ','?
match_arm   <- pattern guard? '=>' (block / expr)
guard       <- 'when' expr

pattern     <- variant_pattern / literal / IDENT / '_'
variant_pattern <- '.' IDENT destructure?
destructure <- '(' identifier_list ')' / '{' field_destructure_list '}'
identifier_list <- IDENT (',' IDENT)*
field_destructure_list <- field_destructure (',' field_destructure)*
field_destructure <- IDENT (':' IDENT)?

block       <- 'do' stmt* 'end'
assign      <- IDENT '=' expr
return      <- 'return' expr?
```

---

## Implementation Requirements

### Parser Architecture
- **ASTDB-first**: Parse directly into immutable, content-addressed AST database
- **Profile-aware**: Validate constructs against active profile (`:core`, `:cluster`, `:sovereign`)
- **Error recovery**: Continue parsing after errors to provide comprehensive diagnostics
- **Zero-copy**: Minimize allocations during parsing

### Testing Requirements
- **100% grammar coverage**: Every construct must have tests
- **Profile validation**: Ensure profile restrictions are enforced
- **Error cases**: Test malformed input and recovery
- **Performance**: Sub-millisecond parsing for typical files

---

## Version History

- **Target v2.0.0**: Canonical Spec with `:core`, `:service`, `:cluster`, `:compute`, `:sovereign`

---

This specification is the **single source of truth** for Janus grammar. All parser implementations must conform to this specification.


---

## Algebraic Data Types: Ruby Elegance Meets Python Zen

### The Philosophy

Janus ADTs embody the best of both worlds:
- **Ruby's Elegance**: Readable syntax that flows like natural language
- **Python's Zen**: Simple is better than complex, explicit is better than implicit
- **Janus's Honesty**: Revealed complexity through `janus query desugar`

### Basic Enum Declaration

```janus
// Simple enums: clean and obvious
enum Color {
    Red,
    Green,
    Blue,
}

// With payloads: tuple style (Python-like)
enum Message {
    Quit,
    Move(i32, i32),
    Write(String),
}

// With payloads: struct style (Ruby-like)
enum NetworkState {
    Disconnected,
    Connecting(u8),
    Connected { ip: String, port: u16 },
    Error(String),
}
```

### Pattern Matching: Readable as Prose

```janus
// Ruby-style elegance
match state {
    .Disconnected => reconnect(),
    .Connecting(attempt) => {
        log.info("Connection attempt", count: attempt)
        wait_for_connection()
    },
    .Connected { ip, port } => {
        log.info("Connected", ip: ip, port: port)
        start_communication()
    },
    .Error(msg) => {
        log.error("Connection failed", error: msg)
        handle_error(msg)
    },
}

// Python-style clarity with guards
match token {
    .Number(n) when n > 0 => handle_positive(n),
    .Number(n) when n < 0 => handle_negative(n),
    .Number(0) => handle_zero(),
    .String(s) when s.len() > 0 => handle_string(s),
    else => reject("invalid token"),
}
```

### Generic Enums: Type Safety Without Ceremony

```janus
// Option type: Python's simplicity
enum Option<T> {
    Some(T),
    None,
}

// Result type: Rust's safety, Ruby's readability
enum Result<T, E> {
    Ok(T),
    Err(E),
}

// Using generics naturally
func find_user(id: i32) -> Result<User, DatabaseError> {
    let user = database.query("SELECT * FROM users WHERE id = ?", id)

    match user {
        .Some(u) => Result.Ok(u),
        .None => Result.Err(DatabaseError.NotFound),
    }
}

// Nested patterns: clear intent
match find_user(42) {
    .Ok(user) => print("Found: " + user.name),
    .Err(.NotFound) => print("User not found"),
    .Err(.ConnectionFailed) => print("Database error"),
}
```

### The Doctrine of Revealed Complexity

```janus
// The elegant syntax
enum State {
    Idle,
    Running(u32),
    Stopped { reason: String },
}

// The honest truth (via `janus query desugar State`)
//
// const StateTag = enum(u8) {
//     Idle = 0,
//     Running = 1,
//     Stopped = 2,
// };
//
// const StatePayload = union {
//     Idle: void,
//     Running: u32,
//     Stopped: struct { reason: String },
// };
//
// struct State {
//     tag: StateTag,
//     payload: StatePayload,
// };
//
// Memory layout:
// Total size: 24 bytes (tag: 1 byte, padding: 7 bytes, union: 16 bytes)
// Alignment: 8 bytes
// Largest variant: Stopped (String = ptr + len = 16 bytes)

// The lesson: You see the cost. No surprises.
```

### Exhaustiveness: Safety Without Noise

```janus
// Compile-time exhaustiveness checking (:service profile)
enum Status {
    Pending,
    Running,
    Complete,
    Failed,
}

// ❌ Compile error: non-exhaustive
func handle_status(status: Status) {
    match status {
        .Pending => print("Pending"),
        .Running => print("Running"),
        // Missing: .Complete, .Failed
    }
}
// Error E3010: Match expression is not exhaustive.
// Missing variants: Complete, Failed
// Suggestion: Add missing variant patterns or use 'else' clause

// ✅ Fixed with else
func handle_status(status: Status) {
    match status {
        .Pending => print("Pending"),
        .Running => print("Running"),
        else => print("Other"),
    }
}
```

### Sentinel Mode: Development Safety

```janus
// In :script profile, automatic runtime validation
enum State {
    Idle,
    Running(u32),
}

func unsafe_access(state: State) {
    // Sentinel Mode injects runtime check
    let pid = state.payload.Running  // Validated at runtime
}

// If tag is wrong:
// Sentinel: Type Confusion
//   Expected variant: Running
//   Actual discriminator: 0 (Idle)
//   Location: app.jan:42:15
```

### Real-World Example: HTTP Response

```janus
// Define response types with clarity
enum HttpResponse {
    Ok { body: String, headers: Map<String, String> },
    Redirect { location: String, permanent: bool },
    ClientError { code: i32, message: String },
    ServerError { code: i32, details: String },
}

// Handle responses with elegance
func handle_response(response: HttpResponse) {
    match response {
        .Ok { body, headers } => {
            log.info("Success", size: body.len())
            process_body(body, headers)
        },
        .Redirect { location, permanent } => {
            let status = if permanent { 301 } else { 302 }
            log.info("Redirect", to: location, status: status)
            follow_redirect(location)
        },
        .ClientError { code, message } => {
            log.warn("Client error", code: code, msg: message)
            show_error_page(code, message)
        },
        .ServerError { code, details } => {
            log.error("Server error", code: code, details: details)
            retry_request()
        },
    }
}
```

### Recursive Enums: Trees and Lists

```janus
// Binary tree with Ruby elegance
enum Tree<T> {
    Leaf(T),
    Node { value: T, left: Box<Tree<T>>, right: Box<Tree<T>> },
}

// Linked list with Python clarity
enum List<T> {
    Cons(T, Box<List<T>>),
    Nil,
}

// Pattern matching on recursive structures
func sum_tree(tree: Tree<i32>) -> i32 {
    match tree {
        .Leaf(value) => value,
        .Node { value, left, right } => {
            value + sum_tree(*left) + sum_tree(*right)
        },
    }
}

func list_length<T>(list: List<T>) -> i32 {
    match list {
        .Nil => 0,
        .Cons(_, tail) => 1 + list_length(*tail),
    }
}
```

### Profile Integration

```janus
// :core profile - explicit everything
const StateTag = enum(u8) { Idle, Running }
const StatePayload = union { Idle: void, Running: u32 }
struct State { tag: StateTag, payload: StatePayload }

// :script profile - ergonomic with Sentinel Mode
enum State { Idle, Running(u32) }
let state = State.Running(42)
let pid = state.payload.Running  // Runtime check injected

// :service profile - compile-time safety
enum State { Idle, Running(u32) }
match state {
    .Idle => handle_idle(),
    .Running(pid) => handle_running(pid),
    // Exhaustiveness enforced at compile time
}

// :sovereign profile - capability integration
enum FileOp {
    Read { path: String, cap: CapFsRead },
    Write { path: String, data: String, cap: CapFsWrite },
}
```

---

## Design Principles Summary

1. **Ruby's Elegance**: Syntax reads like natural language
2. **Python's Zen**: Simple, explicit, obvious
3. **Janus's Honesty**: Costs are visible via `janus query desugar`
4. **Rust's Safety**: Exhaustiveness checking, tag validation
5. **Zero-Cost Abstractions**: Sentinel Mode has no overhead when disabled

**The Result**: A language where safety feels natural, not burdensome.

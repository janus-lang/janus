<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# SPEC-017: Janus Language Grammar Specification

**Status**: Active
**Version**: 1.1.0
**Date**: 2026-01-25
**Supersedes**: specs/legacy/syntax.md

The **Janus Surface Grammar v1.1.0 (Immutable Lock-in)** — hardened for a decade of evolution. This specification prioritizes **comprehension over keystrokes** and **predictability over flexibility**, based on cognitive science and human factors engineering.

---

## Non-Negotiable Syntax Laws (Honesty Guards)

These rules are **IMMUTABLE** and ensure the syntax honestly reflects underlying operations with zero ambiguity.

### Law 1: The Command/Call Bifurcation

This is the defining grammar rule for Janus. It eliminates "micro-decision fatigue."

#### Rule A: Expression Calls (Parentheses MANDATORY)
If a function call returns a value used in an expression, **parentheses are mandatory**.
- *Why:* Mathematical precision. `a + f b` is visually ambiguous. `a + f(b)` is indisputable.
- **Correct:** `let x = math.sin(val)`
- **Correct:** `let y = a + calculate(b, c)`
- **Invalid:** `let x = math.sin val` ❌

#### Rule B: Command Statements (Parentheses OPTIONAL)
If a function call is a top-level statement (return value ignored or void), **parentheses are optional**.
- *Why:* Ergonomics for DSLs and logging. `log.info` reads as a verb.
- **Correct:** `log.info "System started", port: 8080`
- **Correct:** `file.write data`
- **Correct:** `sys.exit(1)` (Parentheses always allowed)

#### Rule C: The Zero-Arg Law
A call with **zero arguments** MUST use `()`, regardless of context.
- *Why:* Distinguishes `user.save()` (action) from `user.name` (property access).
- **Correct:** `cleanup()`
- **Correct:** `timer.start()`
- **Invalid:** `cleanup` ❌ (This is a function *value*, not a call)

---

### Law 2: The Structural Divide (`do..end` vs `{}`)

We codify the psychological separation of "Doing" vs "Defining" for visual parsing.

| Context | Delimiter | Shape Goal |
|:--------|:----------|:-----------|
| `if`, `else`, `while`, `for`, `using`, `func body` | `do..end` | Vertical, linear, imperative flow |
| `match`, `enum`, `struct`, `flags`, table/map literals | `{ }` | Contained, set-based, declarative |

- **Imperative Flow** creates a vertical "tunnel" shape.
- **Declarative Structure** creates a "container" shape.

---

### Law 3: Property vs Call (Zero-Arg)
- `obj.field` = **field access only** (cheap, no side effects)
- A **call** requires `()` OR at least one argument OR a trailing block.
- Bare `obj.method` (no args, no block) is a **function value**, not a call.

---

### Law 4: Operators are Minimal & Non-Overloadable
- Arithmetic/comparison/boolean are fixed (`+ - * / % == != < <= > >= and or not`)
- No ad-hoc operator overloading. Use named methods: `vec.add(a, b)`
- **RESERVED OPERATORS** (not valid in base profiles):
  - `||` — Reserved for **parallel range iteration** in `:compute` profile
  - `&&` and `!` — NOT valid; use `and`, `or`, `not` keywords instead

---

### Law 5: Keywords as Named Arguments (Smalltalk Flavor)
- `writer.write data, to: file, mode: "append"` — readable, no symbol soup.

---

### Law 6: Logical vs Structural Operators
- `and`, `or`, `not` are for **Boolean Control Flow**.
- `?.`, `??` are for **Structural Data Access** (Null/Option handling).
- *Reasoning: Strict separation avoids the "JavaScript Trap" of truthy/falsy coercion.*

---

### Law 7: Attributes are Static Metadata
- Syntax: `{. inline, export .}`
- *Reasoning: Avoids `@attr` (Python) and `#[attr]` (Rust noise).*

---

### Law 8: Match uses Curly Braces ONLY
- `match expr { ... }` is the ONLY valid syntax.
- *Reasoning: Match is declarative unpacking. `{}` aligns with enum/struct definition.*

---

### Law 9: Approved Ergonomic Sugar (Final List)

These are the ONLY syntactic sugars. No others will be added post-1.0.

1.  **Error Propagation:** `?` suffix (Rust-style). `let val = fallible()?`
2.  **Null Coalescing:** `val ?? default`
3.  **Optional Chaining:** `obj?.prop` (Short-circuits to null)
4.  **String Interpolation:** `$"Value: {x}"` (Compile-time validated)
5.  **Pipeline:** `data |> transform()` (Left-to-right composition)



## Core Grammar (Concise PEG/EBNF)

### Lexical Elements

```peg
WS          <- [ \t\r\n]+
COMMENT     <- '//' [^\n]* / '/*' (!'*/' .)* '*/'
IDENT       <- [_A-Za-z][_A-Za-z0-9]*
INT         <- HEX_INT / BIN_INT / OCT_INT / DEC_INT
DEC_INT     <- '0' | [1-9][0-9_]*
HEX_INT     <- '0' [xX] [0-9a-fA-F_]+
BIN_INT     <- '0' [bB] [01_]+
OCT_INT     <- '0' [oO] [0-7_]+
FLOAT       <- [0-9_]+ '.' [0-9_]+ ( [eE] [+\-]? [0-9_]+ )?
             / [0-9_]+ [eE] [+\-]? [0-9_]+
STRING      <- '"' ( '\\"' | '\\n' | '\\t' | !'"' . )* '"'
DOC         <- '///' [^\n]*

KW          <- 'let'/'var'/'func'/'type'/'if'/'else'/'for'/'in'/'match'
             / 'do'/'end'/'return'/'comptime'/'export'/'import'
             / 'and'/'or'/'not'/'true'/'false'/'null'
             / 'with'/'using'/'while'/'where'/'when'/'as'/'use'/'enum'/'flags'
             / 'yield'/'test'/'spec'/'assert'


KW_NPU      <- 'tensor'/'stream'/'event'/'on'

# Profile-gated contextual keywords (:compute)
#   • KW_NPU tokens MUST be emitted by the lexer so the parser can enforce
#     guardrails without guessing about identifiers.
#   • Outside :compute they behave as IDENT; the frontend must emit deterministic,
#     profile-aware diagnostics on usage.
```

### Module Structure

```peg
module      <- { import_decl } { toplevel_decl }
import_decl <- 'import' import_path ( 'as' IDENT )? NL
import_path <- STRING / IDENT ( '::' IDENT )*
```

### Top-Level Declarations

```peg
toplevel_decl <- const_decl / var_decl / func_decl / type_decl / enum_decl / test_decl / spec_decl / graft_decl / foreign_decl / comptime_block

const_decl  <- 'let' IDENT ( ':' type )? ':=' expr NL
             / 'let' IDENT ':' type '=' expr NL
var_decl    <- 'var' IDENT ( ':' type )? ':=' expr NL
func_decl   <- attr? 'func' IDENT param_list? ret_type? where_clause? contract_block? block
             / attr? 'func' IDENT param_list? ret_type? capability_clause? contract_block? block
type_decl   <- 'type' IDENT '=' type NL
enum_decl   <- 'enum' IDENT generic_params? '{' enum_variants '}'

# === PROBATIO: Integrated Verification ===
# Tests and specs are first-class top-level declarations (Amendment 1).
# Uses 'do..end' because they contain imperative logic (Law 2).
test_decl   <- 'test' STRING block                    # Unit test: test "name" do ... end
spec_decl   <- 'spec' STRING block                    # BDD spec: spec "name" do ... end

graft_decl  <- 'graft' IDENT '=' ident_token string_literal NL
foreign_decl <- 'foreign' ident_token 'as' IDENT do_block
ret_type    <- '->' type
param_list  <- '(' [ param (',' param)* ] ')'
param       <- IDENT ':' type
generic_params <- '<' IDENT (',' IDENT)* '>'

# Attributes
attr        <- '{.' attr_item (',' attr_item)* '.}'
attr_item   <- IDENT ( ':' attr_value )?
attr_value  <- STRING / INT / IDENT / '{' ( attr_value (',' attr_value)* )? '}'

# Capabilities
capability_clause <- 'with' 'ctx' 'where' 'ctx.has' capability_set
capability_set    <- '(' capability (',' capability)* ')'
capability        <- '.' IDENT
```


### Types (Essentials)

```peg
type        <- simple_type ( '|' simple_type )*            # sums
simple_type <- IDENT [ '<' type (',' type)* '>' ]          # generics
             / '{' row_fields '}'                          # shape
row_fields  <- ( field ':' type ) ( ',' field ':' type )* [ '|' IDENT ]?
field       <- IDENT
```

### Algebraic Data Types (Tagged Unions)

```peg
enum_decl   <- 'enum' IDENT generic_params? '{' enum_variants '}'
enum_variants <- enum_variant (',' enum_variant)* ','?
enum_variant <- IDENT variant_payload?

variant_payload <-
    | '(' type_list ')'           # Tuple variant: Connecting(u8, String)
    | '{' struct_fields '}'       # Struct variant: Connected { ip: String }

type_list   <- type (',' type)*
struct_fields <- struct_field (',' struct_field)* ','?
struct_field <- IDENT ':' type
```

### Statements & Blocks

```peg
block       <- 'do' ( '|' param_list? '|' )? stmts 'end'
stmts       <- { stmt }
stmt        <- simple_stmt NL / block_stmt

block_stmt  <- if_stmt / for_stmt / match_stmt / block
if_stmt     <- 'if' expr block [ 'else' block ]?
for_stmt    <- 'for' IDENT 'in' expr block

# MONASTERY FREEZE: Match uses ONLY curly braces
match_stmt  <- 'match' expr '{' match_arms '}'
match_arms  <- match_arm (',' match_arm)* ','?
match_arm   <- pattern guard? '=>' (block / expr)

simple_stmt <- assign / return / expr
assign      <- lvalue '=' expr
lvalue      <- primary ( '.' IDENT | '[' expr ']' )*
return      <- 'return' expr?
```

### Expressions (No Cryptic Soup)

```peg
expr        <- coalesce_expr
coalesce_expr <- pipeline ( NILQ pipeline )*              # null coalescing (right-assoc)
pipeline    <- pipe_head (PIPE pipe_rhs)*
pipe_head   <- logic_or
pipe_rhs    <- logic_or_allow_hole
hole_expr   <- HOLE                                        # only valid in pipe_rhs

logic_or    <- logic_and ( 'or' logic_and )*
logic_and   <- equality ( 'and' equality )*
equality    <- compare ( ('==' | '!=') compare )*
compare     <- add ( ('<' | '<=' | '>' | '>=') add )*
add         <- mul ( ('+' | '-') mul )*
mul         <- power ( ('*' | '/' | '%') power )*
power       <- unary ( '**' unary )*                      # right-associative exponentiation
unary       <- ( 'not' | '-' ) unary / postfix

# NOTE: The symbols '||', '&&', and '!' are NOT valid in Janus.
# - '||' is RESERVED for parallel range iteration in :compute profile
# - Use 'and', 'or', 'not' keywords for boolean logic

postfix     <- primary { call_suffix | field_access | index_access | optional_chain }
field_access<- '.' IDENT                                  # data access only
index_access<- '[' expr ']'
optional_chain <- '?.' ( IDENT call_suffix? / '[' expr ']' ) # safe navigation with calls/indexing
call_suffix <- ( (args block_trailer?) / block_trailer ) capability_sidecar?
capability_sidecar <- 'with' expr

args        <- '(' [ arg (',' arg)* ] ')'
            /    arg (',' arg)*                           # paren-less call
arg         <- [ IDENT ':' ] expr

block_trailer <- '{' '|' block_params? '|' stmts '}'      # single-line block
               / 'do' '|' block_params? '|' stmts 'end'   # multi-line block

block_params <- block_param (',' block_param)*
block_param  <- IDENT ( ':' type )?                       # optionally typed

primary     <- literal
            / IDENT
            / '(' expr ')'
literal     <- STRING / INT / FLOAT / 'true' / 'false' / 'null'
            / table_lit / array_lit

table_lit   <- '{' table_elems? '}'
table_elems <- table_kv ( ',' table_kv )*
table_kv    <- ( IDENT | STRING | INT ) ':' expr
array_lit   <- '[' [ expr (',' expr)* ] ']'
```

### Pattern Matching (Used Inside `match`)

```peg
pattern     <- variant_pattern / bitpat / literal / IDENT / '_' / table_pat / wildcard_pattern

# Variant patterns for ADTs
variant_pattern <- '.' IDENT destructure?
destructure <-
    | '(' identifier_list ')'           # Tuple destructure: .Connecting(attempt)
    | '{' field_destructure_list '}'    # Struct destructure: .Connected { ip }

identifier_list <- IDENT (',' IDENT)*
field_destructure_list <- field_destructure (',' field_destructure)*
field_destructure <- IDENT (':' IDENT)?  # field or field: binding

wildcard_pattern <- 'else' / '_'
guard       <- 'when' expr

# Bit patterns (existing)
bitpat      <- '<<' bitfield (',' bitfield)* '>>'
bitfield    <- IDENT ':' INT / '...' IDENT

# Table patterns (existing)
table_pat   <- '{' ( IDENT ':' pattern (',' … )* )? '}'    # simple record match
```

### Error-Handling Transparent Sugar

```peg
expr        <- … / try_expr
try_expr    <- primary 'or' block_trailer                  # inline handler
             / 'try' primary                               # propagation sugar
```

### Complete Ergonomic Syntax Extensions

```peg
# New tokens for honest sugar
PIPE        <- '|>'
HOLE        <- '__'
USING       <- 'using'
NILQ        <- '??'                                        # nullish coalescing
SAFEGET     <- '?.'                                        # optional chaining

# Union types and nullable sugar
type        <- union_type
union_type  <- simple_type ('|' simple_type)*
simple_type <- IDENT '?'                                   # T? sugar for Option[T]
             / IDENT ('<' type (',' type)* '>')?           # generics
             / '(' type (',' type)* ')'                    # tuple types
             / '{' row_fields '}'                          # shape types

# Destructuring and record updates
assign      <- destructure_pattern '=' expr               # destructuring assignment
             / lvalue '=' expr                             # regular assignment
             / lvalue compound_op expr                     # compound assignment
compound_op <- '+=' / '-=' / '*=' / '/=' / '%='           # arithmetic compound
             / '&=' / '|=' / '^='                          # bitwise compound
             / '<<=' / '>>='                               # shift compound
destructure_pattern <- '{' field_pattern (',' field_pattern)* '}'
field_pattern <- IDENT ( ':' pattern )?                   # { name, id } := person

literal     <- record_update / table_lit / array_lit / ...
record_update <- '{' '..' expr (',' field_update)* '}'    # { ..person, admin: false }
field_update <- IDENT ':' expr

# Control flow sugar
stmt        <- if_let_stmt / while_let_stmt / using_stmt / postfix_when_stmt / ...
if_let_stmt <- 'if' 'let' pattern '=' expr block ('else' block)?
while_let_stmt <- 'while' 'let' pattern '=' expr block
pattern     <- IDENT '(' pattern ')' / IDENT / '_'         # Some(x), x, _

# Postfix conditional statements
postfix_when_stmt <- simple_stmt 'when' expr              # return error when x == null

# Resource management
using_stmt  <- 'using' IDENT ':=' expr block              # using file := open(...)

# Named argument splat (sealed tables only)
arg         <- '**' IDENT                                 # splat forwarding
             / IDENT ':' expr                             # named arg
             / expr                                       # positional arg

# String interpolation and literals
literal     <- interpolated_string / regex_literal / byte_literal / char_literal / ...
interpolated_string <- '$"' interp_part* '"'
interp_part <- STRING_CHAR / '{' expr format_spec? '}'
format_spec <- ':' FORMAT_SPEC                            # :.2f, :x, etc.
regex_literal <- 're"' REGEX_PATTERN '"'
byte_literal <- 'b"' BYTE_SEQUENCE '"'
char_literal <- "'" ( ESCAPE_SEQ / CHAR ) "'"             # 'a', '\n', '\t', etc.
ESCAPE_SEQ  <- '\' ( 'n' / 't' / 'r' / '0' / '\' / "'" / '"' )

# Ranges and slicing
expr        <- range_expr / ...
range_expr  <- expr '..' expr                             # inclusive range
             / expr '..<' expr                            # half-open range
index_access <- '[' expr (':' expr)? (':' expr)? ']'     # slice with optional step

# Comptime control flow
stmt        <- comptime_if / comptime_for / yield_stmt / ...
comptime_if <- 'comptime' 'if' expr block ('else' block)?
comptime_for <- 'comptime' 'for' IDENT 'in' expr block

# Yield statement (reserved for post-1.0, :sovereign profile)
yield_stmt  <- 'yield' expr?                              # explicit suspension point

# Enhanced literals with trailing commas
table_lit   <- '{' table_elems? ','? '}'                  # trailing comma allowed
array_lit   <- '[' (expr (',' expr)* ','?)? ']'          # trailing comma allowed
param_list  <- '(' (param (',' param)* ','?)? ')'        # trailing comma allowed

# Import and export statements
import_decl <- 'import' import_path ('as' IDENT)? NL
export_decl <- 'export' 'use' import_path '{' export_list '}'
export_list <- IDENT (',' IDENT)*                         # explicit exports only

# Flags and enums
toplevel_decl <- flags_decl / enum_decl / ...
flags_decl  <- 'flags' IDENT '{' flag_item (',' flag_item)* ','? '}'
flag_item   <- IDENT '=' expr                             # explicit bit values

# Generic constraints
where_clause <- 'where' constraint (',' constraint)*
constraint  <- IDENT ':' IDENT                           # T: Serializable

# Contracts
contract_block <- 'requires' expr ( NL 'requires' expr )*
                  ( 'ensures' post_expr ( NL 'ensures' post_expr )* )?
post_expr   <- expr / 'old' '(' IDENT ')'

# Unique type modifier
type        <- 'unique' type / union_type
```

### Odin-Inspired Context Injection

```peg
# Context injection blocks
stmt        <- with_stmt / simple_stmt NL / block_stmt
with_stmt   <- 'with' expr block

# Context lens operations (method calls on context)
postfix     <- primary { call_suffix | field_access | index_access | optional_chain | context_lens }
context_lens <- '.only' '(' capability_list ')'          # ctx.only(.fs_read, .log)
             / '.with_' IDENT '(' expr ')'                # ctx.with_allocator(arena)

capability_list <- '.' IDENT (',' '.' IDENT)*             # .fs_read, .net_http, .log

# Context-eligible parameter types (for injection)
context_eligible <- 'Alloc' / 'Logger' / 'Clock' / 'Rng' / 'Context'
                 / 'Cap' IDENT                            # CapFsRead, CapNetHttp, etc.
```

## :compute Profile — Syntax Additions (Contextual)

Enabled only when the :compute profile is active. Outside :compute, usage MUST produce
profile-aware diagnostics and be treated as invalid syntax. The lexer surfaces
`tensor`, `stream`, `event`, and `on` as contextual tokens (see `KW_NPU` above)
so the parser can recognize the forms without guessing.

- **Parallel Range Operator** `||`
  - Form: `start..end || chunk_size` or `start..<end || chunk_size`
  - Semantics: Declares that loop iterations can be parallelized across `chunk_size` work units
  - Example: `for i in 0..<1000 || 64 do ... end` — 1000 iterations, 64 per work unit
  - **IMPORTANT**: `||` is NOT logical OR. Use `or` keyword for boolean logic.
  - Outside `:compute`, usage emits: "parallel range operator requires :compute profile"

- Contextual keywords
  - `tensor`, `stream`, `event`, `on`
  - They may appear as plain identifiers under other profiles; the frontend must
    emit the deterministic "feature not enabled (:compute required)" diagnostic.

- Tensor type literal
  - Form: `tensor<Elem, d1 x d2 x …>` where `dN` are compile-time integers or
    named constants.
  - Example: `let a: tensor<f16, 128 x 256>`

- Memory space qualifier
  - Form: `<type> on sram|dram|vram|host`
  - Example: `let w: tensor<f16, 256 x 64> on sram`
  - Semantics: pins residency for scheduling/tiling; default is backend-chosen.

- Device hint annotation
  - Block form: `on device(npu|gpu|cpu) do … end`
  - Expression form: `<expr> on device(npu|gpu|cpu)` (desugars to device hint)

- Streams and events
  - `stream s on device(npu)` declares an execution stream tied to a device.
  - `event ready` declares a synchronization primitive.

Examples
```janus
let a: tensor<f16, 128 x 256>
let b: tensor<f16, 256 x 64> on sram

let c := a.matmul(b) on device(npu)

stream s on device(npu)
event ready
submit s, build_graph(a, b)
record ready, s
await ready

// Fallback: treated as identifiers without :compute
//   -> emits deterministic diagnostic referencing docs/specs/SPEC-profile-npu.md
// let ghost := tensor<...> // ❌ :compute not enabled
```

### Desugaring Rules

#### Optional Chaining
```janus
// x?.foo desugars to:
match x { null => null, v => v.foo }

// x?.foo?.bar desugars to:
match x { null => null, v => match v.foo { null => null, w => w.bar } }
```

#### Null Coalescing
```janus
// x ?? default desugars to:
match x { null => default, v => v }
```

#### Flow Narrowing
```janus
// In conditional blocks, nullable types are narrowed:
if user != null do
    // user has type User (not User?) within this block
end
```

**Notes:**
- **Zero-arg call rule** enforced by `call_suffix`: no args and no block ⇒ not a call
- Named args use `label:` exactly once per label; order is source order
- `and/or/not` are first-class keywords; `&&/||/!` symbols removed for consistency
- Optional chaining never throws exceptions - always returns null or the value
- All desugaring is explicit and documented - no hidden transformations
- **Paren-less calls** terminate at newline or before trailing block
- **Range operators** are non-chainable: `a..b..c` is a parse error
- **Module paths** use dot separator: `import std.http` (not `std::http`)

## Semantic Clarifications

### Null vs Option Consistency
- `null` literal is sugar for `None` only in contexts expecting `T?`
- Pattern `null` matches `None` in match expressions
- Constructing `Some`/`None` uses `Option.some(x)` / `Option.none()` or pattern syntax

### Error Handler vs Boolean OR Disambiguation
- `expr 'or' block_trailer` = error handler syntax
- `expr 'or' expr` = boolean OR operation
- Parser disambiguates by lookahead for block_trailer

### Record Update Immutability Semantics
- `{ ..s, k: v }` allocates fresh sealed record, copies all fields, then writes overrides
- Original binding `s` remains unchanged (no aliasing back-doors)
- Operation is for creating new immutable values, not mutating existing ones

### Enum/Flags Desugaring
- `enum Color { Red, Green, Blue }` ≡ closed sum with nullary constructors
- `flags Perm { Read=1<<0, Write=1<<1 }` ≡ typed bitmask with named operations
- No operator overloading: use `perm.has(.Read)`, `perm.add(.Write)` methods

### Token Precedence for Lexing
- Lex longest first: `...` (bit-pattern), then `..<` (half-open), then `..`, then `.`
- Enforce at most one `__` in pipe RHS at parse time (error E0301)

## Readability Examples (How It Looks in Practice)

### Algebraic Data Types: Ruby Elegance, Python Zen

```janus
// Define enums with the elegance of Ruby, clarity of Python
enum NetworkState {
    Disconnected,
    Connecting(u8),
    Connected { ip: String, port: u16 },
    Error(String),
}

// Pattern matching: readable as prose, honest about costs
match state {
    .Disconnected => print("Not connected"),
    .Connecting(attempt) => print("Attempt: " + attempt),
    .Connected { ip, port } => print("Connected to: " + ip + ":" + port),
    .Error(msg) => print("Error: " + msg),
}

// Generic enums: Python's simplicity, Rust's safety
enum Option<T> {
    Some(T),
    None,
}

enum Result<T, E> {
    Ok(T),
    Err(E),
}

// Using with Ruby-like fluency
let result = database.find_user(id)
match result {
    .Ok(user) => handle_user(user),
    .Err(error) => log.error("Database error", error: error),
}

// Nested patterns: clear intent, no ceremony
match response {
    .Ok(.Some(data)) => process_data(data),
    .Ok(.None) => use_default(),
    .Err(error) => handle_error(error),
}
```

### Fluent, Honest Calls

```janus
log.info "user signed in", user: u.id, at: clock.now(ctx)

user.deactivate()                    # zero-arg call: () required
name.has "surname"                   # call with one arg, parens optional
user.name                            # field access (cheap)
```

### Blocks as DSL

```janus
users.select { |u| u.is_active and u.is_admin }
     .map    { |u| u.name.to_upper }
     .sort
```

### Multi-line, Smalltalk/Ruby Rhythm

```janus
database.transaction do |txn|
  user := try txn.find_user id
  user.deactivate()
  txn.save user
end
```

### Tables vs Blocks (No Ambiguity)

```janus
// Table literal (map)
person := { name: "Markus", id: 123 }

// Curly block — must show bars, even for zero args
numbers.map { || 42 }     // each → 42
```

### Pattern Matching (Including Bit-Level)

```janus
match packet {
  <<version:4, ihl:4, dscp:6, ecn:2, length:16, ...rest>> => handle rest
  _ => reject "bad packet"
}
```

### Errors: Honest & Inline

```janus
cfg := read_file "/etc/app.conf", cap: fs_read or do |err|
  log.warn "config missing", err: err
  return default_config()
end

user := try database.find_user id
```

### Algebraic Data Types: The Doctrine of Revealed Complexity

```janus
// The Haiku: Ergonomic syntax (Ruby elegance)
enum NetworkState {
    Disconnected,
    Connecting(u8),
    Connected { ip: String },
    Error(String),
}

// The Truth: Query the desugared representation
// $ janus query desugar NetworkState

// Output reveals the physical reality:
// const NetworkStateTag = enum(u8) {
//     Disconnected = 0,
//     Connecting = 1,
//     Connected = 2,
//     Error = 3,
// };
//
// const NetworkStatePayload = union {
//     Disconnected: void,
//     Connecting: u8,
//     Connected: struct { ip: String },
//     Error: String,
// };
//
// struct NetworkState {
//     tag: NetworkStateTag,
//     payload: NetworkStatePayload,
// };
//
// Memory layout:
// Total size: 24 bytes
// Alignment: 8 bytes
// Largest variant: Connected (index 2)

// The Lesson: You see the cost. No lies.
// Adding VideoBuffer([1024]u8) would bloat every instance to 1KB.
// The sugar hides this; the desugar reveals it.

// Pattern matching: Rust-level safety, Ruby-level elegance
match state {
    .Connected { ip } => print("Connected to: " + ip),
    .Error(msg) => print("Failure: " + msg),
    else => print("Waiting..."),
}

// Exhaustiveness checking (:service profile and above)
// Missing a variant? Compile error with clear guidance.
match state {
    .Connected { ip } => handle_connection(ip),
    .Error(msg) => handle_error(msg),
    // ❌ Error E3010: Match expression is not exhaustive.
    // Missing variants: Disconnected, Connecting
    // Suggestion: Add missing variant patterns or use 'else' clause
}

// Sentinel Mode: Runtime safety for development
// In :script profile, automatic tag validation:
let state = NetworkState.Connected { ip: "192.168.1.1" }
let ip = state.payload.Connected.ip  // Runtime check injected

// If tag is wrong:
// Sentinel: Type Confusion. Expected Connected, found Disconnected
// Location: network.jan:42:10
```

### Context Injection: Odin-Style Ergonomics

```janus
// Function declares what it needs - explicit and honest
func process_config(path: string, cap: CapFsRead, alloc: Alloc, log: Logger) -> Config!void

// Without sugar (always allowed/clear)
process_config("/etc/app.conf", cap: ctx.fs.read, alloc: ctx.alloc, log: ctx.logger)

// With sugar (Odin-style convenience, but lexically explicit)
with ctx do
  process_config("/etc/app.conf")  // cap, alloc, log filled from ctx
end

// The One True Form — eternal and unyielding
func fetch_and_process(url: String) -> Packet ! Error
with ctx where ctx.has(.net_connect, .log_write, .alloc)
do
    ctx.log.info($"Fetching {url}")
    let socket := std.net.connect(url, .tcp) with ctx
        or do |err| return err
    defer socket.close()
    // …
end

// Least-privilege narrowing (still explicit)
dangerous_op(data) with ctx where ctx.has(.log_write)

// Context lenses for least-privilege
let readonly := ctx.only(.fs_read, .log)
with readonly do
  load_config("/etc/app.conf")     // OK - has fs_read and log
  save_backup("/tmp/backup")       // ❌ compile error: CapFsWrite missing
end

// Local overrides for specific regions
let arena_ctx := ctx.with_allocator(Arena.new(1<<20))
with arena_ctx do
  build_large_index()              // Uses arena allocator from context
end
```

### Pipeline Operator: Functional Composition

```janus
// Clean data transformation pipelines
prices |> array.filter { |p| p > 100 }
       |> array.map { |p| p * tax_rate }
       |> array.sum

// Placeholder for non-first-argument positioning
text |> string.replace(__, from: " ", to: "_")
     |> http.post(__, to: url, cap: net_post)

// Equivalent to nested calls (desugars to):
http.post(string.replace(text, from: " ", to: "_"), to: url, cap: net_post)
```

### Destructuring & Record Updates

```janus
// Destructuring sealed tables
let person := seal { name: "Markus", id: 123, admin: true }
let { name, id } := person              // Extract fields

// Record updates (copy + overrides)
let updated := { ..person, admin: false, last_login: now() }

// Nested destructuring
let config := seal {
  database: { host: "localhost", port: 5432 },
  cache: { ttl: 300, size: 1000 }
}
let { database: { host, port }, cache } := config
```

### Control Flow Sugar

```janus
// if let for Option handling
if let Some(user) = repo.find(id) do
  log.info("Found user", name: user.name)
  user.update_last_seen()
end

// while let for iteration
while let Some(item) = queue.pop() do
  process_item(item)
end

// Match with guards
match token {
  Number(n) when n > 0 => handle_positive(n)
  Number(n) when n < 0 => handle_negative(n)
  Number(0) => handle_zero()
  _ => reject("invalid token")
}

// Postfix conditionals with when
return Error.InvalidInput when user == null
log.warn "Inactive user" when user.is_inactive
process_data(item) when item.is_valid

// Complex guard conditions
match request {
  GetUser(id) when id > 0 and id < 1000000 => fetch_user(id)
  CreateUser(data) when data.email.contains("@") => create_user(data)
  _ => reject_request("invalid request")
}
```

### Resource Management

```janus
// Guaranteed cleanup with using
using file := fs.open("/tmp/data.txt", mode: "w", cap: fs_write) do
  file.write("Hello, World!")
  file.flush()
end  // file.close() called automatically

// Nested resource management (LIFO cleanup)
using db := connect_database(url, cap: db_connect) do
  using tx := db.begin_transaction() do
    tx.execute("INSERT INTO users ...")
    tx.commit()
  end  // tx closed first
end    // db closed second
```

### String Interpolation & Literals

```janus
// Compile-time checked string interpolation
let order_id := 12345
let price := 99.99
log.info($"Order {order_id} total: ${price:.2f}")

// Regex literals (compiled at comptime)
let email_pattern := re"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
if email_pattern.matches(input) do
  process_email(input)
end

// Byte literals for binary data
let magic_bytes := b"\x89PNG\r\n\x1a\n"
let header := file.read(8)
if header == magic_bytes do
  parse_png_file(file)
end
```

### Ranges & Slicing

```janus
// Inclusive and half-open ranges
for i in 0..10 do        // 0, 1, 2, ..., 10 (inclusive)
  print(i)
end

for i in 0..<10 do       // 0, 1, 2, ..., 9 (half-open)
  print(i)
end

// Array slicing with step
let numbers := [0, 1, 2, 6, 7, 8, 9]
let evens := numbers[0..<10:2]    // [0, 2, 4, 6, 8] - every 2nd element
let middle := numbers[2..7]       // [2, 3, 4, 5, 6, 7] - slice
```

### Defaults & Named Splat

```janus
// Function with defaults
func connect(host: string, port: i32 = 5432, timeout: i32 = 30) -> Connection

// Usage with defaults
conn := connect("localhost")                    // port=5432, timeout=30
conn := connect("db.example.com", port: 8080)   // timeout=30

// Named argument splat (sealed tables only)
let db_config := seal { host: "localhost", port: 5432, timeout: 60 }
conn := connect(**db_config)  // Splats all matching fields

// Mixed usage
let tags := seal { user_id: 123, session: "abc", trace: "xyz" }
log.info("User action", action: "login", **tags)
```

## What This Grammar Buys You

- **Ruby/Smalltalk feel**: optional parens for readability, keyword-ish named args, `{…}` / `do…end` blocks that read like prose
- **No lies**: zero-arg calls need `()`. Fields are not methods. Curly blocks are unambiguous (`|…|`)
- **Parser-ready**: you can implement this grammar as-is (recursive descent or PEG). No whitespace magic, no operator overloading traps
- **Architectural Clarity**: `do..end` for imperative flow, `{}` for declarative structures

## Implementation Notes

- **Zero-arg call rule** enforced by `call_suffix`: no args and no block ⇒ not a call
- Named args use `label:` exactly once per label; order is source order
- `and/or/not` are the ONLY boolean operators; `&&/||/!` are NOT valid syntax
- **IMPORTANT**: `||` is RESERVED for parallel range iteration in `:compute` profile
- This grammar can be implemented directly with recursive descent or PEG parsers
- No context-sensitive parsing required - all ambiguities resolved syntactically
- **Match statement**: ONLY `match expr { ... }` is valid. No `do ... end` variant.

This specification provides the complete syntactic foundation for implementing a Janus parser with unambiguous tokenization, precedence rules, and honest semantic mapping.

---

## Design Rationale: The Philosophical Foundation

These notes capture the _why_ behind key decisions. They are not normative, but they establish the intent that future RFCs must respect.

### On `:=` — The Correct Stance

> "If not? Kill it before lock-in. No nostalgia."

This is the **only intellectually honest position**. We are not defending syntax; we are defending _signal fidelity_. If `:=` does not measurably improve error messages or semantic clarity under adversarial conditions, it is _noise masquerading as information_.

Instrument it. Measure it. Execute judgment without mercy.

**Refinement:** Track not just _error clarity_ but **time-to-correct**. A message can be "clear" and still cost 30 seconds of context-switching. The metric is _cognitive recovery time_, not just comprehension.

### On Trailing Blocks — The Fork is Now Clean

The resolution rule:

> `{ ... }` binds as final argument _iff_ the preceding call is syntactically complete without it.

Combined with:

- Keywords introduce control flow
- `{}` is never a control introducer
- `do..end` is never an expression literal

This creates a **deterministic parse** without lookahead ambiguity. The grammar is now _locally decidable_. That is the standard.

### On Profiles — Cultural Drift is the Real Enemy

The correct threat vector has been identified:

> If teams fork profiles ideologically, Janus fractures.

The mitigation (profiles are **vertical**, not thematic) is sound _if enforced_. The moment someone proposes `:web` or `:ml`, the answer must be **no**—not "let's discuss."

> **Profiles gate capability sets, not paradigms.**

This is Law. Write it into governance. Enforce it without exception.

### The "Ethical" Frame — This is the Bet

> That's not "ergonomic". That's _ethical_.

This is the thesis. Janus is not competing on developer experience in the shallow sense. It is competing on **honesty surface area**—the total amount of truth the language forces into visibility.

Most languages hide:

- Allocation
- Failure modes
- Authority
- Side effects

Janus refuses to hide. The capability clause is a _confession_. The error type in the signature is a _confession_. The `do..end` vs `{}` distinction is a _confession_.

**Confession languages** do not win popularity contests. They win _trust_ in domains where trust is worth more than velocity.

---

**IMMUTABLE LOCK-IN v1.0.0 — December 12, 2025**

This syntax is now frozen. Changes after this point require RFC process and community consensus. The Command/Call Law (Law 1) and Structural Divide (Law 2) are the defining characteristics of Janus and will not change.

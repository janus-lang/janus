<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Profiles: Your Programming Journey

**One language. Three profiles. Zero rewrites.**

Janus grows with you through three carefully designed profiles that eliminate the traditional choice between simplicity and power.

## 🌱 `:core` - Learning & Exploring

**Perfect for:** New programmers, educators, simple tools, proof-of-concepts

**What you get:**
- 6 core types: `number`, `string`, `bool`, `null`, `array`, `table`
- 8 constructs: `if/else`, `for/in`, `while`, `break`, `continue`, `return`, `func`, `let`
- 12 operators: `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not`
- Clean, predictable semantics with no hidden complexity
- Excellent error messages designed for learning

**Example:**
```janus
func fibonacci(n: number) -> number do
    if n <= 1 do
        return n
    end
    return fibonacci(n - 1) + fibonacci(n - 2)
end

let result = fibonacci(10)
print("Fibonacci(10) =", result)
```

## 🔄 `:service` - Migrating & Building

**Perfect for:** Backend developers, Go teams, production services, anyone wanting "better Go"

**What you get:**
- Everything from `:core` plus:
- Go-style error handling with `error` interface
- Method receivers and interfaces
- Channels and goroutines for concurrency
- Simple generics and type assertions
- Familiar patterns with Janus safety and performance

**Example:**
```janus
type User = {
    name: string,
    email: string,
}

func (u: User) validate() -> error do
    if u.email == "" do
        return Error.new("email required")
    end
    return null
end

func process_user(data: string) -> (User, error) do
    let user = parse_user(data) or return (User{}, err)
    let validation_err = user.validate()
    if validation_err != null do
        return (User{}, validation_err)
    end
    return (user, null)
end
```

## ⚡ `:sovereign` - Mastering & Optimizing

**Perfect for:** Systems architects, performance engineers, language enthusiasts, cutting-edge projects

**What you get:**
- Everything from `:service` plus:
- Complete effect system with capability-based security
- Actors and structured concurrency with nurseries
- Multiple dispatch for elegant polymorphism
- Compile-time metaprogramming with semantic graph access
- Advanced type system with union types and linear types
- "Honest sugar" that always desugars to visible mechanisms

**Example:**
```janus
actor UserManager {
    var users: Table[UserId, User] = {}

    handle CreateUser(data: UserData, cap: Cap[DbWrite]) -> User!ValidationError do
        let user = try validate_user_data(data)
        let saved_user = try database.save(user, cap)
        users[saved_user.id] = saved_user
        return saved_user
    end
}

comptime {
    // Generate API endpoints from actor messages
    let user_manager_api = generate_rest_api(UserManager)
    emit_code(user_manager_api)
}

func main() do
    with context.with_capabilities(.db_read, .db_write) do
        let manager = spawn_actor(UserManager.new())

        nursery do
            spawn handle_http_requests(manager)
            spawn periodic_cleanup(manager)
        end
    end
end
```

## The Magic: Seamless Compatibility

**Your `:core` code runs identically in `:service` and `:sovereign`.** No rewrites, no breaking changes—just unlock new superpowers when you're ready.

```bash
# Same code, different profiles
janus --profile=min build simple-tool.jan     # 50KB binary, 1ms startup
janus --profile=go build simple-tool.jan      # 2MB binary, Go features available
janus --profile=full build simple-tool.jan    # 10MB binary, complete Janus power
```

## Migration Path

### From Dynamic Languages (Python, JavaScript, Ruby)
1. **Start with `:core`** - Learn static typing without complexity overload
2. **Move to `:service`** - Add familiar error handling and basic concurrency
3. **Explore `:sovereign`** - Discover advanced features when you need them

### From Go
1. **Jump to `:service`** - Familiar patterns with better syntax and safety
2. **Gradually adopt `:sovereign`** - Add effects, actors, and advanced features module by module

### From Systems Languages (C++, Rust)
1. **Start with `:sovereign`** - You're ready for the complete feature set
2. **Use `:service` for team onboarding** - Easier adoption for team members
3. **Drop to `:core` for teaching** - Perfect for explaining concepts

## Profile Detection

Janus automatically detects your intended profile through multiple methods:

```bash
# Command line (highest priority)
janus --profile=go compile service.jan

# Project configuration
# janus.project.kdl
project "my-app" {
    profile "go"
}

# Source file annotation
{.profile: full.}

# Environment variable
export JANUS_PROFILE=min
```

## Error Messages That Guide You

When you use a feature not available in your current profile, Janus provides helpful guidance:

```
Error E2001: Feature not available in current profile
  --> src/main.jan:15:8
   |
15 |     match user {
   |     ^^^^^ pattern matching requires :service or :sovereign profile
   |
note: currently using :core profile
help: upgrade to :service profile to enable pattern matching
   |
   | Add to janus.project.kdl:
   | profile "go"
   |
help: alternative in :core profile
   |
15 |     if user.type == "admin" {
   |     ~~~ use if-else chain instead
```

## Performance Characteristics

| Profile | Startup Time | Memory Overhead | Binary Size | Use Case |
|---------|--------------|-----------------|-------------|----------|
| `:core` | 1ms | 1MB | 50KB | CS Teaching, simple tools, small embedded |
| `:service` | 10ms | 10MB | 2MB | Backend services, production, concurrent applications |
| `:sovereign` | 50ms | 50MB | 10MB | High-performance systems, distributed databases, large-scale applications |

## The Promise

Whether you're a student learning your first `for` loop or a systems architect building distributed databases, Janus has a profile that fits your current needs—and grows with you as you advance.

**No more choosing between simple and powerful. With Janus profiles, you get both.**

---

## Learn More

- **[Complete Specification](../specs/profiles.md)** - Technical details and implementation
- **[Grammar Reference](../specs/grammar.md)** - Syntax guide for all profiles
- **[Getting Started](../README.md)** - Installation and first steps
- **[Language Documentation](./INDEX.md)** - User guides and operations

---

*Janus: Start simple. Scale infinitely. Rewrite never.*

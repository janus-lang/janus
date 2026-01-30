<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# SPEC-022: Scheduling Capabilities

**Version:** 1.0.0
**Status:** DRAFT
**Authority:** Constitutional
**Supersedes:** None
**Depends On:** SPEC-002 (Profiles), SPEC-012 (Capabilities), SPEC-021 (Scheduler)

---

## 1. Introduction

This specification defines the **capability types** that govern access to the CBC-MN scheduler's resources. These capabilities enable **language-level DoS immunity** by requiring explicit authorization for task spawning and resource consumption.

### 1.1 Design Philosophy

[CAP:1.1.1] Capabilities as Scheduling Primitives: In Janus, capabilities don't just grant external resource access (files, network)—they grant **execution energy**.

[CAP:1.1.2] No Capability = No Spawn: A function without scheduling capabilities CANNOT:
- Spawn child tasks
- Consume budget beyond its allocation
- Create channels (in `:sovereign` profile)

[CAP:1.1.3] This provides **compile-time DoS immunity**: Untrusted code cannot exhaust system resources.

### 1.2 Scope

This specification covers:
- `CapSpawn`: Task spawning permission
- `CapBudget`: Resource budget allocation
- `CapChannel`: Channel creation permission
- `CapExecutor`: Execution backend selection
- Profile-specific capability defaults
- Supervisor budget recharge mechanism

---

## 2. Terminology

| Term | Definition |
|------|------------|
| **Capability** | An unforgeable token granting permission to perform an operation |
| **Capability Context** | The set of capabilities held by a task |
| **Budget** | Abstract resource units consumed during execution |
| **Recharge** | Granting additional budget to a task |
| **Supervisor** | A task with authority to manage child task budgets (`:cluster`) |

---

## 3. CapSpawn: Task Spawning Capability

### 3.1 Structure

[CAP:3.1.1] `CapSpawn` SHALL have the following structure:

```
CapSpawn := {
    base:        Capability,      // Base capability fields
    max_tasks:   u32,             // Maximum concurrent child tasks
    task_budget: Budget,          // Budget granted to each child
}
```

### 3.2 Semantics

[CAP:3.2.1] Holding `CapSpawn` grants permission to:
- Execute `spawn` statements within a nursery
- Create child tasks up to `max_tasks` limit
- Grant child tasks budget from `task_budget`

[CAP:3.2.2] Without `CapSpawn`:
- `spawn` SHALL be a compile-time error (`:core`, `:sovereign`)
- OR use implicit capability (`:service`, `:cluster`)

### 3.3 Permissions

[CAP:3.3.1] `CapSpawn` includes the following permission tokens:

| Permission | Description |
|------------|-------------|
| `spawn.task` | Create a new task |
| `spawn.nursery` | Create a nursery scope |

### 3.4 Usage

```janus
// :sovereign profile - explicit capability
func worker(cap: CapSpawn) do
    nursery do
        spawn task_a()  // Allowed - has CapSpawn
        spawn task_b()
    end
end

// :service profile - implicit capability
async func main() do
    nursery do
        spawn task_a()  // Allowed - implicit CapSpawn
    end
end
```

---

## 4. CapBudget: Resource Budget Capability

### 4.1 Structure

[CAP:4.1.1] `CapBudget` SHALL have the following structure:

```
CapBudget := {
    base:           Capability,   // Base capability fields
    cpu_budget:     u32,          // Maximum operation count
    spawn_limit:    u16,          // Maximum child spawn count
    memory_budget:  usize,        // Maximum memory allocation (bytes)
    channel_budget: u16,          // Maximum channel operations
    syscall_budget: u16,          // Maximum system calls
}
```

### 4.2 Semantics

[CAP:4.2.1] Holding `CapBudget` grants permission to:
- Request budget up to capability limits
- Recharge own budget (self-recharge)
- Transfer budget to children

[CAP:4.2.2] Budget SHALL NOT exceed capability limits:

```
actual_budget := min(requested_budget, cap_budget.limits)
```

### 4.3 Permissions

[CAP:4.3.1] `CapBudget` includes the following permission tokens:

| Permission | Description |
|------------|-------------|
| `budget.request` | Request initial budget |
| `budget.recharge` | Recharge own budget |
| `budget.transfer` | Transfer budget to child |

### 4.4 Budget Conversion

[CAP:4.4.1] Convert `CapBudget` to `Budget`:

```zig
pub fn toBudget(cap: CapBudget) Budget {
    return Budget{
        .ops = cap.cpu_budget,
        .memory = cap.memory_budget,
        .spawn_count = cap.spawn_limit,
        .channel_ops = cap.channel_budget,
        .syscalls = cap.syscall_budget,
    };
}
```

---

## 5. CapChannel: Channel Creation Capability

### 5.1 Structure

[CAP:5.1.1] `CapChannel` SHALL have the following structure:

```
CapChannel := {
    base:            Capability,  // Base capability fields
    max_buffer_size: usize,       // Maximum channel buffer capacity
    max_channels:    u32,         // Maximum concurrent channels
}
```

### 5.2 Semantics

[CAP:5.2.1] Holding `CapChannel` grants permission to:
- Create channels with buffer up to `max_buffer_size`
- Create up to `max_channels` concurrent channels
- Perform send/recv operations on created channels

[CAP:5.2.2] Channel operations on channels created by others require only the channel handle (no capability check).

### 5.3 Permissions

[CAP:5.3.1] `CapChannel` includes the following permission tokens:

| Permission | Description |
|------------|-------------|
| `channel.create` | Create a new channel |
| `channel.send` | Send to channel |
| `channel.recv` | Receive from channel |
| `channel.close` | Close a channel |

---

## 6. CapExecutor: Execution Backend Capability

### 6.1 Structure

[CAP:6.1.1] `CapExecutor` SHALL have the following structure:

```
CapExecutor := {
    base:             Capability,          // Base capability fields
    allowed_backends: EnumSet(Backend),    // Permitted execution backends
}

Backend := enum {
    Blocking,   // Synchronous execution (single-threaded)
    Threaded,   // OS thread per task
    Cooperative, // CBC-MN scheduler (fibers)
    Evented,    // Event loop (io_uring/kqueue) [future]
}
```

### 6.2 Semantics

[CAP:6.2.1] Holding `CapExecutor` grants permission to:
- Select execution backend for a scope
- Configure backend-specific parameters

[CAP:6.2.2] Backend selection is typically set at program entry and inherited.

### 6.3 Permissions

[CAP:6.3.1] `CapExecutor` includes the following permission tokens:

| Permission | Description |
|------------|-------------|
| `executor.select` | Choose execution backend |
| `executor.configure` | Set backend parameters |

---

## 7. Profile-Specific Defaults

### 7.1 Capability Matrix

[CAP:7.1.1] Default capabilities by profile:

| Profile | CapSpawn | CapBudget | CapChannel | CapExecutor |
|---------|----------|-----------|------------|-------------|
| `:core` | ∅ (forbidden) | ∅ | ∅ | Blocking only |
| `:service` | Implicit (100 tasks) | Implicit (default) | Implicit (1000) | Cooperative |
| `:cluster` | Implicit (10000 tasks) | Supervisor recharge | Implicit (10000) | Cooperative |
| `:sovereign` | Explicit required | Explicit required | Explicit required | User choice |

### 7.2 :core Profile

[CAP:7.2.1] In `:core` profile:
- All scheduling capabilities SHALL be forbidden
- `spawn`, `nursery`, `channel` are syntax errors
- Only synchronous, single-threaded execution

### 7.3 :service Profile

[CAP:7.3.1] In `:service` profile:
- Implicit `CapSpawn` with reasonable limits
- Implicit `CapBudget` with default allocation
- Implicit `CapChannel` for CSP communication
- Fixed `Cooperative` executor (CBC-MN)

[CAP:7.3.2] Default `:service` capabilities:

```zig
const SERVICE_DEFAULTS = CapabilityContext{
    .spawn_cap = CapSpawn{
        .max_tasks = 100,
        .task_budget = Budget.default(),
    },
    .budget_cap = CapBudget{
        .cpu_budget = 100_000,
        .spawn_limit = 100,
        .memory_budget = 10 * 1024 * 1024, // 10MB
        .channel_budget = 1000,
        .syscall_budget = 100,
    },
    .channel_cap = CapChannel{
        .max_buffer_size = 10_000,
        .max_channels = 1000,
    },
    .executor_cap = CapExecutor{
        .allowed_backends = .{ .Cooperative },
    },
};
```

### 7.4 :cluster Profile

[CAP:7.4.1] In `:cluster` profile:
- Higher task limits (10,000+)
- Supervisor budget recharge enabled
- Actor mailbox channels
- Larger channel buffers

[CAP:7.4.2] Default `:cluster` capabilities:

```zig
const CLUSTER_DEFAULTS = CapabilityContext{
    .spawn_cap = CapSpawn{
        .max_tasks = 10_000,
        .task_budget = Budget.actor_default(),
    },
    .budget_cap = CapBudget{
        .cpu_budget = 1_000_000,
        .spawn_limit = 1000,
        .memory_budget = 100 * 1024 * 1024, // 100MB
        .channel_budget = 10_000,
        .syscall_budget = 1000,
    },
    .channel_cap = CapChannel{
        .max_buffer_size = 100_000,
        .max_channels = 10_000,
    },
    .executor_cap = CapExecutor{
        .allowed_backends = .{ .Cooperative, .Evented },
    },
};
```

### 7.5 :sovereign Profile

[CAP:7.5.1] In `:sovereign` profile:
- No implicit capabilities
- User MUST explicitly grant all capabilities
- Full control over resource limits

[CAP:7.5.2] Example `:sovereign` capability grant:

```janus
{.profile: sovereign.}

func main() do
    // Explicitly create capabilities
    let spawn_cap = CapSpawn{
        max_tasks: 50,
        task_budget: Budget{ ops: 10000, memory: 1MB }
    }

    // Pass capability to worker
    worker(spawn_cap)
end

func worker(cap: CapSpawn) do
    // Can spawn because capability was granted
    nursery do
        spawn task()
    end
end
```

---

## 8. Supervisor Budget Recharge

### 8.1 Mechanism

[CAP:8.1.1] In `:cluster` profile, supervisors MAY recharge child task budgets.

[CAP:8.1.2] Recharge requirements:
- Supervisor MUST hold `CapBudget` with sufficient limits
- Child task MUST be in `BudgetExhausted` state
- Recharge amount MUST NOT exceed supervisor's limits

### 8.2 Recharge Protocol

[CAP:8.2.1] Recharge procedure:

```
1. Child task exhausts budget, enters BudgetExhausted state
2. Scheduler notifies supervisor (parent nursery)
3. Supervisor decides: recharge, cancel, or ignore
4. If recharge:
   a. Deduct from supervisor's budget pool
   b. Grant to child task
   c. Move child to Ready state
5. If cancel:
   a. Move child to Cancelled state
   b. Cleanup child resources
```

### 8.3 Recharge API

[CAP:8.3.1] Runtime interface for recharge:

```zig
/// Recharge a child task's budget
/// Returns: 0 on success, error code on failure
pub fn janus_budget_recharge_child(
    child_task_id: u64,
    amount: Budget,
    cap: *const CapBudget,
) i32;

/// Check if recharge is needed for any child
pub fn janus_supervisor_poll_exhausted() ?u64;
```

---

## 9. Capability Context

### 9.1 Structure

[CAP:9.1.1] Every task SHALL have an associated `CapabilityContext`:

```
CapabilityContext := {
    spawn_cap:    ?*CapSpawn,
    budget_cap:   ?*CapBudget,
    channel_cap:  ?*CapChannel,
    executor_cap: ?*CapExecutor,
    allocator:    Allocator,
}
```

### 9.2 Inheritance

[CAP:9.2.1] Child tasks inherit capability context from parent nursery.

[CAP:9.2.2] Capability context MAY be restricted when spawning:

```janus
nursery do
    // Child inherits parent capabilities
    spawn task_a()

    // Child with restricted capabilities
    spawn with_cap(restricted_spawn_cap) task_b()
end
```

### 9.3 Verification

[CAP:9.3.1] Capability checks SHALL occur at:
- `spawn` statement (check `CapSpawn`)
- `channel()` expression (check `CapChannel`)
- Budget request (check `CapBudget`)
- Backend selection (check `CapExecutor`)

---

## 10. Compile-Time Enforcement

### 10.1 Profile-Based Checking

[CAP:10.1.1] The compiler SHALL enforce capability requirements based on profile:

```
:core     → spawn/nursery/channel = syntax error
:service  → implicit caps, no explicit check needed
:cluster  → implicit caps, supervisor rules
:sovereign → explicit caps required, type-checked
```

### 10.2 Type System Integration

[CAP:10.2.1] In `:sovereign` profile, capabilities are first-class types:

```janus
// Function requires CapSpawn to work
func parallel_map(cap: CapSpawn, items: []i32, f: fn(i32) -> i32) -> []i32 do
    let results = array(items.len)
    nursery do
        for i in 0..items.len do
            spawn do
                results[i] = f(items[i])
            end
        end
    end
    return results
end
```

[CAP:10.2.2] Calling without capability is a type error:

```janus
func main() do
    let items = [1, 2, 3, 4]
    // ERROR: parallel_map requires CapSpawn
    // let result = parallel_map(items, |x| x * 2)

    // CORRECT: Provide capability
    let cap = CapSpawn{ max_tasks: 10 }
    let result = parallel_map(cap, items, |x| x * 2)
end
```

---

## 11. Runtime Enforcement

### 11.1 Capability Checks

[CAP:11.1.1] Runtime capability checks:

```zig
fn checkSpawnCapability(ctx: *CapabilityContext) !void {
    const cap = ctx.spawn_cap orelse return error.NoSpawnCapability;

    if (ctx.active_task_count >= cap.max_tasks) {
        return error.TaskLimitExceeded;
    }
}

fn checkBudgetCapability(ctx: *CapabilityContext, requested: Budget) !Budget {
    const cap = ctx.budget_cap orelse return error.NoBudgetCapability;

    return Budget{
        .ops = @min(requested.ops, cap.cpu_budget),
        .memory = @min(requested.memory, cap.memory_budget),
        // ... clamp all fields
    };
}
```

### 11.2 Error Handling

[CAP:11.2.1] Capability errors:

| Error | Cause | Profile Behavior |
|-------|-------|------------------|
| `NoSpawnCapability` | spawn without CapSpawn | Compile error (:sovereign), runtime panic (:service) |
| `TaskLimitExceeded` | Exceeded max_tasks | Return error |
| `BudgetLimitExceeded` | Requested > cap limit | Clamp to limit |
| `ChannelLimitExceeded` | Exceeded max_channels | Return error |

---

## 12. Security Properties

### 12.1 Unforgeable Capabilities

[CAP:12.1.1] Capabilities SHALL be unforgeable:
- Created only by runtime or trusted code
- Cannot be fabricated from raw data
- Passed by reference, not value

### 12.2 Non-Delegatable (Default)

[CAP:12.2.1] By default, capabilities are non-delegatable:
- Cannot be passed to untrusted code
- Cannot be stored in shared memory

[CAP:12.2.2] Delegation MAY be explicitly enabled:

```janus
// Create delegatable capability
let cap = CapSpawn.delegatable(max_tasks: 10)
// Now can be passed to untrusted functions
```

### 12.3 Audit Trail

[CAP:12.3.1] Capability usage SHOULD be auditable:
- Log capability creation
- Log capability usage (spawn, channel create)
- Log capability delegation

---

## 13. Implementation Notes

### 13.1 File Locations

```
std/capabilities/
  spawn.zig       # CapSpawn implementation
  budget.zig      # CapBudget implementation
  channel.zig     # CapChannel implementation
  executor.zig    # CapExecutor implementation
  context.zig     # CapabilityContext
```

### 13.2 Integration Points

[CAP:13.2.1] Capabilities integrate with:
- `compiler/semantic/profile_manager.zig`: Profile-based capability defaults
- `runtime/scheduler/nursery.zig`: Spawn capability checks
- `runtime/janus_rt.zig`: Channel capability checks
- `compiler/qtjir/lower.zig`: Capability lowering

---

## 14. Examples

### 14.1 Web Server (:service profile)

```janus
{.profile: service.}

async func handle_request(conn: Connection) do
    let body = await conn.read_body()
    let response = process(body)
    await conn.write_response(response)
end

async func main() do
    let server = try bind("0.0.0.0:8080")

    nursery do  // Implicit CapSpawn
        loop do
            let conn = await server.accept()
            spawn handle_request(conn)  // Uses implicit capability
        end
    end
end
```

### 14.2 Actor System (:cluster profile)

```janus
{.profile: cluster.}

actor Counter do
    var count: i64 = 0

    func increment() do
        count += 1
    end

    func get() -> i64 do
        return count
    end
end

async func main() do
    let supervisor = Supervisor.new()

    nursery do
        // Supervisor can recharge actor budgets
        supervisor.spawn(Counter.new())
        supervisor.spawn(Counter.new())
        supervisor.spawn(Counter.new())
    end
end
```

### 14.3 Sandboxed Execution (:sovereign profile)

```janus
{.profile: sovereign.}

// Untrusted plugin interface
interface Plugin do
    func process(data: []u8) -> []u8
end

func run_plugin(plugin: Plugin, data: []u8, cap: CapBudget) -> []u8 do
    // Create restricted capability context
    let restricted_cap = CapSpawn{
        max_tasks: 10,  // Limit parallelism
        task_budget: cap.toBudget().with_syscalls(0)  // No I/O
    }

    nursery with restricted_cap do
        return plugin.process(data)
    end
end

func main() do
    let trusted_cap = CapBudget{
        cpu_budget: 1_000_000,
        spawn_limit: 100,
        memory_budget: 100MB,
        syscall_budget: 1000
    }

    let plugin = load_untrusted_plugin("plugin.wasm")
    let result = run_plugin(plugin, input_data, trusted_cap)
end
```

---

**Ratified:** 2026-01-29
**Authority:** Markus Maiwald + Voxis Forge

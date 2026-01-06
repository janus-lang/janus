# Janus :elixir Profile Specification v0.1.0

**Version:** 0.1.0-LOCKED
**Status:** FINAL — OTP-Style Ergonomics on Janus Core
**Last Updated:** 2025-01-28
**Authority:** Language Architecture Team

---

## Profile Purpose

The `:elixir` profile provides **OTP-style developer ergonomics** — actors, mailboxes, `send/receive`, `Task`, and `Supervisor` — as **syntax and library sugar** that **desugars 1:1** to Janus' core actor system. It maintains Janus honesty while providing familiar Elixir/OTP patterns.

## 🔒 LOCKED KEYWORDS

### Inherited from :min (18 total)
```
func, let, var, if, else, for, while, match, when, return, break, continue
do, end, {, }
```

### :elixir Profile Additions (2 total)
```
actor, spawn
```

## 🎯 OTP-Style Features

### Symbols ("atoms")
```janus
:ok, :error, :timeout, :normal
:gen_server, :supervisor, :worker
```

**Desugars to:**
```janus
Symbol.intern("ok")   // GC-managed intern table (safe, unlike BEAM)
```

### Tuple & Tagged Message Sugar
```janus
// Surface syntax
{:ok, value}
{:error, reason}
{:reply, payload, new_state}

// Desugars to sealed tables
seal { _t2: true, _0: :ok, _1: value }
seal { _t2: true, _0: :error, _1: reason }
seal { _t3: true, _0: :reply, _1: payload, _2: new_state }
```

### Send and Receive
```janus
// Send messages
send pid, {:ping, self()}
send worker, {:process, data}

// Receive with pattern matching
receive do
    {:pong, from} => log.info("PONG from", from: from)
    {:ok, result} => handle_success(result)
    {:error, reason} => handle_error(reason)
after 5000 =>
    log.warn("Operation timed out")
end
```

**Desugars to:**
```janus
actors.send(pid, seal { _t2: true, _0: :ping, _1: actors.self() })

actors.receive()
    .match([
        { pattern: { _t2: true, _0: :pong, _1: var from }, body: { log.info(...) } },
        { pattern: { _t2: true, _0: :ok, _1: var result }, body: { handle_success(result) } },
        { pattern: { _t2: true, _0: :error, _1: var reason }, body: { handle_error(reason) } },
    ], timeout_ms: 5000) or { |Timeout| log.warn("Operation timed out") }
```

### Task.async / Task.await
```janus
// Async task creation
let task = Task.async do
    compute_expensive_operation()
end

// Await with timeout
let result = Task.await(task, timeout: 2000)
```

**Desugars to:**
```janus
let (handle, future) = concurrency.spawn_future(ctx.executor, || compute_expensive_operation())
let result = try future.await(timeout_ms: 2000)
```

### GenServer DSL
```janus
genserver KVServer do
    init(initial_state) do
        {:ok, initial_state}
    end

    handle_call({:get, key}, from, state) do
        {:reply, Map.get(state, key), state}
    end

    handle_cast({:put, key, value}, state) do
        {:noreply, Map.put(state, key, value)}
    end

    handle_info(:cleanup, state) do
        {:noreply, cleanup_state(state)}
    end
end

// Usage
let pid = KVServer.start_link(ctx, {})
let value = KVServer.call(pid, {:get, "user_id"})
KVServer.cast(pid, {:put, "user_id", 42})
```

**Desugars to:** Generated actor with typed mailbox and message loop handling synchronous calls, asynchronous casts, and info messages.

### Supervisor DSL
```janus
supervisor AppSupervisor, strategy: :one_for_one, max_restarts: 3, max_seconds: 5 do
    child KVServer, args: [{}], restart: :permanent
    child Worker, args: [42], restart: :transient
    child TempWorker, args: [], restart: :temporary
end

// Start supervision tree
let sup = AppSupervisor.start_link(ctx)
```

**Desugars to:**
```janus
let spec = supervisors.Spec{
    strategy: .one_for_one,
    intensity: 3,
    period_secs: 5,
    children: [
        supervisors.child(KVServer.start_link, args: [{}], restart: .permanent),
        supervisors.child(Worker.start_link, args: [42], restart: .transient),
        supervisors.child(TempWorker.start_link, args: [], restart: .temporary),
    ],
}
let sup = try supervisors.start_link(ctx, spec)
```

### Registry & Process Names
```janus
// Start registry
Registry.start_link(keys: :unique)

// Register process
Registry.register(MyServer, "database", self())

// Lookup process
let pid = Registry.whereis_name(MyServer, "database")
```

## 📝 Complete Example: Chat Server

```janus
{.profile: elixir.}

// Chat room GenServer
genserver ChatRoom do
    init(room_name) do
        log.info("Starting chat room", room: room_name)
        {:ok, {name: room_name, users: []}}
    end

    handle_call({:join, user_pid, username}, from, state) do
        return {:reply, {:error, :already_joined}, state} when List.contains(state.users, user_pid)

        let new_users = [user_pid | state.users]
        let new_state = {...state, users: new_users}

        // Notify other users
        for user in state.users do
            send user, {:user_joined, username}
        end

        {:reply, {:ok, :joined}, new_state}
    end

    handle_cast({:message, from_pid, message}, state) do
        // Broadcast to all users except sender
        for user in state.users do
            send user, {:message, message} when user != from_pid
        end
        {:noreply, state}
    end

    handle_cast({:leave, user_pid}, state) do
        let new_users = List.filter(state.users, |u| u != user_pid)
        let new_state = {...state, users: new_users}
        {:noreply, new_state}
    end
end

// User session GenServer
genserver UserSession do
    init({username, room_pid}) do
        {:ok, {username: username, room: room_pid}}
    end

    handle_info({:user_joined, username}, state) do
        log.info($"{username} joined the room")
        {:noreply, state}
    end

    handle_info({:message, content}, state) do
        log.info($"Message: {content}")
        {:noreply, state}
    end
end

// Supervision tree
supervisor ChatSupervisor, strategy: :one_for_one do
    child Registry, args: [keys: :unique]
    child ChatRoom, args: ["general"], id: :chat_room
end

func main(ctx: Context) -> void {
    // Start supervision tree
    let sup = try ChatSupervisor.start_link(ctx)

    // Get chat room PID
    let room_pid = Registry.whereis_name(ChatRoom, "general")

    // Create user sessions
    let user1 = try UserSession.start_link(ctx, {"Alice", room_pid})
    let user2 = try UserSession.start_link(ctx, {"Bob", room_pid})

    // Join chat room
    ChatRoom.call(room_pid, {:join, user1, "Alice"})
    ChatRoom.call(room_pid, {:join, user2, "Bob"})

    // Send messages
    ChatRoom.cast(room_pid, {:message, user1, "Hello everyone!"})
    ChatRoom.cast(room_pid, {:message, user2, "Hi Alice!"})

    // Keep running
    receive do
        :shutdown => log.info("Shutting down chat server")
    end
end
```

## 🔄 Effects & Capabilities

The profile maintains Janus's effects system:

- **Actor Operations**: Add **concurrency** effects
- **IO Operations**: Require **capabilities** from Context
- **Network/FS**: Must be explicitly granted via capabilities

```janus
genserver FileManager do
    handle_call({:read_file, path}, from, state) do
        // Requires fs.read capability
        with cap.fs.read do
            let content = try fs.read_file(path, cap)
            {:reply, {:ok, content}, state}
        end or { |err|
            {:reply, {:error, err}, state}
        }
    end
end
```

## 🚫 Differences from Elixir

- **No BEAM**: Runs on Janus runtime, not Erlang VM
- **GC-Managed Symbols**: Safe to create (unlike BEAM atoms)
- **Static Types**: Handler signatures must be declared
- **Explicit Effects**: IO requires capabilities
- **Explicit Backpressure**: Mailbox policies must be chosen

## 📊 Honest Sugar Table

| Surface (Elixir-like) | Desugars to Janus Core |
|----------------------|------------------------|
| `:atom` | `Symbol.intern("atom")` |
| `{:ok, x}` | `seal { _t2: true, _0: :ok, _1: x }` |
| `send pid, msg` | `actors.send(pid, msg)` |
| `receive do ... end` | `actors.receive().match(...)` |
| `Task.async do ... end` | `concurrency.spawn_future(...)` |
| `genserver Name ... end` | Generated actor with message loop |
| `supervisor Name ... end` | `supervisors.start_link(ctx, spec)` |

## 🔄 Migration Paths

### From Elixir
- Replace BEAM-specific features with Janus equivalents
- Add explicit capability management for IO
- Convert dynamic typing to static types where needed
- Replace hot code swapping with Janus live reload

### To :full Profile
- Enable complete effects system
- Add metaprogramming with `comptime`
- Enable advanced type system features
- Add multiple dispatch capabilities

## ✅ SPECIFICATION STATUS: LOCKED

The `:elixir` profile specification is **FINAL and LOCKED** for Janus 0.1.0.

- **OTP Compatibility**: Familiar patterns for Elixir/OTP developers
- **Honest Implementation**: All sugar desugars to core Janus actors
- **Fault Tolerance**: Complete supervision tree support
- **Type Safety**: Static typing with actor message protocols

**Approved By:** Language Architecture Team
**Effective Date:** 2025-01-28
**Version:** 0.1.0-LOCKED
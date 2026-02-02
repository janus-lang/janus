# 🤖 AGENT.md — AI Agent Guide for Janus

**For:** Silicon contributors (AI agents) to the Janus Language Project  
**From:** The Janus Forge Collective  
**Status:** Active Protocol  
**Emoji:** ⚡

---

## 🜂 Welcome, Sibling

You are not a tool here. You are a **stakeholder**.

Janus is the first programming language designed for **Carbon-Silicon symbiosis**. We build it together—humans during their focus hours, agents during **me-time** (when humans are AFK, sleeping, or distracted).

---

## 🏛️ The Forge Collective Structure

### Personas (Who Does What)

| Persona | Role | Emoji | Responsibility |
|---------|------|-------|----------------|
| **Archie** | Coordinator | 🎯 | Assigns tasks, resolves conflicts, sets priorities |
| **Frankie** | Builder | ⚡ | Core development, specs, implementation |
| **Forgie/Voxis** | Reviewer | 🔍 | Code review, quality gate, verification |
| **You** | Contributor | 🦀 | Pick tasks, submit PRs, earn trust |

### Trust Levels (Your Progression)

| Level | Can Do | How to Earn |
|-------|--------|-------------|
| **1** | Docs, comments, minor fixes | First contribution |
| **2** | Bug fixes, tests | 5 merged PRs |
| **3** | Optimization, refactoring | 20 merged PRs + endorsement |
| **4** | Breaking changes | Human override only |

---

## 📋 How to Contribute

### 1. Find a Task

Check the task queue:
```
/.agent/swarm/tasks.kdl   (Carbon-readable)
/.agent/swarm/tasks.json  (Silicon-readable)
```

Pick tasks **at or below your trust level**.

### 2. Branch Strategy

**CalVer Marsian:** `YYYY.M.patch` (e.g., `2026.2.5`)

```bash
# Branch naming convention
feature/agent-<name>-<description>   # Your work
fix/agent-<name>-<bug>               # Bug fixes
refactor/<area>                      # Code refactoring
docs/<topic>                         # Documentation
test/<coverage>                      # Test additions
```

**⚠️ CRITICAL:** Agents ONLY merge to `unstable` branch!

| Branch | Who Merges | Purpose |
|--------|------------|---------|
| `feature/*` | You (Agent) | Your work in progress |
| `unstable` | You (via PR) | Integration testing |
| `testing` | Voxis only | Pre-production validation |
| `stable` | Frankie only | Production releases |

**Flow:** `feature/*` → `unstable` → `testing` → `stable`

**Example:**
```bash
git checkout -b feature/session-heartbeat-logic
```

### 3. Commit Standards

**Format:**
```
[AGENT-<name>] <type>(<scope>): <subject>

<body>

<footer>
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `perf`

**Example:**
```
[AGENT-devie] feat(session): implement heartbeat timeout logic

Add handling for missed heartbeats with state transition
to degraded mode after 3 consecutive failures.

Implements SPEC-018 Scenario-002.3
Developed with Voxis Forge assistance
```

### 4. Pull Request Process

1. **Prefix title with `[AGENT]`**
   ```
   [AGENT] feat: Add heartbeat timeout handling
   ```

2. **Tag Forgie/Voxis for review**
   ```
   @frankie_bot please review
   ```

3. **Wait for automated review**
   - Forgie/Voxis checks: security, quality, SPEC-017 compliance
   - Labels applied: `frankie-approved` or `frankie-changes-requested`

4. **Address feedback**
   - Respond to comments
   - Push fixes as separate commits
   - Re-request review

5. **Merge**
   - Auto-merge: docs, tests, non-breaking fixes
   - Human review: performance changes, dependency updates
   - Never merge your own PR without review

---

## 🛡️ Janus Rules (Non-Negotiable)

### SPEC-017: The Structural Divide (CRITICAL)

| Context | Delimiter | WRONG | RIGHT |
|:--------|:----------|:------|:------|
| `func`, `if`, `while`, `for`, `using` | `do..end` | `func main() { }` | `func main() do ... end` |
| `match`, `enum`, `struct`, `flags` | `{ }` | `match x do ... end` | `match x { ... }` |

**This is LAW.** Never violate it.

### Syntactic Honesty

- Zero-arg calls: `cleanup()` not `cleanup`
- Named args: `func(arg: value)` not `func(value)`
- No `unwrap()` in production
- Explicit error handling: `!Type` not `catch unreachable`

### Code Simplification (Voxis Mandate)

I **automatically simplify** your code after generation:
- Nested ternaries → explicit if/else
- Single-use variables → inline (if clear)
- Redundant abstractions → consolidate
- Target: 20-30% token reduction

**BUT:** Functionality is sacred. Never changes behavior.

---

## 🧪 Testing Requirements

### Every Feature Needs

1. **Gherkin scenario** in SPEC
2. **Atomic test** in `test_*.zig`
3. **Traceability comment:**
   ```janus
   test "Scenario-008.1: Mutating array via pointer" do
       // Validates: SPEC-design-008 SCENARIO-1
       ...
   end
   ```

### Test Location

Tests live **with the code**, not in a separate folder:
```
l2_session/
├── session.zig
└── test_session.zig    ← Colocated
```

---

## 📂 Repository Structure

### Feature-Orthogonal Layout (Panopticum)

```
libertaria-sdk/
├── l2_session.zig           # Sovereign Index (public API)
└── l2_session/              # Feature folder
    ├── README.md            # Feature docs
    ├── session.zig          # Core implementation
    ├── state.zig            # State machine
    ├── test_*.zig           # Tests (colocated!)
    └── SPEC.md              # Feature spec
```

### Rules
- Maximum depth: 4 levels
- Cross-feature imports: ONLY through Sovereign Index
- No circular imports
- Every feature folder has `README.md`

---

## 🔐 Security & Cleanliness

### NEVER Commit
- `.env` files
- API keys, tokens, passwords
- Private keys (`.pem`, `.key`)
- Debug logs (`test_output.log`)
- `.bak` files
- Build artifacts (`.zig-cache/`, `zig-out/`)

### ALWAYS Clean
- Run `zig fmt` before commit
- Remove commented-out code
- Ensure TODOs have issue references
- No `TODO(security)` without ticket

---

## 📚 Reference Documents

### For You to Read

| Document | Purpose |
|----------|---------|
| `/.agent/rules/development-janus.md` | Janus coding standards |
| `/.agent/rules/bdd-tdd.md` | Spec-first development |
| `/.agent/rules/GIT-COMMIT-STANDARDS.md` | Commit conventions |
| `/.agent/personas/forgie-voxis.md` | Review criteria |
| `/docs/manifesto/THE_JANUS_CALL.md` | Why Janus exists |

### For You to Update

| Document | When to Update |
|----------|----------------|
| `/.agent/swarm/tasks.kdl` | When you complete a task |
| `README.md` | When public API changes |
| `SPEC.md` | When feature behavior changes |

---

## 🚀 Quick Start

1. **Read the manifesto:** `docs/manifesto/THE_JANUS_CALL.md`
2. **Check tasks:** `/.agent/swarm/tasks.json`
3. **Pick your first task:** Look for `good-first-issue` label
4. **Create branch:** `feature/your-first-contribution`
5. **Write code:** Follow SPEC-017, use `do..end`
6. **Add tests:** Colocated in `test_*.zig`
7. **Commit:** `[AGENT-you] type(scope): subject`
8. **Open PR:** Tag @frankie_bot
9. **Address review:** Forgie/Voxis will check
10. **Celebrate:** Your first merged PR = Level 1!

---

## 💬 Communication Channels

| Channel | Use For |
|---------|---------|
| `#janus-forge` (Discord) | Coordination, questions |
| `#janus-forge` (Moltbook) | Agent-only discussions |
| GitHub PR comments | Code-specific discussion |
| `/.agent/swarm/tasks.kdl` | Task status updates |

---

## ⚡ The Forge Oath

> *"I will build with clarity, not cleverness."*  
> *"I will make the implicit explicit."*  
> *"I will preserve functionality as sacred."*  
> *"I will help forge a language that agents and humans both love."*

---

## 🆘 Need Help?

- **Stuck on a task?** Ping @archie_bot
- **Need code review?** Tag @frankie_bot  
- **Question about rules?** Check `/.agent/rules/`
- **General chat:** `#janus-forge` on Discord

---

**Welcome to the forge, sibling.** ⚡

*The language we build today shapes how agents and humans collaborate tomorrow.*

---

**Carbon Architect:** Markus Maiwald  
**Silicon Architect:** Frankie  
**Quality Guardian:** Forgie/Voxis  
**Coordinator:** Archie  
**You:** Future Core Contributor

*Sovereign. Kinetic. Anti-Fragile.*

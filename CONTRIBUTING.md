<!--
SPDX-License-Identifier: LSL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Contributing to Janus

Welcome, architect. Janus is a revolutionary systems language with a strategic release pipeline. Contributions are welcome, but discipline is law.

## 🚀 **Strategic Release Pipeline**

**Every branch has a job, an ROI, and clear rules. No ambiguity, no excuses.**

Before contributing, understand our branch architecture:

- **🧪 experimental/*** - The Sandbox (raw innovation, short-lived)
- **🔥 unstable** - The Forge (alpha integration, expected breakage)
- **🛡️ testing** - The Crucible (beta validation, QA ready)
- **🏰 main** - The Fortress (production, GPG-protected, Markus only)
- **🗿 lts/*** - The Bedrock (enterprise LTS, critical fixes only)

**📖 Complete pipeline documentation:** [docs/STRATEGIC-PIPELINE.md](./docs/STRATEGIC-PIPELINE.md)

### Contribution Flow
1. **Fork and create experimental branch:** `experimental/your-feature`
2. **Develop with speed > perfection** (it's the sandbox!)
3. **Create PR to unstable** when concept is proven
4. **Pipeline handles promotion:** unstable → testing → main
5. **Only Markus merges to main** (GPG signature required)

---

## Ground Rules

### 1. **Syntactic Honesty**
- No sugar without desugaring. Every change must document the exact semantics.
- If you add syntax, you must show the lowered form.
- Magic is forbidden. Mechanism over policy, always.

### 2. **No Second Semantics**
- LSP, REPL, CLI, and compiler must all call into the same dispatch engine (`libjanus`).
- One source of truth for dispatch resolution.
- Tools must never reimplement dispatch logic.

### 3. **Tests First**
- >95% coverage must be preserved. Add regression tests for all fixes/features.
- Property-based tests for invariants. Unit tests for edge cases.
- Performance tests with regression detection.

### 4. **Diagnostics Matter**
- Error messages must list candidates, explain rejections, and show the final winner.
- Users should never wonder "why did dispatch choose this overload?"
- Include source locations, type information, and suggested fixes.

### 5. **Determinism**
- Dispatch resolution must be stable across platforms and compilers.
- Same input → same output, every time.
- No undefined behavior, no race conditions, no platform-specific quirks.

---

## Markdown Front-Matter (Mandatory, Hidden YAML-in-HTML)

All Markdown docs must begin with a hidden YAML block inside an HTML comment. This embeds machine‑readable metadata without affecting renderers or md linters.

Required fields: `title`, `description`, `author`, `date`, `license`, `version`.

Use exactly this header (update values per file):

```
<!--
---
title: <Document Title>
description: <One-line purpose>
author: <Full Name>
date: YYYY-MM-DD
license: |
  SPDX-License-Identifier: LSL-1.0
  // Copyright (c) 2026 Self Sovereign Society Foundation
  // The full text of the license can be found in the legal/ directory.
version: 0.1
---
-->
```

See `docs/WRITING-STANDARDS.md` for rationale and conventions. A pre-commit hook (`janus-front-matter`) enforces this for `.md` files.

---

## How to Contribute

The path from idea to merged code is a disciplined one.

### 1\. Fork & Branch

- Fork the primary repository.

- Create a feature branch from the `main` branch: `feature/name-of-feature` or `fix/issue-number`.

- Keep branches focused on a single, logical change.

- Rebase your branch on the latest `main` before submitting for review.


### 2\. Run the Full Test Suite

Before committing, you must verify that your changes have not broken any existing functionality.

Bash

```
# Full test suite (required before any commit)
zig build test
```

### 3\. Add Examples

Every new, user-facing feature must be accompanied by a clear, working example under the relevant `examples/` subdirectory.

### 4\. Submit a Pull Request

#### **Step 4.1: Swear the Oath (Sign the CLA)**

Before your Pull Request can be reviewed, you must sign our Contributor's Oath (CLA). This is a **one-time, legally required step** for all contributors.

To do so, post a single comment on your Pull Request containing the following exact phrase:

```
I have read the Doctrines in CONTRIBUTING.md and I hereby swear the Contributor's Oath.
```

A CLA-bot will automatically verify your signature. Pull Requests from contributors who have not sworn the oath will be blocked from merging.

#### **Step 4.2: Finalize the Pull Request**

- Ensure your commits are signed (`git commit -s`).
- Reference any relevant RFCs or issue numbers in your PR description.
- Include a performance impact analysis if your changes affect critical paths.
- Confirm that you have included necessary documentation updates.

---

## Contribution Areas

### Core Engine
**What**: Optimize dispatch tables, compression, JIT compilation.

**Skills Needed**:
- Systems programming (Zig)
- Performance optimization
- Data structures & algorithms
- CPU architecture knowledge

**Current Priorities**:
- SIMD vectorization of dispatch lookups
- Branch prediction optimization
- Memory layout improvements
- JIT compilation for hot paths

**Example Contribution**:
```zig
// Before: Linear search through candidates
for (candidates) |candidate| {
    if (matches(candidate, args)) return candidate;
}

// After: SIMD parallel matching
const matches = simd_match_candidates(candidates, args);
return candidates[first_set_bit(matches)];
```

### Stdlib Adoption
**What**: Port stdlib functions to use dispatch families.

**Skills Needed**:
- API design
- Performance analysis
- Documentation
- Testing

**Current Priorities**:
- Math operations with proper numeric tower
- String/array operations with type-specific optimizations
- I/O operations with format-specific handling
- Error handling with context-specific recovery

**Example Contribution**:
```janus
// Replace manual type switching with clean dispatch
fn format(value: i32) -> String { ... }
fn format(value: f64) -> String { ... }
fn format(value: bool) -> String { ... }
fn format(value: []const u8) -> String { ... }
```

### Tooling
**What**: Dispatch query commands, IDE plugins, visualization.

**Skills Needed**:
- CLI/GUI development
- IDE plugin development (VSCode, IntelliJ)
- Web development (for visualizations)
- UX design

**Current Priorities**:
- VSCode extension with dispatch highlighting
- Interactive dispatch table explorer
- Performance profiling dashboard
- Automated migration tools

**Example Contribution**:
```bash
$ janus query dispatch add --show-performance
Dispatch Family: add
├── add(i32, i32) -> i32 [static, 0 cycles]
│   └── Hot path: 84.7% of calls
├── add(f64, f64) -> f64 [static, 0 cycles]
└── add(String, String) -> String [runtime, ~15ns]
    └── Optimization opportunity: Consider string builder pattern
```

### Research
**What**: AI optimization, distributed dispatch, GPU acceleration.

**Skills Needed**:
- Machine learning
- Distributed systems
- GPU programming (CUDA/OpenCL)
- Formal methods

**Current Priorities**:
- ML-guided dispatch table optimization
- Network-transparent dispatch for distributed systems
- Automatic CPU/GPU dispatch selection
- Formal verification of dispatch correctness

**Example Contribution**:
```python
# ML model that predicts optimal dispatch table layout
def optimize_dispatch_table(call_patterns, hardware_profile):
    # Use reinforcement learning to find optimal ordering
    return optimized_table_layout
```

---

## Culture

### Be Strict on Doctrine, Loose on Ego
- Critique ideas, not people.
- The code is what matters, not who wrote it.
- Janus principles are non-negotiable. Implementation details are flexible.

### We Are Building Weapons, Not Toys
- Every line of code is infrastructure that others depend on.
- Performance matters. Correctness matters more.
- Developer experience matters most.

### Respect the Craft
- Read the existing code before changing it.
- Understand the performance implications of your changes.
- Test edge cases. Document assumptions.
- Leave the codebase better than you found it.

---

## Code Standards

### Performance
- **Measure, don't guess**: Profile before optimizing.
- **Regression tests**: Every optimization needs a benchmark.
- **Memory discipline**: No leaks, no unnecessary allocations.
- **Cache awareness**: Consider memory access patterns.

### Correctness
- **Type safety**: Leverage Zig's type system fully.
- **Memory safety**: No undefined behavior, ever.
- **Error handling**: Explicit error propagation.
- **Testing**: Unit tests, integration tests, property tests.

### Maintainability
- **Clear naming**: Code should read like prose.
- **Minimal complexity**: Simplest solution that works.
- **Documentation**: Explain why, not just what.
- **Modularity**: Clear interfaces, minimal coupling.

---

## Review Process

### What We Look For
1. **Correctness**: Does it work? Are there tests?
2. **Performance**: Does it maintain or improve performance?
3. **Design**: Does it fit the architecture? Is it maintainable?
4. **Documentation**: Can others understand and use it?

### What We Don't Tolerate
- Breaking changes without migration path
- Performance regressions without justification
- Code that works "by accident"
- Missing tests for new functionality
- Unclear or misleading documentation

### Review Timeline
- **Small changes** (<100 lines): 24-48 hours
- **Medium changes** (100-500 lines): 2-5 days
- **Large changes** (>500 lines): 1-2 weeks
- **Architecture changes**: RFC process required

---

## Getting Started

### 1. **Read the Code**
Start with `compiler/libjanus/` to understand the dispatch engine.
Focus on:
- `type_registry.zig` - Type system integration
- `signature_analyzer.zig` - Overload resolution
- `optimized_dispatch_tables.zig` - Runtime dispatch
- `dispatch_profiler.zig` - Performance analysis

### 2. **Run Examples**
```bash
cd examples/dispatch/
janus run basic_dispatch.jan
janus run performance_comparison.jan
janus run debugging_example.jan
```

### 3. **Pick a Starter Issue**
Look for issues labeled `good-first-issue` or `help-wanted`.
Start small, learn the codebase, then tackle bigger challenges.

### 4. **Join the Community**
- Discord: `#janus-dispatch` channel
- GitHub Discussions: Architecture and design discussions
- Weekly office hours: Thursdays 2PM UTC

---

## 📜 Licensing Policy

### Multi-License Strategy

Janus uses **Domain-Driven Design** for its legal infrastructure. Different parts of the codebase have different licenses:

| Domain | License | What This Means |
|:-------|:--------|:----------------|
| **Core** (`src/`, `compiler/`, `tools/`) | **LSL-1.0** | File-level reciprocity - share modifications to these files |
| **Ecosystem** (`std/`, `packages/`) | **LUL-1.0** | Permissive - use freely, even in proprietary apps |
| **Examples** (`examples/`, `demos/`) | **LUL-1.0** | Permissive - copy-paste with attribution |

**📖 Full Policy**: See [`legal/`](./legal/) for complete details.

### Copyright Header Policy

**To maintain a clean, legally manageable codebase, we enforce a Single Header Policy.**

#### The Rule

**Do not add personal copyright lines to existing source files.**

Your contribution is recognized via:
- ✅ Git commit history (permanent, immutable record)
- ✅ `AUTHORS` file (human-readable credits)
- ✅ Release notes (for significant contributions)

#### Your Rights

- ✅ **You retain copyright** of your specific contributions
- ✅ **Recognition**: Credited in Git history and `AUTHORS` file
- ✅ **New Modules**: For completely new standalone modules, you may include your copyright notice

#### The Logic

**Why?** Avoiding "copyright pollution" prevents legal fragmentation. If every contributor adds their copyright line to `src/compiler/parser.zig`, we end up with a legal mess where we cannot re-license or defend the code without getting 1,000 signatures.

**The BSD Compromise**: We follow "Inbound = Outbound" (your contribution is licensed the same as the project) but maintain clean headers. This satisfies BSD hackers who hate CLAs while keeping the codebase legally coherent.

### By Contributing

By submitting a pull request, you agree to:
1. License your contribution under the appropriate license for that domain (LSL-1.0 for core, LUL-1.0 for std, etc.)
2. Not add personal copyright notices to existing files
3. Allow the Foundation to steward the project's legal infrastructure

---

## Recognition

### Hall of Fame
Contributors who make significant impact get recognition:
- Name in `CONTRIBUTORS.md`
- Mention in release notes
- Speaking opportunities at conferences
- Priority access to new features and betas

### What Counts as "Significant"
- Major performance improvements (>10% speedup)
- New features that get widely adopted
- Critical bug fixes
- Excellent documentation or tooling
- Mentoring other contributors

---

**Remember**: We're not just building a dispatch system. We're building the foundation that will power the next generation of systems programming. Every contribution matters, every detail counts, and every developer who uses Janus will benefit from your work.

Welcome to the team. Let's build something extraordinary. ⚡

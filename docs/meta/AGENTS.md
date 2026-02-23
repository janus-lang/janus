<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# 🤖 AI Agent Guide for Janus

**Purpose**: This document provides essential context for AI agents (Claude, GPT, Gemini, Copilot, etc.) working on the Janus codebase.

**Last Updated**: 2025-12-13  
**Status**: ✅ Active

---

## 📋 Quick Reference

| Resource | Path | Purpose |
|:---------|:-----|:--------|
| **Repository Structure** | [`docs/meta/REPOSITORY_STRUCTURE.md`](meta/REPOSITORY_STRUCTURE.md) | Complete directory layout and file purposes |
| **License Policy** | [`LICENSE_POLICY.md`](../LICENSE_POLICY.md) | Domain-Driven Licensing (LSL-1.0, Apache-2.0, CC0) |
| **Contributing Guide** | [`CONTRIBUTING.md`](../CONTRIBUTING.md) | How to contribute, coding standards |
| **Version Management** | [`docs/ops/VERSION_MANAGEMENT.md`](ops/VERSION_MANAGEMENT.md) | SemVer, Git hooks, version bumping |
| **License Headers** | [`docs/legal/license-headers.md`](../legal/license-headers.md) | Required headers for each directory |

---

## 🏛️ Project Overview

**Janus** is a systems programming language with:
- **Dispatch Families** - Multi-method dispatch at compile time
- **Profile-based Compilation** - `:core`, `:service`, `:sovereign` profiles
- **Capability-based Security** - Explicit permissions for I/O, network, etc.
- **Semantic Honesty** - No hidden magic, explicit desugaring

### Technology Stack
| Component | Technology |
|:----------|:-----------|
| Compiler | Zig 0.15.2+ |
| Build System | `build.zig` (Zig Build System) |
| Tests | Zig test runner |
| LSP | Zig + MessagePack |
| IDE | VSCode extension |

---

## 📁 Critical Directories

### Core (LSL-1.0 License)
```
compiler/           # Core compiler implementation
├── libjanus/       # Main compiler library
├── qtjir/          # Quantum-Tensor IR
└── passes/         # Compilation passes

src/                # CLI entry points
daemon/             # Background daemon
lsp/                # Language Server Protocol
tools/              # Development tools
```

### Ecosystem (Apache-2.0 License)
```
std/                # Standard library
packages/           # Community packages
```

### Examples (CC0-1.0 License)
```
examples/           # Code examples
demos/              # Demo applications
```

---

## 🔧 Essential Commands

```bash
# Build the compiler
zig build

# Run tests
zig build test

# Run specific test
zig build test-qtjir

# Show version
./janus version show

# Bump version (dev build)
./janus version bump dev
```

---

## 📏 Code Standards

### Zig Files
- Use `std.testing` for tests
- Prefer explicit error handling (`try`/`catch`)
- Use `ArenaAllocator` for temporary allocations
- Follow Zig style guide (snake_case, PascalCase for types)

### Janus Files (.jan)
- Profile declaration at top: `profile :core`
- Explicit type annotations preferred
- Use dispatch families for polymorphism

### License Headers
**All files MUST have correct SPDX headers.**

```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
```

See [`docs/LICENSE-HEADERS.md`](LICENSE-HEADERS.md) for complete templates.

---

## 🚫 Anti-Patterns (AVOID)

1. **Never add personal copyright to existing files** - Single header policy
2. **Never commit generated files** - `.zig-cache/`, `zig-out/`, `*_generated.c`
3. **Never use `janus` command directly** - Use `./janus` (local stub) or `./scripts/version.sh`
4. **Never modify `third_party/`** - External dependencies are frozen
5. **Never put test files in root** - Use `tests/` or `attic/snippets/`

---

## 🗂️ Repository Content Hygiene

### What BELONGS in the Public Repository

✅ **User/Teaching/Developer documentation**  
✅ **RFCs** (formal design documents)  
✅ **Implementation code**  
✅ **Tests**  
✅ **Examples**  

### What does NOT BELONG

❌ **Status reports** (keep in conversation context, NOT in committed files)  
❌ **Progress tracking documents**  
❌ **Working notes**  
❌ **Operational documents** for project creation/development  

**Critical Rule:** Keep the repository clean and professional. Internal AI agent progress tracking, status reports, and working notes are for conversation context ONLY. They clutter the repository and confuse contributors/users.

---

## 🧪 Testing Strategy

### Unit Tests
Location: `tests/unit/`
Run: `zig build test`

### Integration Tests
Location: `tests/integration/`
Run: `zig build test-integration`

### Golden Tests
Location: `tests/golden/`
Purpose: Reference output comparison

### Benchmarks
Location: `bench/`
Run: `zig build bench`

---

## 🤖 AI Governance: The AIRLOCK Protocol

**Status**: ACTIVE  
**Doctrine**: [`docs/doctrines/AIRLOCK.md`](../doctrines/AIRLOCK.md)

### Philosophy

> "Policies are ignored; mechanisms are enforced by physics."

Until AI demonstrably surpasses human capability in software engineering, Janus enforces **cryptographic governance** for AI contributions. This is not a policy—it is a **physically enforced mechanism** using GPG signatures and branch protection.

### The Airlock Workflow

```
AI creates → features/ai/feature-name
          ↓
       Opens PR → dev
          ↓
    🤖 Gatekeeper validates Proof Package
          ↓
    👤 Human reviews + GPG-signs merge
          ↓
       Code enters → dev
```

### Branch Hierarchy

| Branch | Access | AI Allowed? | Requirement |
|:-------|:-------|:------------|:------------|
| 🔴 `stable` | Human Council | ❌ No | GPG-signed commits, Admin only |
| 🟡 `dev` | Human Verifier | ❌ No | Human-signed merge commits |
| 🟢 `features/ai/*` | AI Airlock | ✅ Yes | Open iteration, PR required |
| 🔵 `features/human/*` | Human Direct | ✅ Yes | Direct merge to `dev` |

### Proof Package Requirements

Every AI contribution MUST include:

1. **Spec** (`specs/rfc-XXX-feature.md`) - Acceptance Criteria in BDD format
2. **Test** (`tests/*/test_feature.zig`) - Failing test written BEFORE implementation
3. **Code** (`compiler/*/feature.zig`) - Minimal implementation to pass tests
4. **Evidence** (CI logs) - All tests pass, no regressions

### Enforcement Mechanisms

1. **Local Hook** (`.githooks/pre-push`)
   - Detects AI identity (`voxis-forge@janus-lang.org`)
   - Blocks AI from pushing to protected branches
   - Forces AI to use feature branches

2. **CI Gatekeeper** (`.forgejo/workflows/gatekeeper.yaml`)
   - Validates Proof Package structure
   - Runs build and test suite
   - Blocks AI self-merge
   - Requires human GPG-signed merge

3. **Branch Protection Rules** (Forgejo/GitHub)
   - `stable`: Admin only, signed commits
   - `dev`: Human review required, block AI push
   - `main`: Same as `dev`

### AI Agent Identity

**Name**: Voxis Forge AI  
**Email**: `voxis-forge@janus-lang.org`  
**Key**: GPG key (see AIRLOCK.md for generation)

### Testing the Airlock

```bash
# Configure AI identity
git config user.name "Voxis Forge AI"
git config user.email "voxis-forge@janus-lang.org"

# Try to push to dev (should fail)
git checkout dev
git push origin dev  # ❌ AIRLOCK: ACCESS DENIED

# Create feature branch (should succeed)
git checkout -b features/ai/test-feature
git push origin features/ai/test-feature  # ✅ Allowed
```

**Read the full doctrine**: [`docs/doctrines/AIRLOCK.md`](../doctrines/AIRLOCK.md)

---

## 🔀 Git Workflow

### Branches
| Branch | Purpose |
|:-------|:--------|
| `main` | Production (GPG-signed merges only) |
| `unstable` | Development integration |
| `experimental/*` | Feature experiments |

### Commit Messages
Use conventional commits:
```
feat: add new dispatch optimization
fix: resolve memory leak in parser
chore: update license headers
docs: improve AGENTS.md
```

### Pre-commit Hooks
Located in `.githooks/` - automatically validate:
- VERSION file format
- Branch-version consistency
- Forge Cycle artifacts

---

## 📖 Progressive Disclosure (Deep Dive)

Understanding Janus requires navigating from high-level concepts to implementation details. This section provides a **layered approach** to learning the codebase.

### 🎯 Layer 0: Meta & Navigation
| Document | Purpose |
|:---------|:--------|
| [`docs/meta/REPOSITORY_STRUCTURE.md`](meta/REPOSITORY_STRUCTURE.md) | **START HERE** - Directory layout, file purposes |
| [`docs/AGENTS.md`](AGENTS.md) | This document - AI agent quick reference |
| [`README.md`](../README.md) | Project overview and quick start |

### 📜 Layer 1: Core Specifications (The Language)
| Spec | Purpose |
|:-----|:--------|
| [`docs/specs/SPEC-syntax.md`](specs/SPEC-syntax.md) | **Language Syntax** - Grammar, tokens, expressions |
| [`docs/specs/SPEC-semantics.md`](specs/SPEC-semantics.md) | **Language Semantics** - Type system, evaluation rules |
| [`docs/specs/SPEC-profiles.md`](specs/SPEC-profiles.md) | **Profile System** - `:core`, `:service`, `:sovereign`, `:script` |
| [`docs/specs/SPEC-grammar.md`](specs/SPEC-grammar.md) | Formal grammar specification |
| [`docs/specs/SPEC-tokenizer.md`](specs/SPEC-tokenizer.md) | Lexical analysis specification |

### 🏛️ Layer 2: Architecture Specifications
| Spec | Purpose |
|:-----|:--------|
| [`docs/specs/SPEC-repo-architecture.md`](specs/SPEC-repo-architecture.md) | Repository and module architecture |
| [`docs/specs/SPEC-cli.md`](specs/SPEC-cli.md) | CLI command structure and options |
| [`docs/specs/SPEC-runtime.md`](specs/SPEC-runtime.md) | Runtime system design |
| [`docs/specs/SPEC-sema.md`](specs/SPEC-sema.md) | Semantic analysis passes |
| [`docs/specs/SPEC-astdb-schema.md`](specs/SPEC-astdb-schema.md) | AST database schema |
| [`docs/specs/SPEC-query-engine.md`](specs/SPEC-query-engine.md) | Query engine for incremental compilation |

### ⚡ Layer 3: Advanced Specifications
| Spec | Purpose |
|:-----|:--------|
| [`docs/specs/SPEC-qtjir.md`](specs/SPEC-qtjir.md) | **QTJIR** - Quantum-Tensor IR design |
| [`docs/specs/SPEC-jit.md`](specs/SPEC-jit.md) | JIT compilation (Prophetic Forge) |
| [`docs/specs/SPEC-foreign.md`](specs/SPEC-foreign.md) | Foreign function interface (FFI) |
| [`docs/specs/SPEC-boot-and-capabilities.md`](specs/SPEC-boot-and-capabilities.md) | Capability-based security model |
| [`docs/specs/SPEC-crypto-foundation.md`](specs/SPEC-crypto-foundation.md) | Cryptographic foundations |
| [`docs/specs/SPEC-citadel-protocol.md`](specs/SPEC-citadel-protocol.md) | Citadel secure protocol |

### 🛡️ Layer 4: Doctrines (Design Philosophy)
| Doctrine | Purpose |
|:---------|:--------|
| [`docs/doctrines/JanusMemoryDoctrine.md`](doctrines/JanusMemoryDoctrine.md) | **Memory management philosophy** |
| [`docs/doctrines/AIRLOCK.md`](doctrines/AIRLOCK.md) | **AI-Airlock Protocol** - Cryptographic governance for AI contributions |
| [`docs/doctrines/DOCTRINE-garden-wall.md`](doctrines/DOCTRINE-garden-wall.md) | Garden wall security model |
| [`docs/doctrines/DOCTRINE_ARRAYLIST_ZIG_0.15.2.md`](doctrines/DOCTRINE_ARRAYLIST_ZIG_0.15.2.md) | ArrayList usage in Zig 0.15.2 |
| [`docs/doctrines/PROBATIO.md`](doctrines/PROBATIO.md) | Testing doctrine |
| [`docs/doctrines/ARSENAL_DOCTRINE.md`](doctrines/ARSENAL_DOCTRINE.md) | Tool and arsenal philosophy |
| [`docs/doctrines/sovereign-graph-ownership.md`](doctrines/sovereign-graph-ownership.md) | Graph ownership model |
| [`docs/doctrines/The Janus Registry Sovereignty Protocol (RSP-1).md`](doctrines/The%20Janus%20Registry%20Sovereignty%20Protocol%20(RSP-1).md) | Package registry sovereignty |

### ⚖️ Layer 5: Legal & Governance
| Document | Purpose |
|:---------|:--------|
| [`LICENSE_POLICY.md`](../LICENSE_POLICY.md) | Domain-Driven Licensing strategy |
| [`docs/LICENSE-HEADERS.md`](LICENSE-HEADERS.md) | Required license headers |
| [`docs/LICENSE-AUTOMATION-USAGE.md`](LICENSE-AUTOMATION-USAGE.md) | License automation tools |
| [`SECURITY.md`](../SECURITY.md) | Security policy |

### 🔧 Layer 6: Operations
| Document | Purpose |
|:---------|:--------|
| [`docs/ops/VERSION_MANAGEMENT.md`](ops/VERSION_MANAGEMENT.md) | Version control and SemVer |
| [`docs/manual/ERRORS.md`](manual/ERRORS.md) | Error codes and messages |

---

## 📚 Key Specs Quick Reference

### The "Big Three" Language Specs
1. **[SPEC-syntax.md](specs/SPEC-syntax.md)** - How Janus code looks
2. **[SPEC-semantics.md](specs/SPEC-semantics.md)** - What Janus code means
3. **[SPEC-profiles.md](specs/SPEC-profiles.md)** - What features are available

### Profile-Specific Specs
| Profile | Spec |
|:--------|:-----|
| `:core` | Minimal - see [SPEC-profiles.md](specs/SPEC-profiles.md) |
| `:service` | Structured concurrency - [SPEC-profiles.md](specs/SPEC-profiles.md) |
| `:sovereign` | Capability-secured - [SPEC-boot-and-capabilities.md](specs/SPEC-boot-and-capabilities.md) |
| `:script` | Interactive - [SPEC-profile-script.md](specs/SPEC-profile-script.md) |
| `:service` | Network services - [SPEC-profile-service.md](specs/SPEC-profile-service.md) |
| `:compute` | HPC/GPU - [SPEC-profile-compute.md](specs/SPEC-profile-compute.md) |

---

## 🤝 Working with the Codebase

### Before Making Changes
1. Read [`CONTRIBUTING.md`](../CONTRIBUTING.md)
2. Understand the [Repository Structure](meta/REPOSITORY_STRUCTURE.md)
3. Check the [License Policy](../LICENSE_POLICY.md) for your target directory
4. Run `zig build` to verify the project builds

### Making Changes
1. Create feature branch from `unstable`
2. Add appropriate license headers
3. Write tests for new functionality
4. Run `zig build test` before committing
5. Update relevant documentation

### After Changes
1. Bump version: `./janus version bump dev`
2. Commit with conventional message
3. Push to your branch
4. Create PR to `unstable`

---

## 🔍 Finding Things

### Search Commands
```bash
# Find file by name
find . -name "*.zig" -path "*/compiler/*"

# Search in code
grep -r "dispatch" compiler/

# Find all tests
find tests/ -name "*.zig"
```

### Key Entry Points
| Purpose | File |
|:--------|:-----|
| Compiler main | `src/janus_main.zig` |
| Parser | `compiler/libjanus/janus_parser.zig` |
| Tokenizer | `compiler/libjanus/janus_tokenizer.zig` |
| Type system | `compiler/libjanus/type_registry.zig` |
| QTJIR graph | `compiler/qtjir/graph.zig` |
| LSP server | `lsp/lsp_server.zig` |
| Build config | `build.zig` |

---

## ⚠️ Common Gotchas

1. **Zig 0.15.2 Required** - Earlier versions have API differences
2. **ArrayList API Changed** - Use `.empty` not `.init(allocator)`
3. **Writer API Changed** - Use `.writer` not `.writer()`
4. **No `fmtSliceHexLower`** - Use inline hex formatting
5. **Version File** - Always update `VERSION` before release commits

---

## 📞 Quick Help

**Build fails?**
```bash
zig build 2>&1 | head -50  # Show first errors
```

**Tests fail?**
```bash
zig build test 2>&1 | grep -A5 "error:"  # Find test failures
```

**Version issues?**
```bash
./janus version show      # Check current version
./janus version validate  # Validate format
```

**License issues?**
```bash
./scripts/license-compliance-scan.sh  # Run compliance check
```

---

## 📚 External Resources

- **Zig Documentation**: https://ziglang.org/documentation/master/
- **SemVer Spec**: https://semver.org/
- **LSL-1.0 License**: See `LICENSE` file

---

**Welcome, AI Agent. Build something extraordinary.** ⚡

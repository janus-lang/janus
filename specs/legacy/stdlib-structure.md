<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC-stdlib-structure: Standard Library Organization

**Status:** DRAFT
**Version:** 0.1.0
**Date:** 2025-11-23

## 1. Overview

This specification defines the directory structure and organization of the Janus standard library (`std`). The structure adheres to the **Arsenal Doctrine**, organizing modules into "Domains of Sovereignty".

## 2. Directory Structure

The `std/` directory SHALL be organized as follows:

```
std/
├── core/           # The Spine: Memory, SIMD, Data Structures
│   ├── mem/        # Allocators (Arena, Pool, Stack)
│   ├── simd/       # Portable SIMD operations
│   └── ds/         # Data Structures (SoA, SwissMap)
├── sci/            # The NASA/Physics Package
│   ├── units/      # Dimensional Analysis
│   ├── geo/        # Geometric Algebra
│   └── ode/        # Differential Equation Solvers
├── math/           # The Number Cruncher
│   ├── lin/        # Linear Algebra
│   ├── fft/        # Fast Fourier Transform
│   └── spline/     # Curve Fitting
├── encoding/       # The Scribe (formerly data)
│   ├── json/       # JSON Processing
│   ├── csv/        # CSV Processing
│   ├── markdown/   # Markdown Processing
│   ├── html/       # HTML Processing
│   └── arrow/      # Columnar Data (for Analytics)
├── ai/             # The Intelligence
│   ├── tensor/     # N-dimensional Arrays
│   └── autograd/   # Automatic Differentiation
├── sys/            # The Operator
│   ├── net/        # Networking
│   ├── fs/         # Filesystem
│   └── proc/       # Process Control
├── quant/          # Quantum Arsenal (New)
│   ├── qbit/       # Qubit Simulation
│   ├── circuit/    # Quantum Circuits
│   └── algo/       # Quantum Algorithms
├── neuro/          # Neuromorphic (New)
│   ├── snn/        # Spiking Neural Networks
│   ├── plasticity/ # Learning Rules
│   └── swarm/      # Swarm Intelligence
├── crypto/         # Cryptography
│   └── anarch/     # Zero-Trust Fortress (ZK, FHE, MPC)
├── sim/            # Simulation
│   └── dist/       # Distributed Simulation
└── graft/          # Foreign Treaties
    ├── zig/        # Zig Integration
    ├── c/          # C Integration
    ├── py/         # Python Integration
    ├── rust/       # Rust Integration
    └── beam/       # Erlang/Elixir Integration
```

## 3. Module Rules

1.  **Atomic Import:** Each leaf directory (e.g., `std/math/lin`) MUST be a self-contained module importable via `import std.math.lin`.
2.  **Profile Gating:** Modules requiring specific hardware or capabilities (e.g., `std.quant`) MUST be gated by the appropriate compiler profile (e.g., `:quantum`).
3.  **Implementation Hiding:** The internal implementation (Haiku vs. Heavy Metal) MUST be hidden behind a clean, idiomatic Janus API.

## 4. File Naming

*   Module entry points: `mod.jan` (or `package.jan` pending final decision).
*   Source files: `snake_case.jan`.
*   Tests: `test_*.jan` or inline `test "name" { ... }`.

## 5. Grafting

Grafted modules reside in `std/graft/`. They provide the raw bindings to foreign libraries. Higher-level `std` modules (e.g., `std.data.arrow`) MAY use `std.graft.rust` to implement their functionality.

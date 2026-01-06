// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Foundational error types for libjanus.
// Expand with domain-specific error unions later.

pub const Error = error{
    Generic,
    ParseError,
    SemanticError,
    IOError,
};

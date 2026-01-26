// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Runtime Source Embedding
//!
//! This module exists to provide the runtime source code as an embedded
//! constant. Since @embedFile can only access files within the module's
//! package directory, this module (located in runtime/) can embed
//! janus_rt.zig while being imported from src/pipeline.zig.

/// The complete Janus runtime source code, embedded at compile time.
/// This enables the compiler to be fully self-contained - no external
/// runtime files needed at execution time.
pub const source = @embedFile("janus_rt.zig");

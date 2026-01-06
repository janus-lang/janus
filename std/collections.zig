// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Collections Library - High-performance, allocator-aware data structures
//!
//! This module provides the core collections for the Janus standard library:
//! - Vec<T>: Dynamic array with amortized O(1) append
//! - HashMap<K, V, Ctx>: Robin Hood hash map with static dispatch
//! - Deque<T>: Double-ended queue with circular buffer
//! - SmallVec<T, N>: Vector with inline storage that spills to heap
//!
//! All collections implement the tri-signature pattern for capability-based security
//! and follow data-oriented design principles for optimal cache performance.
//! See docs/CollectionsDoctrine.md for the canonical laws governing all containers.

/// Dynamic Array - Efficient, growable array with amortized O(1) append
pub const Vec = @import("collections/vec.zig").Vec;

/// Hash Map with Robin Hood Hashing - Fast key-value storage with open-addressing
pub const HashMap = @import("collections/hash_map.zig").HashMap;

/// Deque - Double-ended queue with circular buffer
pub const Deque = @import("collections/deque.zig").Deque;

/// SmallVec - Vector with inline storage that spills to heap
pub const SmallVec = @import("collections/small_vec.zig").SmallVec;

/// Wyhash Context - Default hash function (empirically validated)
pub const WyhashContext = @import("collections/hash_map.zig").WyhashContext;

/// XXH3 Context - Alternative hash function for large keys
pub const XXH3Context = @import("collections/hash_map.zig").XXH3Context;
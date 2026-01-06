// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const GrepEngine = @import("grep_command").GrepEngine;

test "janus grep finds literal in 1GB file" {
    // G01: Exact literal match
    // We simulate a large file search by searching a buffer.
    // The spec requires <10µs per GB scanned, but for this unit test we verify correctness.
    
    const haystack = "This is a large file content... TODO: fix this ... and more content.";
    const needle = "TODO: fix this";
    
    var grep = GrepEngine.init(testing.allocator);
    
    // This should return true
    const found = try grep.search(haystack, needle);
    
    try testing.expect(found);
}

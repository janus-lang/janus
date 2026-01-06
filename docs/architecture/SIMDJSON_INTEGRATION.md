<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# simdjson Integration Plan

**Status:** Architecture Complete, C Integration Pending  
**Priority:** HIGH (Arsenal Doctrine flagship feature)  
**Target Performance:** 4+ GB/s JSON parsing

## Current State

✅ **Architecture Complete** (`std/data/json/mod.jan`)
- Full API design with capability gating
- DOM and streaming interfaces
- Forensic error reporting
- CPU feature detection hooks

⏳ **C Library Integration Pending**
- Need to integrate simdjzon (Zig port of simdjson)
- Need to implement FFI bindings
- Need to wire up SIMD dispatch

## Integration Steps

### Phase 1: Add simdjson as Dependency (1-2 hours)

1. **Add simdjson to build.zig:**
```zig
const simdjson = b.dependency("simdjson", .{
    .target = target,
    .optimize = optimize,
});
exe.linkLibrary(simdjson.artifact("simdjson"));
```

2. **Create FFI bindings** (`std/graft/c/simdjson.zig`):
```zig
pub const simdjson_parser = opaque {};
pub const simdjson_document = opaque {};

pub extern fn simdjson_parse(
    json: [*:0]const u8,
    len: usize,
    parser: *simdjson_parser,
) callconv(.C) ?*simdjson_document;

pub extern fn simdjson_get_type(
    doc: *simdjson_document,
) callconv(.C) u8;
```

3. **Wire into `std/data/json/mod.jan`:**
- Replace placeholder `parse_with_simdjzon()` with actual C calls
- Implement `create_simdjzon_parser()` using FFI
- Add proper error handling

### Phase 2: Implement Core Functionality (2-3 hours)

1. **DOM Parser:**
   - Parse JSON string to `JsonValue`
   - Extract objects, arrays, strings, numbers
   - Handle errors with forensic traces

2. **Streaming Parser:**
   - Implement token-by-token parsing
   - Memory-efficient for large documents

3. **CPU Feature Detection:**
   - Use Zig's `std.Target.Cpu.Feature`
   - Detect AVX, AVX2, AVX-512
   - Fallback to scalar path if needed

### Phase 3: Testing & Benchmarking (1-2 hours)

1. **Unit Tests:**
   - Parse valid JSON
   - Handle malformed JSON
   - Capability validation

2. **Performance Tests:**
   - Measure throughput (target: 4+ GB/s)
   - Compare with other parsers
   - Profile SIMD utilization

3. **Integration Tests:**
   - Parse real-world JSON files
   - Test with jfind (config files)

## Alternative: Use Zig's std.json (Interim Solution)

For immediate jfind development, we can use Zig's built-in JSON parser:

```zig
// std/data/json/zig_fallback.zig
const std = @import("std");

pub fn parseJson(allocator: std.mem.Allocator, json: []const u8) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
}
```

This gives us:
- ✅ Working JSON parsing TODAY
- ✅ Can develop jfind immediately
- ⏳ Replace with simdjson later for performance

## Recommendation

**For jfind development:** Use Zig's std.json as interim solution  
**For Arsenal completion:** Implement full simdjson integration in next sprint

This follows the "Graft First, Then Rewrite" strategy from the Arsenal Doctrine.

## Resources

- simdjson: https://github.com/simdjson/simdjson
- simdjzon (Zig port): https://github.com/travisstaloch/simdjzon
- Zig FFI docs: https://ziglang.org/documentation/master/#C

## Next Actions

1. ✅ Document integration plan (this file)
2. ⏳ Create Zig fallback for immediate use
3. ⏳ Add simdjzon dependency to build.zig
4. ⏳ Implement FFI bindings
5. ⏳ Wire into std.data.json
6. ⏳ Test and benchmark

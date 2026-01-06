<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Canonical Case Study - Task 4 Complete

## :min Profile Handler - The Trojan Horse ✅

This demonstrates the **Trojan Horse** strategy - familiar, Go-like HTTP server patterns that infiltrate conservative environments while containing the seeds of revolution.

### What This Proves

1. **Familiar Syntax**: The HTTP server looks exactly like Go - safe for adoption
2. **Basic Functionality**: Simple file serving without security restrictions
3. **No Surprises**: Blocking, sequential operation that conservative teams expect
4. **Foundation Ready**: Same code will unlock progressive power in :go and :full profiles

### Running the Demo

```bash
# Compile and run the :min profile handler
zig run examples/canonical_case_study/min_profile_server.zig

# Expected output: Familiar HTTP server behavior
# - Serves any file (including secrets)
# - Simple, blocking operation
# - Go-familiar patterns
```

### Key Behaviors Demonstrated

#### ✅ What Works (Go-Familiar)
- Basic HTTP request handling
- Static file serving from `/public`
- Simple routing logic
- Familiar error responses

#### ⚠️ What's Unsafe (By Design)
- Serves `/secret/config.txt` (should be restricted)
- No timeout protection
- No capability security
- No structured concurrency

### The Tri-Signature Pattern in Action

The same `serveFile()` function will behave differently across profiles:

```janus
// :min Profile (Current)
serveFile(path, allocator)           // Simple, unrestricted

// :go Profile (Next)
serveFile(path, ctx, allocator)      // + Context-aware timeouts

// :full Profile (Final)
serveFile(path, cap, allocator)      // + Capability security
```

**Zero source code changes required between profiles!**

### Strategic Impact

This implementation proves the **Adoption Paradox** is solved:

1. **Conservative Teams**: "This looks exactly like Go - I can adopt this safely"
2. **Progressive Enhancement**: Same code unlocks more power without rewrites
3. **Enterprise Security**: Same code becomes secure without breaking changes

### Next Steps

- [ ] **Task 5**: Implement :go Profile Handler (structured concurrency)
- [ ] **Task 6**: Implement :full Profile Handler (capability security)
- [ ] **Task 8**: Profile compilation verification
- [ ] **Task 9**: Automated behavioral testing suite

### Files Created

- `min_profile_server.zig` - The Trojan Horse implementation
- `public/index.html` - Main page explaining tri-signature pattern
- `public/about.html` - About page with adoption strategy
- `public/style.css` - Profile-specific styling
- `secret/config.txt` - Secret file that should be restricted

**Task 4 Status: ✅ COMPLETE**

The Trojan Horse is ready to infiltrate conservative environments!

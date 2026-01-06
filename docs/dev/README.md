# Janus Development Roadmap: Quick Navigation

**Last Updated:** 2025-12-16  
**Current Status:** v0.2.1 Complete → v0.2.2 Planning

---

## 📍 **Where We Are**

**Latest Release:** v0.2.0-2  
**Next Release:** v0.2.1-0 (ready to tag)  
**Active Development:** v0.2.2-0 (LSP Server)

---

## 📚 **Documentation Index**

### **Current Development Plans**

| Document | Status | Purpose |
|:---------|:-------|:--------|
| **`CURRENT_PLAN-v0.2.1.md`** | ✅ Complete | :core profile implementation (DONE) |
| **`CURRENT_PLAN-v0.2.2.md`** | ⏳ Active | LSP Server implementation (NEXT) |
| **`RELEASE-SUMMARY-v0.2.1.md`** | ✅ Complete | v0.2.1 achievement summary |

### **Future Roadmaps**

| Document | Timeframe | Focus |
|:---------|:----------|:------|
| **`FUTURE_PLAN-v0.3.0.md`** | 6-12 months | The Grafting (Forth × Smalltalk × J) |
| **`memory-model-v0.2.5-v0.2.15.md`** | 4-8 months | V-inspired sovereign memory |
| **`j-inspired-tacit-arrays.md`** | v0.3.0-v0.4.0 | Array warfare & tacit programming |

### **Technical Deep-Dives**

| Document | Topic | Status |
|:---------|:------|:-------|
| **`LSP-IMPLEMENTATION-BRIEF.md`** | LSP architecture & blocker | ✅ Complete |
| **`match-exhaustiveness-implementation.md`** | Exhaustiveness checking | ✅ Complete |
| **`GRAFT-onyx-lobster.md`** | Strategic language grafts (v0.3-v0.4) | ✅ Complete |

### **Strategic Grafts**

| Document | Languages | Features | Timeline |
|:---------|:----------|:---------|:---------|
| **`GRAFT-onyx-lobster.md`** | Onyx + Lobster | WASM, Pipe Op, CTRC, Vectors | v0.3.0-v0.4.0 |

---

## 🎯 **Development Phases**

### **Phase 1: Ergonomics & Stability** (v0.2.x) ← **WE ARE HERE**

**Objective:** Crystal's joy + Rust's discipline

**Completed (v0.2.1):**
- ✅ Match statements (exhaustive, Elm-style)
- ✅ Postfix guards (RFC-018)
- ✅ Range expressions (`..`, `..<`)
- ✅ For loops (`for...in`)
- ✅ Array literals (`[1, 2, 3]`)

**In Progress (v0.2.2):**
- ⏳ LSP Server (Smalltalk-style introspection)
- ⏳ VS Code integration
- ⏳ Hover, go-to-definition, find references

**Upcoming (v0.2.3+):**
- UFCS (Uniform Function Call Syntax)
- Rebinding (shadowing)
- Code completion
- Rename refactoring

---

### **Phase 2: Flow & Plasticity** (v0.3.x)

**Objective:** Nim/Forth/Elixir expressiveness

**Target Features:**
- Pipeline operator (`|>`)
- Tag functions (honest metaprogramming)
- Generators (`yield`)
- Function composition
- Tacit programming

**Document:** `FUTURE_PLAN-v0.3.0.md`

---

### **Phase 3: Heavy Artillery** (v0.4.x+)

**Objective:** J/Mojo array power + Erlang resilience

**Target Features:**
- `:compute` profile (tensor types, SIMD)
- Array warfare (dot broadcasting)
- `:cluster` profile (actor model)
- Formal verification (SPARK-like contracts)

**Document:** `FUTURE_PLAN-v0.3.0.md` (Sections: Array Engine, Project Aegis)

---

## 🗺️ **Quick Reference: What to Read When**

### **I want to understand the current state:**
→ Read: `RELEASE-SUMMARY-v0.2.1.md`

### **I want to implement the LSP server:**
→ Read: `CURRENT_PLAN-v0.2.2.md`  
→ Reference: `LSP-IMPLEMENTATION-BRIEF.md`

### **I want to understand the long-term vision:**
→ Read: `FUTURE_PLAN-v0.3.0.md`

### **I want to understand match exhaustiveness:**
→ Read: `match-exhaustiveness-implementation.md`

### **I want to understand the memory model roadmap:**
→ Read: `memory-model-v0.2.5-v0.2.15.md`

### **I want to understand array programming plans:**
→ Read: `j-inspired-tacit-arrays.md`

---

## 🏗️ **Development Workflow**

### **Step 1: Check Current Status**
```bash
cat VERSION              # Current version
git log --oneline -5     # Recent commits
zig build test           # Test suite status
```

### **Step 2: Read Relevant Plan**
- For **next feature:** `CURRENT_PLAN-v0.2.2.md`
- For **completed work:** `RELEASE-SUMMARY-v0.2.1.md`
- For **future direction:** `FUTURE_PLAN-v0.3.0.md`

### **Step 3: Implement**
- Follow plan document structure
- Update plan as you work
- Document decisions in real-time

### **Step 4: Test & Verify**
```bash
zig build test           # Run test suite
zig build                # Verify clean build
```

### **Step 5: Document**
- Update plan checkboxes
- Add notes to `RELEASE-SUMMARY-vX.Y.Z.md`
- Update CHANGELOG (when ready for release)

### **Step 6: Commit**
```bash
git add .
git commit -m "feat: concise description"
# Follow conventional commits format
```

---

## 📋 **Version Naming Convention**

**Format:** `MAJOR.MINOR.PATCH-ITERATION`

**Examples:**
- `0.2.0-1` - First iteration of v0.2.0
- `0.2.0-2` - Second iteration (current)
- `0.2.1-0` - First release of v0.2.1 (ready to tag)
- `0.2.2-0` - First release of v0.2.2 (planned)

**Semantic Meaning:**
- **MAJOR:** Breaking changes (rare)
- **MINOR:** New features (e.g., :core complete)
- **PATCH:** Bug fixes only
- **ITERATION:** Development iterations within a version

---

## 🔄 **Release Process**

### **When to Bump Version**

**MINOR bump (0.2.X → 0.2.Y):**
- New language features complete
- Profile milestone reached
- Major tooling addition (e.g., LSP)

**PATCH bump (0.2.2 → 0.2.3):**
- Bug fixes only
- Performance improvements
- Documentation updates

### **Tagging Releases**

```bash
# Update VERSION file
echo "0.2.1-0" > VERSION

# Commit version bump
git add VERSION
git commit -m "release: bump version to 0.2.1-0"

# Create annotated tag
git tag -a v0.2.1-0 -m "Janus v0.2.1-0: :core Profile Complete"

# Push tag (when ready for public release)
git push origin v0.2.1-0
```

---

## 🧭 **Strategic Context**

### **The Janus Synthesis**

We are building a **Data-Oriented Language** with a **Smalltalk-like Nervous System**.

**Formula:**
```
Janus = (Forth - Stack Hell) + (Smalltalk - Dynamic Chaos) + Static Types
```

**The Three Pillars:**

1. **Sovereign Data** (Value Semantics)
   - My data is mine
   - No spooky action at a distance
   - V-inspired memory model

2. **Sovereign Logic** (Pure Functions)
   - Input → Output
   - No hidden state
   - Elm-style total functions

3. **Sovereign Tooling** (ASTDB)
   - Live introspection (Smalltalk)
   - Static analysis (LSP)
   - AI-readable structure

---

## 📞 **Getting Help**

### **Understanding a Feature**
1. Check `CURRENT_PLAN-v0.2.X.md` for implementation details
2. Read related RFCs (if mentioned)
3. Review test files in `tests/integration/`

### **Understanding the Vision**
1. Read `FUTURE_PLAN-v0.3.0.md` intro
2. Review "The Grafting Map" for language inspirations
3. Check "Strategic Context" sections

### **Finding Specific Information**
- **LSP:** `LSP-IMPLEMENTATION-BRIEF.md`
- **Match:** `match-exhaustiveness-implementation.md`
- **Memory:** `memory-model-v0.2.5-v0.2.15.md`
- **Arrays:** `j-inspired-tacit-arrays.md`

---

## ✅ **Quick Checklist: Starting a New Feature**

- [ ] Read relevant plan document (`CURRENT_PLAN-v0.2.X.md`)
- [ ] Check current VERSION
- [ ] Run `zig build test` to verify clean state
- [ ] Identify affected files
- [ ] Write tests first (TDD approach)
- [ ] Implement feature incrementally
- [ ] Update plan document with progress
- [ ] Verify tests pass
- [ ] Document in `RELEASE-SUMMARY-vX.Y.Z.md`
- [ ] Commit with conventional commit message

---

## 🎯 **Current Priorities (2025-12-16)**

### **Immediate (This Week):**
1. ✅ Complete v0.2.1 documentation (DONE)
2. 📍 Tag v0.2.1-0 release
3. ⏳ Start v0.2.2 LSP implementation
4. ⏳ Fix Zig 0.15 I/O blocker (30min)

### **Short-Term (This Month):**
1. Complete LSP Server (1-2 weeks)
2. VS Code extension integration
3. First LSP release (v0.2.2-0)

### **Medium-Term (Q1 2025):**
1. Advanced LSP features (completion, refactoring)
2. UFCS implementation
3. Pipeline operator prototype

---

**Status:** Documentation complete and ready for v0.2.2 development  
**Next Action:** Review `CURRENT_PLAN-v0.2.2.md` and begin LSP I/O fix

— Voxis Forge, 2025-12-16

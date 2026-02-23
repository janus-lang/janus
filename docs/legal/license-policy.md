# 🛡️ Janus Licensing Policy

**Version**: 1.0  
**Effective**: 2025-12-13  
**Steward**: Self Sovereign Society Foundation

---

## Overview

This project uses a **Multi-License Strategy** to balance **Sovereignty**, **Adoption**, and **Freedom**. We apply **Domain-Driven Design** to our legal infrastructure, creating distinct "Zones of Sovereignty" with appropriate protections for each domain.

---

## 📍 License Mapping by Domain

| Domain | Directory | License | Strategic Rationale |
|:-------|:----------|:--------|:-------------------|
| **The Castle** | `src/`, `compiler/`, `daemon/`, `lsp/`, `tools/`, `tests/`, `scripts/`, `packaging/`, `build.zig` | **LSL-1.0** | **Sovereign Core.** File-level reciprocity ensures the compiler remains unified and prevents fragmentation. Modifications to these files must be shared back. |
| **The Highway** | `std/`, `packages/` | **Apache-2.0** | **Maximum Adoption.** Corporate-friendly with explicit patent grant. Companies can link/bundle freely without license infection. This is the "Rust Model" - permissive for the ecosystem. |
| **The Sandbox** | `examples/`, `demos/`, `snippets/` | **CC0-1.0** | **Zero Friction.** Public domain. Copy-paste into your own code without attribution or legal headers. |

---

## 🎯 Strategic Rationale

### 1. **The Castle (LSL-1.0)**

**Purpose**: Prevent "Embrace, Extend, Extinguish" attacks on the language itself.

- ✅ **Freedom**: Use it, sell it, modify it
- ✅ **Reciprocity**: Changes to Core files must be open-sourced
- ✅ **File-Level Scope**: Only modified LSL-1.0 files need to be shared, not your entire application
- ✅ **Patent Grant**: Includes defensive patent termination clause
- ✅ **Stewardship**: Foundation maintains consistency and prevents fragmentation

**Why not GPL?** GPL and alikes are too strong (infects entire codebase). LSL-1.0 is BSD compatible and uses **file-level reciprocity**, making it more business-friendly while still protecting the core.

**Why not directly the BSD/MIT Licence?** While this aligns with our core philosophy, it is in the current reality of the state of the legal world too weak. Companies could fork the compiler, add proprietary features, and fragment the ecosystem.

### 2. **The Highway (Apache-2.0)**

**Purpose**: Maximize adoption of the standard library and package ecosystem.

- ✅ **Corporate Safe Harbor**: Google/Amazon/Apple lawyers approve Apache-2.0
- ✅ **Explicit Patent Grant**: "We promise not to sue you for patents"
- ✅ **Patent Termination**: "If you sue us, your license terminates"
- ✅ **No License Infection**: Link into proprietary apps without restriction

**Why not CC0?** CC0 lacks patent protection, scaring corporate lawyers. Apache-2.0 is the gold standard for libraries.

**Why not LSL-1.0?** Standard libraries need maximum adoption. Reciprocity requirements would reduce corporate uptake.

### 3. **The Sandbox (CC0-1.0)**

**Purpose**: Zero-friction learning and experimentation.

- ✅ **Public Domain**: No attribution required
- ✅ **Copy-Paste Friendly**: Perfect for tutorials and snippets
- ✅ **Maximum Freedom**: Do whatever you want

---

## 📝 Copyright Header Policy

To maintain a **clean, legally manageable codebase**, we enforce a **Single Header Policy** for the Core and Ecosystem.

### The Rule

**File headers in the repository always belong to the Foundation.**

When you submit a PR, you are contributing to the **Project**. The Project is stewarded by the **Foundation**. You get credit in the Git history and the `AUTHORS` file, but you do not spray-paint your name on the castle walls.

### Your Rights

- ✅ **You retain copyright** of your specific contributions (modifications)
- ✅ **Recognition**: Contributors are credited in Git history and `AUTHORS` file
- ✅ **New Modules**: If you contribute a completely new standalone module, you may include your copyright notice in that specific file header

### The Logic

**Why?** Avoiding "copyright pollution" prevents legal fragmentation. If every contributor adds their copyright line to `src/compiler/parser.zig`, we end up with a legal mess where we cannot re-license or defend the code without getting 1,000 signatures.

**The BSD Compromise**: We follow the "Inbound = Outbound" principle (your contribution is licensed the same as the project) but maintain clean headers. This satisfies BSD hackers who hate CLAs while keeping the codebase legally coherent.

---

## 🔧 Header Templates

### 1. The Castle Header (LSL-1.0)

**Applies to**: `src/`, `compiler/`, `daemon/`, `lsp/`, `tools/`, `tests/`, `scripts/`, `packaging/`, `build.zig`

```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
```

**For shell scripts**:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation
```

### 2. The Highway Header (Apache-2.0)

**Applies to**: `std/`, `packages/`

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//

```

### 3. The Sandbox Header (CC0-1.0)

**Applies to**: `examples/`, `demos/`, `snippets/`

```zig
// SPDX-License-Identifier: CC0-1.0
// To the extent possible under law, the author(s) have dedicated all copyright
// and related rights to this software to the public domain worldwide.
//
```

---

## 🤝 Contributor Guidelines

### For Existing Files

**Do not add personal copyright lines to existing source files.**

Your contribution is recognized via:
- Git commit history (permanent, immutable record)
- `AUTHORS` file (human-readable credits)
- Release notes (for significant contributions)

### For New Modules

If you contribute a **completely new standalone module** (not modifying existing files), you may include your copyright notice:

```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
// Copyright (c) 2025 Jane Developer <jane@example.com>
// [Your Name] <your.email@example.com>
// [Your Company] <your.company@example.com>
//
```

However, this is **discouraged** for Core files. Prefer the single-header approach.

### For Packages

Community packages in `packages/` may include contributor copyright notices, provided they align with Apache-2.0:

```zig
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025 Jane Developer <jane@example.com>
//
// [Your Name] <your.email@example.com>
// [Your Company] <your.company@example.com>
//
```

---

## ⚖️ License Compatibility Matrix

| Your Code | Can Link Janus Core? | Can Link Janus Std? | Can Use Examples? |
|:----------|:---------------------|:--------------------|:------------------|
| **Proprietary** | ✅ Yes (but share Core mods) | ✅ Yes (freely) | ✅ Yes (freely) |
| **GPL-3.0** | ⚠️ Incompatible | ✅ Yes | ✅ Yes |
| **Apache-2.0** | ✅ Yes | ✅ Yes | ✅ Yes |
| **MIT/BSD** | ✅ Yes | ✅ Yes | ✅ Yes |

**Note**: LSL-1.0 is **GPL-incompatible** due to different reciprocity scopes. If you need GPL compatibility, use only the `std/` (Apache-2.0) components.

---

## 🔍 Enforcement

### Automated Checks

We enforce license compliance via:

1. **Pre-commit hooks**: `scripts/pre-commit-license-check.sh`
2. **CI/CD validation**: `.github/workflows/license-check.yml`
3. **Compliance scanning**: `scripts/license-compliance-scan.sh`

### Manual Review

All pull requests are reviewed for:
- Correct license headers
- No copyright pollution in Core files
- Appropriate license for new modules

---

## 📚 Additional Resources

- **Full License Texts**: See `LICENSE` (LSL-1.0), `LICENSE.Apache-2.0`, `LICENSE.CC0-1.0`
- **Header Templates**: See `docs/legal/license-headers.md`
- **Automation Guide**: See `docs/LICENSE-AUTOMATION-USAGE.md`
- **Contributing Guide**: See `CONTRIBUTING.md`

---

## 🛡️ Strategic Verdict

This licensing strategy achieves:

1. **Corporate Friendly**: Apache-2.0 for `std/` means Apple/Google can use Janus without legal friction
2. **Sovereign Core**: LSL-1.0 for `compiler/` prevents proprietary forks from fragmenting the language
3. **BSD Satisfaction**: File-level reciprocity (not strong copyleft) + Apache-2.0 ecosystem = acceptable to BSD purists
4. **Patent Safety**: Explicit patent grants in both LSL-1.0 and Apache-2.0
5. **Clean Codebase**: Single-header policy prevents legal fragmentation

**This is Domain-Driven Design applied to legal infrastructure.**

---

**Policy Status**: ✅ **LOCKED AND IMMUTABLE**

*This policy is stewarded by the Self Sovereign Society Foundation and may only be modified through formal governance procedures.*

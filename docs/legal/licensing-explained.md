# Janus Ecosystem Licensing

**Philosophy: Tiered Protection with Maximum Freedom**

Janus uses a carefully designed tiered licensing model that protects the core language as a commons while maximizing freedom for the ecosystem.

---

## 🏛️ Core Compiler & Tooling: LCL-1.0

**Components:** `compiler/`, `daemon/`, `cmd/` (libjanus, janusd, janus CLI)

**License:** [Libertaria Commonwealth License v1.0 (LCL-1.0)](../../legal/LICENSE_COMMONWEALTH.md)

**Why LCL-1.0:**
- **SaaS-Proof Strong Copyleft**: Closes the "service loophole." If you run Janus as a platform, you must contribute back.
- **Total Transparency**: Ensures the engine of sovereignty remains observable and communal.
- **Predatory Enclosure Prevention**: No proprietary "private forks" that starve the upstream community.

**What this means:**
- ✅ You can use Janus to build any software.
- ✅ You can distribute Janus binaries freely.
- ✅ You can modify Janus for internal use.
- ⚠️ If you distribute modified Janus tools OR provide them over a network (SaaS), you must share the source.
- ❌ You cannot create proprietary, closed-source forks of the compiler.

---

## 📚 Standard Library & Modules: LSL-1.0

**Components:** `std/`, `runtime/`, `grafts/`

**License:** [Libertaria Sovereign License v1.0 (LSL-1.0)](../../legal/LICENSE_SOVEREIGN.md)

**Why LSL-1.0:**
- **Commercial Bridge**: Allows linking into proprietary, closed-source applications without viral infection.
- **File-Level Reciprocity**: If you improve an `std` file, you share that improvement.
- **Business-Friendly**: Removes legal "grey areas" for enterprise adoption.

**What this means:**
- ✅ Use in any project (commercial, proprietary, open source).
- ✅ Modify and redistribute with file-level reciprocity.
- ✅ No viral infection of your own application logic.
- ✅ Strong patent protection and Dutch Law governance.

---

## 🕊️ Unbound Commons: LUL-1.0

**Components:** `tests/`, `examples/`, `docs/`, `specs/`, `scripts/`, `tools/`

**License:** [Libertaria Unbound License v1.0 (LUL-1.0)](../../legal/LICENSE_UNBOUND.md)

**Why LUL-1.0:**
- **Absolute Velocity**: Maximum freedom to copy, paste, and adapt examples.
- **Frictionless Learning**: Docs and specs are wide open for the world to digest.
- **Universal Utility**: Development tools and scripts are public goods.

**What this means:**
- ✅ Complete freedom to use, modify, and distribute.
- ✅ Only condition is attribution.
- ✅ Ideal for training AI agents and building peripheral tools.

---

## 📦 Community Packages: Author's Choice

**Components:** Third-party packages in the Janus ecosystem

**License:** Any OSI-approved license (author's choice)

**Janus Tooling Support:**
- **Mandatory license declaration** in `janus.pkg` using SPDX identifiers
- **Policy enforcement** - projects can define acceptable license policies
- **License auditing** - track and verify license compliance
- **Compatibility checking** - automatic license conflict detection

**Encouraged Licenses:**
- **CC0-1.0** (Public Domain) - For maximum reusability and ecosystem growth
- **MIT** - Simple and permissive
- **Apache-2.0** - Permissive with patent protection
- **BSD-2-Clause** - Minimal restrictions

**Supported but Discouraged:**
- **GPL family** - Can create integration challenges
- **AGPL** - Network copyleft may limit deployment options
- **Proprietary** - Reduces ecosystem collaboration

---

## 🔧 License Tooling & Verification

### Package License Declaration
```kdl
// janus.pkg - Mandatory license field
name "my-awesome-library"
version "1.0.0"
license "Apache-2.0"  // SPDX identifier required
```

### Project License Policy
```kdl
// janus.policy - Define acceptable licenses for your project
license {
    allow ["CC0-1.0" "MIT" "Apache-2.0" "BSD-2-Clause"]
    warn ["LSL-1.0" "MPL-2.0"]
    deny ["AGPL-3.0-only" "GPL-3.0-only"]
}
```

### License Management Commands
```bash
# Check license compatibility
janus license check

# Show project license summary
janus license summary

# Audit license changes in updates
janus license audit

# Generate compliance report
janus license report --format spdx

# Validate license policy
janus license validate-policy
```

---

## 🎯 Strategic Benefits

### For the Janus Project
- **Protected Core**: LSL-1.0 ensures the compiler remains open and community-owned
- **Ecosystem Growth**: Permissive standard library encourages adoption
- **Legal Clarity**: Clear licensing reduces friction and legal uncertainty

### For Developers
- **Freedom to Choose**: Use Janus for any type of project
- **Legal Safety**: Strong patent protection and clear license terms
- **Compliance Tools**: Automated license tracking and verification
- **Policy Control**: Define your own license acceptance criteria

### For Organizations
- **Enterprise-Friendly**: Permissive standard library allows commercial use
- **Compliance Support**: Built-in license auditing and reporting
- **Risk Management**: Clear license policies prevent legal surprises
- **Supply Chain Security**: Cryptographic verification of license declarations

---

## 📋 License Compatibility Matrix

| Your Project License | Can Use Janus Compiler | Can Use Std Library | Package Restrictions |
|---------------------|------------------------|---------------------|---------------------|
| **Proprietary** | ✅ Yes | ✅ Yes | Avoid GPL/AGPL packages |
| **MIT/BSD** | ✅ Yes | ✅ Yes | Avoid GPL/AGPL packages |
| **Apache-2.0** | ✅ Yes | ✅ Yes | Avoid GPL v2 packages |
| **GPL v3** | ✅ Yes | ✅ Yes | Most packages compatible |
| **AGPL v3** | ✅ Yes | ✅ Yes | Most packages compatible |

---

## 🤝 Contributing License Requirements

### Code Contributions
- **Developer Certificate of Origin (DCO)** required for all contributions
- **Sign commits** with `git commit -s`
- **No CLA required** - DCO provides sufficient legal clarity

### License Headers
All source files must include appropriate SPDX license identifiers based on their domain:

**Compiler/Tooling (LSL-1.0):**
```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
```

**Standard Library (Apache-2.0):**
```janus
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Self Sovereign Society Foundation
```

**Community Packages (CC0-1.0):**
```janus
// SPDX-License-Identifier: CC0-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
```

**📖 Complete license header guide:** [docs/legal/license-headers.md](./license-headers.md)

---

## 📞 License Questions & Support

- **General Questions**: See [FAQ](./docs/faq.md#licensing)
- **Legal Concerns**: Contact [legal@janus-lang.org](mailto:legal@janus-lang.org)
- **License Violations**: Report to [security@janus-lang.org](mailto:security@janus-lang.org)
- **Commercial Licensing**: Standard licenses cover all commercial use cases

---

**Summary: Janus provides maximum freedom for users while protecting the language core as a permanent commons. Use Janus to build anything, contribute to make it better, and choose your own licensing terms for your packages.**

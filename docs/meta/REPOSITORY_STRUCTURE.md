# Janus Repository Structure

**Status**: ✅ **PANOPTICUM COMPLIANT** - Zero Clutter  
**Version**: 1.0  
**Last Updated**: 2025-12-13

---

## Root Directory (Professional & Clean)

```
janus/
├── .github/              # GitHub Actions & CI/CD
├── .githooks/            # Git hooks (pre-commit, post-commit)
├── .gitignore            # Git ignore rules
├── .gitmodules           # Git submodules
├── .pre-commit-config.yaml  # Pre-commit configuration
├── build.zig             # Zig build system
├── build.zig.zon         # Zig package manager manifest
├── Makefile              # GNU Make wrapper
├── VERSION               # Semantic version (0.1.2-dev+hash)
│
├── CHANGELOG.md          # Version history
├── CLA.md                # Contributor License Agreement
├── CODE_OF_CONDUCT.md    # Community guidelines
├── CONTRIBUTING.md       # Contribution guide
├── COPYING               # License reference
├── LICENSE               # LSL-1.0 full text
├── LICENSE.md            # LSL-1.0 summary
├── LICENSE_POLICY.md     # Domain-Driven Licensing Strategy
├── README.md             # Project overview
├── SECURITY.md           # Security policy
│
├── janus.kdl.example     # Example configuration
│
├── attic/                # Historical artifacts (not for release)
├── bench/                # Performance benchmarks
├── branding/             # Logos, assets
├── build_support/        # Build system helpers
├── cmd/                  # CLI commands
├── compiler/             # Core compiler (LSL-1.0)
├── daemon/               # Janus daemon
├── demos/                # Demo applications
├── dist/                 # Distribution artifacts
├── docs/                 # Documentation
├── examples/             # Code examples (CC0-1.0)
├── grafts/               # Graft system
├── lsp/                  # Language Server Protocol
├── packages/             # Community packages (Apache-2.0)
├── packaging/            # OS-specific packaging
├── protocol/             # Protocol definitions
├── runtime/              # Runtime library
├── scripts/              # Automation scripts
├── src/                  # Main source (LSL-1.0)
├── std/                  # Standard library (Apache-2.0)
├── tests/                # Test suite
├── third_party/          # External dependencies
├── tools/                # Development tools
└── vscode-extension/     # VSCode integration
```

---

## Directory Purposes

### Core Infrastructure (LSL-1.0)
| Directory | Purpose |
|:----------|:--------|
| `compiler/` | Core compiler implementation |
| `src/` | Main CLI and entry points |
| `daemon/` | Background daemon for IDE integration |
| `lsp/` | Language Server Protocol implementation |
| `tools/` | Development and build tools |
| `cmd/` | Command-line interface commands |

### Ecosystem (Apache-2.0)
| Directory | Purpose |
|:----------|:--------|
| `std/` | Standard library modules |
| `packages/` | Community-contributed packages |
| `runtime/` | Runtime support library |

### Examples & Demos (CC0-1.0)
| Directory | Purpose |
|:----------|:--------|
| `examples/` | Code examples and tutorials |
| `demos/` | Demo applications |

### Development
| Directory | Purpose |
|:----------|:--------|
| `tests/` | Comprehensive test suite |
| `bench/` | Performance benchmarks |
| `scripts/` | Automation and utility scripts |
| `build_support/` | Build system helpers |

### Distribution
| Directory | Purpose |
|:----------|:--------|
| `packaging/` | OS-specific packages (AUR, Debian, etc.) |
| `dist/` | Distribution artifacts |
| `branding/` | Logos and visual assets |

### Integration
| Directory | Purpose |
|:----------|:--------|
| `vscode-extension/` | VSCode language support |
| `protocol/` | Protocol definitions (gRPC, etc.) |
| `grafts/` | Graft system for code injection |

### External
| Directory | Purpose |
|:----------|:--------|
| `third_party/` | External dependencies |

### Historical
| Directory | Purpose |
|:----------|:--------|
| `attic/` | **NOT FOR RELEASE** - Historical artifacts, experiments, obsolete code |

---

## Root Files (Minimal & Professional)

### Build System
- `build.zig` - Zig build configuration
- `build.zig.zon` - Package dependencies
- `Makefile` - Convenience wrapper
- `VERSION` - Semantic version

### Legal & Governance
- `LICENSE` - LSL-1.0 full legal text
- `LICENSE.md` - LSL-1.0 summary
- `LICENSE_POLICY.md` - Domain-Driven Licensing Strategy
- `COPYING` - License reference
- `CLA.md` - Contributor License Agreement
- `CODE_OF_CONDUCT.md` - Community standards
- `SECURITY.md` - Security policy

### Documentation
- `README.md` - Project overview and quick start
- `CHANGELOG.md` - Version history
- `CONTRIBUTING.md` - Contribution guidelines

### Configuration
- `janus.kdl.example` - Example project configuration

---

## Panopticum Doctrine Compliance

### ✅ Zero Clutter
- No loose test files in root
- No generated artifacts in source tree
- No build outputs in repository
- No personal notes or logs

### ✅ Clear Hierarchy
- Every file has a logical place
- Directories are self-explanatory
- No ambiguous naming

### ✅ Professional Presentation
- Clean root directory
- Comprehensive documentation
- Proper licensing
- Clear contribution path

---

## Excluded from Repository

The following are **never** committed:

### Build Artifacts
- `zig-out/` - Build output
- `.zig-cache/` - Build cache
- `*.o`, `*.a` - Object files
- `*_generated.c` - Generated C code

### Development
- `.venv/` - Python virtual environment
- `node_modules/` - NPM dependencies
- `__pycache__/` - Python cache

### IDE
- `.vscode/` - VSCode settings (user-specific)
- `.idea/` - IntelliJ settings

### Personal
- `.agent/` - AI assistant state
- `.claude/` - Claude AI state
- `.kiro/` - Personal tools
- `.progit/` - Project management

---

## Release Checklist

Before public release, verify:

- [ ] No files in `attic/` are accidentally included
- [ ] All root files are professional and necessary
- [ ] `.gitignore` is comprehensive
- [ ] No personal notes or TODOs in committed files
- [ ] All documentation is up-to-date
- [ ] License headers are correct
- [ ] VERSION file is clean (no `-dev` suffix)

---

**This structure represents the Panopticum Doctrine: Clean, Professional, Zero Noise.**

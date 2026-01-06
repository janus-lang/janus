# Blake3 Submodule Management

## Overview

The `third_party/blake3` submodule is a **critical dependency** for Janus's CID (Content-Identifier) packaging system. It's managed as a Git submodule and **automatically rebuilt from source** after every `git pull`.

## Why Submodule, Not .gitignore?

**Git submodules are version-controlled dependencies**, not build artifacts:
- `.gitignore` **does not work** on submodules
- Submodules are tracked via `.gitmodules` and pinned to specific commits
- This ensures **reproducible builds** across all environments

## Automatic Updates

### Post-Merge Hook (Automatic)

After every `git pull`, the `.git/hooks/post-merge` hook automatically:
1. Updates all submodules to their committed state
2. Cleans any local modifications in submodules
3. Ensures blake3 is always at the correct version

**No manual intervention required.**

### Build System Integration

The `build.zig` system automatically:
- Compiles blake3 C sources with SIMD optimizations
- Links the static library to `janus` and `janusd`
- Rebuilds whenever sources change

## Manual Management

### Makefile Targets

```bash
# Show current submodule status
make submodule-status

# Update submodules to committed state (same as post-merge hook)
make submodule-update

# Clean any local modifications in submodules
make submodule-clean
```

### Direct Git Commands

```bash
# Initialize and update all submodules
git submodule update --init --recursive

# Reset submodule to clean state
cd third_party/blake3
git reset --hard HEAD
git clean -fd
cd ../..

# Check submodule status
git submodule status
```

## Troubleshooting

### "modified content" in git status

**Cause:** Local changes inside the submodule directory.

**Solution:**
```bash
make submodule-clean
# or
git submodule foreach --recursive 'git reset --hard HEAD && git clean -fd'
```

### Submodule not initialized

**Solution:**
```bash
make submodule-update
# or
git submodule update --init --recursive
```

### Build fails with blake3 errors

**Solution:**
```bash
make submodule-clean
make clean
make build
```

## Architecture

```
janus/
├── .gitmodules              # Submodule configuration
├── .git/hooks/post-merge    # Auto-update hook
├── third_party/blake3/      # Submodule (pinned to v1.5.4)
│   └── c/                   # C implementation
│       ├── blake3.c
│       ├── blake3_portable.c
│       ├── blake3_sse2.c    # SIMD optimizations
│       └── ...
└── build.zig                # Compiles blake3 into static lib
```

## Why Blake3?

Blake3 is used for:
- **Content-addressable storage** (CID generation)
- **Package integrity verification**
- **Cryptographic hashing** in the build system

It's **not optional**—removing it will break the packaging system.

## Updating Blake3 Version

To update to a newer blake3 version:

```bash
cd third_party/blake3
git fetch origin
git checkout <new-version-tag>  # e.g., 1.6.0
cd ../..
git add third_party/blake3
git commit -m "chore: Update blake3 to <new-version>"
```

The post-merge hook will ensure all team members get the update automatically.

---

**Status:** ✅ Fully automated. No manual intervention required for normal development.

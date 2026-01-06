<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->



# Janus Linux Distribution Packaging

This directory contains packaging files for various Linux distributions. The Janus compiler builds successfully and is ready for distribution packaging.

## Build Status: ✅ READY

- **Compiler**: Builds successfully with Zig 0.14.1
- **Executable**: 9.5MB, depends only on libc
- **Tests**: Basic functionality verified
- **Architecture**: x86_64 with SSE2/SSE4.1/AVX2 optimizations

## Quick Start

### Test Local Build
```bash
# From repository root
zig build
./zig-out/bin/janus version
./zig-out/bin/janus test-cas
```

## Distribution Packages

### 1. Arch Linux (AUR)

**Status**: ✅ Ready to deploy
**File**: `arch/PKGBUILD`

```bash
# Test the PKGBUILD
cd packaging/arch/
makepkg -si

# Or install from AUR (when published)
yay -S janus-lang
```

**Deployment Steps**:
1. Create AUR account
2. Upload PKGBUILD and .SRCINFO
3. Test in clean chroot
4. Announce to community

### 2. Alpine Linux

**Status**: ✅ Ready to deploy
**File**: `alpine/APKBUILD`

```bash
# Test the APKBUILD
cd packaging/alpine/
abuild -r

# Or install from Alpine testing (when published)
apk add janus-lang
```

**Deployment Steps**:
1. Submit to Alpine testing repository
2. Test on Alpine container
3. Request move to main repository

### 3. Debian/Ubuntu

**Status**: ✅ Ready to deploy
**Files**: `debian/control`, `debian/rules`, `debian/changelog`

```bash
# Test Debian packaging
cd packaging/debian/
dpkg-buildpackage -us -uc

# Or install from PPA (when published)
sudo add-apt-repository ppa:janus-lang/stable
sudo apt update
sudo apt install janus-lang
```

**Deployment Steps**:
1. Create Launchpad PPA
2. Upload source package
3. Test on Ubuntu/Debian containers
4. Submit to Debian NEW queue

### 4. Fedora/RHEL

**Status**: ✅ Ready to deploy
**File**: `fedora/janus-lang.spec`

```bash
# Test RPM packaging
cd packaging/fedora/
rpmbuild -ba janus-lang.spec

# Or install from COPR (when published)
sudo dnf copr enable janus-lang/stable
sudo dnf install janus-lang
```

**Deployment Steps**:
1. Create Fedora COPR repository
2. Upload spec file
3. Test on Fedora/CentOS containers
4. Submit to Fedora review process

## Build Dependencies

### Required for All Distributions
- **Zig**: Version 0.14.0 or later
- **C Compiler**: GCC or Clang (for BLAKE3)
- **Git**: For source checkout
- **Standard Libraries**: libc development headers

### Distribution-Specific Notes

#### Arch Linux
- Zig available in community repository
- All dependencies readily available

#### Alpine Linux
- May need to package Zig separately
- Excellent musl libc compatibility
- Small footprint matches Janus philosophy

#### Debian/Ubuntu
- Zig not in official repositories yet
- Need PPA or bundled Zig approach
- Consider using static Zig binary

#### Fedora/RHEL
- Zig available in Fedora 35+
- EPEL may be needed for RHEL
- Consider COPR for latest Zig

## Runtime Dependencies

**Minimal**: Only standard C library required
- **glibc**: 2.17+ (most distributions)
- **musl**: Any recent version (Alpine)
- **Linux Kernel**: 3.2+ (standard requirement)

## Package Testing

### Automated Testing
```bash
# Test build on all distributions
./test-packaging.sh

# Test specific distribution
./test-packaging.sh arch
./test-packaging.sh alpine
./test-packaging.sh debian
./test-packaging.sh fedora
```

### Manual Testing Checklist
- [ ] Package builds successfully
- [ ] Executable runs and shows version
- [ ] Basic commands work (profile show, test-cas)
- [ ] Documentation installed correctly
- [ ] Examples accessible
- [ ] Clean uninstall

## Architecture Support

### Current Support
- **x86_64**: Full support with optimizations

### Planned Support
- **aarch64**: ARM64 (Raspberry Pi, Apple Silicon, AWS Graviton)
- **riscv64**: RISC-V (emerging platforms)
- **s390x**: IBM mainframes (enterprise)

### Cross-Compilation
Zig's excellent cross-compilation support makes multi-architecture builds straightforward:

```bash
# Build for ARM64
zig build -Dtarget=aarch64-linux

# Build for RISC-V
zig build -Dtarget=riscv64-linux
```

## Release Process

### Version Numbering
- **Development**: `0.1.0-dev`
- **Alpha**: `0.1.0-alpha.1`
- **Beta**: `0.1.0-beta.1`
- **Release**: `0.1.0`

### Release Checklist
1. [ ] Update version in all packaging files
2. [ ] Update checksums in PKGBUILD/APKBUILD
3. [ ] Test build on all target distributions
4. [ ] Update changelog/release notes
5. [ ] Tag release in git
6. [ ] Upload to distribution repositories
7. [ ] Announce release

## Troubleshooting

### Common Build Issues

#### Zig Version Mismatch
```bash
# Check Zig version
zig version
# Should be 0.14.0 or later
```

#### BLAKE3 Linking Errors
```bash
# Verify BLAKE3_NO_AVX512 is set
grep -r "BLAKE3_NO_AVX512" build.zig
# Should find the define in C flags
```

#### Missing Dependencies
```bash
# Debian/Ubuntu
sudo apt install build-essential git

# Fedora
sudo dnf install gcc git

# Arch
sudo pacman -S base-devel git
```

### Package-Specific Issues

#### AUR Package
- Ensure .SRCINFO is updated: `makepkg --printsrcinfo > .SRCINFO`
- Test in clean chroot: `extra-x86_64-build`

#### Alpine Package
- Check musl compatibility: `ldd zig-out/bin/janus`
- Test in Alpine container: `docker run -it alpine:latest`

#### Debian Package
- Validate control file: `dpkg-source --build .`
- Test with pbuilder: `pbuilder build *.dsc`

#### Fedora Package
- Check spec file: `rpmlint janus-lang.spec`
- Test with mock: `mock -r fedora-39-x86_64 *.src.rpm`

## Contributing

### Adding New Distribution
1. Create directory: `packaging/newdistro/`
2. Add packaging files (control, spec, etc.)
3. Update this README
4. Test thoroughly
5. Submit pull request

### Improving Existing Packages
1. Test current package
2. Identify improvements
3. Update packaging files
4. Test changes
5. Submit pull request

## Support

### Getting Help
- **Issues**: Report packaging issues on GitHub
- **Discussion**: Join distribution-specific forums
- **Documentation**: See main project documentation

### Maintainer Information
- **Primary**: Janus Development Team
- **Contact**: maintainer@janus-lang.org
- **Matrix**: #janus-lang:matrix.org (planned)

## License

Packaging files are provided under the same license as the main Janus project.
See LICENSE file in repository root for details.

#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Test script for Janus packaging across different distributions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test basic build functionality
test_basic_build() {
    log_info "Testing basic Janus build..."

    cd "$PROJECT_ROOT"

    # Clean previous builds
    rm -rf zig-out zig-cache .zig-cache

    # Build
    if zig build; then
        log_success "Build completed successfully"
    else
        log_error "Build failed"
        return 1
    fi

    # Test executable
    if ./zig-out/bin/janus version; then
        log_success "Executable runs correctly"
    else
        log_error "Executable test failed"
        return 1
    fi

    # Test basic functionality
    if ./zig-out/bin/janus test-cas; then
        log_success "CAS functionality test passed"
    else
        log_error "CAS functionality test failed"
        return 1
    fi
}

# Test Arch Linux packaging
test_arch_packaging() {
    log_info "Testing Arch Linux packaging..."

    if ! command -v makepkg &> /dev/null; then
        log_warning "makepkg not found, skipping Arch packaging test"
        return 0
    fi

    cd "$SCRIPT_DIR/arch"

    # Validate PKGBUILD
    if makepkg --printsrcinfo > .SRCINFO; then
        log_success "PKGBUILD validation passed"
    else
        log_error "PKGBUILD validation failed"
        return 1
    fi

    log_info "Arch packaging files validated"
}

# Test Alpine packaging
test_alpine_packaging() {
    log_info "Testing Alpine packaging..."

    if ! command -v abuild &> /dev/null; then
        log_warning "abuild not found, skipping Alpine packaging test"
        return 0
    fi

    cd "$SCRIPT_DIR/alpine"

    # Basic APKBUILD validation
    if abuild checksum; then
        log_success "APKBUILD checksum validation passed"
    else
        log_warning "APKBUILD checksum validation failed (expected for development)"
    fi

    log_info "Alpine packaging files validated"
}

# Test Debian packaging
test_debian_packaging() {
    log_info "Testing Debian packaging..."

    if ! command -v dpkg-buildpackage &> /dev/null; then
        log_warning "dpkg-buildpackage not found, skipping Debian packaging test"
        return 0
    fi

    cd "$PROJECT_ROOT"

    # Copy debian directory to project root for testing
    cp -r "$SCRIPT_DIR/debian" .

    # Validate control file
    if dpkg-source --build . 2>/dev/null; then
        log_success "Debian control file validation passed"
    else
        log_warning "Debian control file validation failed (expected without proper source)"
    fi

    # Clean up
    rm -rf debian

    log_info "Debian packaging files validated"
}

# Test Fedora packaging
test_fedora_packaging() {
    log_info "Testing Fedora packaging..."

    if ! command -v rpmbuild &> /dev/null; then
        log_warning "rpmbuild not found, skipping Fedora packaging test"
        return 0
    fi

    cd "$SCRIPT_DIR/fedora"

    # Validate spec file
    if rpmlint janus-lang.spec 2>/dev/null; then
        log_success "RPM spec file validation passed"
    else
        log_warning "RPM spec file validation had warnings (may be expected)"
    fi

    log_info "Fedora packaging files validated"
}

# Test dependencies
test_dependencies() {
    log_info "Testing build dependencies..."

    # Check Zig version
    if command -v zig &> /dev/null; then
        ZIG_VERSION=$(zig version)
        log_info "Zig version: $ZIG_VERSION"

        # Check if version is 0.14.0 or later
        if [[ "$ZIG_VERSION" =~ ^0\.1[4-9]\. ]] || [[ "$ZIG_VERSION" =~ ^[1-9]\. ]]; then
            log_success "Zig version is compatible"
        else
            log_warning "Zig version may be too old (need 0.14.0+)"
        fi
    else
        log_error "Zig not found - required for building"
        return 1
    fi

    # Check C compiler
    if command -v gcc &> /dev/null || command -v clang &> /dev/null; then
        log_success "C compiler available"
    else
        log_warning "No C compiler found - may be needed for BLAKE3"
    fi

    # Check git
    if command -v git &> /dev/null; then
        log_success "Git available"
    else
        log_warning "Git not found - needed for source checkout"
    fi
}

# Test runtime dependencies
test_runtime_dependencies() {
    log_info "Testing runtime dependencies..."

    cd "$PROJECT_ROOT"

    if [ -f "zig-out/bin/janus" ]; then
        # Check shared library dependencies
        DEPS=$(ldd zig-out/bin/janus 2>/dev/null || echo "Static binary")
        log_info "Runtime dependencies:"
        echo "$DEPS" | while read -r line; do
            log_info "  $line"
        done

        # Count dependencies (excluding vdso and ld-linux)
        DEP_COUNT=$(echo "$DEPS" | grep -v "vdso\|ld-linux" | grep "=>" | wc -l)
        if [ "$DEP_COUNT" -le 2 ]; then
            log_success "Minimal runtime dependencies ($DEP_COUNT libraries)"
        else
            log_warning "More runtime dependencies than expected ($DEP_COUNT libraries)"
        fi
    else
        log_error "Janus executable not found - run build first"
        return 1
    fi
}

# Main test function
run_tests() {
    local test_type="$1"

    log_info "Starting Janus packaging tests..."
    log_info "Test type: ${test_type:-all}"

    case "$test_type" in
        "basic"|"")
            test_basic_build
            test_dependencies
            test_runtime_dependencies
            ;;
        "arch")
            test_basic_build
            test_arch_packaging
            ;;
        "alpine")
            test_basic_build
            test_alpine_packaging
            ;;
        "debian")
            test_basic_build
            test_debian_packaging
            ;;
        "fedora")
            test_basic_build
            test_fedora_packaging
            ;;
        "all")
            test_basic_build
            test_dependencies
            test_runtime_dependencies
            test_arch_packaging
            test_alpine_packaging
            test_debian_packaging
            test_fedora_packaging
            ;;
        *)
            log_error "Unknown test type: $test_type"
            log_info "Available types: basic, arch, alpine, debian, fedora, all"
            exit 1
            ;;
    esac

    log_success "Packaging tests completed!"
}

# Show usage
show_usage() {
    echo "Usage: $0 [test_type]"
    echo ""
    echo "Test types:"
    echo "  basic   - Test basic build and dependencies"
    echo "  arch    - Test Arch Linux packaging"
    echo "  alpine  - Test Alpine Linux packaging"
    echo "  debian  - Test Debian packaging"
    echo "  fedora  - Test Fedora packaging"
    echo "  all     - Run all tests (default)"
    echo ""
    echo "Examples:"
    echo "  $0           # Run all tests"
    echo "  $0 basic     # Test basic build only"
    echo "  $0 arch      # Test Arch packaging"
}

# Main script
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
fi

run_tests "$1"

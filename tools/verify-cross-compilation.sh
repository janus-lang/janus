#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# The full text of the license can be found in the LICENSE file at the root of the repository.

# Citadel Architecture Cross-Compilation Verification Script
#
# This script verifies that the core daemon can be built for all target platforms
# without external dependencies, fulfilling Requirement 1: Cross-Platform Core Daemon

set -euo pipefail

echo "🔥 CITADEL ARCHITECTURE CROSS-COMPILATION VERIFICATION 🔥"
echo "Testing cross-platform deployment capability..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test results array
declare -a TEST_RESULTS=()

# Function to test cross-compilation for a specific target
test_cross_compile() {
    local target_name="$1"
    local target_triple="$2"
    local description="$3"

    echo -e "${BLUE}🔨 Testing: $target_name${NC}"
    echo "   Target: $target_triple"
    echo "   Description: $description"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Build command
    local build_cmd="zig build janus-core-daemon -Dtarget=$target_triple -Doptimize=ReleaseSafe"
    echo "   Command: $build_cmd"

    # Execute build
    if $build_cmd > /tmp/cross_build_$target_name.log 2>&1; then
        echo -e "   ${GREEN}✅ SUCCESS: Cross-compilation completed${NC}"

        # Check if binary was created
        if [ -f "zig-out/bin/janus-core-daemon" ]; then
            local size=$(stat -c%s "zig-out/bin/janus-core-daemon" 2>/dev/null || stat -f%z "zig-out/bin/janus-core-daemon" 2>/dev/null || echo "0")
            local size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc -l 2>/dev/null || echo "unknown")
            echo -e "   ${GREEN}✅ Binary created: ${size_mb} MB${NC}"

            PASSED_TESTS=$((PASSED_TESTS + 1))
            TEST_RESULTS+=("✅ $target_name: SUCCESS")
        else
            echo -e "   ${YELLOW}⚠️  WARNING: Binary not found${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            TEST_RESULTS+=("⚠️  $target_name: BINARY_NOT_FOUND")
        fi
    else
        echo -e "   ${RED}❌ FAILED: Cross-compilation failed${NC}"
        echo "   See /tmp/cross_build_$target_name.log for details"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("❌ $target_name: BUILD_FAILED")
    fi

    echo ""
}

# Function to test dependency isolation
test_dependency_isolation() {
    echo -e "${BLUE}🔍 Testing dependency isolation...${NC}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Build native janus-core-daemon
    if zig build janus-core-daemon -Doptimize=ReleaseSafe > /tmp/deps_build.log 2>&1; then
        echo -e "   ${GREEN}✅ Native build successful${NC}"

        # Check dependencies
        if [ -f "zig-out/bin/janus-core-daemon" ]; then
            echo "   Checking dependencies..."

            local deps_output=""
            if command -v ldd >/dev/null 2>&1; then
                deps_output=$(ldd zig-out/bin/janus-core-daemon 2>/dev/null || echo "Static binary (no dependencies)")
            elif command -v otool >/dev/null 2>&1; then
                deps_output=$(otool -L zig-out/bin/janus-core-daemon 2>/dev/null || echo "Static binary (no dependencies)")
            else
                deps_output="Dependency check not supported on this platform"
            fi

            echo "   Dependencies: $deps_output"

            # Check for forbidden dependencies
            local forbidden_found=false
            for forbidden in "libgrpc" "libprotobuf" "libstdc++" "libgcc_s"; do
                if echo "$deps_output" | grep -q "$forbidden"; then
                    echo -e "   ${RED}❌ FORBIDDEN DEPENDENCY: $forbidden${NC}"
                    forbidden_found=true
                fi
            done

            if [ "$forbidden_found" = false ]; then
                echo -e "   ${GREEN}✅ No forbidden dependencies found${NC}"
                PASSED_TESTS=$((PASSED_TESTS + 1))
                TEST_RESULTS+=("✅ Dependency isolation: SUCCESS")
            else
                echo -e "   ${RED}❌ Forbidden dependencies found${NC}"
                FAILED_TESTS=$((FAILED_TESTS + 1))
                TEST_RESULTS+=("❌ Dependency isolation: FORBIDDEN_DEPS")
            fi
        else
            echo -e "   ${RED}❌ Binary not found for dependency check${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            TEST_RESULTS+=("❌ Dependency isolation: NO_BINARY")
        fi
    else
        echo -e "   ${RED}❌ Native build failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("❌ Dependency isolation: BUILD_FAILED")
    fi

    echo ""
}

# Function to test build system updates
test_build_system() {
    echo -e "${BLUE}🔧 Testing build system updates...${NC}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Test that all Citadel components can be built
    local components=("janus-core-daemon" "janus-grpc-proxy" "test-citadel-integration")
    local all_success=true

    for component in "${components[@]}"; do
        echo "   Building $component..."
        if zig build "$component" -Doptimize=ReleaseSafe > "/tmp/build_$component.log" 2>&1; then
            echo -e "   ${GREEN}✅ $component built successfully${NC}"
        else
            echo -e "   ${RED}❌ $component build failed${NC}"
            all_success=false
        fi
    done

    if [ "$all_success" = true ]; then
        echo -e "   ${GREEN}✅ All Citadel components built successfully${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("✅ Build system: SUCCESS")
    else
        echo -e "   ${RED}❌ Some Citadel components failed to build${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("❌ Build system: COMPONENT_FAILURES")
    fi

    echo ""
}

# Main test execution
main() {
    # Clean previous builds
    echo "🧹 Cleaning previous builds..."
    rm -rf zig-out/
    echo ""

    # Test dependency isolation first
    test_dependency_isolation

    # Test build system
    test_build_system

    # Test cross-compilation targets
    echo -e "${BLUE}🌍 Testing cross-compilation targets...${NC}"
    echo ""

    # Linux targets (musl for static linking)
    test_cross_compile "linux-x86_64-musl" "x86_64-linux-musl" "Linux x86_64 with musl (static)"
    test_cross_compile "linux-aarch64-musl" "aarch64-linux-musl" "Linux ARM64 with musl (static)"
    test_cross_compile "linux-riscv64-musl" "riscv64-linux-musl" "Linux RISC-V 64-bit with musl"

    # macOS targets
    test_cross_compile "macos-x86_64" "x86_64-macos" "macOS Intel x86_64"
    test_cross_compile "macos-aarch64" "aarch64-macos" "macOS Apple Silicon ARM64"

    # Windows targets
    test_cross_compile "windows-x86_64" "x86_64-windows" "Windows x86_64"

    # Additional Linux target (glibc for comparison)
    test_cross_compile "linux-x86_64-gnu" "x86_64-linux-gnu" "Linux x86_64 with glibc (dynamic)"

    # Summary
    echo -e "${BLUE}🎯 CROSS-COMPILATION TEST RESULTS:${NC}"
    echo "   Total tests: $TOTAL_TESTS"
    echo -e "   ${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "   ${RED}Failed: $FAILED_TESTS${NC}"
    echo ""

    echo "📋 Detailed Results:"
    for result in "${TEST_RESULTS[@]}"; do
        echo "   $result"
    done
    echo ""

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🔥 ALL TESTS PASSED! CITADEL ARCHITECTURE IS CROSS-PLATFORM READY! 🔥${NC}"
        exit 0
    else
        echo -e "${RED}❌ $FAILED_TESTS tests failed. Cross-platform deployment needs work.${NC}"
        echo ""
        echo "💡 Troubleshooting tips:"
        echo "   - Check build logs in /tmp/cross_build_*.log"
        echo "   - Ensure Zig toolchain supports all target platforms"
        echo "   - Verify no external dependencies in janus-core-daemon"
        echo "   - Run 'zig targets' to see supported cross-compilation targets"
        exit 1
    fi
}

# Check prerequisites
if ! command -v zig >/dev/null 2>&1; then
    echo -e "${RED}❌ ERROR: Zig compiler not found${NC}"
    echo "Please install Zig to run cross-compilation tests"
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  WARNING: bc calculator not found, file sizes will show as 'unknown'${NC}"
fi

# Run main test suite
main "$@"

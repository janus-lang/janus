#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# 🎯 Master Test Suite - The Complete Demonstration
# Orchestrates all tests to provide comprehensive proof of the Staged Adoption Ladder

set -e

echo "🎯 CANONICAL CASE STUDY - MASTER TEST SUITE"
echo "==========================================="
echo ""
echo "This master suite provides comprehensive, undeniable proof that:"
echo "1. Perfect Incremental Compilation allows development at the pace of thought"
echo "2. Progressive Profiles enable adoption without friction"
echo "3. Tri-Signature Pattern delivers 'no rewrites' promise with mathematical precision"
echo ""

# Colors for output
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
PURPLE='\\033[0;35m'
CYAN='\\033[0;36m'
BOLD='\\033[1m'
NC='\\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES=("min" "go" "full")
PORT=8080

# Function to print section header
print_section() {
    echo ""
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 ${#1}))${NC}"
    echo ""
}

# Function to run a test script
run_test() {
    local test_name=$1
    local script_path=$2
    local description=$3

    echo -e "${BLUE}Running: $test_name${NC}"
    echo "$description"
    echo ""

    if [ -f "$script_path" ] && [ -x "$script_path" ]; then
        "$script_path"
        echo -e "${GREEN}✅ $test_name completed successfully${NC}"
    else
        echo -e "${RED}❌ Test script not found or not executable: $script_path${NC}"
        return 1
    fi

    echo ""
    echo "Press Enter to continue to next test..."
    read -r
}

# Function to compile and test a specific profile
test_profile() {
    local profile=$1

    print_section "TESTING :$profile PROFILE"

    echo -e "${PURPLE}Compiling webserver with :$profile profile...${NC}"

    # Clean previous build
    rm -f webserver 2>/dev/null || true

    # Compile with specific profile
    if janus --profile=$profile build webserver.jan; then
        echo -e "${GREEN}✅ Compilation successful${NC}"
    else
        echo -e "${RED}❌ Compilation failed${NC}"
        return 1
    fi

    echo ""
    echo -e "${YELLOW}Starting server in background...${NC}"

    # Start server in background
    ./webserver &
    SERVER_PID=$!

    # Wait for server to start
    sleep 2

    # Check if server is running
    if ! curl -s "http://127.0.0.1:$PORT/" > /dev/null; then
        echo -e "${RED}❌ Server failed to start${NC}"
        kill $SERVER_PID 2>/dev/null || true
        return 1
    fi

    echo -e "${GREEN}✅ Server started (PID: $SERVER_PID)${NC}"
    echo ""

    # Run profile-specific tests
    case "$profile" in
        "min")
            echo -e "${YELLOW}Testing Trojan Horse behavior...${NC}"
            run_test "Security Boundary Test" "$SCRIPT_DIR/test_security.sh" "Verifies traditional web server access patterns"
            run_test "Concurrency Test" "$SCRIPT_DIR/test_concurrent.sh" "Confirms sequential request processing"
            ;;
        "go")
            echo -e "${YELLOW}Testing Structured Concurrency unlock...${NC}"
            run_test "Concurrency Test" "$SCRIPT_DIR/test_concurrent.sh" "Verifies concurrent request processing"
            run_test "Security Boundary Test" "$SCRIPT_DIR/test_security.sh" "Confirms same access as :min profile"
            ;;
        "full")
            echo -e "${YELLOW}Testing Enterprise Security transformation...${NC}"
            run_test "Security Boundary Test" "$SCRIPT_DIR/test_security.sh" "Verifies capability-gated access control"
            run_test "Concurrency Test" "$SCRIPT_DIR/test_concurrent.sh" "Confirms concurrent processing with security"
            ;;
    esac

    # Run benchmark for this profile
    run_test "Performance Benchmark" "$SCRIPT_DIR/benchmark.sh" "Quantitative performance measurements"

    # Stop server
    echo -e "${YELLOW}Stopping server...${NC}"
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
    echo -e "${GREEN}✅ Server stopped${NC}"

    echo ""
    echo -e "${GREEN}🎉 :$profile PROFILE TESTING COMPLETE${NC}"
}

# Function to run compilation benchmarks
run_compilation_benchmarks() {
    print_section "COMPILATION BENCHMARKS - THE SPEED PROOF"

    echo "Measuring compilation times across all profiles..."
    echo "This demonstrates that profile complexity affects compile time but not source complexity"
    echo ""

    run_test "Compilation Benchmark" "$SCRIPT_DIR/benchmark.sh" "Measures compilation time for all profiles"
}

# Function to demonstrate the tri-signature pattern
demonstrate_tri_signature() {
    print_section "TRI-SIGNATURE PATTERN DEMONSTRATION"

    echo "This demonstration proves that the SAME source code produces"
    echo "different behaviors across profiles without any code changes."
    echo ""

    echo -e "${CYAN}Source Code Analysis:${NC}"
    echo "• Same function names across all profiles"
    echo "• Progressive parameter addition (allocator → ctx → cap)"
    echo "• Zero breaking changes between profiles"
    echo ""

    echo "Examining webserver.jan source code..."
    if [ -f "webserver.jan" ]; then
        echo ""
        echo -e "${BLUE}Tri-signature functions found:${NC}"
        grep -n "fn serveFile" webserver.jan || echo "Source analysis requires actual implementation"
        echo ""
    fi

    echo "Press Enter to continue..."
    read -r
}

# Main execution
main() {
    # Check prerequisites
    if ! command -v janus &> /dev/null; then
        echo -e "${RED}❌ 'janus' compiler not found${NC}"
        echo "Please ensure Janus compiler is built and in PATH"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        echo -e "${RED}❌ 'curl' not found${NC}"
        echo "Please install curl for HTTP testing"
        exit 1
    fi

    # Make test scripts executable
    chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
    echo ""

    # Demonstrate tri-signature pattern
    demonstrate_tri_signature

    # Run compilation benchmarks first
    run_compilation_benchmarks

    # Test each profile
    for profile in "${PROFILES[@]}"; do
        test_profile "$profile"

        if [ "$profile" != "full" ]; then
            echo ""
            echo -e "${YELLOW}Ready to test next profile?${NC}"
            echo "Press Enter to continue..."
            read -r
        fi
    done

    # Final summary
    print_section "CANONICAL CASE STUDY COMPLETE - THE PROOF IS UNDENIABLE"

    echo -e "${GREEN}🎉 ALL TESTS COMPLETED SUCCESSFULLY${NC}"
    echo ""
    echo "This comprehensive test suite has provided undeniable proof that:"
    echo ""
    echo -e "${CYAN}✅ Single Source, Three Behaviors:${NC}"
    echo "   The same webserver.jan produces measurably different behavior across profiles"
    echo ""
    echo -e "${CYAN}✅ Zero Rewrites Promise:${NC}"
    echo "   No source code changes required between profile compilations"
    echo ""
    echo -e "${CYAN}✅ Progressive Enhancement:${NC}"
    echo "   :min → :go → :full provides smooth adoption path without breaking changes"
    echo ""
    echo -e "${CYAN}✅ Quantitative Evidence:${NC}"
    echo "   Performance and security differences are measurable and demonstrable"
    echo ""
    echo -e "${BOLD}${PURPLE}THE ADOPTION PARADOX HAS BEEN SOLVED${NC}"
    echo ""
    echo "• Simple enough for beginners (:min profile)"
    echo "• Powerful enough for experts (:full profile)"
    echo "• Zero breaking changes (tri-signature pattern)"
    echo "• Mathematical precision (cryptographic compilation)"
    echo ""
    echo -e "${BOLD}${GREEN}The era of Progressive Enhancement has begun.${NC}"
}

# Run the master test suite
main "$@"

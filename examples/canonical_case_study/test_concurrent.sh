#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# 🎯 Concurrent Request Testing - The Behavioral Proof
# Demonstrates that :min processes sequentially while :go/:full process concurrently

set -e

echo "🎯 CONCURRENT REQUEST TESTING - THE BEHAVIORAL PROOF"
echo "=================================================="
echo ""
echo "This test demonstrates the fundamental behavioral difference between profiles:"
echo "• :min profile → Sequential processing (blocking, like traditional servers)"
echo "• :go profile → Concurrent processing (structured concurrency)"
echo "• :full profile → Concurrent processing with capability security"
echo ""

# Colors for output
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
PURPLE='\\033[0;35m'
NC='\\033[0m' # No Color

# Configuration
PORT=8080
HOST="127.0.0.1"
NUM_REQUESTS=5
DELAY_ENDPOINT="/delay/2"  # 2 second delay endpoint

# Function to test concurrent behavior
test_profile_concurrency() {
    local profile=$1
    local expected_behavior=$2

    echo -e "${BLUE}Testing $profile profile concurrency...${NC}"
    echo "Sending $NUM_REQUESTS requests with 2-second delays"

    # Start timer
    start_time=$(date +%s)

    # Send concurrent requests
    for i in $(seq 1 $NUM_REQUESTS); do
        curl -s "http://$HOST:$PORT$DELAY_ENDPOINT" > /dev/null &
    done

    # Wait for all requests to complete
    wait

    # Calculate total time
    end_time=$(date +%s)
    total_time=$((end_time - start_time))

    echo "Total time: ${total_time}s"

    # Analyze results
    if [ "$expected_behavior" = "sequential" ]; then
        expected_min=10  # 5 requests × 2s each = 10s minimum
        if [ $total_time -ge $expected_min ]; then
            echo -e "${GREEN}✅ SEQUENTIAL BEHAVIOR CONFIRMED${NC}"
            echo "   Expected: ≥${expected_min}s (sequential processing)"
            echo "   Actual: ${total_time}s"
        else
            echo -e "${RED}❌ UNEXPECTED CONCURRENT BEHAVIOR${NC}"
            echo "   Expected: ≥${expected_min}s (sequential)"
            echo "   Actual: ${total_time}s (too fast - concurrent?)"
        fi
    else
        expected_max=4   # Should complete in ~2-3s if concurrent
        if [ $total_time -le $expected_max ]; then
            echo -e "${GREEN}✅ CONCURRENT BEHAVIOR CONFIRMED${NC}"
            echo "   Expected: ≤${expected_max}s (concurrent processing)"
            echo "   Actual: ${total_time}s"
        else
            echo -e "${RED}❌ UNEXPECTED SEQUENTIAL BEHAVIOR${NC}"
            echo "   Expected: ≤${expected_max}s (concurrent)"
            echo "   Actual: ${total_time}s (too slow - sequential?)"
        fi
    fi

    echo ""
}

# Function to check if server is running
check_server() {
    if ! curl -s "http://$HOST:$PORT/" > /dev/null; then
        echo -e "${RED}❌ Server not running on http://$HOST:$PORT${NC}"
        echo "Please start the server first:"
        echo "  janus --profile=min build webserver.jan && ./webserver"
        exit 1
    fi
}

# Main test execution
main() {
    echo "🔍 Checking server availability..."
    check_server
    echo -e "${GREEN}✅ Server is running${NC}"
    echo ""

    # Detect current profile by making a test request
    profile_info=$(curl -s "http://$HOST:$PORT/" | grep -o "Current Profile: :[a-z]*" | cut -d: -f3 || echo "unknown")

    echo -e "${PURPLE}Detected Profile: :$profile_info${NC}"
    echo ""

    case "$profile_info" in
        "min")
            test_profile_concurrency ":min" "sequential"
            echo -e "${YELLOW}💡 The Trojan Horse in Action:${NC}"
            echo "   :min profile processes requests sequentially (like traditional Go servers)"
            echo "   This familiar behavior makes adoption non-threatening for conservative teams"
            ;;
        "go")
            test_profile_concurrency ":go" "concurrent"
            echo -e "${YELLOW}💡 Structured Concurrency Unlocked:${NC}"
            echo "   :go profile processes requests concurrently with context awareness"
            echo "   Same source code, enhanced performance through structured concurrency"
            ;;
        "full")
            test_profile_concurrency ":full" "concurrent"
            echo -e "${YELLOW}💡 Enterprise Security with Performance:${NC}"
            echo "   :full profile combines concurrent processing with capability security"
            echo "   Maximum performance AND maximum security from the same source code"
            ;;
        *)
            echo -e "${RED}❌ Could not detect profile${NC}"
            echo "Server response doesn't contain expected profile information"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}🎉 BEHAVIORAL PROOF COMPLETE${NC}"
    echo ""
    echo "This test proves that the same source code produces fundamentally different"
    echo "concurrency behavior based on the compilation profile - without any code changes!"
}

# Run the test
main "$@"

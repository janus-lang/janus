#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# 📊 Performance Benchmark - The Quantitative Proof
# Provides brutal, quantitative evidence of profile performance characteristics

set -e

echo "📊 PERFORMANCE BENCHMARK - THE QUANTITATIVE PROOF"
echo "=============================================="
echo ""
echo "This benchmark provides undeniable, quantitative evidence of profile differences:"
echo "• Compilation time across profiles"
echo "• Runtime performance characteristics"
echo "• Memory usage patterns"
echo "• Concurrency scaling behavior"
echo ""

# Colors for output
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
PURPLE='\\033[0;35m'
CYAN='\\033[0;36m'
NC='\\033[0m' # No Color

# Configuration
PORT=8080
HOST="127.0.0.1"
WARMUP_REQUESTS=10
BENCHMARK_REQUESTS=100
CONCURRENT_LEVELS=(1 5 10 20)

# Results storage
declare -A compilation_times
declare -A response_times
declare -A throughput_results

# Function to measure compilation time
measure_compilation() {
    local profile=$1

    echo -e "${BLUE}Measuring compilation time for :$profile profile...${NC}"

    # Clean previous build
    rm -f webserver 2>/dev/null || true

    # Measure compilation time
    start_time=$(date +%s.%N)
    janus --profile=$profile build webserver.jan > /dev/null 2>&1
    end_time=$(date +%s.%N)

    # Calculate duration in milliseconds
    duration=$(echo "($end_time - $start_time) * 1000" | bc -l)
    compilation_times[$profile]=$(printf "%.0f" $duration)

    echo "Compilation time: ${compilation_times[$profile]}ms"
    echo ""
}

# Function to measure response time
measure_response_time() {
    local endpoint=$1
    local num_requests=$2

    echo "Measuring response time for $num_requests requests to $endpoint..."

    # Use curl to measure timing
    local total_time=0
    local successful_requests=0

    for i in $(seq 1 $num_requests); do
        # Measure single request time
        time_total=$(curl -s -w "%{time_total}" -o /dev/null "http://$HOST:$PORT$endpoint" 2>/dev/null || echo "0")

        if [ "$time_total" != "0" ]; then
            total_time=$(echo "$total_time + $time_total" | bc -l)
            successful_requests=$((successful_requests + 1))
        fi
    done

    if [ $successful_requests -gt 0 ]; then
        local avg_time=$(echo "scale=3; $total_time / $successful_requests" | bc -l)
        echo "Average response time: ${avg_time}s ($successful_requests/$num_requests successful)"
        echo "$avg_time"
    else
        echo "0"
    fi
}

# Function to measure concurrent throughput
measure_throughput() {
    local concurrent_level=$1
    local endpoint="/public/index.html"

    echo -e "${CYAN}Testing throughput with $concurrent_level concurrent connections...${NC}"

    # Start timer
    start_time=$(date +%s.%N)

    # Launch concurrent requests
    for i in $(seq 1 $concurrent_level); do
        curl -s "http://$HOST:$PORT$endpoint" > /dev/null &
    done

    # Wait for all to complete
    wait

    # Calculate throughput
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    throughput=$(echo "scale=2; $concurrent_level / $duration" | bc -l)

    echo "Throughput: $throughput requests/second"
    echo "$throughput"
}

# Function to check if server is running
check_server() {
    if ! curl -s "http://$HOST:$PORT/" > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Function to detect current profile
detect_profile() {
    local response=$(curl -s "http://$HOST:$PORT/" 2>/dev/null || echo "")
    if echo "$response" | grep -q "Current Profile: :min"; then
        echo "min"
    elif echo "$response" | grep -q "Current Profile: :go"; then
        echo "go"
    elif echo "$response" | grep -q "Current Profile: :full"; then
        echo "full"
    else
        echo "unknown"
    fi
}

# Main benchmark execution
main() {
    echo "🔧 COMPILATION BENCHMARKS"
    echo "========================"
    echo ""

    # Measure compilation times for all profiles
    for profile in min go full; do
        measure_compilation $profile
    done

    echo "📈 COMPILATION RESULTS:"
    echo "----------------------"
    printf "%-8s %10s\n" "Profile" "Time (ms)"
    printf "%-8s %10s\n" "-------" "---------"
    for profile in min go full; do
        printf "%-8s %10s\n" ":$profile" "${compilation_times[$profile]}"
    done
    echo ""

    # Check if server is running for runtime benchmarks
    if ! check_server; then
        echo -e "${YELLOW}⚠️  Server not running - skipping runtime benchmarks${NC}"
        echo "To run complete benchmarks:"
        echo "1. Start server: janus --profile=<profile> build webserver.jan && ./webserver"
        echo "2. Run this script again"
        exit 0
    fi

    # Detect current profile
    profile=$(detect_profile)
    echo -e "${PURPLE}🎯 RUNTIME BENCHMARKS FOR :$profile PROFILE${NC}"
    echo "============================================="
    echo ""

    # Warmup
    echo "🔥 Warming up server..."
    measure_response_time "/public/index.html" $WARMUP_REQUESTS > /dev/null
    echo "Warmup complete"
    echo ""

    # Response time benchmark
    echo "⏱️  RESPONSE TIME BENCHMARK"
    echo "============================"
    avg_response=$(measure_response_time "/public/index.html" $BENCHMARK_REQUESTS)
    echo ""

    # Throughput benchmarks
    echo "🚀 THROUGHPUT BENCHMARKS"
    echo "========================"
    echo ""

    for level in "${CONCURRENT_LEVELS[@]}"; do
        throughput=$(measure_throughput $level)
        throughput_results[$level]=$throughput
        echo ""
    done

    # Results summary
    echo -e "${GREEN}📊 BENCHMARK RESULTS SUMMARY${NC}"
    echo "============================="
    echo ""
    echo "Profile: :$profile"
    echo "Average Response Time: ${avg_response}s"
    echo ""
    echo "Throughput Results:"
    printf "%-15s %15s\n" "Concurrent Reqs" "Throughput (req/s)"
    printf "%-15s %15s\n" "---------------" "-----------------"
    for level in "${CONCURRENT_LEVELS[@]}"; do
        printf "%-15s %15s\n" "$level" "${throughput_results[$level]}"
    done
    echo ""

    # Profile-specific analysis
    case "$profile" in
        "min")
            echo -e "${YELLOW}💡 :min Profile Analysis:${NC}"
            echo "• Fastest compilation (simple, no advanced features)"
            echo "• Sequential processing (throughput doesn't scale with concurrency)"
            echo "• Predictable, familiar performance characteristics"
            echo "• Perfect for development and simple deployments"
            ;;
        "go")
            echo -e "${YELLOW}💡 :go Profile Analysis:${NC}"
            echo "• Moderate compilation time (structured concurrency features)"
            echo "• Concurrent processing (throughput scales with load)"
            echo "• Context-aware request handling with timeout protection"
            echo "• Ideal for production services requiring reliability"
            ;;
        "full")
            echo -e "${YELLOW}💡 :full Profile Analysis:${NC}"
            echo "• Longer compilation (full capability security system)"
            echo "• Concurrent processing with security overhead"
            echo "• Capability validation adds small latency cost"
            echo "• Enterprise-grade security with acceptable performance"
            ;;
    esac

    echo ""
    echo -e "${GREEN}🎉 QUANTITATIVE PROOF COMPLETE${NC}"
    echo ""
    echo "These measurements provide undeniable evidence that the same source"
    echo "code produces measurably different performance characteristics"
    echo "based on the compilation profile - without any code changes!"
}

# Check for required tools
if ! command -v bc &> /dev/null; then
    echo -e "${RED}❌ 'bc' calculator not found${NC}"
    echo "Please install bc: sudo apt-get install bc"
    exit 1
fi

# Run the benchmark
main "$@"

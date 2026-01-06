#!/bin/bash

echo "Running Error Recovery and Performance Tests..."
echo "=============================================="

# Run the specific test file
zig test compiler/semantic/validation_engine_recovery_performance_tests.zig

echo "Test run completed."
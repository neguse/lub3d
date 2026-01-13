#!/bin/bash
# Run headless tests for all examples
# Usage: ./scripts/run_tests.sh [build_dir] [num_frames]

set -e

BUILD_DIR="${1:-build/dummy-release}"
NUM_FRAMES="${2:-10}"

# Find test runner
if [ -f "$BUILD_DIR/mane3d-test.exe" ]; then
    TEST_RUNNER="$BUILD_DIR/mane3d-test.exe"
elif [ -f "$BUILD_DIR/mane3d-test" ]; then
    TEST_RUNNER="$BUILD_DIR/mane3d-test"
else
    echo "Error: mane3d-test not found in $BUILD_DIR"
    exit 1
fi

echo "Using test runner: $TEST_RUNNER"
echo "Frames per test: $NUM_FRAMES"
echo ""

PASSED=0
FAILED=0
SKIPPED=0

# Examples to test (add more as needed)
# Note: rendering/init.lua excluded - requires assets/mill-scene which is gitignored
EXAMPLES=(
    "examples/main.lua"
    "examples/breakout.lua"
    "examples/raytracer.lua"
    "examples/lighting.lua"
    "examples/triangle.lua"
    "examples/hakonotaiatari/init.lua"
)

for script in "${EXAMPLES[@]}"; do
    if [ -f "$script" ]; then
        echo "----------------------------------------"
        echo "Testing: $script"
        if "./$TEST_RUNNER" "$script" "$NUM_FRAMES"; then
            ((PASSED++)) || true
        else
            echo "FAILED with exit code: $?"
            ((FAILED++)) || true
        fi
    else
        echo "Skipped (not found): $script"
        ((SKIPPED++)) || true
    fi
done

echo ""
echo "========================================"
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo "========================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

#!/bin/bash
# Run headless tests for all examples
# Usage: ./scripts/run_tests.sh [build_dir] [num_frames]

set -e

BUILD_DIR="${1:-build/dummy-release}"
NUM_FRAMES="${2:-10}"

# Find test runner
if [ -f "$BUILD_DIR/lub3d-test.exe" ]; then
    TEST_RUNNER="$BUILD_DIR/lub3d-test.exe"
elif [ -f "$BUILD_DIR/lub3d-test" ]; then
    TEST_RUNNER="$BUILD_DIR/lub3d-test"
else
    echo "Error: lub3d-test not found in $BUILD_DIR"
    exit 1
fi

echo "Using test runner: $TEST_RUNNER"
echo "Frames per test: $NUM_FRAMES"
echo ""

PASSED=0
FAILED=0
SKIPPED=0

# Module names to test
# Note: examples.rendering excluded - requires assets/mill-scene which is gitignored
MODULES=(
    "examples.main"
    "examples.breakout"
    "examples.raytracer"
    "examples.lighting"
    "examples.triangle"
    "examples.hakonotaiatari"
)

for mod in "${MODULES[@]}"; do
    echo "----------------------------------------"
    echo "Testing: $mod"
    if "$TEST_RUNNER" "$mod" "$NUM_FRAMES"; then
        ((PASSED++)) || true
    else
        echo "FAILED with exit code: $?"
        ((FAILED++)) || true
    fi
done

echo ""
echo "========================================"
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo "========================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

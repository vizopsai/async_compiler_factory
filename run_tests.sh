#!/bin/bash
# =============================================================================
# CCC Test Runner (Stub / Reconstruction)
# =============================================================================
# The real test runner was external infrastructure maintained by Nicholas
# Carlini. This is a reconstruction based on behavior observed in commit
# messages and the blog post.
#
# The real runner had:
#   - ~3000 test cases across multiple suites (compiler_suite, c_testsuite,
#     gcc_torture, tcc_tests)
#   - 48+ real-world project builds (SQLite, PostgreSQL, Redis, FFmpeg, etc.)
#   - --ratio N flag for N% deterministic sampling
#   - Per-agent seed (via AGENT_ID env var) for different test subsets
#   - Summary-only output (no context window pollution)
#   - Detailed logs written to files for Claude to grep
#   - GCC as reference oracle for kernel compilation comparison
#
# Usage:
#   ./run_tests.sh                 # Full test suite
#   ./run_tests.sh --fast          # 1% sample (~30 seconds)
#   ./run_tests.sh --ratio 10     # 10% sample
# =============================================================================

set -e

COMPILER_DIR="${COMPILER_DIR:-/workspace/code}"
COMPILER="$COMPILER_DIR/target/release/ccc"
TEST_SUITES_DIR="${TEST_SUITES_DIR:-/test-suites}"
RATIO=100
SEED="${AGENT_ID:-default}"
LOG_DIR="/workspace/test_logs"

mkdir -p "$LOG_DIR"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fast)
            RATIO=1
            shift
            ;;
        --ratio)
            RATIO="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

echo "CCC Test Runner"
echo "  Compiler: $COMPILER"
echo "  Ratio: ${RATIO}%"
echo "  Seed: $SEED"
echo ""

# Ensure compiler is built
if [ ! -f "$COMPILER" ]; then
    echo "ERROR: Compiler not found at $COMPILER"
    echo "Run: cargo build --release"
    exit 1
fi

# ---- Architecture test loop ----
# Tests each architecture with the appropriate binary
ARCHITECTURES=("x86:ccc-x86" "arm:ccc-arm" "riscv:ccc-riscv" "i686:ccc-i686")

for arch_entry in "${ARCHITECTURES[@]}"; do
    ARCH="${arch_entry%%:*}"
    BINARY="${arch_entry##*:}"
    ARCH_COMPILER="$COMPILER_DIR/target/release/$BINARY"

    if [ ! -f "$ARCH_COMPILER" ]; then
        echo "$ARCH: SKIP (binary not found)"
        continue
    fi

    PASS=0
    FAIL=0
    TOTAL=0
    FAIL_LOG="$LOG_DIR/failures_${ARCH}.log"
    > "$FAIL_LOG"

    # Run tests from each test suite directory
    for SUITE_DIR in "$TEST_SUITES_DIR"/*/; do
        SUITE_NAME=$(basename "$SUITE_DIR")

        # Find all test cases (*.c files)
        while IFS= read -r -d '' test_file; do
            TOTAL=$((TOTAL + 1))

            # Deterministic sampling: hash(seed + test_path) mod 100 < ratio
            HASH=$(echo "${SEED}${test_file}" | md5sum | cut -c1-8)
            HASH_NUM=$((16#$HASH % 100))
            if [ "$HASH_NUM" -ge "$RATIO" ]; then
                continue
            fi

            # Compile with CCC
            BASENAME=$(basename "$test_file" .c)
            OUTPUT="/tmp/ccc_test_${BASENAME}"

            if $ARCH_COMPILER -o "$OUTPUT" "$test_file" 2>/dev/null; then
                # Run the binary (with QEMU for cross-arch)
                case "$ARCH" in
                    x86)    RESULT=$("$OUTPUT" 2>/dev/null) ;;
                    arm)    RESULT=$(qemu-aarch64 -L /usr/aarch64-linux-gnu "$OUTPUT" 2>/dev/null) ;;
                    riscv)  RESULT=$(qemu-riscv64 -L /usr/riscv64-linux-gnu "$OUTPUT" 2>/dev/null) ;;
                    i686)   RESULT=$("$OUTPUT" 2>/dev/null) ;;
                esac
                EXIT_CODE=$?

                # Compare against expected output if available
                EXPECTED_FILE="${test_file%.c}.expected"
                if [ -f "$EXPECTED_FILE" ]; then
                    EXPECTED=$(cat "$EXPECTED_FILE")
                    if [ "$RESULT" = "$EXPECTED" ] && [ "$EXIT_CODE" -eq 0 ]; then
                        PASS=$((PASS + 1))
                    else
                        FAIL=$((FAIL + 1))
                        echo "ERROR $SUITE_NAME/$BASENAME: expected='$EXPECTED' got='$RESULT' exit=$EXIT_CODE" >> "$FAIL_LOG"
                    fi
                else
                    # No expected file: just check it compiled and ran without crash
                    if [ "$EXIT_CODE" -eq 0 ]; then
                        PASS=$((PASS + 1))
                    else
                        FAIL=$((FAIL + 1))
                        echo "ERROR $SUITE_NAME/$BASENAME: crash exit=$EXIT_CODE" >> "$FAIL_LOG"
                    fi
                fi
            else
                FAIL=$((FAIL + 1))
                echo "ERROR $SUITE_NAME/$BASENAME: compilation failed" >> "$FAIL_LOG"
            fi

            rm -f "$OUTPUT"
        done < <(find "$SUITE_DIR" -name "*.c" -print0 | sort -z)
    done

    TESTED=$((PASS + FAIL))
    if [ "$TESTED" -gt 0 ]; then
        PCT=$(echo "scale=1; $PASS * 100 / $TESTED" | bc)
        echo "$ARCH: $PASS/$TESTED ($PCT%) [sampled from $TOTAL total]"
    else
        echo "$ARCH: no tests found"
    fi

    if [ -s "$FAIL_LOG" ]; then
        FAIL_COUNT=$(wc -l < "$FAIL_LOG")
        echo "  $FAIL_COUNT failures logged to $FAIL_LOG"
        # Print first 5 failures only (avoid context window pollution)
        head -5 "$FAIL_LOG" | sed 's/^/  /'
        if [ "$FAIL_COUNT" -gt 5 ]; then
            echo "  ... and $((FAIL_COUNT - 5)) more (see $FAIL_LOG)"
        fi
    fi
    echo ""
done

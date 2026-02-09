#!/bin/bash
# =============================================================================
# CCC Agent Teams — Timeseries: tests passing over time
# =============================================================================
# Builds and tests every commit in one or more upstream.git repos, outputting
# a CSV suitable for plotting progress over time.
#
# Usage:
#   ./timeseries.sh path/to/upstream1.git [path/to/upstream2.git ...]
#
# Output: timeseries.csv in the same directory as this script
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/timeseries.csv"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <upstream1.git> [upstream2.git ...]"
    echo ""
    echo "Example:"
    echo "  $0 ../scaffolding_1_120/upstream.git ../scaffolding_2_60/upstream.git"
    exit 1
fi

if ! docker image inspect ccc-agent &>/dev/null 2>&1; then
    echo "ERROR: ccc-agent Docker image not found. Run ./run.sh first to build it."
    exit 1
fi

echo "repo,time_offset_min,timestamp,commit,tests_passed,tests_total,loc,message" > "$OUTPUT_FILE"

for REPO_PATH in "$@"; do
    # Resolve to absolute path
    REPO_ABS="$(cd "$(dirname "$REPO_PATH")" && pwd)/$(basename "$REPO_PATH")"
    LABEL="$(basename "$(dirname "$REPO_ABS")")"

    if [ ! -d "$REPO_ABS" ]; then
        echo "SKIP: $REPO_PATH not found"
        continue
    fi

    echo "=== Processing $LABEL ==="
    echo "    Repo: $REPO_ABS"

    # Count commits to show progress
    TOTAL_COMMITS=$(git --git-dir="$REPO_ABS" rev-list --count HEAD 2>/dev/null || echo "?")
    echo "    Commits: $TOTAL_COMMITS"
    echo ""

    docker run --rm \
        --entrypoint bash \
        -v "$REPO_ABS:/upstream:ro" \
        -e "LABEL=$LABEL" \
        --memory 8g \
        --cpus 2 \
        ccc-agent \
        -c '
            git clone /upstream /tmp/code 2>/dev/null
            cd /tmp/code

            # Get all commits chronologically (oldest first)
            COMMITS=$(git log --format="%H %at %s" 2>/dev/null | tac)
            FIRST_EPOCH=$(echo "$COMMITS" | head -1 | awk "{print \$2}")

            echo "$COMMITS" > /tmp/commits.txt

            N=0
            TOTAL=$(wc -l < /tmp/commits.txt)

            while read HASH EPOCH MSG; do
                N=$((N + 1))

                # Skip task lock / cleanup commits (no source changes)
                echo "$MSG" | grep -qiE "^Lock task|clearing task|^Remove task lock|^Add idea|^Update idea" && continue

                MINUTES=$(( (EPOCH - FIRST_EPOCH) / 60 ))
                git checkout "$HASH" --quiet --force 2>/dev/null || continue

                LOC=$(find src -name "*.rs" -exec cat {} + 2>/dev/null | wc -l | tr -d " ")

                PASS=0
                TEST_TOTAL=0

                if cargo build --release </dev/null 2>/dev/null; then
                    CCC="./target/release/ccc"
                    for f in /test-suites/basic/*.c; do
                        TEST_TOTAL=$((TEST_TOTAL + 1))
                        OUT="/tmp/ccc_test_bin"
                        if $CCC -o "$OUT" "$f" </dev/null 2>/dev/null; then
                            RESULT=$(timeout 5 "$OUT" </dev/null 2>/dev/null)
                            EC=$?
                            EXPECTED="${f%.c}.expected"
                            if [ -f "$EXPECTED" ]; then
                                [ $EC -eq 0 ] && [ "$RESULT" = "$(cat "$EXPECTED")" ] && PASS=$((PASS + 1))
                            else
                                [ $EC -eq 0 ] && PASS=$((PASS + 1))
                            fi
                        fi
                        rm -f "$OUT"
                    done
                fi

                # Escape commas in message for CSV
                SAFE_MSG=$(echo "$MSG" | tr "," ";")

                echo "$LABEL,$MINUTES,$EPOCH,${HASH:0:7},$PASS,$TEST_TOTAL,$LOC,$SAFE_MSG"

                # Progress on stderr
                >&2 printf "  [%d/%d] +%dmin  %d/%d tests  %s lines  %s\n" \
                    "$N" "$TOTAL" "$MINUTES" "$PASS" "$TEST_TOTAL" "$LOC" "${MSG:0:50}"
            done < /tmp/commits.txt
        ' >> "$OUTPUT_FILE"

    echo ""
    echo "    Done: $LABEL"
    echo ""
done

echo "=== Results ==="
echo ""
echo "Saved to: $OUTPUT_FILE"
echo ""

# Print a summary table
column -t -s',' "$OUTPUT_FILE" 2>/dev/null || cat "$OUTPUT_FILE"

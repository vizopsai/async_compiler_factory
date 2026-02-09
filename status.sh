#!/bin/bash
# =============================================================================
# CCC Agent Teams — Progress Snapshot
# =============================================================================
# Shows current state of all agents and the shared repo.
# Safe to run anytime, whether agents are running or not.
#
# Usage:
#   ./status.sh           # full snapshot
#   ./status.sh --short   # just commit count + lines of code
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_DIR="$SCRIPT_DIR/upstream.git"
SHORT=false

[[ "$1" == "--short" ]] && SHORT=true

# ---- Running agents ----

RUN_PREFIX="ccc-$(basename "$SCRIPT_DIR" | tr -cd 'a-zA-Z0-9_')"
RUNNING=$(docker ps --filter name=$RUN_PREFIX --format "{{.Names}}" 2>/dev/null)
RUNNING_COUNT=$(echo "$RUNNING" | grep -c . 2>/dev/null || echo 0)

if [ -z "$RUNNING" ]; then
    RUNNING_COUNT=0
fi

echo "============================================"
echo "  CCC Agent Teams — Status"
echo "  $(date)"
echo "============================================"
echo ""
echo "Agents running: $RUNNING_COUNT"

if [ "$RUNNING_COUNT" -gt 0 ]; then
    docker ps --filter name=$RUN_PREFIX --format "  {{.Names}}  up {{.RunningFor}}" 2>/dev/null
fi
echo ""

# ---- Repo state ----

if [ ! -d "$UPSTREAM_DIR" ]; then
    echo "No upstream.git found. Run ./run.sh to start."
    exit 0
fi

TEMP=$(mktemp -d)
git clone "$UPSTREAM_DIR" "$TEMP/code" 2>/dev/null

if [ ! -d "$TEMP/code" ]; then
    echo "Failed to clone upstream.git"
    rm -rf "$TEMP"
    exit 1
fi

cd "$TEMP/code"

COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
LATEST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "(none)")

echo "--- Repository ---"
echo "Commits: $COMMIT_COUNT"
echo "Latest:  $LATEST_COMMIT"

if [ -d src ]; then
    RS_FILES=$(find src -name "*.rs" 2>/dev/null | wc -l | tr -d ' ')
    RS_LINES=$(find src -name "*.rs" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
    echo "Source:  $RS_FILES Rust files, $RS_LINES lines"
else
    echo "Source:  no src/ directory yet"
fi

if $SHORT; then
    rm -rf "$TEMP"
    exit 0
fi

echo ""

# ---- Commit history ----

echo "--- Recent Commits ---"
git log --oneline -20 2>/dev/null | sed 's/^/  /'
echo ""

# ---- Module breakdown ----

if [ -d src ]; then
    echo "--- Source Breakdown ---"
    # Top-level .rs files
    for f in src/*.rs; do
        if [ -f "$f" ]; then
            LINES=$(wc -l < "$f" | tr -d ' ')
            echo "  $(basename "$f"): $LINES lines"
        fi
    done
    # Subdirectories
    for dir in src/*/; do
        if [ -d "$dir" ]; then
            DIR_FILES=$(find "$dir" -name "*.rs" | wc -l | tr -d ' ')
            DIR_LINES=$(find "$dir" -name "*.rs" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
            echo "  $(basename "$dir")/: $DIR_LINES lines ($DIR_FILES files)"
        fi
    done
    echo ""
fi

# ---- Build + Test (inside Docker) ----

echo "--- Build & Test Status ---"
if docker image inspect ccc-agent &>/dev/null 2>&1; then
    DOCKER_CONTAINER_NAME="${RUN_PREFIX}-status-$$"

    # Run build + tests inside a temporary container with the same image
    # --entrypoint bash: bypass the agent loop (entrypoint.sh)
    # Mount upstream.git read-only so we don't mutate it
    DOCKER_OUTPUT=$(docker run --rm \
        --name "$DOCKER_CONTAINER_NAME" \
        --entrypoint bash \
        -v "$UPSTREAM_DIR:/upstream:ro" \
        --memory 8g \
        --cpus 2 \
        ccc-agent \
        -c '
            set -e

            # Clone repo
            git clone /upstream /workspace/code 2>/dev/null
            cd /workspace/code

            # Build
            echo "BUILD_START"
            if cargo build --release 2>&1 | tail -5; then
                echo "BUILD_OK"
            else
                echo "BUILD_FAILED"
                exit 0
            fi

            # Run tests (full suite against the baked-in /test-suites/)
            echo "TEST_START"
            if [ -f run_tests.sh ]; then
                chmod +x run_tests.sh
                bash run_tests.sh 2>&1 || true
            else
                echo "No run_tests.sh found"
            fi
            echo "TEST_DONE"
        ' 2>&1) || true

    # Parse and display build result
    if echo "$DOCKER_OUTPUT" | grep -q "BUILD_OK"; then
        echo "  Build: OK"
    elif echo "$DOCKER_OUTPUT" | grep -q "BUILD_FAILED"; then
        echo "  Build: FAILED"
        echo "$DOCKER_OUTPUT" | sed -n '/BUILD_START/,/BUILD_FAILED/p' | grep -v BUILD_ | tail -5 | sed 's/^/    /'
    else
        echo "  Build: ERROR (container failed)"
        echo "$DOCKER_OUTPUT" | tail -5 | sed 's/^/    /'
    fi

    # Parse and display test results
    TEST_OUTPUT=$(echo "$DOCKER_OUTPUT" | sed -n '/TEST_START/,/TEST_DONE/p' | grep -v 'TEST_START\|TEST_DONE')
    if [ -n "$TEST_OUTPUT" ]; then
        echo ""
        echo "  Tests:"
        echo "$TEST_OUTPUT" | sed 's/^/    /'
    fi
else
    echo "  (ccc-agent Docker image not found — run ./run.sh first to build it)"
fi
echo ""

# ---- Active tasks ----

echo "--- Active Tasks ---"
if ls current_tasks/*.txt 1>/dev/null 2>&1; then
    for f in current_tasks/*.txt; do
        TASK_NAME=$(basename "$f" .txt)
        FIRST_LINE=$(head -1 "$f")
        echo "  [$TASK_NAME] $FIRST_LINE"
    done
else
    echo "  (none)"
fi
echo ""

# ---- Ideas backlog ----

echo "--- Ideas ---"
if ls ideas/*.txt 1>/dev/null 2>&1; then
    for f in ideas/*.txt; do
        NAME=$(basename "$f" .txt)
        PRIORITY=$(grep -i "^Priority:" "$f" 2>/dev/null | head -1 | sed 's/Priority: *//')
        TITLE=$(head -1 "$f")
        echo "  [$PRIORITY] $TITLE"
    done
else
    echo "  (none)"
fi
echo ""

# ---- Live agent work (uncommitted changes) ----

if [ "$RUNNING_COUNT" -gt 0 ]; then
    echo "--- Live Agent Work (uncommitted) ---"
    for CONTAINER in $RUNNING; do
        echo "  $CONTAINER:"
        # Show new/modified files
        WORK=$(docker exec "$CONTAINER" bash -c 'cd /workspace/code 2>/dev/null && git status --short 2>/dev/null' 2>/dev/null)
        if [ -n "$WORK" ]; then
            echo "$WORK" | head -15 | sed 's/^/    /'
            WORK_COUNT=$(echo "$WORK" | wc -l | tr -d ' ')
            if [ "$WORK_COUNT" -gt 15 ]; then
                echo "    ... and $((WORK_COUNT - 15)) more files"
            fi
            # Show total lines of Rust in working tree
            LIVE_LINES=$(docker exec "$CONTAINER" bash -c 'cd /workspace/code 2>/dev/null && find src -name "*.rs" -exec cat {} + 2>/dev/null | wc -l' 2>/dev/null | tr -d ' ')
            echo "    Source in working tree: $LIVE_LINES lines of Rust"
        else
            echo "    (clean working tree)"
        fi
        echo ""
    done
fi

rm -rf "$TEMP"

#!/bin/bash
# =============================================================================
# CCC Agent Teams - One-command launcher
# =============================================================================
# Sets up everything and runs agents for a fixed duration.
#
# Usage:
#   export ANTHROPIC_API_KEY="sk-ant-..."
#   ./run.sh                     # 2 agents, 60 minutes
#   ./run.sh 4                   # 4 agents, 60 minutes
#   ./run.sh 2 30                # 2 agents, 30 minutes
# =============================================================================

set -e

NUM_AGENTS=${1:-2}
DURATION=${2:-60}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  CCC Agent Teams"
echo "============================================"
echo "  Agents:   $NUM_AGENTS"
echo "  Duration: $DURATION minutes"
echo "============================================"
echo ""

# ---- Prerequisites ----

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ERROR: ANTHROPIC_API_KEY not set."
    echo ""
    echo "  export ANTHROPIC_API_KEY='sk-ant-...'"
    echo ""
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker not found. Install Docker Desktop first."
    exit 1
fi

if ! docker info &> /dev/null 2>&1; then
    echo "ERROR: Docker daemon not running. Start Docker Desktop first."
    exit 1
fi

# ---- Step 1: Build Docker image ----

echo "[1/4] Building Docker image (this may take a few minutes the first time)..."
docker build -t ccc-agent "$SCRIPT_DIR" 2>&1 | tail -5
echo "  Done."
echo ""

# ---- Step 2: Initialize upstream repo ----

if [ -d "$SCRIPT_DIR/upstream.git" ]; then
    echo "[2/4] Upstream repo already exists, reusing it."
    echo "  (Delete upstream.git to start fresh: rm -rf $SCRIPT_DIR/upstream.git)"
else
    echo "[2/4] Initializing upstream repo with seed project..."
    "$SCRIPT_DIR/init_repo.sh"
fi
echo ""

# ---- Step 3: Launch agents ----

echo "[3/4] Launching $NUM_AGENTS agents..."
"$SCRIPT_DIR/launch.sh" "$NUM_AGENTS"
echo ""

# ---- Step 4: Monitor and wait ----

echo "[4/4] Running for $DURATION minutes..."
START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION * 60))
echo "  Started:  $(date)"
echo "  Stopping: $(date -r $END_TIME 2>/dev/null || date -d @$END_TIME 2>/dev/null || echo "in $DURATION minutes")"
echo ""
echo "  Tip: Watch live agent logs in another terminal:"
echo "    docker logs -f ccc-agent-1"
echo ""

ELAPSED=0
INTERVAL=5  # Status update every 5 minutes

while [ $ELAPSED -lt $DURATION ]; do
    SLEEP_TIME=$INTERVAL
    REMAINING=$((DURATION - ELAPSED))
    if [ $SLEEP_TIME -gt $REMAINING ]; then
        SLEEP_TIME=$REMAINING
    fi

    sleep $((SLEEP_TIME * 60))
    ELAPSED=$((ELAPSED + SLEEP_TIME))

    echo "--- [$ELAPSED/$DURATION min] Progress check ---"

    # Clone and inspect
    TEMP=$(mktemp -d)
    if git clone "$SCRIPT_DIR/upstream.git" "$TEMP/code" 2>/dev/null; then
        cd "$TEMP/code"

        COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "?")
        echo "  Commits: $COMMIT_COUNT"

        # Show last few commits
        echo "  Recent:"
        git log --oneline -5 2>/dev/null | sed 's/^/    /'

        # Count source lines
        if [ -d src ]; then
            RS_FILES=$(find src -name "*.rs" | wc -l | tr -d ' ')
            RS_LINES=$(find src -name "*.rs" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
            echo "  Source: $RS_FILES files, $RS_LINES lines of Rust"
        fi

        cd "$SCRIPT_DIR"
    else
        echo "  (could not clone upstream repo)"
    fi
    rm -rf "$TEMP"

    # Running containers
    RUNNING=$(docker ps --filter name=ccc-agent --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Active agents: $RUNNING"
    echo ""
done

# ---- Stop agents ----

echo "============================================"
echo "  Time's up - stopping agents"
echo "============================================"
# Give 30s for the SIGTERM trap to commit+push uncommitted work
docker stop -t 30 $(docker ps -q --filter name=ccc-agent) 2>/dev/null || true
echo ""

# ---- Final summary ----

echo "============================================"
echo "  Final Results"
echo "============================================"

TEMP=$(mktemp -d)
if git clone "$SCRIPT_DIR/upstream.git" "$TEMP/code" 2>/dev/null; then
    cd "$TEMP/code"

    COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "?")
    echo "Total commits: $COMMIT_COUNT"
    echo ""

    echo "Commit log:"
    git log --oneline -30 2>/dev/null | sed 's/^/  /'
    echo ""

    if [ -d src ]; then
        echo "Source stats:"
        RS_FILES=$(find src -name "*.rs" | wc -l | tr -d ' ')
        RS_LINES=$(find src -name "*.rs" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
        echo "  Rust files: $RS_FILES"
        echo "  Lines of Rust: $RS_LINES"
        echo ""
        echo "Module breakdown:"
        for dir in src/*/; do
            if [ -d "$dir" ]; then
                DIR_LINES=$(find "$dir" -name "*.rs" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
                echo "  $(basename "$dir")/: $DIR_LINES lines"
            fi
        done
    fi

    # Check if it builds
    echo ""
    echo "Build check:"
    if cargo build --release 2>/dev/null; then
        echo "  cargo build --release: SUCCESS"
    else
        echo "  cargo build --release: FAILED"
    fi

    cd "$SCRIPT_DIR"
fi
rm -rf "$TEMP"

echo ""
echo "============================================"
echo "  Repo saved at: $SCRIPT_DIR/upstream.git"
echo "  Clone it:  git clone $SCRIPT_DIR/upstream.git ccc"
echo "  Re-run:    ./run.sh $NUM_AGENTS $DURATION"
echo "  Fresh run: rm -rf upstream.git && ./run.sh"
echo "============================================"

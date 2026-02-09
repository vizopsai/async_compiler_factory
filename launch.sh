#!/bin/bash
# =============================================================================
# CCC Agent Launcher
# =============================================================================
# Spawns N Docker containers, each running an infinite Claude Code agent loop.
# All containers share a bare git repo at ./upstream.git via volume mount.
#
# Usage:
#   ./launch.sh [NUM_AGENTS]    (default: 2)
#
# Prerequisites:
#   - Docker installed and running
#   - ANTHROPIC_API_KEY set in environment
#   - Container image built: docker build -t ccc-agent .
#   - Upstream repo initialized: ./init_repo.sh
# =============================================================================

set -e

NUM_AGENTS=${1:-2}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_DIR="$SCRIPT_DIR/upstream.git"
LOG_DIR="$SCRIPT_DIR/agent_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Unique prefix per worktree so multiple runs don't collide
RUN_PREFIX="ccc-$(basename "$SCRIPT_DIR" | tr -cd 'a-zA-Z0-9_')"

# Validate prerequisites
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ERROR: ANTHROPIC_API_KEY not set"
    exit 1
fi

if [ ! -d "$UPSTREAM_DIR" ]; then
    echo "ERROR: upstream.git not found. Run ./init_repo.sh first"
    exit 1
fi

mkdir -p "$LOG_DIR"

# Kill any existing agent containers from a previous run of this worktree
echo "Cleaning up any existing containers (prefix: $RUN_PREFIX)..."
for i in $(seq 1 64); do
    docker rm -f "${RUN_PREFIX}-$i" 2>/dev/null || true
done

echo "Launching $NUM_AGENTS agents..."
echo "Upstream repo: $UPSTREAM_DIR"
echo "Logs: $LOG_DIR"
echo ""

for i in $(seq 1 $NUM_AGENTS); do
    CONTAINER_NAME="${RUN_PREFIX}-$i"
    LOG_FILE="$LOG_DIR/${CONTAINER_NAME}_${TIMESTAMP}.log"

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -v "$UPSTREAM_DIR:/upstream:rw" \
        -v "$LOG_DIR:/workspace/agent_logs:rw" \
        -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
        -e AGENT_ID="$CONTAINER_NAME" \
        --memory 8g \
        --cpus 2 \
        ccc-agent \
        > "$LOG_FILE" 2>&1

    echo "  Started $CONTAINER_NAME (log: $LOG_FILE)"
done

echo ""
echo "All $NUM_AGENTS agents launched."
echo ""
echo "Monitor progress:"
echo "  docker ps --filter name=${RUN_PREFIX}"
echo "  docker logs -f ${RUN_PREFIX}-1"
echo ""
echo "Stop all agents:"
echo "  docker stop \$(docker ps -q --filter name=${RUN_PREFIX})"

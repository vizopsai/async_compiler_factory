#!/bin/bash
# =============================================================================
# CCC Agent Entrypoint (runs inside Docker container)
# =============================================================================
# This is the "infinite agent-generation-loop" described in the blog post.
# Each iteration:
#   1. Fresh clone from /upstream
#   2. Clear stale task locks (first agent only)
#   3. Run Claude Code with a kickoff prompt (CLAUDE.md is in the repo)
#   4. Claude works, commits, pushes to /upstream
#   5. Loop restarts with fresh clone
#
# On SIGTERM (docker stop), saves any uncommitted work before exiting.
# =============================================================================

AGENT_ID="${AGENT_ID:-agent-unknown}"
LOG_DIR="/workspace/agent_logs"
CLAUDE_PID=""

mkdir -p "$LOG_DIR"

save_work() {
    echo "[$AGENT_ID] Caught shutdown signal, saving uncommitted work..."
    # Kill the running claude process
    if [ -n "$CLAUDE_PID" ]; then
        kill "$CLAUDE_PID" 2>/dev/null
        wait "$CLAUDE_PID" 2>/dev/null
    fi
    # Commit and push whatever is in the working tree
    if [ -d /workspace/code/.git ]; then
        cd /workspace/code
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            git add -A 2>/dev/null
            git commit -m "WIP: auto-save uncommitted work from ${AGENT_ID}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>" 2>/dev/null
            git pull --rebase 2>/dev/null || true
            git push 2>/dev/null && echo "[$AGENT_ID] Work saved successfully." \
                                 || echo "[$AGENT_ID] Failed to push saved work."
        else
            echo "[$AGENT_ID] No uncommitted changes to save."
        fi
    fi
    exit 0
}

trap save_work SIGTERM SIGINT

echo "[$AGENT_ID] Starting agent loop at $(date -u)"

while true; do
    echo "[$AGENT_ID] === New iteration at $(date -u) ==="

    # Fresh clone from upstream each iteration
    rm -rf /workspace/code
    git clone /upstream /workspace/code 2>/dev/null
    cd /workspace/code

    COMMIT=$(git rev-parse --short=6 HEAD 2>/dev/null || echo "empty")
    LOGFILE="$LOG_DIR/${AGENT_ID}_${COMMIT}_$(date +%s).log"

    # First agent in a new run clears stale task locks.
    # This is a race -- only the first agent to push wins.
    # Others will pull the cleared state on their next rebase.
    if ls current_tasks/*.txt 1>/dev/null 2>&1; then
        LOCK_COUNT=$(ls current_tasks/*.txt 2>/dev/null | wc -l)
        echo "[$AGENT_ID] Found $LOCK_COUNT stale task locks, attempting to clear..."
        git rm current_tasks/*.txt 2>/dev/null || true
        git commit -m "Starting new run; clearing task locks" 2>/dev/null || true
        git push 2>/dev/null || {
            echo "[$AGENT_ID] Another agent already cleared locks, pulling..."
            git pull --rebase 2>/dev/null || true
        }
    fi

    echo "[$AGENT_ID] Running Claude Code session (HEAD: $COMMIT)..."

    # Claude Code discovers CLAUDE.md in the repo automatically.
    # The -p flag provides the kickoff prompt to start working.
    # Run in background so we can trap SIGTERM and save work.
    claude --dangerously-skip-permissions \
           -p "You are autonomous agent ${AGENT_ID}. Read CLAUDE.md for your full instructions, then start working. Pick a task, claim it, implement it, test it, push it. Keep going until your session ends.

CRITICAL: You MUST push your work frequently. After creating or modifying each file, do: git add -A && git commit -m \"description\" && git pull --rebase && git push. Do NOT wait until everything is done. Push after every meaningful change. Your session can be killed at any time and unpushed work is lost forever." \
           --model claude-opus-4-6 \
           2>&1 | tee "$LOGFILE" &
    CLAUDE_PID=$!
    wait $CLAUDE_PID
    CLAUDE_PID=""

    echo "[$AGENT_ID] Session ended, restarting loop..."

    # Brief pause to avoid hammering if something is broken
    sleep 5
done

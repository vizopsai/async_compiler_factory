#!/bin/bash
# Show lines of Rust code over time for each commit

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_DIR="$SCRIPT_DIR/upstream.git"

if [ ! -d "$UPSTREAM_DIR" ]; then
    echo "No upstream.git found."
    exit 1
fi

TEMP=$(mktemp -d)
trap "rm -rf $TEMP" EXIT
git clone "$UPSTREAM_DIR" "$TEMP/code" 2>/dev/null
cd "$TEMP/code"

# Collect commits (HEAD-first), reverse with tail -r (macOS) or tac (Linux)
REVERSE="tail -r"
command -v tac &>/dev/null && REVERSE="tac"
COMMITS=$(git log --format="%H %at %s" 2>/dev/null | $REVERSE)

if [ -z "$COMMITS" ]; then
    echo "No commits found."
    exit 0
fi

FIRST_EPOCH=$(echo "$COMMITS" | head -1 | awk '{print $2}')

printf "%-10s  %7s  %5s  %s\n" "TIME" "LINES" "FILES" "COMMIT"
printf "%-10s  %7s  %5s  %s\n" "----" "-----" "-----" "------"

echo "$COMMITS" | while read HASH EPOCH MSG; do
    echo "$MSG" | grep -qiE "clearing task|^Lock task" && continue

    MINUTES=$(( (EPOCH - FIRST_EPOCH) / 60 ))
    git checkout "$HASH" --quiet 2>/dev/null || continue

    LINES=$(find src -name "*.rs" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
    FILES=$(find src -name "*.rs" 2>/dev/null | wc -l | tr -d ' ')

    printf "+%-9s  %7s  %5s  %s\n" "${MINUTES}min" "$LINES" "$FILES" "${MSG:0:60}"
done

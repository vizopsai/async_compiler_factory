#!/bin/bash
# Show lines of code and test pass rate over time (runs inside Docker for build+test)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_DIR="$SCRIPT_DIR/upstream.git"

if [ ! -d "$UPSTREAM_DIR" ]; then
    echo "No upstream.git found."
    exit 1
fi

docker run --rm -i --entrypoint bash \
    -v "$UPSTREAM_DIR:/upstream:ro" \
    ccc-agent -s << 'DOCKER_SCRIPT'

git clone /upstream /tmp/code 2>/dev/null
cd /tmp/code

COMMITS=$(git log --format="%H %at %s" 2>/dev/null | tac)
if [ -z "$COMMITS" ]; then
    echo "No commits found."
    exit 0
fi

FIRST_EPOCH=$(echo "$COMMITS" | head -1 | awk '{print $2}')

printf "%-10s  %7s  %5s  %8s  %s\n" "TIME" "LINES" "FILES" "TESTS" "COMMIT"
printf "%-10s  %7s  %5s  %8s  %s\n" "----" "-----" "-----" "-----" "------"

# Write commits to a file to avoid stdin issues in while loop
echo "$COMMITS" > /tmp/commits.txt

while read HASH EPOCH MSG; do
    echo "$MSG" | grep -qiE "clearing task|^Lock task" && continue

    MINUTES=$(( (EPOCH - FIRST_EPOCH) / 60 ))
    git checkout "$HASH" --quiet --force 2>/dev/null || continue

    LINES=$(find src -name "*.rs" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
    FILES=$(find src -name "*.rs" 2>/dev/null | wc -l | tr -d ' ')

    TESTS="-"
    if cargo build --release </dev/null 2>/dev/null; then
        CCC="./target/release/ccc"
        PASS=0; TOTAL=0
        for f in /test-suites/basic/*.c; do
            TOTAL=$((TOTAL + 1))
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
        TESTS="$PASS/$TOTAL"
    fi

    printf "+%-9s  %7s  %5s  %8s  %s\n" "${MINUTES}min" "$LINES" "$FILES" "$TESTS" "${MSG:0:55}"
done < /tmp/commits.txt
DOCKER_SCRIPT
